import { describe, it, expect, beforeAll } from 'vitest';
import { readFile, access } from 'node:fs/promises';
import { join } from 'node:path';
import { validate, type DetailedValidateResult } from 'ai-skills-manager';

const SKILL_DIR = 'plugins/lwndev-sdlc/skills/implementing-plan-phases';
const SKILL_MD_PATH = join(SKILL_DIR, 'SKILL.md');
const WORKFLOW_EXAMPLE_PATH = join(SKILL_DIR, 'references', 'workflow-example.md');
const GITHUB_TEMPLATES_PATH = join(SKILL_DIR, 'references', 'github-templates.md');
const STEP_DETAILS_PATH = join(SKILL_DIR, 'references', 'step-details.md');
const PR_TEMPLATE_PATH = join(SKILL_DIR, 'assets', 'pr-template.md');

describe('implementing-plan-phases skill', () => {
  let skillMd: string;
  let workflowExample: string;
  let stepDetails: string;
  let prTemplate: string;

  beforeAll(async () => {
    skillMd = await readFile(SKILL_MD_PATH, 'utf-8');
    workflowExample = await readFile(WORKFLOW_EXAMPLE_PATH, 'utf-8');
    stepDetails = await readFile(STEP_DETAILS_PATH, 'utf-8');
    prTemplate = await readFile(PR_TEMPLATE_PATH, 'utf-8');
  });

  describe('SKILL.md', () => {
    it('should have frontmatter with name: implementing-plan-phases', () => {
      expect(skillMd).toMatch(/^---\s*\n[\s\S]*?name:\s*implementing-plan-phases[\s\S]*?---/);
    });

    it('should have frontmatter with non-empty description', () => {
      const match = skillMd.match(/^---\s*\n[\s\S]*?description:\s*(.+)[\s\S]*?---/);
      expect(match).not.toBeNull();
      expect(match![1].trim().length).toBeGreaterThan(0);
    });

    it('should not mention GitHub issue comments in description frontmatter', () => {
      const frontmatter = skillMd.match(/^---\s*\n([\s\S]*?)---/)?.[1] ?? '';
      expect(frontmatter).not.toContain('GitHub issue comments');
    });

    it('should include "When to Use" section', () => {
      expect(skillMd).toContain('## When to Use');
    });

    it('should include "Quick Start" section', () => {
      expect(skillMd).toContain('## Quick Start');
    });

    it('should include "Verification" section', () => {
      expect(skillMd).toContain('## Verification');
    });

    it('should specify feat/{Feature ID} branch naming format', () => {
      expect(skillMd).toContain('feat/{Feature ID}');
    });

    it('should document status tracking workflow', () => {
      expect(skillMd).toContain('🔄 In Progress');
      expect(skillMd).toContain('✅ Complete');
    });

    it('should include PR creation step after all phases complete', () => {
      expect(skillMd).toContain('**After all phases complete:** Create pull request');
      expect(skillMd).toContain('Closes #N');
    });

    it('should not contain inline gh issue comment instructions', () => {
      expect(skillMd).not.toContain('gh issue comment');
    });

    it('should contain delegation note referencing managing-work-items', () => {
      expect(skillMd).toContain('managing-work-items');
      expect(skillMd).toContain(
        'Issue tracking (start/completion comments) is handled by the orchestrator'
      );
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

  describe('references', () => {
    it('should have workflow-example.md', () => {
      expect(workflowExample).toBeDefined();
      expect(workflowExample.length).toBeGreaterThan(0);
    });

    it('should no longer have github-templates.md', async () => {
      await expect(access(GITHUB_TEMPLATES_PATH)).rejects.toThrow();
    });

    it('should have step-details.md', () => {
      expect(stepDetails).toBeDefined();
      expect(stepDetails.length).toBeGreaterThan(0);
    });

    it('should not reference github-templates.md in SKILL.md', () => {
      expect(skillMd).not.toContain('github-templates.md');
    });
  });

  describe('assets', () => {
    it('should have pr-template.md', () => {
      expect(prTemplate).toBeDefined();
      expect(prTemplate.length).toBeGreaterThan(0);
    });

    it('should include implementation plan link in PR template', () => {
      expect(prTemplate).toContain('Implementation Plan');
    });

    it('should include Closes #N in PR template', () => {
      expect(prTemplate).toContain('Closes #N');
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
