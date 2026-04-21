import { describe, it, expect } from 'vitest';
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';

// ---------------------------------------------------------------------------
// FEAT-020 integration test — plugin-shared scripts library (AC-7)
//
// Asserts filesystem-level invariants of plugins/lwndev-sdlc/scripts/:
//   * directory exists and is non-empty
//   * every canonical script file exists and has the owner-execute bit set
//   * running each script with no args exits non-zero with a usage message
//   * pr-body.tmpl asset exists and is non-empty
//   * the bats-fixture count matches the script count (ten)
// ---------------------------------------------------------------------------

const SCRIPTS_DIR = 'plugins/lwndev-sdlc/scripts';
const TESTS_DIR = join(SCRIPTS_DIR, 'tests');
const ASSETS_DIR = join(SCRIPTS_DIR, 'assets');
const PR_BODY_TMPL = join(ASSETS_DIR, 'pr-body.tmpl');

const CANONICAL_SCRIPTS = [
  'next-id.sh',
  'slugify.sh',
  'resolve-requirement-doc.sh',
  'build-branch-name.sh',
  'ensure-branch.sh',
  'check-acceptance.sh',
  'checkbox-flip-all.sh',
  'commit-work.sh',
  'create-pr.sh',
  'branch-id-parse.sh',
] as const;

describe('shared-scripts library: directory layout', () => {
  it('should have the scripts directory and it should be non-empty', () => {
    expect(existsSync(SCRIPTS_DIR)).toBe(true);
    const entries = readdirSync(SCRIPTS_DIR);
    expect(entries.length).toBeGreaterThan(0);
  });
});

describe('shared-scripts library: script files exist and are executable', () => {
  for (const scriptName of CANONICAL_SCRIPTS) {
    const scriptPath = join(SCRIPTS_DIR, scriptName);

    it(`${scriptName} should exist`, () => {
      expect(existsSync(scriptPath)).toBe(true);
    });

    it(`${scriptName} should have the owner-execute bit set`, () => {
      const stat = statSync(scriptPath);
      // 0o100 is the owner-execute bit; truthy when set.
      expect(stat.mode & 0o100).toBeTruthy();
    });
  }
});

describe('shared-scripts library: usage-error sanity (missing args)', () => {
  for (const scriptName of CANONICAL_SCRIPTS) {
    const scriptPath = join(SCRIPTS_DIR, scriptName);

    it(`${scriptName} should exit non-zero with a usage message when invoked without args`, () => {
      const result = spawnSync('bash', [scriptPath], {
        encoding: 'utf-8',
        // Ensure the arg validator fires before any git/gh lookup. A hermetic
        // CWD is fine here — the usage check is the first thing each script does.
        cwd: process.cwd(),
      });

      expect(result.status).not.toBe(0);
      expect(result.status).not.toBeNull();

      const stderr = result.stderr ?? '';
      // Arg parsers emit a line that starts with `error:` or includes `usage:`.
      expect(stderr.toLowerCase()).toMatch(/error:|usage:/);
    });
  }
});

describe('shared-scripts library: pr-body.tmpl asset', () => {
  it('should exist at scripts/assets/pr-body.tmpl', () => {
    expect(existsSync(PR_BODY_TMPL)).toBe(true);
  });

  it('should be non-empty', () => {
    const contents = readFileSync(PR_BODY_TMPL, 'utf-8');
    expect(contents.trim().length).toBeGreaterThan(0);
  });
});

describe('shared-scripts library: bats fixture count', () => {
  it('should contain exactly ten .bats files, one per script', () => {
    expect(existsSync(TESTS_DIR)).toBe(true);
    const batsFiles = readdirSync(TESTS_DIR).filter((f) => f.endsWith('.bats'));
    expect(batsFiles.length).toBe(CANONICAL_SCRIPTS.length);
    expect(batsFiles.length).toBe(10);
  });

  it('should have a .bats fixture for every canonical script', () => {
    const batsFiles = new Set(readdirSync(TESTS_DIR).filter((f) => f.endsWith('.bats')));
    for (const scriptName of CANONICAL_SCRIPTS) {
      const expectedBats = scriptName.replace(/\.sh$/, '.bats');
      expect(batsFiles.has(expectedBats)).toBe(true);
    }
  });
});
