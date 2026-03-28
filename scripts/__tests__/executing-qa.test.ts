import { describe, it, expect, beforeAll } from 'vitest';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { validate, type DetailedValidateResult } from 'ai-skills-manager';

const SKILL_DIR = 'plugins/lwndev-sdlc/skills/executing-qa';
const SKILL_MD_PATH = join(SKILL_DIR, 'SKILL.md');
const TEMPLATE_PATH = join(SKILL_DIR, 'assets', 'test-results-template.md');

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

    it('should document auto-fix behavior', () => {
      expect(skillMd).toContain('Auto-fix');
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

    it('should use type: prompt for the stop hook', () => {
      const frontmatter = skillMd.match(/^---\s*\n([\s\S]*?)---/)?.[1] ?? '';
      expect(frontmatter).toContain('type: prompt');
    });

    it('should use haiku model for the stop hook', () => {
      const frontmatter = skillMd.match(/^---\s*\n([\s\S]*?)---/)?.[1] ?? '';
      expect(frontmatter).toContain('model: haiku');
    });

    it('should check stop_hook_active to prevent infinite loops', () => {
      const frontmatter = skillMd.match(/^---\s*\n([\s\S]*?)---/)?.[1] ?? '';
      expect(frontmatter).toContain('stop_hook_active');
    });

    it('should handle both verification and reconciliation phases', () => {
      const frontmatter = skillMd.match(/^---\s*\n([\s\S]*?)---/)?.[1] ?? '';
      expect(frontmatter).toContain('QA verification');
      expect(frontmatter).toContain('reconciliation');
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

    it('should contain Coverage Analysis section', () => {
      expect(template).toContain('## Coverage Analysis');
    });

    it('should contain Code Path Verification Results section', () => {
      expect(template).toContain('## Code Path Verification Results');
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
