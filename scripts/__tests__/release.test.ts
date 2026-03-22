import { execSync } from 'node:child_process';
import { mkdtemp, writeFile, readFile, mkdir, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

const RELEASE_SCRIPT = join(process.cwd(), 'scripts/release.ts');

// Helper to run the release script in a given cwd
function runRelease(args: string, cwd: string): { stdout: string; exitCode: number } {
  try {
    const stdout = execSync(`tsx ${RELEASE_SCRIPT} ${args}`, {
      cwd,
      encoding: 'utf-8',
      stdio: ['pipe', 'pipe', 'pipe'],
    });
    return { stdout, exitCode: 0 };
  } catch (err: unknown) {
    const error = err as { stdout: string; status: number };
    return { stdout: error.stdout ?? '', exitCode: error.status ?? 1 };
  }
}

// Helper to create a minimal plugin structure in a temp git repo
async function createTestRepo(): Promise<string> {
  const dir = await mkdtemp(join(tmpdir(), 'release-test-'));

  // Init git repo
  execSync('git init', { cwd: dir, stdio: 'pipe' });
  execSync('git config user.email "test@test.com"', { cwd: dir, stdio: 'pipe' });
  execSync('git config user.name "Test"', { cwd: dir, stdio: 'pipe' });

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
        version: '1.0.0',
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
            version: '1.0.0',
          },
        ],
      },
      null,
      2
    ) + '\n'
  );

  await writeFile(join(pluginDir, 'README.md'), '# test-plugin\n\nA test plugin.\n');

  await writeFile(
    join(skillsDir, 'SKILL.md'),
    '---\nname: test-skill\ndescription: A test skill\n---\n\n# Test Skill\n'
  );

  // Initial commit
  execSync('git add -A', { cwd: dir, stdio: 'pipe' });
  execSync('git commit -m "feat(init): initial commit"', { cwd: dir, stdio: 'pipe' });

  // Add another commit for changelog content
  await writeFile(join(dir, 'dummy.txt'), 'change');
  execSync('git add -A', { cwd: dir, stdio: 'pipe' });
  execSync('git commit -m "fix(core): fix a bug"', { cwd: dir, stdio: 'pipe' });

  return dir;
}

describe('release script argument validation', () => {
  let testDir: string;

  beforeAll(async () => {
    testDir = await createTestRepo();
  });

  afterAll(async () => {
    await rm(testDir, { recursive: true, force: true });
  });

  it('should error when neither --bump nor --version is provided', () => {
    const { stdout, exitCode } = runRelease('', testDir);
    expect(exitCode).toBe(1);
    expect(stdout).toContain('Specify --bump <patch|minor|major> or --version <x.y.z>');
  });

  it('should error when both --bump and --version are provided', () => {
    const { stdout, exitCode } = runRelease('--bump patch --version 2.0.0', testDir);
    expect(exitCode).toBe(1);
    expect(stdout).toContain('Specify either --bump or --version, not both');
  });

  it('should error with invalid bump type', () => {
    const { stdout, exitCode } = runRelease('--bump invalid', testDir);
    expect(exitCode).toBe(1);
    expect(stdout).toContain('Invalid bump type "invalid"');
  });

  it('should error with invalid semver version', () => {
    const { stdout, exitCode } = runRelease('--version not-a-version', testDir);
    expect(exitCode).toBe(1);
    expect(stdout).toContain('"not-a-version" is not a valid semver version');
  });

  it('should error when explicit version is not greater than current', () => {
    const { stdout, exitCode } = runRelease('--version 0.1.0', testDir);
    expect(exitCode).toBe(1);
    expect(stdout).toContain('must be greater than current version');
  });

  it('should error when plugin is not found', () => {
    const { stdout, exitCode } = runRelease('--plugin nonexistent --bump patch', testDir);
    expect(exitCode).toBe(1);
    expect(stdout).toContain('Plugin "nonexistent" not found');
    expect(stdout).toContain('Available plugins:');
  });
});

