import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { execSync } from 'node:child_process';
import { access, readdir, readFile, rm, mkdir, writeFile, mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import semver from 'semver';
import { validate, type DetailedValidateResult } from 'ai-skills-manager';

const PLUGIN_DIR = 'plugins/lwndev-sdlc';
const MANIFEST_PATH = join(PLUGIN_DIR, '.claude-plugin', 'plugin.json');
const SKILLS_DIR = join(PLUGIN_DIR, 'skills');

describe('build script validation', () => {
  let buildOutput: string;

  beforeAll(() => {
    buildOutput = execSync('npm run validate', {
      encoding: 'utf-8',
      stdio: ['pipe', 'pipe', 'pipe'],
    });
  });

  it('should exit with code 0 on success', () => {
    expect(buildOutput).toBeDefined();
  });

  it('should output validation summary', () => {
    expect(buildOutput).toContain('Validating plugin');
    expect(buildOutput).toContain('Validation Summary');
    expect(buildOutput).toContain('Passed');
  });

  it('should display detailed validation check counts', () => {
    const checkPattern = /Validated \(\d+\/\d+ checks passed\)/g;
    const matches = buildOutput.match(checkPattern) ?? [];
    expect(matches.length).toBeGreaterThanOrEqual(1);
  });

  it('should validate every skill in the plugin', async () => {
    const entries = await readdir(SKILLS_DIR, { withFileTypes: true });
    const expectedCount = entries.filter(
      (e) => e.isDirectory() && !e.name.startsWith('.') && !e.name.startsWith('_')
    ).length;

    const validatedPattern = /Validating: /g;
    const matches = buildOutput.match(validatedPattern) ?? [];
    expect(matches.length).toBe(expectedCount);
  });
});

describe('plugin structure', () => {
  it('should have .claude-plugin directory with plugin.json', async () => {
    await expect(access(MANIFEST_PATH)).resolves.toBeUndefined();

    const content = await readFile(MANIFEST_PATH, 'utf-8');
    const manifest = JSON.parse(content);

    expect(manifest.name).toBe('lwndev-sdlc');
    expect(semver.valid(manifest.version)).toBeTruthy();
    expect(manifest.description).toBeTruthy();
    expect(manifest.author).toEqual({ name: 'lwndev' });
  });

  it('should have plugin.json version matching marketplace.json version', async () => {
    const pluginContent = await readFile(MANIFEST_PATH, 'utf-8');
    const pluginManifest = JSON.parse(pluginContent);

    const marketplaceContent = await readFile('.claude-plugin/marketplace.json', 'utf-8');
    const marketplace = JSON.parse(marketplaceContent);

    const entry = marketplace.plugins.find((p: { name: string }) => p.name === pluginManifest.name);
    expect(entry).toBeDefined();
    expect(entry.version).toBe(pluginManifest.version);
  });

  it('should have skills directory with all expected skills', async () => {
    const entries = await readdir(SKILLS_DIR, { withFileTypes: true });
    const skillDirs = entries
      .filter((e) => e.isDirectory() && !e.name.startsWith('.') && !e.name.startsWith('_'))
      .map((e) => e.name);

    expect(skillDirs).toContain('documenting-features');
    expect(skillDirs).toContain('creating-implementation-plans');
    expect(skillDirs).toContain('implementing-plan-phases');
    expect(skillDirs).toContain('documenting-chores');
    expect(skillDirs).toContain('executing-chores');
    expect(skillDirs).toContain('documenting-bugs');
    expect(skillDirs).toContain('executing-bug-fixes');
    expect(skillDirs).toContain('documenting-qa');
    expect(skillDirs).toContain('executing-qa');
    expect(skillDirs).toContain('reviewing-requirements');
    expect(skillDirs).toContain('finalizing-workflow');
    expect(skillDirs).toContain('orchestrating-workflows');
    expect(skillDirs).toContain('managing-work-items');
    expect(skillDirs).toContain('addressing-qa-findings');
  });

  it('should include SKILL.md in each skill directory', async () => {
    const entries = await readdir(SKILLS_DIR, { withFileTypes: true });
    const skillDirs = entries
      .filter((e) => e.isDirectory() && !e.name.startsWith('.') && !e.name.startsWith('_'))
      .map((e) => e.name);

    for (const skillDir of skillDirs) {
      const skillMdPath = join(SKILLS_DIR, skillDir, 'SKILL.md');
      await expect(access(skillMdPath)).resolves.toBeUndefined();
    }
  });

  it('should include README.md at plugin root', async () => {
    const readmePath = join(PLUGIN_DIR, 'README.md');
    await expect(access(readmePath)).resolves.toBeUndefined();
  });
});

describe('marketplace manifest validation', () => {
  it('should have source paths that resolve to plugin directories', async () => {
    const content = await readFile('.claude-plugin/marketplace.json', 'utf-8');
    const marketplace = JSON.parse(content);

    for (const plugin of marketplace.plugins) {
      const sourcePath = plugin.source.replace('./', '');
      await expect(access(sourcePath)).resolves.toBeUndefined();
      await expect(
        access(join(sourcePath, '.claude-plugin', 'plugin.json'))
      ).resolves.toBeUndefined();
    }
  });

  it('should list plugins whose names match plugin.json names', async () => {
    const content = await readFile('.claude-plugin/marketplace.json', 'utf-8');
    const marketplace = JSON.parse(content);

    for (const plugin of marketplace.plugins) {
      const sourcePath = plugin.source.replace('./', '');
      const manifestContent = await readFile(
        join(sourcePath, '.claude-plugin', 'plugin.json'),
        'utf-8'
      );
      const manifest = JSON.parse(manifestContent);
      expect(manifest.name).toBe(plugin.name);
    }
  });
});

describe('build script failure handling', () => {
  // Build a fake plugins/ tree containing a bad skill, then run `npm run validate`
  // pointed at it via the PLUGINS_DIR env override. Asserts the CLI rendering
  // (printError lines, summary) end-to-end without touching the real plugins/ tree.
  let pluginsRoot: string;
  let buildOutput: string;
  let buildExitCode: number;

  beforeAll(async () => {
    pluginsRoot = await mkdtemp(join(tmpdir(), 'build-bad-plugins-'));
    const pluginDir = join(pluginsRoot, 'fixture-plugin');
    await mkdir(join(pluginDir, '.claude-plugin'), { recursive: true });
    await writeFile(
      join(pluginDir, '.claude-plugin', 'plugin.json'),
      JSON.stringify({
        name: 'fixture-plugin',
        version: '0.0.0',
        description: 'Bad-skill fixture',
        author: { name: 'tests' },
      })
    );
    const skillDir = join(pluginDir, 'skills', 'bad-skill-dir');
    await mkdir(skillDir, { recursive: true });
    await writeFile(
      join(skillDir, 'SKILL.md'),
      '---\nname: wrong-name-mismatch\ndescription: A test skill with intentional issues\n---\n\n# Bad Skill\n'
    );

    try {
      buildOutput = execSync('npm run validate', {
        encoding: 'utf-8',
        stdio: ['pipe', 'pipe', 'pipe'],
        env: { ...process.env, PLUGINS_DIR: pluginsRoot },
      });
      buildExitCode = 0;
    } catch (err) {
      const e = err as { stdout?: Buffer | string; stderr?: Buffer | string; status?: number };
      buildOutput = (e.stdout?.toString() ?? '') + (e.stderr?.toString() ?? '');
      buildExitCode = e.status ?? 1;
    }
  });

  afterAll(async () => {
    await rm(pluginsRoot, { recursive: true, force: true });
  });

  it('should exit non-zero when validation fails', () => {
    expect(buildExitCode).not.toBe(0);
  });

  it('should render the failed check name in CLI output', () => {
    expect(buildOutput).toContain('nameMatchesDirectory');
  });

  it('should render a failure summary line', () => {
    expect(buildOutput).toMatch(/Validation failed: \d+\/\d+ checks failed/);
  });

  it('should still validate via the API for unit-level coverage', async () => {
    const skillPath = join(pluginsRoot, 'fixture-plugin', 'skills', 'bad-skill-dir');
    const result = (await validate(skillPath, { detailed: true })) as DetailedValidateResult;
    expect(result.valid).toBe(false);
    expect(result.checks.nameMatchesDirectory?.passed).toBe(false);
  });
});
