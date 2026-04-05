import { describe, it, expect, beforeAll } from 'vitest';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { validate, type DetailedValidateResult } from 'ai-skills-manager';

const SKILL_DIR = 'plugins/lwndev-sdlc/skills/documenting-features';
const SKILL_MD_PATH = join(SKILL_DIR, 'SKILL.md');
const TEMPLATE_PATH = join(SKILL_DIR, 'assets', 'feature-requirements.md');

describe('documenting-features skill', () => {
  let skillMd: string;
  let template: string;

  beforeAll(async () => {
    skillMd = await readFile(SKILL_MD_PATH, 'utf-8');
    template = await readFile(TEMPLATE_PATH, 'utf-8');
  });

  describe('SKILL.md', () => {
    it('should have frontmatter with name: documenting-features', () => {
      expect(skillMd).toMatch(/^---\s*\n[\s\S]*?name:\s*documenting-features[\s\S]*?---/);
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

    it('should specify requirements/features/ as file location', () => {
      expect(skillMd).toContain('requirements/features/');
    });
  });

  describe('allowed-tools', () => {
    it('should have allowed-tools in frontmatter', () => {
      expect(skillMd).toMatch(/^---\s*\n[\s\S]*?allowed-tools:[\s\S]*?---/);
    });

    it('should include Read, Write, Edit, Glob, Grep', () => {
      const frontmatter = skillMd.match(/^---\s*\n([\s\S]*?)---/)?.[1] ?? '';
      expect(frontmatter).toContain('- Read');
      expect(frontmatter).toContain('- Write');
      expect(frontmatter).toContain('- Edit');
      expect(frontmatter).toContain('- Glob');
      expect(frontmatter).toContain('- Grep');
    });

    it('should NOT include Bash or Agent', () => {
      const frontmatter = skillMd.match(/^---\s*\n([\s\S]*?)---/)?.[1] ?? '';
      expect(frontmatter).not.toContain('- Bash');
      expect(frontmatter).not.toContain('- Agent');
    });
  });

  describe('feature requirements template', () => {
    it('should exist as assets/feature-requirements.md', () => {
      expect(template).toBeDefined();
      expect(template.length).toBeGreaterThan(0);
    });
  });

  describe('issue fetch delegation', () => {
    it('should accept #N argument format for issue references', () => {
      expect(skillMd).toMatch(/#<number>/);
      expect(skillMd).toContain('#14');
    });

    it('should delegate issue fetch to managing-work-items skill', () => {
      expect(skillMd).toContain('managing-work-items');
      expect(skillMd).toMatch(/managing-work-items fetch/);
    });

    it('should not reference direct gh CLI usage for issue fetch', () => {
      // The skill does not have Bash in allowed-tools, so it cannot call gh directly.
      // Issue fetch is delegated to managing-work-items which has Bash.
      expect(skillMd).not.toMatch(/`gh issue view/);
      expect(skillMd).not.toMatch(/`gh api/);
    });

    it('should maintain graceful degradation when fetch fails', () => {
      expect(skillMd).toMatch(/warn.*continue with manual input/i);
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
