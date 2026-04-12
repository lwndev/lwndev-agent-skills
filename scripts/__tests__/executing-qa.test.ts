import { describe, it, expect, beforeAll, afterEach } from 'vitest';
import { execSync } from 'node:child_process';
import { readFile, access } from 'node:fs/promises';
import { constants, mkdirSync, writeFileSync, rmSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { validate, type DetailedValidateResult } from 'ai-skills-manager';

const SKILL_DIR = 'plugins/lwndev-sdlc/skills/executing-qa';
const SKILL_MD_PATH = join(SKILL_DIR, 'SKILL.md');
const TEMPLATE_PATH = join(SKILL_DIR, 'assets', 'test-results-template.md');
const STOP_HOOK_PATH = join(SKILL_DIR, 'scripts', 'stop-hook.sh');

describe('executing-qa skill', () => {
  let skillMd: string;
  let template: string;

  beforeAll(async () => {
    skillMd = await readFile(SKILL_MD_PATH, 'utf-8');
    template = await readFile(TEMPLATE_PATH, 'utf-8');
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

    it('should document qa-verifier subagent delegation', () => {
      expect(skillMd).toContain('qa-verifier');
    });

    it('should document the verification ralph loop', () => {
      expect(skillMd).toContain('Verification Ralph Loop');
    });

    it('should document the reconciliation loop', () => {
      expect(skillMd).toContain('Reconciliation Loop');
    });

    it('should document fix behavior for failed entries', () => {
      expect(skillMd).toContain('Fix issues');
    });

    it('should document preservation rules for existing documents', () => {
      expect(skillMd).toContain('Preservation Rules');
    });
  });

  describe('allowed-tools', () => {
    it('should have allowed-tools in frontmatter', () => {
      expect(skillMd).toMatch(/^---\s*\n[\s\S]*?allowed-tools:[\s\S]*?---/);
    });

    it('should include Read, Write, Edit, Bash, Glob, Grep, Agent', () => {
      const frontmatter = skillMd.match(/^---\s*\n([\s\S]*?)---/)?.[1] ?? '';
      expect(frontmatter).toContain('- Read');
      expect(frontmatter).toContain('- Write');
      expect(frontmatter).toContain('- Edit');
      expect(frontmatter).toContain('- Bash');
      expect(frontmatter).toContain('- Glob');
      expect(frontmatter).toContain('- Grep');
      expect(frontmatter).toContain('- Agent');
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

  describe('stop hook behavior', () => {
    const STATE_FILE = '.sdlc/qa/.executing-active';

    function runHook(stdinJson: string): { exitCode: number; stderr: string } {
      try {
        execSync(`echo '${stdinJson.replace(/'/g, "'\\''")}' | bash ${STOP_HOOK_PATH}`, {
          encoding: 'utf-8',
          stdio: ['pipe', 'pipe', 'pipe'],
        });
        return { exitCode: 0, stderr: '' };
      } catch (err: unknown) {
        const e = err as { status: number; stderr?: string };
        return { exitCode: e.status, stderr: e.stderr ?? '' };
      }
    }

    function createStateFile(): void {
      mkdirSync('.sdlc/qa', { recursive: true });
      writeFileSync(STATE_FILE, '');
    }

    function removeStateFile(): void {
      try {
        rmSync(STATE_FILE);
      } catch {
        // ignore if not present
      }
    }

    afterEach(() => {
      removeStateFile();
    });

    it('exits 0 immediately when state file does not exist (skill not active)', () => {
      removeStateFile();
      const result = runHook(
        JSON.stringify({
          stop_hook_active: false,
          last_assistant_message: 'I am reading the test plan.',
        })
      );
      expect(result.exitCode).toBe(0);
    });

    it('exits 2 when state file is present and keywords are absent', () => {
      createStateFile();
      const result = runHook(
        JSON.stringify({
          stop_hook_active: false,
          last_assistant_message: 'I am reading the test plan.',
        })
      );
      expect(result.exitCode).toBe(2);
    });

    it('exits 0 and removes state file when state file is present and keywords match', () => {
      createStateFile();
      const result = runHook(
        JSON.stringify({
          stop_hook_active: false,
          last_assistant_message:
            'QA verification passed with all entries clean. Documentation reconciliation is complete. Results saved to qa/test-results/QA-results-FEAT-003.md.',
        })
      );
      expect(result.exitCode).toBe(0);
      expect(existsSync(STATE_FILE)).toBe(false);
    });

    it('exits 0 and removes state file when stop_hook_active is true', () => {
      createStateFile();
      const result = runHook(
        JSON.stringify({ stop_hook_active: true, last_assistant_message: '' })
      );
      expect(result.exitCode).toBe(0);
      expect(existsSync(STATE_FILE)).toBe(false);
    });

    it('exits 0 when both verification and reconciliation are complete', () => {
      createStateFile();
      const result = runHook(
        JSON.stringify({
          stop_hook_active: false,
          last_assistant_message:
            'QA verification passed with all entries clean. Documentation reconciliation is complete. Results saved to qa/test-results/QA-results-FEAT-003.md.',
        })
      );
      expect(result.exitCode).toBe(0);
    });

    it('exits 2 when only verification is complete (no reconciliation)', () => {
      createStateFile();
      const result = runHook(
        JSON.stringify({
          stop_hook_active: false,
          last_assistant_message: 'QA verification passed. Now starting reconciliation.',
        })
      );
      expect(result.exitCode).toBe(2);
      expect(result.stderr).toContain('reconciliation');
    });

    it('exits 2 when only reconciliation is complete (no verification)', () => {
      createStateFile();
      const result = runHook(
        JSON.stringify({
          stop_hook_active: false,
          last_assistant_message: 'Documentation reconciliation is complete.',
        })
      );
      expect(result.exitCode).toBe(2);
      expect(result.stderr).toContain('verification');
    });

    it('exits 0 when results file is mentioned with verification indicator', () => {
      createStateFile();
      const result = runHook(
        JSON.stringify({
          stop_hook_active: false,
          last_assistant_message: 'All entries passed verification. Saved QA-results-FEAT-003.md.',
        })
      );
      expect(result.exitCode).toBe(0);
    });

    it('exits 2 when neither verification nor reconciliation is detected', () => {
      createStateFile();
      const result = runHook(
        JSON.stringify({
          stop_hook_active: false,
          last_assistant_message: 'I am reading the test plan.',
        })
      );
      expect(result.exitCode).toBe(2);
    });

    it('exits 0 on empty stdin', () => {
      createStateFile();
      const result = runHook('');
      expect(result.exitCode).toBe(0);
    });

    it('exits 0 on malformed JSON', () => {
      createStateFile();
      const result = runHook('not json at all');
      expect(result.exitCode).toBe(0);
    });

    it('script checks for both verification and reconciliation patterns', async () => {
      const scriptContent = await readFile(STOP_HOOK_PATH, 'utf-8');
      expect(scriptContent).toContain('HAS_VERIFICATION');
      expect(scriptContent).toContain('HAS_RECONCILIATION');
    });
  });

  describe('test results template', () => {
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

    it('should contain Per-Entry Verification Results section', () => {
      expect(template).toContain('## Per-Entry Verification Results');
    });

    it('should have NTA-mirrored columns in Per-Entry Verification Results', () => {
      expect(template).toMatch(
        /## Per-Entry Verification Results[\s\S]*?\| # \| Test Description \| Target File\(s\) \| Requirement Ref \| Result \| Notes \|/
      );
    });

    it('should contain Issues Found and Fixed section', () => {
      expect(template).toContain('## Issues Found and Fixed');
    });

    it('should contain Reconciliation Summary section', () => {
      expect(template).toContain('## Reconciliation Summary');
    });

    it('should contain Deviation Notes section', () => {
      expect(template).toContain('## Deviation Notes');
    });

    it('should include verdict field in metadata', () => {
      expect(template).toContain('Verdict');
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
