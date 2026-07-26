import { describe, it, expect } from 'vitest';
import { existsSync, readdirSync, statSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';

const SHARED_DIR = 'tests/bats/shared';
const SHARED_SCRIPTS_DIR = 'plugins/lwndev-sdlc/scripts';
const QA_DIR = 'tests/bats/qa';
// FEAT-033 Phase 6 / FR-9 adoption sweep: husky-hooks bats dropped the `qa-`
// prefix to stay in tests/bats/qa/ without tripping the FR-9 safety-net glob
// (tests/bats/qa/qa-*.bats). The file content is unchanged.
const RELOCATED_BASENAME = 'husky-hooks.bats';
const PRE_MOVE_PATH = join(SHARED_DIR, 'qa-CHORE-037-husky-hooks.bats');
const POST_MOVE_PATH = join(QA_DIR, RELOCATED_BASENAME);

describe('BUG-016: relocated QA fixture — inputs', () => {
  it('[P0] pre-move path no longer exists under tests/bats/shared/', () => {
    expect(existsSync(PRE_MOVE_PATH)).toBe(false);
  });

  it('[P0] post-move path exists under tests/bats/qa/', () => {
    expect(existsSync(POST_MOVE_PATH)).toBe(true);
  });

  it('[P0] every canonical .bats under tests/bats/shared/ has a shared-script peer', () => {
    expect(existsSync(SHARED_DIR)).toBe(true);
    // Set-based parity, not a hard-coded total. CLAUDE.md ("QA Test Lifecycle"):
    // length assertions over directories that may receive *.qa.* siblings must
    // filter those out and use set-based parity rather than hard-coded totals.
    //
    // A bare count expresses no invariant — it fires on any unrelated change to
    // the directory and is "fixed" by bumping another magic number. The real
    // invariant is one canonical fixture per canonical shared script, so a
    // relocation (FEAT-033 Phase 2) or a removed shim (FEAT-033 Phase 5) shows
    // up as the specific name that moved.
    const fixtures = new Set(
      readdirSync(SHARED_DIR)
        .filter((f) => f.endsWith('.bats') && !f.includes('.qa.'))
        .map((f) => f.replace(/\.bats$/, ''))
    );
    const scripts = new Set(
      readdirSync(SHARED_SCRIPTS_DIR)
        .filter((f) => f.endsWith('.sh'))
        .map((f) => f.replace(/\.sh$/, ''))
    );

    // Fixtures with no shared-script peer, by design. git-env.bats covers
    // tests/bats/helpers/git-env.bash — a test helper, not a plugin script, so
    // it has no peer under plugins/lwndev-sdlc/scripts/ (issue #326).
    const PEERLESS = new Set(['git-env']);

    expect([...fixtures].filter((f) => !scripts.has(f) && !PEERLESS.has(f)).sort()).toEqual([]);
    expect([...scripts].filter((s) => !fixtures.has(s)).sort()).toEqual([]);
  });

  it('[P0] relocated file is non-empty and a regular file', () => {
    expect(existsSync(POST_MOVE_PATH)).toBe(true);
    const stat = statSync(POST_MOVE_PATH);
    expect(stat.isFile()).toBe(true);
    expect(stat.size).toBeGreaterThan(0);
  });

  it('[P1] no file matching qa-* prefix remains under tests/bats/shared/', () => {
    const orphaned = readdirSync(SHARED_DIR).filter((f) => f.startsWith('qa-'));
    expect(orphaned).toEqual([]);
  });
});

describe('BUG-016: tests/bats/qa/ directory — cross-cutting', () => {
  it('[P1] tests/bats/qa/ directory exists', () => {
    expect(existsSync(QA_DIR)).toBe(true);
    expect(statSync(QA_DIR).isDirectory()).toBe(true);
  });

  it('[P1] tests/bats/qa/ contains the relocated fixture', () => {
    const batsFiles = readdirSync(QA_DIR).filter((f) => f.endsWith('.bats'));
    expect(batsFiles).toContain(RELOCATED_BASENAME);
  });
});

describe('BUG-016: package.json test:bats glob — dependency', () => {
  it('[P1] package.json test:bats glob recursively scans tests/bats (no shared/ pinning)', () => {
    const pkg = JSON.parse(readFileSync('package.json', 'utf-8'));
    const cmd = pkg.scripts?.['test:bats'] ?? '';
    // The relocated file is only picked up if the runner globs recursively
    // under tests/bats (not pinned to tests/bats/shared/).
    expect(cmd).toMatch(/tests\/bats(\b|$)/);
    expect(cmd).not.toMatch(/tests\/bats\/shared\b/);
    expect(cmd).toMatch(/-r\b/); // recursive flag
  });

  it('[P1] bats --list (recursive) discovers the relocated fixture path', () => {
    const result = spawnSync('npx', ['bats', '--no-tempdir-cleanup', '-r', '--count', QA_DIR], {
      encoding: 'utf-8',
    });
    // bats --count emits an integer test count on stdout for the directory.
    // Relocated file has at least one @test block (it ships a real test case
    // for the husky-hook QA fixture). Count > 0 confirms discovery + parse.
    expect(result.status).toBe(0);
    const count = parseInt((result.stdout ?? '').trim(), 10);
    expect(count).toBeGreaterThan(0);
  });
});

describe('BUG-016: layout validator — environment', () => {
  it('[P2] scripts/validate-test-layout.ts accepts tests/bats/qa/ as a valid path', () => {
    // The validator scans the repo and exits non-zero on misplaced test files.
    // After relocation, validator must continue to exit 0 — the new directory
    // is allowed by the catch-all "any .bats under tests/bats/" rule.
    const result = spawnSync('npx', ['tsx', 'scripts/validate-test-layout.ts'], {
      encoding: 'utf-8',
    });
    expect(result.status).toBe(0);
  });
});