describe('release script full workflow', () => {
  let testDir: string;

  beforeEach(async () => {
    testDir = await createTestRepo();
  });

  afterEach(async () => {
    await rm(testDir, { recursive: true, force: true });
  });

  it('should bump patch version and update all files', async () => {
    const { stdout, exitCode } = runRelease('--bump patch', testDir);
    expect(exitCode).toBe(0);

    // Check output
    expect(stdout).toContain('1.0.0 → 1.0.1');
    expect(stdout).toContain('release(test-plugin): v1.0.1');

    // Verify plugin.json
    const pluginJson = JSON.parse(
      await readFile(join(testDir, 'plugins/test-plugin/.claude-plugin/plugin.json'), 'utf-8')
    );
    expect(pluginJson.version).toBe('1.0.1');

    // Verify marketplace.json
    const marketplace = JSON.parse(
      await readFile(join(testDir, '.claude-plugin/marketplace.json'), 'utf-8')
    );
    expect(marketplace.plugins[0].version).toBe('1.0.1');

    // Verify changelog
    const changelog = await readFile(join(testDir, 'plugins/test-plugin/CHANGELOG.md'), 'utf-8');
    expect(changelog).toContain('## [1.0.1]');
    expect(changelog).toContain('### Bug Fixes');
    expect(changelog).toContain('fix a bug');

    // Verify README
    const readme = await readFile(join(testDir, 'plugins/test-plugin/README.md'), 'utf-8');
    expect(readme).toContain('**Version:** 1.0.1');
    expect(readme).toContain('**Released:**');

    // Verify git commit
    const log = execSync('git log --oneline -1', { cwd: testDir, encoding: 'utf-8' });
    expect(log).toContain('release(test-plugin): v1.0.1');

    // Verify no tag was created
    const tags = execSync('git tag -l', { cwd: testDir, encoding: 'utf-8' }).trim();
    expect(tags).toBe('');
  });

  it('should bump minor version', async () => {
    const { exitCode } = runRelease('--bump minor', testDir);
    expect(exitCode).toBe(0);

    const pluginJson = JSON.parse(
      await readFile(join(testDir, 'plugins/test-plugin/.claude-plugin/plugin.json'), 'utf-8')
    );
    expect(pluginJson.version).toBe('1.1.0');
  });

  it('should bump major version', async () => {
    const { exitCode } = runRelease('--bump major', testDir);
    expect(exitCode).toBe(0);

    const pluginJson = JSON.parse(
      await readFile(join(testDir, 'plugins/test-plugin/.claude-plugin/plugin.json'), 'utf-8')
    );
    expect(pluginJson.version).toBe('2.0.0');
  });

  it('should set explicit version', async () => {
    const { stdout, exitCode } = runRelease('--version 3.0.0', testDir);
    expect(exitCode).toBe(0);
    expect(stdout).toContain('1.0.0 → 3.0.0');

    const pluginJson = JSON.parse(
      await readFile(join(testDir, 'plugins/test-plugin/.claude-plugin/plugin.json'), 'utf-8')
    );
    expect(pluginJson.version).toBe('3.0.0');
  });

  it('should auto-select plugin when only one exists', async () => {
    const { stdout, exitCode } = runRelease('--bump patch', testDir);
    expect(exitCode).toBe(0);
    expect(stdout).toContain('Using plugin: test-plugin');
  });

  it('should select plugin with --plugin flag', async () => {
    const { exitCode } = runRelease('--plugin test-plugin --bump patch', testDir);
    expect(exitCode).toBe(0);
  });

  it('should sync description from plugin.json to marketplace.json when drifted', async () => {
    // Create description drift
    const marketplacePath = join(testDir, '.claude-plugin/marketplace.json');
    const marketplace = JSON.parse(await readFile(marketplacePath, 'utf-8'));
    marketplace.plugins[0].description = 'Old description';
    await writeFile(marketplacePath, JSON.stringify(marketplace, null, 2) + '\n');
    execSync('git add -A && git commit -m "chore: drift description"', {
      cwd: testDir,
      stdio: 'pipe',
    });

    const { stdout, exitCode } = runRelease('--bump patch', testDir);
    expect(exitCode).toBe(0);
    expect(stdout).toContain('Syncing description');

    const updated = JSON.parse(await readFile(marketplacePath, 'utf-8'));
    expect(updated.plugins[0].description).toBe('A test plugin');
  });

  it('should group commits by conventional type in changelog', async () => {
    // Add some more typed commits
    await writeFile(join(testDir, 'feat.txt'), 'new feature');
    execSync('git add -A && git commit -m "feat(ui): add new button"', {
      cwd: testDir,
      stdio: 'pipe',
    });
    await writeFile(join(testDir, 'docs.txt'), 'docs');
    execSync('git add -A && git commit -m "docs: update readme"', {
      cwd: testDir,
      stdio: 'pipe',
    });

    const { exitCode } = runRelease('--bump minor', testDir);
    expect(exitCode).toBe(0);

    const changelog = await readFile(join(testDir, 'plugins/test-plugin/CHANGELOG.md'), 'utf-8');
    expect(changelog).toContain('### Features');
    expect(changelog).toContain('### Bug Fixes');
    expect(changelog).toContain('### Documentation');
    expect(changelog).toContain('**ui:** add new button');
  });

  it('should filter noise commits from changelog', async () => {
    // Add noise commits
    await writeFile(join(testDir, 'noise1.txt'), 'noise');
    execSync('git add -A && git commit -m "address review feedback"', {
      cwd: testDir,
      stdio: 'pipe',
    });
    await writeFile(join(testDir, 'noise2.txt'), 'noise');
    execSync('git add -A && git commit -m "mark CHORE-015 as completed"', {
      cwd: testDir,
      stdio: 'pipe',
    });
    await writeFile(join(testDir, 'noise3.txt'), 'noise');
    execSync('git add -A && git commit -m "update CHORE-012 status to completed"', {
      cwd: testDir,
      stdio: 'pipe',
    });

    const { exitCode } = runRelease('--bump patch', testDir);
    expect(exitCode).toBe(0);

    const changelog = await readFile(join(testDir, 'plugins/test-plugin/CHANGELOG.md'), 'utf-8');
    // Noise should be excluded
    expect(changelog).not.toContain('address review feedback');
    expect(changelog).not.toContain('mark CHORE-015 as completed');
    expect(changelog).not.toContain('update CHORE-012 status');
    // Real commits should remain
    expect(changelog).toContain('fix a bug');
  });

  it('should filter merge commits from changelog', async () => {
    await writeFile(join(testDir, 'merge.txt'), 'merge');
    execSync('git add -A && git commit -m "Merge pull request #42 from user/branch"', {
      cwd: testDir,
      stdio: 'pipe',
    });

    const { exitCode } = runRelease('--bump patch', testDir);
    expect(exitCode).toBe(0);

    const changelog = await readFile(join(testDir, 'plugins/test-plugin/CHANGELOG.md'), 'utf-8');
    expect(changelog).not.toContain('Merge pull request');
  });

  it('should collapse same-scope commits into single entry', async () => {
    // Add multiple commits with the same scope
    await writeFile(join(testDir, 'feat1.txt'), 'feat1');
    execSync('git add -A && git commit -m "feat(auth): add login endpoint"', {
      cwd: testDir,
      stdio: 'pipe',
    });
    await writeFile(join(testDir, 'feat2.txt'), 'feat2');
    execSync('git add -A && git commit -m "feat(auth): add logout endpoint"', {
      cwd: testDir,
      stdio: 'pipe',
    });
    await writeFile(join(testDir, 'feat3.txt'), 'feat3');
    execSync('git add -A && git commit -m "feat(auth): add token refresh"', {
      cwd: testDir,
      stdio: 'pipe',
    });

    const { exitCode } = runRelease('--bump minor', testDir);
    expect(exitCode).toBe(0);

    const changelog = await readFile(join(testDir, 'plugins/test-plugin/CHANGELOG.md'), 'utf-8');
    // Should have a single collapsed entry for auth scope
    expect(changelog).toContain('**auth:**');
    expect(changelog).toContain('(+2 more)');
    // Should NOT have 3 separate auth entries
    const authMatches = changelog.match(/\*\*auth:\*\*/g);
    expect(authMatches).toHaveLength(1);
  });

  it('should not collapse single-commit scopes', async () => {
    await writeFile(join(testDir, 'feat1.txt'), 'feat1');
    execSync('git add -A && git commit -m "feat(ui): add button"', {
      cwd: testDir,
      stdio: 'pipe',
    });

    const { exitCode } = runRelease('--bump minor', testDir);
    expect(exitCode).toBe(0);

    const changelog = await readFile(join(testDir, 'plugins/test-plugin/CHANGELOG.md'), 'utf-8');
    expect(changelog).toContain('**ui:** add button');
    expect(changelog).not.toContain('+');
  });

  it('should show no notable changes when all commits are noise', async () => {
    // Tag current state so only noise commits are in range
    execSync('git tag "test-plugin@1.0.0"', { cwd: testDir, stdio: 'pipe' });

    await writeFile(join(testDir, 'noise1.txt'), 'noise');
    execSync('git add -A && git commit -m "address review feedback"', {
      cwd: testDir,
      stdio: 'pipe',
    });
    await writeFile(join(testDir, 'noise2.txt'), 'noise');
    execSync('git add -A && git commit -m "mark CHORE-015 as completed"', {
      cwd: testDir,
      stdio: 'pipe',
    });

    const { exitCode } = runRelease('--bump patch', testDir);
    expect(exitCode).toBe(0);

    const changelog = await readFile(join(testDir, 'plugins/test-plugin/CHANGELOG.md'), 'utf-8');
    expect(changelog).toContain('No notable changes');
  });

  it('should prepend new version to existing changelog', async () => {
    // First release
    runRelease('--bump patch', testDir);

    // Add another commit
    await writeFile(join(testDir, 'another.txt'), 'change');
    execSync('git add -A && git commit -m "feat: another feature"', {
      cwd: testDir,
      stdio: 'pipe',
    });

    // Second release
    const { exitCode } = runRelease('--version 2.0.0', testDir);
    expect(exitCode).toBe(0);

    const changelog = await readFile(join(testDir, 'plugins/test-plugin/CHANGELOG.md'), 'utf-8');
    const v2Pos = changelog.indexOf('## [2.0.0]');
    const v1Pos = changelog.indexOf('## [1.0.1]');
    expect(v2Pos).toBeLessThan(v1Pos); // Newest first
  });
});

