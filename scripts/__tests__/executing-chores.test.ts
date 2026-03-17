import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { validate, type DetailedValidateResult } from 'ai-skills-manager';

const SKILL_DIR = 'plugins/lwndev-sdlc/skills/executing-chores';
const SKILL_MD_PATH = join(SKILL_DIR, 'SKILL.md');
const PR_TEMPLATE_PATH = join(SKILL_DIR, 'assets', 'pr-template.md');
const WORKFLOW_PATH = join(SKILL_DIR, 'references', 'workflow-details.md');
const GITHUB_TEMPLATES_PATH = join(SKILL_DIR, 'references', 'github-templates.md');

describe('executing-chores skill', () => {
  let skillMd: string;
  let prTemplate: string;
  let workflow: string;
  let githubTemplates: string;

  beforeAll(async () => {
    skillMd = await readFile(SKILL_MD_PATH, 'utf-8');
    prTemplate = await readFile(PR_TEMPLATE_PATH, 'utf-8');
    workflow = await readFile(WORKFLOW_PATH, 'utf-8');
    githubTemplates = await readFile(GITHUB_TEMPLATES_PATH, 'utf-8');
  });

  describe('SKILL.md', () => {
    it('should have frontmatter with name: executing-chores', () => {
      expect(skillMd).toMatch(/^---\s*\n[\s\S]*?name:\s*executing-chores[\s\S]*?---/);
    });

    it('should have frontmatter with non-empty description', () => {
      const match = skillMd.match(/^---\s*\n[\s\S]*?description:\s*(.+)[\s\S]*?---/);
      expect(match).not.toBeNull();
      expect(match![1].trim().length).toBeGreaterThan(0);
    });

    it('should include "When to Use This Skill" section', () => {
      expect(skillMd).toContain('## When to Use This Skill');
    });

    it('should include "Quick Start" section', () => {
      expect(skillMd).toContain('## Quick Start');
    });

    it('should include "Verification Checklist" section', () => {
      expect(skillMd).toContain('## Verification Checklist');
    });

    it('should include "Relationship to Other Skills" section', () => {
      expect(skillMd).toContain('## Relationship to Other Skills');
    });

    it('should reference documenting-chores as prerequisite skill', () => {
      expect(skillMd).toContain('documenting-chores');
    });

    it('should specify chore/CHORE-XXX branch naming format', () => {
      expect(skillMd).toContain('chore/CHORE-XXX');
    });

    it('should specify chore(category): commit message format', () => {
      expect(skillMd).toMatch(/chore\(category\):/);
    });

    it('should document that PR body must include Closes #N when GitHub issue exists', () => {
      expect(skillMd).toContain('Closes #N');
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

  describe('PR template', () => {
    it('should exist as assets/pr-template.md', () => {
      expect(prTemplate).toBeDefined();
      expect(prTemplate.length).toBeGreaterThan(0);
    });

    it('should include Closes #N placeholder', () => {
      expect(prTemplate).toContain('Closes #N');
    });
  });

  describe('workflow details', () => {
    it('should exist as references/workflow-details.md', () => {
      expect(workflow).toBeDefined();
      expect(workflow.length).toBeGreaterThan(0);
    });
  });

  describe('GitHub templates', () => {
    it('should exist as references/github-templates.md', () => {
      expect(githubTemplates).toBeDefined();
      expect(githubTemplates.length).toBeGreaterThan(0);
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
