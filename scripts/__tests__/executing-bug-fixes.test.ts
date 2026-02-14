import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { validate, type DetailedValidateResult } from 'ai-skills-manager';

const SKILL_DIR = 'src/skills/executing-bug-fixes';
const SKILL_MD_PATH = join(SKILL_DIR, 'SKILL.md');
const PR_TEMPLATE_PATH = join(SKILL_DIR, 'assets', 'pr-template.md');
const WORKFLOW_PATH = join(SKILL_DIR, 'references', 'workflow-details.md');
const GITHUB_TEMPLATES_PATH = join(SKILL_DIR, 'references', 'github-templates.md');

describe('executing-bug-fixes skill', () => {
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
    it('should have frontmatter with name: executing-bug-fixes', () => {
      expect(skillMd).toMatch(/^---\s*\n[\s\S]*?name:\s*executing-bug-fixes[\s\S]*?---/);
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

    it('should reference documenting-bugs as prerequisite skill', () => {
      expect(skillMd).toContain('documenting-bugs');
    });

    it('should specify fix/BUG-XXX branch naming format', () => {
      expect(skillMd).toContain('fix/BUG-XXX');
    });

    it('should specify fix(category): commit message format', () => {
      expect(skillMd).toMatch(/fix\(category\):/);
    });

    it('should document root cause driven execution', () => {
      expect(skillMd).toContain('Root Cause Driven Execution');
      expect(skillMd).toContain('Redeclare root causes');
      expect(skillMd).toContain('Address root causes systematically');
      expect(skillMd).toContain('Verify per root cause');
    });

    it('should document that PR body must include Closes #N when GitHub issue exists', () => {
      expect(skillMd).toContain('Closes #N');
    });
  });

  describe('PR template', () => {
    it('should exist as assets/pr-template.md', () => {
      expect(prTemplate).toBeDefined();
      expect(prTemplate.length).toBeGreaterThan(0);
    });

    it('should contain Root Cause(s) section', () => {
      expect(prTemplate).toContain('Root Cause(s)');
    });

    it('should contain How Each Root Cause Was Addressed traceability table', () => {
      expect(prTemplate).toContain('How Each Root Cause Was Addressed');
      expect(prTemplate).toContain('| RC | Fix Applied | Files Changed |');
    });

    it('should include per-root-cause verification items in testing checklist', () => {
      expect(prTemplate).toMatch(/RC-\d+ acceptance criteria verified/);
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

    it('should contain Phase 1 (Initialization)', () => {
      expect(workflow).toContain('Phase 1: Initialization');
    });

    it('should contain Phase 2 (Execution)', () => {
      expect(workflow).toContain('Phase 2: Execution');
    });

    it('should contain Phase 3 (Completion)', () => {
      expect(workflow).toContain('Phase 3: Completion');
    });

    it('should include redeclaring root causes from bug document in Phase 1', () => {
      // Extract Phase 1 section using the heading (skip TOC links)
      const phase1Start = workflow.indexOf('## Phase 1: Initialization');
      const phase2Start = workflow.indexOf('## Phase 2: Execution');
      const phase1 = workflow.slice(phase1Start, phase2Start);
      expect(phase1).toMatch(/[Rr]edeclare [Rr]oot [Cc]ause/);
    });

    it('should include verifying reproduction steps no longer trigger the bug', () => {
      expect(workflow).toMatch(/reproduction steps.*no longer/i);
    });
  });

  describe('GitHub templates', () => {
    it('should exist as references/github-templates.md', () => {
      expect(githubTemplates).toBeDefined();
      expect(githubTemplates.length).toBeGreaterThan(0);
    });

    it('should contain starting work comment template with root causes', () => {
      expect(githubTemplates).toContain('Starting Work Comment');
      expect(githubTemplates).toContain('Root Causes to Address');
    });

    it('should contain completion comment template with per-RC resolution status', () => {
      expect(githubTemplates).toContain('Work Complete Comment');
      expect(githubTemplates).toContain('Root Cause Resolution');
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
