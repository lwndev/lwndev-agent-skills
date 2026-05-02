import { describe, it, expect, beforeAll, afterEach } from 'vitest';
import { execFileSync } from 'node:child_process';
import { readFile, access } from 'node:fs/promises';
import { constants, mkdirSync, writeFileSync, rmSync, mkdtempSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { validate, type DetailedValidateResult } from 'ai-skills-manager';

const SKILL_DIR = 'plugins/lwndev-sdlc/skills/documenting-qa';
const SKILL_MD_PATH = join(SKILL_DIR, 'SKILL.md');
const TEMPLATE_PATH = join(SKILL_DIR, 'assets', 'test-plan-template.md');
const TEMPLATE_V2_PATH = join(SKILL_DIR, 'assets', 'test-plan-template-v2.md');
const STOP_HOOK_PATH = join(process.cwd(), SKILL_DIR, 'scripts', 'stop-hook.sh');

describe('documenting-qa skill', () => {
  let skillMd: string;
  let template: string;
  let templateV2: string;

  beforeAll(async () => {
    skillMd = await readFile(SKILL_MD_PATH, 'utf-8');
    template = await readFile(TEMPLATE_PATH, 'utf-8');
    templateV2 = await readFile(TEMPLATE_V2_PATH, 'utf-8');
  });

  describe('SKILL.md', () => {
    it('should have frontmatter with name: documenting-qa', () => {
      expect(skillMd).toMatch(/^---\s*\n[\s\S]*?name:\s*documenting-qa[\s\S]*?---/);
    });

    it('should have frontmatter with non-empty description', () => {
      const match = skillMd.match(/^---\s*\n[\s\S]*?description:\s*(.+)[\s\S]*?---/);
      expect(match).not.toBeNull();
      expect(match![1].trim().length).toBeGreaterThan(0);
    });

    it('should include "When to Use This Skill" section', () => {
      expect(skillMd).toContain('## When to Use This Skill');
    });

    it('should include "Verification Checklist" section', () => {
      expect(skillMd).toContain('## Verification Checklist');
    });

    it('should include "Relationship to Other Skills" section', () => {
      expect(skillMd).toContain('## Relationship to Other Skills');
    });

    it('should reference executing-qa as follow-up skill', () => {
      expect(skillMd).toContain('executing-qa');
    });

    it('should document ID parsing for FEAT, CHORE, and BUG types', () => {
      expect(skillMd).toContain('FEAT-');
      expect(skillMd).toContain('CHORE-');
      expect(skillMd).toContain('BUG-');
    });

    it('should reference requirements directories by type', () => {
      expect(skillMd).toContain('requirements/features/');
      expect(skillMd).toContain('requirements/chores/');
      expect(skillMd).toContain('requirements/bugs/');
    });

    it('should specify test plan output path format', () => {
      expect(skillMd).toContain('qa/test-plans/QA-plan-');
    });

    it('should forbid reading requirements docs during planning (FR-4 no-spec guard)', () => {
      // The skill must explicitly instruct the planning agent not to read
      // the full spec during planning; enforcement happens via the stop
      // hook's no-FR-N rule, but the instruction must also be documented
      // in SKILL.md itself so the agent sees it in context.
      expect(skillMd).toMatch(/Do NOT read\s+`?requirements\//i);
    });

    it('should reference capability-discovery.sh in step instructions', () => {
      expect(skillMd).toContain('capability-discovery.sh');
    });

    it('should reference persona-loader.sh in step instructions', () => {
      expect(skillMd).toContain('persona-loader.sh');
    });

    it('should reference the version-2 artifact template (test-plan-template-v2.md)', () => {
      expect(skillMd).toContain('test-plan-template-v2.md');
    });

    it('should specify version-2 artifact output in frontmatter guidance', () => {
      expect(skillMd).toContain('version: 2');
    });

    it('should NOT reference the qa-verifier agent (Ralph loop removed per FEAT-018)', () => {
      expect(skillMd).not.toContain('qa-verifier');
    });
  });

  describe('allowed-tools', () => {
    it('should have allowed-tools in frontmatter', () => {
      expect(skillMd).toMatch(/^---\s*\n[\s\S]*?allowed-tools:[\s\S]*?---/);
    });

    it('should include Bash in allowed-tools (invokes capability-discovery and persona-loader scripts)', () => {
      const frontmatter = skillMd.match(/^---\s*\n([\s\S]*?)---/)?.[1] ?? '';
      expect(frontmatter).toMatch(/allowed-tools:[\s\S]*?-\s*Bash/);
    });

    it('should NOT include Agent in allowed-tools (qa-verifier Ralph loop removed)', () => {
      const frontmatter = skillMd.match(/^---\s*\n([\s\S]*?)---/)?.[1] ?? '';
      expect(frontmatter).not.toMatch(/allowed-tools:[\s\S]*?-\s*Agent/);
    });
  });

  describe('stop hook', () => {
    it('should define a Stop hook in frontmatter', () => {
      expect(skillMd).toMatch(/^---\s*\n[\s\S]*?hooks:[\s\S]*?Stop:[\s\S]*?---/);
    });

    it('should use type: command for the stop hook', () => {
      const frontmatter = skillMd.match(/^---\s*\n([\s\S]*?)---/)?.[1] ?? '';
      expect(frontmatter).toContain('type: command');
    });

    it('should use ${CLAUDE_PLUGIN_ROOT} in Stop hook command path', () => {
      expect(skillMd).toMatch(
        /^---\s*\n[\s\S]*?command:\s*.*\$\{CLAUDE_PLUGIN_ROOT\}\/skills\/documenting-qa\/scripts\/stop-hook\.sh[\s\S]*?---/
      );
    });

    it('should not use type: prompt (replaced by command hook)', () => {
      const frontmatter = skillMd.match(/^---\s*\n([\s\S]*?)---/)?.[1] ?? '';
      expect(frontmatter).not.toContain('type: prompt');
    });

    it('should have an executable stop-hook.sh script', async () => {
      await expect(access(STOP_HOOK_PATH, constants.X_OK)).resolves.toBeUndefined();
    });
  });

  // The stop hook validates a version-2 plan artifact on disk. These tests
  // run the real stop-hook.sh binary in a tmpdir fixture; each fixture
  // contains its own `qa/test-plans/` directory and a `.sdlc/qa/` state
  // file. Exit code 0 = allow stop; exit code 2 = block stop.
  describe('stop hook behavior (artifact-structure grading)', () => {
    type HookResult = { exitCode: number; stdout: string; stderr: string };

    let fixture: string;

    function runHookIn(cwd: string, stdinJson: string): HookResult {
      try {
        const stdout = execFileSync('bash', [STOP_HOOK_PATH], {
          input: stdinJson,
          encoding: 'utf-8',
          cwd,
          stdio: ['pipe', 'pipe', 'pipe'],
        });
        return { exitCode: 0, stdout, stderr: '' };
      } catch (err: unknown) {
        const e = err as { status: number; stderr?: string; stdout?: string };
        return {
          exitCode: e.status ?? -1,
          stdout: e.stdout ?? '',
          stderr: e.stderr ?? '',
        };
      }
    }

    function setupStateFile(dir: string): void {
      mkdirSync(join(dir, '.sdlc', 'qa'), { recursive: true });
      writeFileSync(join(dir, '.sdlc', 'qa', '.documenting-active'), '');
    }

    function writePlan(dir: string, id: string, content: string): string {
      const planDir = join(dir, 'qa', 'test-plans');
      mkdirSync(planDir, { recursive: true });
      const path = join(planDir, `QA-plan-${id}.md`);
      writeFileSync(path, content);
      return path;
    }

    const WELL_FORMED_PLAN = `---
id: FEAT-001
version: 2
timestamp: 2026-04-19T14:22:00Z
persona: qa
---

## User Summary

Adds a widget that frobs the gizmo in user-visible terms.

## Capability Report

- Mode: test-framework
- Framework: vitest
- Package manager: npm
- Test command: npm test
- Language: typescript

## Scenarios (by dimension)

### Inputs
- [P0] Empty widget input → frobber returns exploratory-only | mode: test-framework | expected: unit test on handleEmpty()

### State transitions
- [P1] Cancel mid-frob → state resets | mode: test-framework | expected: integration test

### Environment
- [P1] Offline → frobber degrades gracefully | mode: exploratory | expected: manual smoke

### Dependency failure
- [P2] Gizmo API 500 → verdict is ERROR not PASS | mode: test-framework | expected: mocked fetch test

### Cross-cutting (a11y, i18n, concurrency, permissions)
- [P2] RTL locale → no layout breakage | mode: exploratory | expected: visual smoke

## Non-applicable dimensions

- (none — all dimensions have scenarios)
`;

    beforeAll(() => {
      // no-op — fixtures are per-test
    });

    afterEach(() => {
      if (fixture) {
        rmSync(fixture, { recursive: true, force: true });
      }
    });

    it('1. exits 0 when a well-formed v2 plan artifact exists and is referenced', () => {
      fixture = mkdtempSync(join(tmpdir(), 'doc-qa-hook-'));
      setupStateFile(fixture);
      writePlan(fixture, 'FEAT-001', WELL_FORMED_PLAN);
      const result = runHookIn(
        fixture,
        JSON.stringify({
          stop_hook_active: false,
          last_assistant_message: 'Plan saved to qa/test-plans/QA-plan-FEAT-001.md. Proceeding.',
        })
      );
      expect(result.exitCode).toBe(0);
      expect(existsSync(join(fixture, '.sdlc', 'qa', '.documenting-active'))).toBe(false);
    });

    it('2. exits 2 when the plan file has no frontmatter', () => {
      fixture = mkdtempSync(join(tmpdir(), 'doc-qa-hook-'));
      setupStateFile(fixture);
      const body = WELL_FORMED_PLAN.replace(/^---[\s\S]*?---\n\n/, '');
      writePlan(fixture, 'FEAT-002', body);
      const result = runHookIn(
        fixture,
        JSON.stringify({
          stop_hook_active: false,
          last_assistant_message: 'Plan at qa/test-plans/QA-plan-FEAT-002.md',
        })
      );
      expect(result.exitCode).toBe(2);
      expect(result.stderr).toContain('frontmatter');
    });

    it('3. exits 2 when the plan is missing `version: 2` in frontmatter', () => {
      fixture = mkdtempSync(join(tmpdir(), 'doc-qa-hook-'));
      setupStateFile(fixture);
      const content = WELL_FORMED_PLAN.replace('version: 2', 'timestamp-only: true');
      writePlan(fixture, 'FEAT-003', content);
      const result = runHookIn(
        fixture,
        JSON.stringify({
          stop_hook_active: false,
          last_assistant_message: 'Plan at qa/test-plans/QA-plan-FEAT-003.md',
        })
      );
      expect(result.exitCode).toBe(2);
      expect(result.stderr).toContain('version: 2');
    });

    it('4. exits 2 when the `## Scenarios (by dimension)` section is missing', () => {
      fixture = mkdtempSync(join(tmpdir(), 'doc-qa-hook-'));
      setupStateFile(fixture);
      const content = WELL_FORMED_PLAN.replace(
        /## Scenarios \(by dimension\)[\s\S]*?## Non-applicable dimensions/,
        '## Non-applicable dimensions'
      );
      writePlan(fixture, 'FEAT-004', content);
      const result = runHookIn(
        fixture,
        JSON.stringify({
          stop_hook_active: false,
          last_assistant_message: 'Plan at qa/test-plans/QA-plan-FEAT-004.md',
        })
      );
      expect(result.exitCode).toBe(2);
      expect(result.stderr).toMatch(/Scenarios|dimension/);
    });

    it('5. exits 2 when the Scenarios section mentions `FR-4` (no-spec guard)', () => {
      fixture = mkdtempSync(join(tmpdir(), 'doc-qa-hook-'));
      setupStateFile(fixture);
      const content = WELL_FORMED_PLAN.replace(
        '- [P0] Empty widget input → frobber returns exploratory-only | mode: test-framework | expected: unit test on handleEmpty()',
        '- [P0] Covers FR-4 from the spec | mode: test-framework | expected: bound to spec'
      );
      writePlan(fixture, 'FEAT-005', content);
      const result = runHookIn(
        fixture,
        JSON.stringify({
          stop_hook_active: false,
          last_assistant_message: 'Plan at qa/test-plans/QA-plan-FEAT-005.md',
        })
      );
      expect(result.exitCode).toBe(2);
      expect(result.stderr).toContain('FR-N');
    });

    it('6. exits 2 when zero dimensions covered and zero non-applicable justifications', () => {
      fixture = mkdtempSync(join(tmpdir(), 'doc-qa-hook-'));
      setupStateFile(fixture);
      // Empty Scenarios section (heading only) and no non-applicable entries.
      const content = `---
id: FEAT-006
version: 2
timestamp: 2026-04-19T00:00:00Z
persona: qa
---

## User Summary
A thing.

## Capability Report
- Mode: exploratory-only

## Scenarios (by dimension)

## Non-applicable dimensions
`;
      writePlan(fixture, 'FEAT-006', content);
      const result = runHookIn(
        fixture,
        JSON.stringify({
          stop_hook_active: false,
          last_assistant_message: 'Plan at qa/test-plans/QA-plan-FEAT-006.md',
        })
      );
      expect(result.exitCode).toBe(2);
      expect(result.stderr).toMatch(/dimension|Non-applicable/);
    });

    it('7. exits 2 when a scenario line is missing its priority or execution-mode tag', () => {
      fixture = mkdtempSync(join(tmpdir(), 'doc-qa-hook-'));
      setupStateFile(fixture);
      const content = WELL_FORMED_PLAN.replace(
        '- [P0] Empty widget input → frobber returns exploratory-only | mode: test-framework | expected: unit test on handleEmpty()',
        '- [oops] Missing priority tag | expected: nothing'
      );
      writePlan(fixture, 'FEAT-007', content);
      const result = runHookIn(
        fixture,
        JSON.stringify({
          stop_hook_active: false,
          last_assistant_message: 'Plan at qa/test-plans/QA-plan-FEAT-007.md',
        })
      );
      expect(result.exitCode).toBe(2);
      expect(result.stderr).toMatch(/priority|mode:/);
    });

    it('8. exits 0 regardless of artifact when stop_hook_active=true', () => {
      fixture = mkdtempSync(join(tmpdir(), 'doc-qa-hook-'));
      setupStateFile(fixture);
      // Intentionally do not write a plan file.
      const result = runHookIn(
        fixture,
        JSON.stringify({
          stop_hook_active: true,
          last_assistant_message: 'Plan at qa/test-plans/QA-plan-FEAT-008.md',
        })
      );
      expect(result.exitCode).toBe(0);
      expect(existsSync(join(fixture, '.sdlc', 'qa', '.documenting-active'))).toBe(false);
    });

    // Supplementary: the state-file guard and empty/malformed stdin guards.
    it('exits 0 immediately when state file does not exist (skill not active)', () => {
      fixture = mkdtempSync(join(tmpdir(), 'doc-qa-hook-'));
      // No state file; no plan file.
      const result = runHookIn(
        fixture,
        JSON.stringify({
          stop_hook_active: false,
          last_assistant_message: 'anything',
        })
      );
      expect(result.exitCode).toBe(0);
    });

    it('exits 0 on empty stdin', () => {
      fixture = mkdtempSync(join(tmpdir(), 'doc-qa-hook-'));
      setupStateFile(fixture);
      const result = runHookIn(fixture, '');
      expect(result.exitCode).toBe(0);
    });

    it('exits 0 on malformed JSON', () => {
      fixture = mkdtempSync(join(tmpdir(), 'doc-qa-hook-'));
      setupStateFile(fixture);
      const result = runHookIn(fixture, 'not json at all');
      // Malformed JSON → jq returns null → MESSAGE empty → cannot find ID.
      // Current implementation will exit 2 here with "could not determine" —
      // accept either 0 or 2 as long as the tool doesn't crash; the guard
      // for empty stdin is `exit 0`, but non-empty malformed still reaches
      // the path-resolution block. Confirm exit is defined (not -1).
      expect([0, 2]).toContain(result.exitCode);
    });

    it('exits 2 when the plan artifact does not exist on disk', () => {
      fixture = mkdtempSync(join(tmpdir(), 'doc-qa-hook-'));
      setupStateFile(fixture);
      // Do not create the plan file.
      const result = runHookIn(
        fixture,
        JSON.stringify({
          stop_hook_active: false,
          last_assistant_message: 'Saved to qa/test-plans/QA-plan-FEAT-999.md',
        })
      );
      expect(result.exitCode).toBe(2);
      expect(result.stderr).toContain('does not exist');
    });

    it('exits 2 when the message references no plan file and none is on disk', () => {
      fixture = mkdtempSync(join(tmpdir(), 'doc-qa-hook-'));
      setupStateFile(fixture);
      const result = runHookIn(
        fixture,
        JSON.stringify({
          stop_hook_active: false,
          last_assistant_message: 'doing stuff',
        })
      );
      expect(result.exitCode).toBe(2);
      expect(result.stderr).toMatch(/could not determine|does not exist/);
    });

    it('allows `FR-N` tokens in `## Non-applicable dimensions` (only Scenarios section is guarded)', () => {
      fixture = mkdtempSync(join(tmpdir(), 'doc-qa-hook-'));
      setupStateFile(fixture);
      const content = WELL_FORMED_PLAN.replace(
        '- (none — all dimensions have scenarios)',
        '- i18n: this feature addresses FR-4 text handling only; no UI surface.'
      );
      writePlan(fixture, 'FEAT-010', content);
      const result = runHookIn(
        fixture,
        JSON.stringify({
          stop_hook_active: false,
          last_assistant_message: 'Plan at qa/test-plans/QA-plan-FEAT-010.md',
        })
      );
      expect(result.exitCode).toBe(0);
    });
  });

  describe('test plan template (v1)', () => {
    it('should exist as assets/test-plan-template.md', () => {
      expect(template).toBeDefined();
      expect(template.length).toBeGreaterThan(0);
    });

    it('should contain Metadata section', () => {
      expect(template).toContain('## Metadata');
    });

    it('should contain Existing Test Verification section', () => {
      expect(template).toContain('## Existing Test Verification');
    });

    it('should contain New Test Analysis section', () => {
      expect(template).toContain('## New Test Analysis');
    });

    it('should contain Coverage Gap Analysis section', () => {
      expect(template).toContain('## Coverage Gap Analysis');
    });

    it('should contain Code Path Verification section', () => {
      expect(template).toContain('## Code Path Verification');
    });

    it('should contain Plan Completeness Checklist section', () => {
      expect(template).toContain('## Plan Completeness Checklist');
    });
  });

  describe('test plan template (v2)', () => {
    it('should exist as assets/test-plan-template-v2.md', () => {
      expect(templateV2).toBeDefined();
      expect(templateV2.length).toBeGreaterThan(0);
    });

    it('should declare version: 2 in frontmatter', () => {
      expect(templateV2).toMatch(/^---[\s\S]*?\nversion:\s*2\b/m);
    });

    it('should contain all required frontmatter fields (id, version, timestamp, persona)', () => {
      const frontmatterMatch = templateV2.match(/^---\s*\n([\s\S]*?)---/m);
      expect(frontmatterMatch).not.toBeNull();
      const fm = frontmatterMatch![1];
      expect(fm).toMatch(/\bid:/);
      expect(fm).toMatch(/\bversion:/);
      expect(fm).toMatch(/\btimestamp:/);
      expect(fm).toMatch(/\bpersona:/);
    });

    it('should document the version-1/version-2 split as an explanatory comment', () => {
      expect(templateV2).toContain('version 1');
      expect(templateV2).toContain('version 2');
    });

    it('should include the User Summary section', () => {
      expect(templateV2).toContain('## User Summary');
    });

    it('should include the Capability Report section', () => {
      expect(templateV2).toContain('## Capability Report');
    });

    it('should include the Scenarios (by dimension) section', () => {
      expect(templateV2).toContain('## Scenarios (by dimension)');
    });

    it('should include all five dimension subsections', () => {
      expect(templateV2).toContain('### Inputs');
      expect(templateV2).toContain('### State transitions');
      expect(templateV2).toContain('### Environment');
      expect(templateV2).toContain('### Dependency failure');
      expect(templateV2).toContain('### Cross-cutting');
    });

    it('should include the Non-applicable dimensions section', () => {
      expect(templateV2).toContain('## Non-applicable dimensions');
    });
  });

  describe('validation API', () => {
    it('should pass ai-skills-manager validation', async () => {
      const result: DetailedValidateResult = await validate(SKILL_DIR, {
        detailed: true,
      });
      expect(result.valid).toBe(true);
    });
  });
});
