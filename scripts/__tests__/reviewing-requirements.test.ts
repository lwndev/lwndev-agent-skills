import { describe, it, expect, beforeAll } from 'vitest';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { validate, type DetailedValidateResult } from 'ai-skills-manager';

const SKILL_DIR = 'plugins/lwndev-sdlc/skills/reviewing-requirements';
const SKILL_MD_PATH = join(SKILL_DIR, 'SKILL.md');
const TEMPLATE_PATH = join(SKILL_DIR, 'assets', 'review-findings-template.md');

describe('reviewing-requirements skill', () => {
  let skillMd: string;
  let template: string;

  beforeAll(async () => {
    skillMd = await readFile(SKILL_MD_PATH, 'utf-8');
    template = await readFile(TEMPLATE_PATH, 'utf-8');
  });

  describe('SKILL.md', () => {
    it('should have frontmatter with name: reviewing-requirements', () => {
      expect(skillMd).toMatch(/^---\s*\n[\s\S]*?name:\s*reviewing-requirements[\s\S]*?---/);
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

    it('should document ID parsing for FEAT, CHORE, and BUG types', () => {
      expect(skillMd).toContain('FEAT-');
      expect(skillMd).toContain('CHORE-');
      expect(skillMd).toContain('BUG-');
    });

    it('should document requirement directory paths', () => {
      expect(skillMd).toContain('requirements/features/');
      expect(skillMd).toContain('requirements/chores/');
      expect(skillMd).toContain('requirements/bugs/');
      expect(skillMd).toContain('requirements/implementation/');
    });
  });

  describe('three-mode documentation', () => {
    it('should mention all three modes in frontmatter description', () => {
      const frontmatter = skillMd.match(/^---\s*\n([\s\S]*?)---/)?.[1] ?? '';
      expect(frontmatter).toContain('standard review');
      expect(frontmatter).toContain('test-plan reconciliation');
      expect(frontmatter).toContain('code-review reconciliation');
    });

    it('should document standard review mode', () => {
      expect(skillMd).toContain('Standard review');
      expect(skillMd).toContain('Steps 2-9');
    });

    it('should document test-plan reconciliation mode', () => {
      expect(skillMd).toContain('## Test-Plan Reconciliation Mode');
      expect(skillMd).toContain('R1');
      expect(skillMd).toContain('Step R7');
    });

    it('should document code-review reconciliation mode', () => {
      expect(skillMd).toContain('## Code-Review Reconciliation Mode');
      expect(skillMd).toContain('CR1');
      expect(skillMd).toContain('Step CR5');
    });

    it('should document mode detection with precedence rule', () => {
      expect(skillMd).toContain('## Step 1.5: Detect Review Mode');
      // FEAT-026 FR-7: precedence now enforced by detect-review-mode.sh script.
      // SKILL.md describes the chain via the script pointer.
      expect(skillMd).toContain('mode precedence chain');
    });

    it('should include mode detection table with all three modes', () => {
      expect(skillMd).toContain('| Standard review |');
      expect(skillMd).toContain('| Test-plan reconciliation |');
      expect(skillMd).toContain('| Code-review reconciliation |');
    });
  });

  describe('code-review reconciliation content', () => {
    it('should document PR detection via detect-review-mode.sh script', () => {
      // FEAT-026 FR-7: branch-naming patterns now live inside detect-review-mode.sh.
      // SKILL.md references the script; the patterns are covered by the script's bats tests.
      expect(skillMd).toContain('detect-review-mode.sh');
      expect(skillMd).toContain('open PR via `gh`');
    });

    it('should document --pr flag support', () => {
      expect(skillMd).toContain('--pr <number>');
    });

    it('should document scope boundary with executing-qa', () => {
      expect(skillMd).toMatch(/[Ee]ntirely advisory/);
      expect(skillMd).toMatch(/[Dd]oes NOT update affected files/);
    });

    it('should document three finding categories', () => {
      expect(skillMd).toContain('Test Plan Staleness');
      expect(skillMd).toContain('GitHub Issue Suggestions');
      expect(skillMd).toMatch(/Requirements\s*↔\s*Code\s*Drift/);
    });

    it('should document severity classification for CR findings', () => {
      // FEAT-026 FR-7: CR staleness severity now expressed as a mapping in the
      // Steps CR1-CR2 script pointer.
      expect(skillMd).toMatch(/signature-changed.*\*\*Error\*\*/);
      expect(skillMd).toContain('**Warning** for drift findings');
    });

    it('should document graceful skip when gh unavailable', () => {
      // FEAT-026 FR-7: pr-diff-vs-plan.sh replaces the git-diff fallback with a
      // graceful-skip contract (exit 0 + [warn] + empty stdout when gh is down).
      expect(skillMd).toContain('graceful skip');
    });

    it('should have verification checklist for code-review reconciliation', () => {
      expect(skillMd).toContain('### Code-Review Reconciliation');
      expect(skillMd).toContain('PR detected and mode entered correctly');
      expect(skillMd).toContain('Scope boundary respected');
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

  describe('review findings template', () => {
    it('should exist as assets/review-findings-template.md', () => {
      expect(template).toBeDefined();
      expect(template.length).toBeGreaterThan(0);
    });

    it('should contain error/warning/info severity sections', () => {
      expect(template).toContain('### Errors');
      expect(template).toContain('### Warnings');
      expect(template).toContain('### Info');
    });

    it('should contain finding format section', () => {
      expect(template).toMatch(/[Ff]inding/);
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
