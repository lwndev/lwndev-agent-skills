import { execSync } from 'node:child_process';
import { access, readdir, readFile, rm, mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import semver from 'semver';

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

  it('should validate all 9 skills', () => {
    const validatedPattern = /Validating: /g;
    const matches = buildOutput.match(validatedPattern) ?? [];
    expect(matches.length).toBe(9);
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

  it('should have skills directory with all 9 skills', async () => {
    const skillDirs = await readdir(SKILLS_DIR);

    expect(skillDirs).toContain('documenting-features');
    expect(skillDirs).toContain('creating-implementation-plans');
    expect(skillDirs).toContain('implementing-plan-phases');
    expect(skillDirs).toContain('documenting-chores');
    expect(skillDirs).toContain('executing-chores');
    expect(skillDirs).toContain('documenting-bugs');
    expect(skillDirs).toContain('executing-bug-fixes');
    expect(skillDirs).toContain('documenting-qa');
    expect(skillDirs).toContain('executing-qa');
    expect(skillDirs.length).toBe(9);
  });

  it('should include SKILL.md in each skill directory', async () => {
    const skillDirs = await readdir(SKILLS_DIR);

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
  const badSkillDir = join('plugins', 'lwndev-sdlc', 'skills', '_test-bad-skill');

  afterAll(async () => {
    await rm(badSkillDir, { recursive: true, force: true });
  });

  it('should display failed check details for invalid skills', async () => {
    await mkdir(badSkillDir, { recursive: true });
    await writeFile(
      join(badSkillDir, 'SKILL.md'),
      '---\nname: wrong-name-mismatch\ndescription: A test skill with intentional issues\n---\n\n# Bad Skill\n'
    );

    let stdout = '';
    try {
      execSync('npm run validate', {
        encoding: 'utf-8',
        stdio: ['pipe', 'pipe', 'pipe'],
      });
    } catch (err: unknown) {
      stdout = (err as { stdout: string }).stdout;
    }

    // Should show per-check failure details (check name + error message)
    expect(stdout).toContain('nameMatchesDirectory');
    // Should show the checks failed summary
    expect(stdout).toMatch(/\d+\/\d+ checks failed/);
  });
});
