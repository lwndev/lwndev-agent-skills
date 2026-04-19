import { describe, it, expect, beforeAll, afterEach } from 'vitest';
import { execFileSync } from 'node:child_process';
import { readFile, access } from 'node:fs/promises';
import { constants, mkdirSync, writeFileSync, rmSync, mkdtempSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { validate, type DetailedValidateResult } from 'ai-skills-manager';

const SKILL_DIR = 'plugins/lwndev-sdlc/skills/executing-qa';
const SKILL_MD_PATH = join(SKILL_DIR, 'SKILL.md');
const TEMPLATE_PATH = join(SKILL_DIR, 'assets', 'test-results-template.md');
const TEMPLATE_V2_PATH = join(SKILL_DIR, 'assets', 'test-results-template-v2.md');
const STOP_HOOK_PATH = join(process.cwd(), SKILL_DIR, 'scripts', 'stop-hook.sh');

describe('executing-qa skill', () => {
  let skillMd: string;
  let template: string;
  let templateV2: string;

  beforeAll(async () => {
    skillMd = await readFile(SKILL_MD_PATH, 'utf-8');
    template = await readFile(TEMPLATE_PATH, 'utf-8');
    templateV2 = await readFile(TEMPLATE_V2_PATH, 'utf-8');
  });

  describe('SKILL.md', () => {
    it('should have frontmatter with name: executing-qa', () => {
      expect(skillMd).toMatch(/^---\s*\n[\s\S]*?name:\s*executing-qa[\s\S]*?---/);
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

    it('should reference documenting-qa as prerequisite skill', () => {
      expect(skillMd).toContain('documenting-qa');
    });

    it('should document ID parsing for FEAT, CHORE, and BUG types', () => {
      expect(skillMd).toContain('FEAT-');
      expect(skillMd).toContain('CHORE-');
      expect(skillMd).toContain('BUG-');
    });

    it('should document loading test plan from qa/test-plans/', () => {
      expect(skillMd).toContain('qa/test-plans/QA-plan-');
    });

    it('should specify test results output path format', () => {
      expect(skillMd).toContain('qa/test-results/QA-results-');
    });
  });

  describe('SKILL.md structural assertions (Phase 5)', () => {
    it('should reference capability-discovery.sh', () => {
      expect(skillMd).toContain('capability-discovery.sh');
    });

    it('should reference persona-loader.sh', () => {
      expect(skillMd).toContain('persona-loader.sh');
    });

    it('should reference test-results-template-v2.md', () => {
      expect(skillMd).toContain('test-results-template-v2.md');
    });

    it('should describe the four verdict values', () => {
      expect(skillMd).toContain('PASS');
      expect(skillMd).toContain('ISSUES-FOUND');
      expect(skillMd).toContain('ERROR');
      expect(skillMd).toContain('EXPLORATORY-ONLY');
    });

    it('should include a Reconciliation Delta step', () => {
      expect(skillMd).toContain('## Reconciliation Delta');
    });

    it('should NOT reference the qa-verifier agent (Ralph loop removed)', () => {
      expect(skillMd).not.toContain('qa-verifier');
    });

    it('should NOT include Agent in allowed-tools (subagent loop removed)', () => {
      const frontmatter = skillMd.match(/^---\s*\n([\s\S]*?)---/)?.[1] ?? '';
      expect(frontmatter).not.toContain('- Agent');
    });

    it('should handle clean branch vs main by emitting ERROR verdict with specific reason (edge case 5)', () => {
      expect(skillMd).toMatch(
        /git diff main\.\.\.HEAD[\s\S]*ERROR[\s\S]*no changes to test relative to main/
      );
    });

    it('should handle missing requirements doc by skipping reconciliation delta with note (edge case 7)', () => {
      expect(skillMd).toMatch(/Reconciliation delta skipped: no requirements doc/);
    });
  });

  describe('allowed-tools', () => {
    it('should have allowed-tools in frontmatter', () => {
      expect(skillMd).toMatch(/^---\s*\n[\s\S]*?allowed-tools:[\s\S]*?---/);
    });

    it('should include Bash (skill invokes capability-discovery and persona-loader)', () => {
      const frontmatter = skillMd.match(/^---\s*\n([\s\S]*?)---/)?.[1] ?? '';
      expect(frontmatter).toContain('- Bash');
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
        /^---\s*\n[\s\S]*?command:\s*.*\$\{CLAUDE_PLUGIN_ROOT\}\/skills\/executing-qa\/scripts\/stop-hook\.sh[\s\S]*?---/
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

  // The stop hook validates a version-2 results artifact on disk; exit 0
  // allows stop, exit 2 blocks it.
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
      writeFileSync(join(dir, '.sdlc', 'qa', '.executing-active'), '');
    }

    function writeResults(dir: string, id: string, content: string): string {
      const resultsDir = join(dir, 'qa', 'test-results');
      mkdirSync(resultsDir, { recursive: true });
      const path = join(resultsDir, `QA-results-${id}.md`);
      writeFileSync(path, content);
      return path;
    }

    const passArtifact = (id: string): string => `---
id: ${id}
version: 2
timestamp: 2026-04-19T14:22:00Z
verdict: PASS
persona: qa
---

## Summary
All adversarial scenarios passed.

## Capability Report
- Mode: test-framework
- Framework: vitest
- Test command: npm test

## Execution Results
- Total: 5
- Passed: 5
- Failed: 0
- Errored: 0
- Exit code: 0
- Duration: 3s
- Test files: [qa-inputs.spec.ts]

## Scenarios Run
| ID | Dimension | Priority | Result | Test file |
|----|-----------|----------|--------|-----------|
| 1  | Inputs    | P0       | PASS   | qa-inputs.spec.ts |

## Findings

## Reconciliation Delta
### Coverage beyond requirements
### Coverage gaps
### Summary
- coverage-surplus: 0
- coverage-gap: 0
`;

    const issuesFoundArtifact = (id: string): string => `---
id: ${id}
version: 2
timestamp: 2026-04-19T14:22:00Z
verdict: ISSUES-FOUND
persona: qa
---

## Summary
One test failed.

## Capability Report
- Mode: test-framework

## Execution Results
- Total: 5
- Passed: 4
- Failed: 1
- Errored: 0
- Exit code: 1
- Duration: 3s
- Test files: [qa-inputs.spec.ts]

## Scenarios Run
| ID | Dimension | Priority | Result | Test file |
|----|-----------|----------|--------|-----------|

## Findings
- severity: high | dimension: Inputs | title: empty-input regression | test: qa-inputs.spec.ts

## Reconciliation Delta
### Summary
- coverage-surplus: 0
- coverage-gap: 0
`;

    const errorArtifact = (id: string): string => `---
id: ${id}
version: 2
timestamp: 2026-04-19T14:22:00Z
verdict: ERROR
persona: qa
---

## Summary
Runner crashed.

## Capability Report
- Mode: test-framework

## Execution Results
- Total: 0
- Passed: 0
- Failed: 0
- Errored: 1
- Exit code: 2
- Duration: 0s
- Test files: []

\`\`\`
Error: cannot find module "foo"
    at Object.resolve (node:internal/modules/cjs/loader:1234:56)
    at require (node:internal/modules/cjs/loader:1345:12)
\`\`\`

## Scenarios Run
| ID | Dimension | Priority | Result | Test file |
|----|-----------|----------|--------|-----------|

## Findings
- Runner compile error

## Reconciliation Delta
### Summary
- coverage-surplus: 0
- coverage-gap: 0
`;

    const exploratoryArtifact = (id: string): string => `---
id: ${id}
version: 2
timestamp: 2026-04-19T14:22:00Z
verdict: EXPLORATORY-ONLY
persona: qa
---

## Summary
No executable runner detected.

## Capability Report
- Mode: exploratory-only

## Scenarios Run
| ID | Dimension | Priority | Result | Test file |
|----|-----------|----------|--------|-----------|

## Findings

## Reconciliation Delta
### Summary
- coverage-surplus: 0
- coverage-gap: 0

## Exploratory Mode
Reason: capability discovery detected no test framework in the consumer repo.
Dimensions covered: inputs, state-transitions, environment, dependency-failure, cross-cutting
`;

    afterEach(() => {
      if (fixture) {
        rmSync(fixture, { recursive: true, force: true });
      }
    });

    // 1
    it('1. exits 0 when a well-formed PASS artifact exists and is referenced', () => {
      fixture = mkdtempSync(join(tmpdir(), 'exec-qa-hook-'));
      setupStateFile(fixture);
      writeResults(fixture, 'FEAT-001', passArtifact('FEAT-001'));
      const result = runHookIn(
        fixture,
        JSON.stringify({
          stop_hook_active: false,
          last_assistant_message: 'Results saved to qa/test-results/QA-results-FEAT-001.md.',
        })
      );
      expect(result.exitCode).toBe(0);
      expect(existsSync(join(fixture, '.sdlc', 'qa', '.executing-active'))).toBe(false);
    });

    // 2
    it('2. exits 0 when a well-formed ISSUES-FOUND artifact exists', () => {
      fixture = mkdtempSync(join(tmpdir(), 'exec-qa-hook-'));
      setupStateFile(fixture);
      writeResults(fixture, 'FEAT-002', issuesFoundArtifact('FEAT-002'));
      const result = runHookIn(
        fixture,
        JSON.stringify({
          stop_hook_active: false,
          last_assistant_message: 'qa/test-results/QA-results-FEAT-002.md',
        })
      );
      expect(result.exitCode).toBe(0);
    });

    // 3
    it('3. exits 0 when a well-formed ERROR artifact exists (stack trace present)', () => {
      fixture = mkdtempSync(join(tmpdir(), 'exec-qa-hook-'));
      setupStateFile(fixture);
      writeResults(fixture, 'FEAT-003', errorArtifact('FEAT-003'));
      const result = runHookIn(
        fixture,
        JSON.stringify({
          stop_hook_active: false,
          last_assistant_message: 'qa/test-results/QA-results-FEAT-003.md',
        })
      );
      expect(result.exitCode).toBe(0);
    });

    // 4
    it('4. exits 0 when a well-formed EXPLORATORY-ONLY artifact exists', () => {
      fixture = mkdtempSync(join(tmpdir(), 'exec-qa-hook-'));
      setupStateFile(fixture);
      writeResults(fixture, 'FEAT-004', exploratoryArtifact('FEAT-004'));
      const result = runHookIn(
        fixture,
        JSON.stringify({
          stop_hook_active: false,
          last_assistant_message: 'qa/test-results/QA-results-FEAT-004.md',
        })
      );
      expect(result.exitCode).toBe(0);
    });

    // 5
    it('5. exits 2 when verdict is PASS but Failed > 0 (verdict/counts inconsistent)', () => {
      fixture = mkdtempSync(join(tmpdir(), 'exec-qa-hook-'));
      setupStateFile(fixture);
      const content = passArtifact('FEAT-005').replace('Failed: 0', 'Failed: 3');
      writeResults(fixture, 'FEAT-005', content);
      const result = runHookIn(
        fixture,
        JSON.stringify({
          stop_hook_active: false,
          last_assistant_message: 'qa/test-results/QA-results-FEAT-005.md',
        })
      );
      expect(result.exitCode).toBe(2);
      expect(result.stderr).toMatch(/PASS.*Failed|Failed.*PASS/i);
    });

    // 6
    it('6. exits 2 when the verdict frontmatter field is missing', () => {
      fixture = mkdtempSync(join(tmpdir(), 'exec-qa-hook-'));
      setupStateFile(fixture);
      const content = passArtifact('FEAT-006').replace('verdict: PASS\n', '');
      writeResults(fixture, 'FEAT-006', content);
      const result = runHookIn(
        fixture,
        JSON.stringify({
          stop_hook_active: false,
          last_assistant_message: 'qa/test-results/QA-results-FEAT-006.md',
        })
      );
      expect(result.exitCode).toBe(2);
      expect(result.stderr).toContain('verdict');
    });

    // 7
    it('7. exits 2 when the verdict value is not in the allowed enum', () => {
      fixture = mkdtempSync(join(tmpdir(), 'exec-qa-hook-'));
      setupStateFile(fixture);
      const content = passArtifact('FEAT-007').replace('verdict: PASS', 'verdict: pass');
      writeResults(fixture, 'FEAT-007', content);
      const result = runHookIn(
        fixture,
        JSON.stringify({
          stop_hook_active: false,
          last_assistant_message: 'qa/test-results/QA-results-FEAT-007.md',
        })
      );
      expect(result.exitCode).toBe(2);
      expect(result.stderr).toMatch(/not one of|pass/);
    });

    // 8
    it('8. exits 2 when ISSUES-FOUND has no failing-test names in Findings', () => {
      fixture = mkdtempSync(join(tmpdir(), 'exec-qa-hook-'));
      setupStateFile(fixture);
      const content = issuesFoundArtifact('FEAT-008').replace(
        '- severity: high | dimension: Inputs | title: empty-input regression | test: qa-inputs.spec.ts',
        '- (empty placeholder)'
      );
      writeResults(fixture, 'FEAT-008', content);
      const result = runHookIn(
        fixture,
        JSON.stringify({
          stop_hook_active: false,
          last_assistant_message: 'qa/test-results/QA-results-FEAT-008.md',
        })
      );
      expect(result.exitCode).toBe(2);
      expect(result.stderr).toMatch(/Findings|failing/);
    });

    // 9
    it('9. exits 2 when ERROR artifact has no stack trace and exit code is zero', () => {
      fixture = mkdtempSync(join(tmpdir(), 'exec-qa-hook-'));
      setupStateFile(fixture);
      // Strip the stack trace block and force Exit code: 0.
      let content = errorArtifact('FEAT-009').replace(/```[\s\S]*?```\n\n/, '');
      content = content.replace('Exit code: 2', 'Exit code: 0');
      writeResults(fixture, 'FEAT-009', content);
      const result = runHookIn(
        fixture,
        JSON.stringify({
          stop_hook_active: false,
          last_assistant_message: 'qa/test-results/QA-results-FEAT-009.md',
        })
      );
      expect(result.exitCode).toBe(2);
      expect(result.stderr).toMatch(/ERROR|stack trace/);
    });

    // 10
    it('10. exits 2 when EXPLORATORY-ONLY has no Reason: line', () => {
      fixture = mkdtempSync(join(tmpdir(), 'exec-qa-hook-'));
      setupStateFile(fixture);
      const content = exploratoryArtifact('FEAT-010').replace(/Reason: .*\n/, '');
      writeResults(fixture, 'FEAT-010', content);
      const result = runHookIn(
        fixture,
        JSON.stringify({
          stop_hook_active: false,
          last_assistant_message: 'qa/test-results/QA-results-FEAT-010.md',
        })
      );
      expect(result.exitCode).toBe(2);
      expect(result.stderr).toMatch(/Reason|Exploratory/);
    });

    // 11
    it('11. exits 2 when PASS is missing the `## Execution Results` section', () => {
      fixture = mkdtempSync(join(tmpdir(), 'exec-qa-hook-'));
      setupStateFile(fixture);
      const content = passArtifact('FEAT-011').replace(
        /## Execution Results[\s\S]*?## Scenarios Run/,
        '## Scenarios Run'
      );
      writeResults(fixture, 'FEAT-011', content);
      const result = runHookIn(
        fixture,
        JSON.stringify({
          stop_hook_active: false,
          last_assistant_message: 'qa/test-results/QA-results-FEAT-011.md',
        })
      );
      expect(result.exitCode).toBe(2);
      expect(result.stderr).toContain('Execution Results');
    });

    // 12
    it('12. exits 0 regardless of artifact when stop_hook_active=true', () => {
      fixture = mkdtempSync(join(tmpdir(), 'exec-qa-hook-'));
      setupStateFile(fixture);
      // No artifact written.
      const result = runHookIn(
        fixture,
        JSON.stringify({
          stop_hook_active: true,
          last_assistant_message: 'anything',
        })
      );
      expect(result.exitCode).toBe(0);
      expect(existsSync(join(fixture, '.sdlc', 'qa', '.executing-active'))).toBe(false);
    });

    // Supplementary coverage beyond the 12 required cases.

    it('exits 2 when frontmatter is malformed (no closing `---`)', () => {
      fixture = mkdtempSync(join(tmpdir(), 'exec-qa-hook-'));
      setupStateFile(fixture);
      // Remove the closing `---` of the frontmatter block.
      const content = passArtifact('FEAT-013').replace(/(persona: qa)\n---/, '$1\n');
      writeResults(fixture, 'FEAT-013', content);
      const result = runHookIn(
        fixture,
        JSON.stringify({
          stop_hook_active: false,
          last_assistant_message: 'qa/test-results/QA-results-FEAT-013.md',
        })
      );
      expect(result.exitCode).toBe(2);
    });

    it('exits 2 when a required top-level section (## Summary) is missing', () => {
      fixture = mkdtempSync(join(tmpdir(), 'exec-qa-hook-'));
      setupStateFile(fixture);
      const content = passArtifact('FEAT-014').replace(
        /## Summary\n[\s\S]*?## Capability Report/,
        '## Capability Report'
      );
      writeResults(fixture, 'FEAT-014', content);
      const result = runHookIn(
        fixture,
        JSON.stringify({
          stop_hook_active: false,
          last_assistant_message: 'qa/test-results/QA-results-FEAT-014.md',
        })
      );
      expect(result.exitCode).toBe(2);
      expect(result.stderr).toContain('Summary');
    });

    it('exits 2 when the message declares a verdict but no artifact file exists', () => {
      fixture = mkdtempSync(join(tmpdir(), 'exec-qa-hook-'));
      setupStateFile(fixture);
      // No artifact is written; the message mentions a path.
      const result = runHookIn(
        fixture,
        JSON.stringify({
          stop_hook_active: false,
          last_assistant_message: 'verdict: PASS. Saved to qa/test-results/QA-results-FEAT-015.md.',
        })
      );
      expect(result.exitCode).toBe(2);
      expect(result.stderr).toContain('does not exist');
    });

    it('exits 2 when the artifact is missing `version: 2` in frontmatter', () => {
      fixture = mkdtempSync(join(tmpdir(), 'exec-qa-hook-'));
      setupStateFile(fixture);
      const content = passArtifact('FEAT-016').replace('version: 2\n', '');
      writeResults(fixture, 'FEAT-016', content);
      const result = runHookIn(
        fixture,
        JSON.stringify({
          stop_hook_active: false,
          last_assistant_message: 'qa/test-results/QA-results-FEAT-016.md',
        })
      );
      expect(result.exitCode).toBe(2);
      expect(result.stderr).toContain('version: 2');
    });

    it('exits 2 when PASS is missing a required counter field (Errored:)', () => {
      fixture = mkdtempSync(join(tmpdir(), 'exec-qa-hook-'));
      setupStateFile(fixture);
      const content = passArtifact('FEAT-017').replace(/- Errored: .*\n/, '');
      writeResults(fixture, 'FEAT-017', content);
      const result = runHookIn(
        fixture,
        JSON.stringify({
          stop_hook_active: false,
          last_assistant_message: 'qa/test-results/QA-results-FEAT-017.md',
        })
      );
      expect(result.exitCode).toBe(2);
      expect(result.stderr).toMatch(/Errored/);
    });

    it('exits 0 immediately when state file does not exist (skill not active)', () => {
      fixture = mkdtempSync(join(tmpdir(), 'exec-qa-hook-'));
      // No state file; no artifact.
      const result = runHookIn(
        fixture,
        JSON.stringify({
          stop_hook_active: false,
          last_assistant_message: 'whatever',
        })
      );
      expect(result.exitCode).toBe(0);
    });

    it('exits 0 on empty stdin', () => {
      fixture = mkdtempSync(join(tmpdir(), 'exec-qa-hook-'));
      setupStateFile(fixture);
      const result = runHookIn(fixture, '');
      expect(result.exitCode).toBe(0);
    });

    it('exits 0 on malformed JSON (guard prevents crashing)', () => {
      fixture = mkdtempSync(join(tmpdir(), 'exec-qa-hook-'));
      setupStateFile(fixture);
      const result = runHookIn(fixture, 'not json at all');
      expect([0, 2]).toContain(result.exitCode);
    });

    // Finding 1 — ISSUES-FOUND Findings-line regex must cover pytest + Go
    // output shapes in addition to vitest/jest (PR #172 code review).

    it('Finding 1: accepts pytest nodeid notation (module.py::test_name)', () => {
      fixture = mkdtempSync(join(tmpdir(), 'exec-qa-hook-'));
      setupStateFile(fixture);
      const content = issuesFoundArtifact('FEAT-F1A').replace(
        '- severity: high | dimension: Inputs | title: empty-input regression | test: qa-inputs.spec.ts',
        '- severity: high | dimension: Inputs | title: empty-input regression | test: tests/test_inputs.py::test_empty_input'
      );
      writeResults(fixture, 'FEAT-F1A', content);
      const result = runHookIn(
        fixture,
        JSON.stringify({
          stop_hook_active: false,
          last_assistant_message: 'qa/test-results/QA-results-FEAT-F1A.md',
        })
      );
      expect(result.exitCode).toBe(0);
    });

    it('Finding 1: accepts pytest class::method::test nodeid', () => {
      fixture = mkdtempSync(join(tmpdir(), 'exec-qa-hook-'));
      setupStateFile(fixture);
      const content = issuesFoundArtifact('FEAT-F1B').replace(
        '- severity: high | dimension: Inputs | title: empty-input regression | test: qa-inputs.spec.ts',
        '- severity: high | dimension: State transitions | title: race | test: tests/test_state.py::TestStateMachine::test_concurrent_writes'
      );
      writeResults(fixture, 'FEAT-F1B', content);
      const result = runHookIn(
        fixture,
        JSON.stringify({
          stop_hook_active: false,
          last_assistant_message: 'qa/test-results/QA-results-FEAT-F1B.md',
        })
      );
      expect(result.exitCode).toBe(0);
    });

    it('Finding 1: accepts Go --- FAIL: TestX verbose-output prefix', () => {
      fixture = mkdtempSync(join(tmpdir(), 'exec-qa-hook-'));
      setupStateFile(fixture);
      const content = issuesFoundArtifact('FEAT-F1C').replace(
        '- severity: high | dimension: Inputs | title: empty-input regression | test: qa-inputs.spec.ts',
        '- severity: high | dimension: Inputs | title: boundary overflow | output: --- FAIL: TestInputValidation'
      );
      writeResults(fixture, 'FEAT-F1C', content);
      const result = runHookIn(
        fixture,
        JSON.stringify({
          stop_hook_active: false,
          last_assistant_message: 'qa/test-results/QA-results-FEAT-F1C.md',
        })
      );
      expect(result.exitCode).toBe(0);
    });

    it('Finding 1: accepts Go "- FAIL TestX" list / summary form', () => {
      fixture = mkdtempSync(join(tmpdir(), 'exec-qa-hook-'));
      setupStateFile(fixture);
      const content = issuesFoundArtifact('FEAT-F1D').replace(
        '- severity: high | dimension: Inputs | title: empty-input regression | test: qa-inputs.spec.ts',
        '- severity: medium | dimension: Dependency failure | title: timeout cascade | output: FAIL TestCascadeTimeouts (subtest)'
      );
      writeResults(fixture, 'FEAT-F1D', content);
      const result = runHookIn(
        fixture,
        JSON.stringify({
          stop_hook_active: false,
          last_assistant_message: 'qa/test-results/QA-results-FEAT-F1D.md',
        })
      );
      expect(result.exitCode).toBe(0);
    });

    it('Finding 1: accepts _test.go filename fragment', () => {
      fixture = mkdtempSync(join(tmpdir(), 'exec-qa-hook-'));
      setupStateFile(fixture);
      const content = issuesFoundArtifact('FEAT-F1E').replace(
        '- severity: high | dimension: Inputs | title: empty-input regression | test: qa-inputs.spec.ts',
        '- severity: high | dimension: Inputs | title: off-by-one | file: qa/inputs_test.go'
      );
      writeResults(fixture, 'FEAT-F1E', content);
      const result = runHookIn(
        fixture,
        JSON.stringify({
          stop_hook_active: false,
          last_assistant_message: 'qa/test-results/QA-results-FEAT-F1E.md',
        })
      );
      expect(result.exitCode).toBe(0);
    });

    it('Finding 1: prose-only finding with no test reference is still rejected (negative control)', () => {
      fixture = mkdtempSync(join(tmpdir(), 'exec-qa-hook-'));
      setupStateFile(fixture);
      // Finding line has no filename fragment, no ::, no FAIL marker, no test: inline.
      const content = issuesFoundArtifact('FEAT-F1N').replace(
        '- severity: high | dimension: Inputs | title: empty-input regression | test: qa-inputs.spec.ts',
        '- severity: high | dimension: Inputs | something went wrong somewhere'
      );
      writeResults(fixture, 'FEAT-F1N', content);
      const result = runHookIn(
        fixture,
        JSON.stringify({
          stop_hook_active: false,
          last_assistant_message: 'qa/test-results/QA-results-FEAT-F1N.md',
        })
      );
      expect(result.exitCode).toBe(2);
      expect(result.stderr).toMatch(/Findings|failing/);
    });

    // Finding 3 — `## Scenarios Run` and `## Reconciliation Delta` are
    // declared required sections in SKILL.md but were not previously
    // enforced by the stop hook. Added unconditional require_section calls
    // and parametrize across all four verdict shapes (PR #172 code review).

    const removeScenariosRun = (content: string): string =>
      content.replace(/## Scenarios Run\n[\s\S]*?(?=## [A-Z])/, '');
    const removeReconciliationDelta = (content: string): string =>
      content.replace(/## Reconciliation Delta\n[\s\S]*?(?=## [A-Z]|$)/, '');

    it('Finding 3: PASS artifact missing `## Scenarios Run` is rejected', () => {
      fixture = mkdtempSync(join(tmpdir(), 'exec-qa-hook-'));
      setupStateFile(fixture);
      const content = removeScenariosRun(passArtifact('FEAT-F3A'));
      writeResults(fixture, 'FEAT-F3A', content);
      const result = runHookIn(
        fixture,
        JSON.stringify({
          stop_hook_active: false,
          last_assistant_message: 'qa/test-results/QA-results-FEAT-F3A.md',
        })
      );
      expect(result.exitCode).toBe(2);
      expect(result.stderr).toContain('Scenarios Run');
    });

    it('Finding 3: PASS artifact missing `## Reconciliation Delta` is rejected', () => {
      fixture = mkdtempSync(join(tmpdir(), 'exec-qa-hook-'));
      setupStateFile(fixture);
      const content = removeReconciliationDelta(passArtifact('FEAT-F3B'));
      writeResults(fixture, 'FEAT-F3B', content);
      const result = runHookIn(
        fixture,
        JSON.stringify({
          stop_hook_active: false,
          last_assistant_message: 'qa/test-results/QA-results-FEAT-F3B.md',
        })
      );
      expect(result.exitCode).toBe(2);
      expect(result.stderr).toContain('Reconciliation Delta');
    });

    it('Finding 3: ISSUES-FOUND artifact missing `## Scenarios Run` is rejected', () => {
      fixture = mkdtempSync(join(tmpdir(), 'exec-qa-hook-'));
      setupStateFile(fixture);
      const content = removeScenariosRun(issuesFoundArtifact('FEAT-F3C'));
      writeResults(fixture, 'FEAT-F3C', content);
      const result = runHookIn(
        fixture,
        JSON.stringify({
          stop_hook_active: false,
          last_assistant_message: 'qa/test-results/QA-results-FEAT-F3C.md',
        })
      );
      expect(result.exitCode).toBe(2);
      expect(result.stderr).toContain('Scenarios Run');
    });

    it('Finding 3: ISSUES-FOUND artifact missing `## Reconciliation Delta` is rejected', () => {
      fixture = mkdtempSync(join(tmpdir(), 'exec-qa-hook-'));
      setupStateFile(fixture);
      const content = removeReconciliationDelta(issuesFoundArtifact('FEAT-F3D'));
      writeResults(fixture, 'FEAT-F3D', content);
      const result = runHookIn(
        fixture,
        JSON.stringify({
          stop_hook_active: false,
          last_assistant_message: 'qa/test-results/QA-results-FEAT-F3D.md',
        })
      );
      expect(result.exitCode).toBe(2);
      expect(result.stderr).toContain('Reconciliation Delta');
    });

    it('Finding 3: ERROR artifact missing `## Scenarios Run` is rejected', () => {
      fixture = mkdtempSync(join(tmpdir(), 'exec-qa-hook-'));
      setupStateFile(fixture);
      const content = removeScenariosRun(errorArtifact('FEAT-F3E'));
      writeResults(fixture, 'FEAT-F3E', content);
      const result = runHookIn(
        fixture,
        JSON.stringify({
          stop_hook_active: false,
          last_assistant_message: 'qa/test-results/QA-results-FEAT-F3E.md',
        })
      );
      expect(result.exitCode).toBe(2);
      expect(result.stderr).toContain('Scenarios Run');
    });

    it('Finding 3: ERROR artifact missing `## Reconciliation Delta` is rejected', () => {
      fixture = mkdtempSync(join(tmpdir(), 'exec-qa-hook-'));
      setupStateFile(fixture);
      const content = removeReconciliationDelta(errorArtifact('FEAT-F3F'));
      writeResults(fixture, 'FEAT-F3F', content);
      const result = runHookIn(
        fixture,
        JSON.stringify({
          stop_hook_active: false,
          last_assistant_message: 'qa/test-results/QA-results-FEAT-F3F.md',
        })
      );
      expect(result.exitCode).toBe(2);
      expect(result.stderr).toContain('Reconciliation Delta');
    });

    it('Finding 3: EXPLORATORY-ONLY artifact missing `## Scenarios Run` is rejected', () => {
      fixture = mkdtempSync(join(tmpdir(), 'exec-qa-hook-'));
      setupStateFile(fixture);
      const content = removeScenariosRun(exploratoryArtifact('FEAT-F3G'));
      writeResults(fixture, 'FEAT-F3G', content);
      const result = runHookIn(
        fixture,
        JSON.stringify({
          stop_hook_active: false,
          last_assistant_message: 'qa/test-results/QA-results-FEAT-F3G.md',
        })
      );
      expect(result.exitCode).toBe(2);
      expect(result.stderr).toContain('Scenarios Run');
    });

    it('Finding 3: EXPLORATORY-ONLY artifact missing `## Reconciliation Delta` is rejected', () => {
      fixture = mkdtempSync(join(tmpdir(), 'exec-qa-hook-'));
      setupStateFile(fixture);
      const content = removeReconciliationDelta(exploratoryArtifact('FEAT-F3H'));
      writeResults(fixture, 'FEAT-F3H', content);
      const result = runHookIn(
        fixture,
        JSON.stringify({
          stop_hook_active: false,
          last_assistant_message: 'qa/test-results/QA-results-FEAT-F3H.md',
        })
      );
      expect(result.exitCode).toBe(2);
      expect(result.stderr).toContain('Reconciliation Delta');
    });

    it('Finding 3: edge case 7 — `## Reconciliation Delta` with skip-note body still passes', () => {
      // When no requirements doc exists (edge case 7), the skill emits the
      // `## Reconciliation Delta` section with a skip note under `### Summary`
      // rather than omitting it. The hook must accept this shape.
      fixture = mkdtempSync(join(tmpdir(), 'exec-qa-hook-'));
      setupStateFile(fixture);
      const content = exploratoryArtifact('FEAT-F3I').replace(
        /## Reconciliation Delta\n[\s\S]*?(?=## [A-Z])/,
        '## Reconciliation Delta\n### Summary\nReconciliation delta skipped: no requirements doc for FEAT-F3I\n\n'
      );
      writeResults(fixture, 'FEAT-F3I', content);
      const result = runHookIn(
        fixture,
        JSON.stringify({
          stop_hook_active: false,
          last_assistant_message: 'qa/test-results/QA-results-FEAT-F3I.md',
        })
      );
      expect(result.exitCode).toBe(0);
    });
  });

  describe('test results template (v1)', () => {
    it('should exist as assets/test-results-template.md', () => {
      expect(template).toBeDefined();
      expect(template.length).toBeGreaterThan(0);
    });

    it('should contain Metadata section', () => {
      expect(template).toContain('## Metadata');
    });

    it('should contain Test Suite Results section', () => {
      expect(template).toContain('## Test Suite Results');
    });

    it('should include verdict field in metadata', () => {
      expect(template).toContain('Verdict');
    });
  });

  describe('test results template (v2)', () => {
    it('should exist as assets/test-results-template-v2.md', () => {
      expect(templateV2).toBeDefined();
      expect(templateV2.length).toBeGreaterThan(0);
    });

    it('should declare version: 2 in frontmatter', () => {
      expect(templateV2).toMatch(/^---[\s\S]*?\nversion:\s*2\b/m);
    });

    it('should contain all required frontmatter fields (id, version, timestamp, verdict, persona)', () => {
      const frontmatterMatch = templateV2.match(/^---\s*\n([\s\S]*?)---/m);
      expect(frontmatterMatch).not.toBeNull();
      const fm = frontmatterMatch![1];
      expect(fm).toMatch(/\bid:/);
      expect(fm).toMatch(/\bversion:/);
      expect(fm).toMatch(/\btimestamp:/);
      expect(fm).toMatch(/\bverdict:/);
      expect(fm).toMatch(/\bpersona:/);
    });

    it('should document the version-1/version-2 split as an explanatory comment', () => {
      expect(templateV2).toContain('version 1');
      expect(templateV2).toContain('version 2');
    });

    it('should include Summary, Capability Report, Execution Results, Scenarios Run, Findings, Reconciliation Delta', () => {
      expect(templateV2).toContain('## Summary');
      expect(templateV2).toContain('## Capability Report');
      expect(templateV2).toContain('## Execution Results');
      expect(templateV2).toContain('## Scenarios Run');
      expect(templateV2).toContain('## Findings');
      expect(templateV2).toContain('## Reconciliation Delta');
    });

    it('should include the optional Exploratory Mode section', () => {
      expect(templateV2).toContain('## Exploratory Mode');
    });

    it('should enumerate the four allowed verdict values', () => {
      const content = templateV2;
      expect(content).toContain('PASS');
      expect(content).toContain('ISSUES-FOUND');
      expect(content).toContain('ERROR');
      expect(content).toContain('EXPLORATORY-ONLY');
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