describe('release script error handling', () => {
  let testDir: string;

  beforeEach(async () => {
    testDir = await createTestRepo();
  });

  afterEach(async () => {
    await rm(testDir, { recursive: true, force: true });
  });

  it('should error when working tree is dirty', async () => {
    // Make working tree dirty
    await writeFile(join(testDir, 'dirty.txt'), 'uncommitted');

    const { stdout, exitCode } = runRelease('--bump patch', testDir);
    expect(exitCode).toBe(1);
    expect(stdout).toContain('Working tree has uncommitted changes');
  });

  it('should error when plugin is not in marketplace.json', async () => {
    // Remove plugin from marketplace
    const marketplacePath = join(testDir, '.claude-plugin/marketplace.json');
    const marketplace = JSON.parse(await readFile(marketplacePath, 'utf-8'));
    marketplace.plugins = [];
    await writeFile(marketplacePath, JSON.stringify(marketplace, null, 2) + '\n');
    execSync('git add -A && git commit -m "chore: remove plugin from marketplace"', {
      cwd: testDir,
      stdio: 'pipe',
    });

    const { stdout, exitCode } = runRelease('--bump patch', testDir);
    expect(exitCode).toBe(1);
    expect(stdout).toContain('Plugin "test-plugin" not found in marketplace.json');
  });
});
