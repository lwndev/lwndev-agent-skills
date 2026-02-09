import { execSync } from 'node:child_process';
import { access, mkdir, readdir, rm, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

describe('build script integration', () => {
  beforeAll(async () => {
    // Run the build script before tests
    execSync('npm run build', { stdio: 'pipe' });
  });

  it('should create dist directory', async () => {
    await expect(access('dist')).resolves.toBeUndefined();
  });

  it('should create .skill files for all source skills', async () => {
    const distFiles = await readdir('dist');
    const skillFiles = distFiles.filter((f) => f.endsWith('.skill'));

    // Should have created skill files
    expect(skillFiles.length).toBeGreaterThan(0);

    // Check for known skills
    expect(skillFiles).toContain('documenting-features.skill');
    expect(skillFiles).toContain('creating-implementation-plans.skill');
    expect(skillFiles).toContain('documenting-chores.skill');
    expect(skillFiles).toContain('executing-chores.skill');
    expect(skillFiles).toContain('implementing-plan-phases.skill');
    expect(skillFiles).toContain('managing-git-worktrees.skill');
  });

  it('should create valid zip archives as .skill files', async () => {
    const distFiles = await readdir('dist');
    const skillFiles = distFiles.filter((f) => f.endsWith('.skill'));

    for (const skillFile of skillFiles) {
      const filePath = join('dist', skillFile);

      // Use unzip -t to test archive validity
      const result = execSync(`unzip -t "${filePath}"`, {
        encoding: 'utf-8',
        stdio: ['pipe', 'pipe', 'pipe'],
      });

      expect(result).toContain('No errors detected');
    }
  });

  it('should include SKILL.md in each package', async () => {
    const distFiles = await readdir('dist');
    const skillFiles = distFiles.filter((f) => f.endsWith('.skill'));

    for (const skillFile of skillFiles) {
      const filePath = join('dist', skillFile);

      // List contents of the zip
      const contents = execSync(`unzip -l "${filePath}"`, {
        encoding: 'utf-8',
      });

      expect(contents).toContain('SKILL.md');
    }
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
    expect(buildOutput).toContain('Building all skills');
    expect(buildOutput).toContain('Build Summary');
    expect(buildOutput).toContain('Successful');
  });

  it('should display detailed validation check counts', () => {
    // Each skill should show per-check validation results (e.g., "24/24 checks passed")
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
