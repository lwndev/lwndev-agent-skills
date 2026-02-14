import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { validate, type DetailedValidateResult } from 'ai-skills-manager';

const SKILL_DIR = 'src/skills/documenting-bugs';
const SKILL_MD_PATH = join(SKILL_DIR, 'SKILL.md');
const TEMPLATE_PATH = join(SKILL_DIR, 'assets', 'bug-document.md');
const CATEGORIES_PATH = join(SKILL_DIR, 'references', 'categories.md');

describe('documenting-bugs skill', () => {
  let skillMd: string;
  let template: string;
  let categories: string;

  beforeAll(async () => {
    skillMd = await readFile(SKILL_MD_PATH, 'utf-8');
    template = await readFile(TEMPLATE_PATH, 'utf-8');
    categories = await readFile(CATEGORIES_PATH, 'utf-8');
  });

  describe('SKILL.md', () => {
    it('should have frontmatter with name: documenting-bugs', () => {
      expect(skillMd).toMatch(/^---\s*\n[\s\S]*?name:\s*documenting-bugs[\s\S]*?---/);
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

    it('should reference executing-bug-fixes as follow-up skill', () => {
      expect(skillMd).toContain('executing-bug-fixes');
    });

    it('should specify requirements/bugs/ as file location', () => {
      expect(skillMd).toContain('requirements/bugs/');
    });

    it('should specify BUG-XXX naming format', () => {
      expect(skillMd).toContain('BUG-XXX');
    });
  });

  describe('bug document template', () => {
    const requiredSections = [
      'Bug ID',
      'GitHub Issue',
      'Category',
      'Severity',
      'Description',
      'Steps to Reproduce',
      'Expected Behavior',
      'Actual Behavior',
      'Root Cause(s)',
      'Affected Files',
      'Acceptance Criteria',
      'Completion',
      'Notes',
    ];

    it.each(requiredSections)('should contain "%s" section', (section) => {
      expect(template).toContain(`## ${section}`);
    });

    it('should use HTML guidance comments', () => {
      expect(template).toMatch(/<!--[\s\S]*?-->/);
    });

    it('should document all 4 severity levels', () => {
      // Extract severity section to avoid matching common words elsewhere
      const severitySection = template.slice(
        template.indexOf('## Severity'),
        template.indexOf('## Description')
      );
      expect(severitySection).toContain('critical');
      expect(severitySection).toContain('high');
      expect(severitySection).toContain('medium');
      expect(severitySection).toContain('low');
    });

    it('should contain RC-N pattern in acceptance criteria section', () => {
      // Extract acceptance criteria section
      const acSection = template.slice(template.indexOf('## Acceptance Criteria'));
      expect(acSection).toMatch(/\(RC-\d+\)/);
    });

    it('should have numbered entries in Root Cause(s) section', () => {
      // Extract root causes section (between ## Root Cause(s) and the next ##)
      const rcMatch = template.match(/## Root Cause\(s\)([\s\S]*?)(?=\n## )/);
      expect(rcMatch).not.toBeNull();
      expect(rcMatch![1]).toMatch(/^\d+\./m);
    });
  });

  describe('categories reference', () => {
    const requiredCategories = [
      'Runtime Error',
      'Logic Error',
      'UI Defect',
      'Performance',
      'Security',
      'Regression',
    ];

    it.each(requiredCategories)('should contain "%s" category', (category) => {
      expect(categories).toContain(`## ${category}`);
    });

    const detailSections = [
      'Common Use Cases',
      'Typical Affected Files',
      'Suggested Acceptance Criteria',
      'Notes',
    ];

    it.each(detailSections)('should include "%s" subsection for each category', (subsection) => {
      // Each of the 6 categories should have this subsection
      const matches = categories.match(new RegExp(`### ${subsection}`, 'g'));
      expect(matches).not.toBeNull();
      expect(matches!.length).toBe(6);
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
