import { describe, it, expect, afterAll } from 'vitest';
import { readFile, readdir, mkdir, writeFile, rm } from 'node:fs/promises';
import { join } from 'node:path';
import matter from 'gray-matter';
import { validate, type DetailedValidateResult } from 'ai-skills-manager';

const SKILLS_DIR = 'plugins/lwndev-sdlc/skills';

const SKILLS_WITH_HINTS = [
  'executing-chores',
  'executing-bug-fixes',
  'implementing-plan-phases',
  'executing-qa',
  'documenting-features',
  'documenting-chores',
  'documenting-bugs',
  'documenting-qa',
  'creating-implementation-plans',
  'reviewing-requirements',
];

const EXCLUDED_SKILLS = ['finalizing-workflow'];

describe('argument-hint across all skills', () => {
  const skillData: Record<string, { frontmatter: Record<string, unknown>; content: string }> = {};

  // Load all SKILL.md files once
  it('should load all skill SKILL.md files', async () => {
    const entries = await readdir(SKILLS_DIR, { withFileTypes: true });
    const skillDirs = entries.filter((e) => e.isDirectory() && !e.name.startsWith('.'));

    for (const dir of skillDirs) {
      const raw = await readFile(join(SKILLS_DIR, dir.name, 'SKILL.md'), 'utf-8');
      const { data, content } = matter(raw);
      skillData[dir.name] = { frontmatter: data, content };
    }

    expect(Object.keys(skillData).length).toBe(13);
  });

  describe('frontmatter presence', () => {
    for (const skill of SKILLS_WITH_HINTS) {
      it(`${skill} should have argument-hint in frontmatter`, () => {
        const data = skillData[skill];
        expect(data, `skill ${skill} not loaded`).toBeDefined();
        expect(data.frontmatter['argument-hint']).toBeDefined();
      });
    }
  });

  describe('finalizing-workflow exclusion', () => {
    it('finalizing-workflow should NOT have argument-hint', () => {
      const data = skillData['finalizing-workflow'];
      expect(data).toBeDefined();
      expect(data.frontmatter['argument-hint']).toBeUndefined();
    });
  });

  describe('hint value constraints', () => {
    for (const skill of SKILLS_WITH_HINTS) {
      it(`${skill} hint should be a non-empty string ≤ 200 characters`, () => {
        const hint = skillData[skill].frontmatter['argument-hint'];
        expect(typeof hint).toBe('string');
        expect((hint as string).trim().length).toBeGreaterThan(0);
        expect((hint as string).length).toBeLessThanOrEqual(200);
      });
    }
  });

  describe('YAML quoting for bracket values', () => {
    for (const skill of SKILLS_WITH_HINTS) {
      it(`${skill} hint should parse as a string (not array)`, () => {
        const hint = skillData[skill].frontmatter['argument-hint'];
        expect(typeof hint, `${skill} argument-hint parsed as ${typeof hint}, not string`).toBe(
          'string'
        );
      });
    }
  });

  describe('argument-handling instructions in SKILL.md body', () => {
    for (const skill of SKILLS_WITH_HINTS) {
      it(`${skill} should contain "When argument is provided" guidance`, () => {
        expect(skillData[skill].content).toContain('When argument is provided');
      });

      it(`${skill} should contain "When no argument is provided" guidance`, () => {
        expect(skillData[skill].content).toContain('When no argument is provided');
      });
    }
  });

  describe('skill coverage completeness', () => {
    it('every skill except finalizing-workflow should have argument-hint', async () => {
      const entries = await readdir(SKILLS_DIR, { withFileTypes: true });
      const skillNames = entries
        .filter((e) => e.isDirectory() && !e.name.startsWith('.'))
        .map((e) => e.name);

      for (const name of skillNames) {
        if (EXCLUDED_SKILLS.includes(name)) {
          expect(
            skillData[name].frontmatter['argument-hint'],
            `${name} should NOT have argument-hint`
          ).toBeUndefined();
        } else {
          expect(
            skillData[name].frontmatter['argument-hint'],
            `${name} is missing argument-hint`
          ).toBeDefined();
        }
      }
    });
  });
});

describe('ai-skills-manager validate API for argument-hint', () => {
  const tempSkillDir = join(SKILLS_DIR, '_test-argument-hint');

  afterAll(async () => {
    await rm(tempSkillDir, { recursive: true, force: true });
  });

  it('should pass argumentHintFormat check with angle-bracket hint', async () => {
    await mkdir(tempSkillDir, { recursive: true });
    await writeFile(
      join(tempSkillDir, 'SKILL.md'),
      `---
name: _test-argument-hint
description: Temporary skill for argument-hint validation test
argument-hint: <query>
---

# Test Skill
`
    );

    const result = (await validate(tempSkillDir, { detailed: true })) as DetailedValidateResult;
    expect(result.checks.argumentHintFormat.passed).toBe(true);
  });

  it('should pass argumentHintFormat check with quoted bracket hint', async () => {
    await writeFile(
      join(tempSkillDir, 'SKILL.md'),
      `---
name: _test-argument-hint
description: Temporary skill for argument-hint validation test
argument-hint: "[feature-name or #issue-number]"
---

# Test Skill
`
    );

    const result = (await validate(tempSkillDir, { detailed: true })) as DetailedValidateResult;
    expect(result.checks.argumentHintFormat.passed).toBe(true);
  });

  it('should pass argumentHintFormat check with mixed bracket hint', async () => {
    await writeFile(
      join(tempSkillDir, 'SKILL.md'),
      `---
name: _test-argument-hint
description: Temporary skill for argument-hint validation test
argument-hint: "<plan-file> [phase-number]"
---

# Test Skill
`
    );

    const result = (await validate(tempSkillDir, { detailed: true })) as DetailedValidateResult;
    expect(result.checks.argumentHintFormat.passed).toBe(true);
  });
});
