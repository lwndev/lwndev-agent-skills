import { execSync } from 'node:child_process';
import { access, readdir, readFile, rm, mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

const PLUGIN_DIR = 'dist/lwndev-sdlc-plugin';
const MANIFEST_PATH = join(PLUGIN_DIR, '.claude-plugin', 'plugin.json');
const SKILLS_DIR = join(PLUGIN_DIR, 'skills');

describe('build script integration', () => {
  beforeAll(async () => {
    execSync('npm run build', { stdio: 'pipe' });
  });

  it('should create plugin output directory', async () => {
    await expect(access(PLUGIN_DIR)).resolves.toBeUndefined();
  });

  it('should create .claude-plugin directory with plugin.json', async () => {
    await expect(access(MANIFEST_PATH)).resolves.toBeUndefined();

    const content = await readFile(MANIFEST_PATH, 'utf-8');
    const manifest = JSON.parse(content);

    expect(manifest.name).toBe('lwndev-sdlc');
    expect(manifest.version).toBe('1.0.0');
    expect(manifest.description).toBeTruthy();
    expect(manifest.author).toEqual({ name: 'lwndev' });
  });

  it('should create skills directory with all 7 skills', async () => {
    const skillDirs = await readdir(SKILLS_DIR);

    expect(skillDirs).toContain('documenting-features');
    expect(skillDirs).toContain('creating-implementation-plans');
    expect(skillDirs).toContain('implementing-plan-phases');
    expect(skillDirs).toContain('documenting-chores');
    expect(skillDirs).toContain('executing-chores');
    expect(skillDirs).toContain('documenting-bugs');
    expect(skillDirs).toContain('executing-bug-fixes');
    expect(skillDirs.length).toBe(7);
  });

  it('should include SKILL.md in each skill directory', async () => {
    const skillDirs = await readdir(SKILLS_DIR);

    for (const skillDir of skillDirs) {
      const skillMdPath = join(SKILLS_DIR, skillDir, 'SKILL.md');
      await expect(access(skillMdPath)).resolves.toBeUndefined();
    }
  });

  it('should include assets directories when present', async () => {
    // documenting-features has assets/
    const assetsPath = join(SKILLS_DIR, 'documenting-features', 'assets');
    await expect(access(assetsPath)).resolves.toBeUndefined();
  });

  it('should include references directories when present', async () => {
    // executing-chores has references/
    const refsPath = join(SKILLS_DIR, 'executing-chores', 'references');
    await expect(access(refsPath)).resolves.toBeUndefined();
  });

  it('should include README.md at plugin root', async () => {
    const readmePath = join(PLUGIN_DIR, 'README.md');
    await expect(access(readmePath)).resolves.toBeUndefined();
  });
});

describe('build script validation', () => {
  let buildOutput: string;

  beforeAll(() => {
    buildOutput = execSync('npm run build', {
      encoding: 'utf-8',
      stdio: ['pipe', 'pipe', 'pipe'],
    });
  });

  it('should exit with code 0 on success', () => {
    expect(buildOutput).toBeDefined();
  });

  it('should output build summary', () => {
    expect(buildOutput).toContain('Building plugin');
    expect(buildOutput).toContain('Build Summary');
    expect(buildOutput).toContain('Successful');
  });

  it('should display detailed validation check counts', () => {
    const checkPattern = /Validated \(\d+\/\d+ checks passed\)/g;
    const matches = buildOutput.match(checkPattern) ?? [];
    expect(matches.length).toBeGreaterThanOrEqual(1);
  });
});

describe('build script failure handling', () => {
  const badSkillDir = join('src', 'skills', '_test-bad-skill');

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
      execSync('npm run build', {
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
