import { describe, it, expect, beforeAll } from 'vitest';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { validate, type DetailedValidateResult } from 'ai-skills-manager';

const SKILL_DIR = 'plugins/lwndev-sdlc/skills/documenting-qa';
const SKILL_MD_PATH = join(SKILL_DIR, 'SKILL.md');
const TEMPLATE_PATH = join(SKILL_DIR, 'assets', 'test-plan-template.md');

describe('documenting-qa skill', () => {
  let skillMd: string;
  let template: string;

  beforeAll(async () => {
    skillMd = await readFile(SKILL_MD_PATH, 'utf-8');
    template = await readFile(TEMPLATE_PATH, 'utf-8');
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

    it('should reference implementation plans for FEAT IDs', () => {
      expect(skillMd).toContain('requirements/implementation/');
    });

    it('should specify test plan output path format', () => {
      expect(skillMd).toContain('qa/test-plans/QA-plan-');
    });

    it('should document qa-verifier subagent delegation', () => {
      expect(skillMd).toContain('qa-verifier');
    });

    it('should document the ralph loop pattern', () => {
      expect(skillMd).toContain('attempt to finish');
      expect(skillMd).toContain('Stop hook');
    });
  });

  describe('allowed-tools', () => {
    it('should have allowed-tools in frontmatter', () => {
      expect(skillMd).toMatch(/^---\s*\n[\s\S]*?allowed-tools:[\s\S]*?---/);
    });

    it('should include Read, Write, Edit, Glob, Grep, Agent', () => {
      const frontmatter = skillMd.match(/^---\s*\n([\s\S]*?)---/)?.[1] ?? '';
      expect(frontmatter).toContain('- Read');
      expect(frontmatter).toContain('- Write');
      expect(frontmatter).toContain('- Edit');
      expect(frontmatter).toContain('- Glob');
      expect(frontmatter).toContain('- Grep');
      expect(frontmatter).toContain('- Agent');
    });

    it('should NOT include Bash', () => {
      const frontmatter = skillMd.match(/^---\s*\n([\s\S]*?)---/)?.[1] ?? '';
      expect(frontmatter).not.toContain('- Bash');
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
  });

  describe('test plan template', () => {
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

    it('should include Status column in New Test Analysis table', () => {
      expect(template).toMatch(/## New Test Analysis[\s\S]*?\| .* \| Status \|/);
    });

    it('should include Status column in Code Path Verification table', () => {
      expect(template).toMatch(/## Code Path Verification[\s\S]*?\| .* \| Status \|/);
    });

    it('should include Status column in Deliverable Verification table', () => {
      expect(template).toMatch(/## Deliverable Verification[\s\S]*?\| .* \| Status \|/);
    });

    it('should not have Exists column in Deliverable Verification table', () => {
      expect(template).not.toMatch(/## Deliverable Verification[\s\S]*?\| .* \| Exists \|/);
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
