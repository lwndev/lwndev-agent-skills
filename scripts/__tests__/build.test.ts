import { execSync } from 'node:child_process';
import { access, readdir } from 'node:fs/promises';
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
  it('should exit with code 0 on success', () => {
    // This should not throw
    expect(() => {
      execSync('npm run build', { stdio: 'pipe' });
    }).not.toThrow();
  });

  it('should output build summary', () => {
    const output = execSync('npm run build', {
      encoding: 'utf-8',
      stdio: ['pipe', 'pipe', 'pipe'],
    });

    expect(output).toContain('Building all skills');
    expect(output).toContain('Build Summary');
    expect(output).toContain('Successful');
  });
});
