import { describe, it, expect, afterEach } from 'vitest';
import { execSync } from 'node:child_process';
import { mkdtemp, writeFile, mkdir, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

const RELEASE_TAG_SCRIPT = join(process.cwd(), 'scripts/release-tag.ts');

// Strip GIT_* env vars so child git processes use their own repo, not the parent's
// (e.g., when tests run inside a pre-commit hook that sets GIT_DIR/GIT_INDEX_FILE)
const cleanEnv = Object.fromEntries(
  Object.entries(process.env).filter(([key]) => !key.startsWith('GIT_'))
);

function runReleaseTag(args: string, cwd: string): { stdout: string; exitCode: number } {
  try {
    const stdout = execSync(`tsx ${RELEASE_TAG_SCRIPT} ${args}`, {
      cwd,
      env: cleanEnv,
      encoding: 'utf-8',
      stdio: ['pipe', 'pipe', 'pipe'],
    });
    return { stdout, exitCode: 0 };
  } catch (err: unknown) {
    const error = err as { stdout: string; status: number };
    return { stdout: error.stdout ?? '', exitCode: error.status ?? 1 };
  }
}

async function createTestRepo(branch = 'main'): Promise<string> {
  const dir = await mkdtemp(join(tmpdir(), 'release-tag-test-'));

  execSync(`git init -b ${branch}`, { cwd: dir, env: cleanEnv, stdio: 'pipe' });
  execSync('git config user.email "test@test.com"', { cwd: dir, env: cleanEnv, stdio: 'pipe' });
  execSync('git config user.name "Test"', { cwd: dir, env: cleanEnv, stdio: 'pipe' });

  // Create plugin structure
  const pluginDir = join(dir, 'plugins', 'test-plugin');
  const manifestDir = join(pluginDir, '.claude-plugin');
  const skillsDir = join(pluginDir, 'skills', 'test-skill');
  const marketplaceDir = join(dir, '.claude-plugin');

  await mkdir(manifestDir, { recursive: true });
  await mkdir(skillsDir, { recursive: true });
  await mkdir(marketplaceDir, { recursive: true });

  await writeFile(
    join(manifestDir, 'plugin.json'),
    JSON.stringify(
      {
        name: 'test-plugin',
        version: '1.2.0',
        description: 'A test plugin',
        author: { name: 'test' },
      },
      null,
      2
    ) + '\n'
  );

  await writeFile(
    join(marketplaceDir, 'marketplace.json'),
    JSON.stringify(
      {
        name: 'test-marketplace',
        owner: { name: 'test' },
        plugins: [
          {
            name: 'test-plugin',
            source: './plugins/test-plugin',
            description: 'A test plugin',
            version: '1.2.0',
          },
        ],
      },
      null,
      2
    ) + '\n'
  );

  await writeFile(
    join(skillsDir, 'SKILL.md'),
    '---\nname: test-skill\ndescription: A test skill\n---\n\n# Test Skill\n'
  );

  execSync('git add -A', { cwd: dir, env: cleanEnv, stdio: 'pipe' });
  execSync('git commit -m "initial commit"', { cwd: dir, env: cleanEnv, stdio: 'pipe' });

  return dir;
}

describe('release:tag script', () => {
  let testDir: string;

  afterEach(async () => {
    if (testDir) {
      await rm(testDir, { recursive: true, force: true });
    }
  });

  it('should error when not on main branch', async () => {
    testDir = await createTestRepo('develop');

    const { stdout, exitCode } = runReleaseTag('', testDir);
    expect(exitCode).toBe(1);
    expect(stdout).toContain('Must be on main branch to tag a release');
    expect(stdout).toContain('Current branch: develop');
  });

  it('should error when working tree is dirty', async () => {
    testDir = await createTestRepo('main');

    await writeFile(join(testDir, 'dirty.txt'), 'uncommitted');

    const { stdout, exitCode } = runReleaseTag('', testDir);
    expect(exitCode).toBe(1);
    expect(stdout).toContain('Working tree has uncommitted changes');
  });

  it('should error when tag already exists', async () => {
    testDir = await createTestRepo('main');

    execSync('git tag -a "test-plugin@1.2.0" -m "existing tag"', {
      cwd: testDir,
      env: cleanEnv,
      stdio: 'pipe',
    });

    const { stdout, exitCode } = runReleaseTag('', testDir);
    expect(exitCode).toBe(1);
    expect(stdout).toContain('Tag "test-plugin@1.2.0" already exists');
  });

  it('should error when plugin is not found', async () => {
    testDir = await createTestRepo('main');

    const { stdout, exitCode } = runReleaseTag('--plugin nonexistent', testDir);
    expect(exitCode).toBe(1);
    expect(stdout).toContain('Plugin "nonexistent" not found');
  });

  it('should create annotated tag on main branch', async () => {
    testDir = await createTestRepo('main');

    const { stdout, exitCode } = runReleaseTag('', testDir);
    expect(exitCode).toBe(0);
    expect(stdout).toContain('test-plugin');
    expect(stdout).toContain('test-plugin@1.2.0');

    // Verify tag exists
    const tags = execSync('git tag -l', { cwd: testDir, env: cleanEnv, encoding: 'utf-8' }).trim();
    expect(tags).toBe('test-plugin@1.2.0');

    // Verify annotation message
    const tagMessage = execSync('git tag -n1 "test-plugin@1.2.0"', {
      cwd: testDir,
      env: cleanEnv,
      encoding: 'utf-8',
    }).trim();
    expect(tagMessage).toContain('Release test-plugin v1.2.0');
  });

  it('should work with explicit --plugin flag', async () => {
    testDir = await createTestRepo('main');

    const { exitCode } = runReleaseTag('--plugin test-plugin', testDir);
    expect(exitCode).toBe(0);

    const tags = execSync('git tag -l', { cwd: testDir, env: cleanEnv, encoding: 'utf-8' }).trim();
    expect(tags).toBe('test-plugin@1.2.0');
  });
});
