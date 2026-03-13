import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { validate, type DetailedValidateResult } from 'ai-skills-manager';

const SKILL_DIR = 'src/skills/documenting-chores';
const SKILL_MD_PATH = join(SKILL_DIR, 'SKILL.md');
const TEMPLATE_PATH = join(SKILL_DIR, 'assets', 'chore-document.md');
const CATEGORIES_PATH = join(SKILL_DIR, 'references', 'categories.md');

describe('documenting-chores skill', () => {
  let skillMd: string;
  let template: string;
  let categories: string;

  beforeAll(async () => {
    skillMd = await readFile(SKILL_MD_PATH, 'utf-8');
    template = await readFile(TEMPLATE_PATH, 'utf-8');
    categories = await readFile(CATEGORIES_PATH, 'utf-8');
  });

  describe('SKILL.md', () => {
    it('should have frontmatter with name: documenting-chores', () => {
      expect(skillMd).toMatch(/^---\s*\n[\s\S]*?name:\s*documenting-chores[\s\S]*?---/);
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

    it('should reference executing-chores as follow-up skill', () => {
      expect(skillMd).toContain('executing-chores');
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

  describe('chore document template', () => {
    it('should exist as assets/chore-document.md', () => {
      expect(template).toBeDefined();
      expect(template.length).toBeGreaterThan(0);
    });
  });

  describe('categories reference', () => {
    it('should exist as references/categories.md', () => {
      expect(categories).toBeDefined();
      expect(categories.length).toBeGreaterThan(0);
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
