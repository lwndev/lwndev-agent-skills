import { mkdir, writeFile, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { getSourceSkills, getSourcePlugins } from '../lib/skill-utils.js';

describe('skill-utils', () => {
  describe('getSourcePlugins', () => {
    it('should discover plugins in plugins/', async () => {
      const plugins = await getSourcePlugins();
      expect(plugins.length).toBeGreaterThan(0);
      expect(plugins).toContain('lwndev-sdlc');
    });

    it('should return plugins sorted by name', async () => {
      const plugins = await getSourcePlugins();
      const sorted = [...plugins].sort();
      expect(plugins).toEqual(sorted);
    });
  });

  describe('getSourceSkills', () => {
    it('should return skills for a given plugin', async () => {
      const skills = await getSourceSkills('lwndev-sdlc');

      expect(skills.length).toBeGreaterThan(0);

      for (const skill of skills) {
        expect(skill).toHaveProperty('name');
        expect(skill).toHaveProperty('description');
        expect(skill).toHaveProperty('path');
        expect(typeof skill.name).toBe('string');
        expect(typeof skill.description).toBe('string');
        expect(skill.name.length).toBeGreaterThan(0);
      }
    });

    it('should return skills sorted by name', async () => {
      const skills = await getSourceSkills('lwndev-sdlc');
      const names = skills.map((s) => s.name);
      const sorted = [...names].sort();
      expect(names).toEqual(sorted);
    });

    it('should include known skills from the project', async () => {
      const skills = await getSourceSkills('lwndev-sdlc');
      const names = skills.map((s) => s.name);

      expect(names).toContain('documenting-features');
      expect(names).toContain('creating-implementation-plans');
      expect(names).toContain('documenting-bugs');
      expect(names).toContain('executing-bug-fixes');
    });

    it('should return documenting-bugs with correct metadata', async () => {
      const skills = await getSourceSkills('lwndev-sdlc');
      const docBugs = skills.find((s) => s.name === 'documenting-bugs');

      expect(docBugs).toBeDefined();
      expect(docBugs?.description).toBeTruthy();
      expect(docBugs?.path).toContain('plugins/lwndev-sdlc/skills/documenting-bugs');
    });

    it('should return executing-bug-fixes with correct metadata', async () => {
      const skills = await getSourceSkills('lwndev-sdlc');
      const execBugFixes = skills.find((s) => s.name === 'executing-bug-fixes');

      expect(execBugFixes).toBeDefined();
      expect(execBugFixes?.description).toBeTruthy();
      expect(execBugFixes?.path).toContain('plugins/lwndev-sdlc/skills/executing-bug-fixes');
    });
  });
});

describe('skill-utils with temp directory', () => {
  let tempDir: string;
  let tempSkillsDir: string;

  beforeEach(async () => {
    tempDir = join(tmpdir(), `skill-test-${Date.now()}`);
    tempSkillsDir = join(tempDir, 'skills');
    await mkdir(tempSkillsDir, { recursive: true });
  });

  afterEach(async () => {
    await rm(tempDir, { recursive: true, force: true });
  });

  it('should parse SKILL.md frontmatter correctly', async () => {
    // Create a test skill
    const skillDir = join(tempSkillsDir, 'test-skill');
    await mkdir(skillDir);
    await writeFile(
      join(skillDir, 'SKILL.md'),
      `---
name: test-skill
description: A test skill for unit testing
---

# Test Skill

This is a test skill.
`
    );

    // Verify the project's skills are parsed correctly
    const skills = await getSourceSkills('lwndev-sdlc');
    const docFeatures = skills.find((s) => s.name === 'documenting-features');

    expect(docFeatures).toBeDefined();
    expect(docFeatures?.description).toBeTruthy();
    expect(docFeatures?.path).toContain('plugins/lwndev-sdlc/skills/documenting-features');
  });
});
