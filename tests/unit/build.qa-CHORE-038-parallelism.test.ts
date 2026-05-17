// QA tests for CHORE-038 — adversarial probing of the parallel-isolation invariants
// established by flipping `fileParallelism: true`. These tests are pure static checks
// against the repo's own files (vitest config, test files, CLAUDE.md). They do not
// run other tests; they validate the structural conditions that keep parallel runs
// race-free. If a future test file regresses on isolation, these tests should fail.

import { describe, it, expect } from 'vitest';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

const REPO_ROOT = process.cwd();
const VITEST_CONFIG = join(REPO_ROOT, 'vitest.config.ts');
const CLAUDE_MD = join(REPO_ROOT, 'CLAUDE.md');
const UNIT_DIR = join(REPO_ROOT, 'tests', 'unit');
const REAL_SKILLS_PATH = 'plugins/lwndev-sdlc/skills';

function unitTestFiles(): string[] {
  return readdirSync(UNIT_DIR)
    .filter((name) => name.endsWith('.test.ts'))
    .map((name) => join(UNIT_DIR, name))
    .filter((p) => statSync(p).isFile());
}

describe('CHORE-038 — vitest config (state transitions [P0])', () => {
  it('vitest.config.ts has fileParallelism: true (regression guard)', () => {
    const config = readFileSync(VITEST_CONFIG, 'utf8');
    expect(config).toMatch(/fileParallelism:\s*true/);
    expect(config).not.toMatch(/fileParallelism:\s*false/);
  });
});

describe('CHORE-038 — test isolation under parallelism (state transitions [P0])', () => {
  it('no test file writes a literal path under plugins/lwndev-sdlc/skills/ as a write target', () => {
    // Detect writeFileSync / mkdirSync / writeFile / cpSync calls whose first
    // argument is a string literal under plugins/lwndev-sdlc/skills/ — that
    // pattern is exactly what the chore was meant to eliminate. The 2 historical
    // offenders (scaffold.test.ts, build.test.ts) now route through mkdtemp.
    const offenders: string[] = [];
    const writeCallPattern =
      /(writeFileSync|writeFile|mkdirSync|mkdir|cpSync|cp)\s*\(\s*(?:join\s*\([^)]*?["']plugins\/lwndev-sdlc\/skills["']|["'][^"']*plugins\/lwndev-sdlc\/skills[^"']*["'])/;
    for (const file of unitTestFiles()) {
      const src = readFileSync(file, 'utf8');
      // skip QA tests that intentionally assert on the path in read-only ways
      // (this very file matches the literal). Filter to call sites only.
      if (writeCallPattern.test(src)) {
        offenders.push(file.replace(REPO_ROOT + '/', ''));
      }
    }
    expect(offenders).toEqual([]);
  });

  it('scaffold.test.ts uses mkdtemp for fixture isolation', () => {
    const src = readFileSync(join(UNIT_DIR, 'scaffold.test.ts'), 'utf8');
    expect(src).toMatch(/mkdtemp/);
  });

  it('build.test.ts uses mkdtemp for fixture isolation', () => {
    const src = readFileSync(join(UNIT_DIR, 'build.test.ts'), 'utf8');
    expect(src).toMatch(/mkdtemp/);
  });

  it('validate-test-layout.test.ts already uses mkdtemp (chore W1 finding — file unchanged)', () => {
    const src = readFileSync(join(UNIT_DIR, 'validate-test-layout.test.ts'), 'utf8');
    expect(src).toMatch(/mkdtemp/);
  });
});

describe('CHORE-038 — env-var safety (cross-cutting [P1])', () => {
  it('no test file rebinds process.env wholesale (forbidden under parallel runs)', () => {
    // `process.env = { ... }` replaces the env object for the entire vitest
    // worker, leaking across files in parallel mode. Tests should use vi.stubEnv
    // or process.env.X = "..." for single-key writes (still scoped per-worker
    // but at least targeted).
    const offenders: string[] = [];
    const wholesalePattern = /^\s*process\.env\s*=\s*[{(]/m;
    for (const file of unitTestFiles()) {
      const src = readFileSync(file, 'utf8');
      if (wholesalePattern.test(src)) {
        offenders.push(file.replace(REPO_ROOT + '/', ''));
      }
    }
    expect(offenders).toEqual([]);
  });
});

describe('CHORE-038 — discovery race-safety (state transitions [P0])', () => {
  it('argument-hint.test.ts filters underscore-prefixed dirs from skill counts', () => {
    // build.test.ts and other tests may inject `_test-bad-skill/` style temp
    // dirs into plugins/lwndev-sdlc/skills/. Tests that count discovered skills
    // must filter those out, otherwise parallel runs flake on transient counts.
    const src = readFileSync(join(UNIT_DIR, 'argument-hint.test.ts'), 'utf8');
    // Either the test no longer counts directly, or it filters by prefix.
    // Match any reasonable filter: `.filter(...startsWith('_')...)` or a
    // `_`-aware count.
    const hasFilter =
      /filter\s*\([^)]*startsWith\s*\(\s*['"]_['"]\s*\)/.test(src) ||
      /!\s*\w+\.startsWith\(['"]_['"]\)/.test(src) ||
      /\.startsWith\(['"]_['"]\)/.test(src);
    expect(hasFilter).toBe(true);
  });
});

describe('CHORE-038 — documentation accuracy (cross-cutting [P2])', () => {
  it('CLAUDE.md no longer asserts tests run sequentially', () => {
    const src = readFileSync(CLAUDE_MD, 'utf8');
    expect(src).not.toMatch(/Tests run sequentially/);
    expect(src).not.toMatch(/fileParallelism:\s*false/);
  });

  it('CLAUDE.md Key Patterns reflects the new parallel + mkdtemp strategy', () => {
    const src = readFileSync(CLAUDE_MD, 'utf8');
    expect(src).toMatch(/parallel/i);
    expect(src).toMatch(/mkdtemp|isolat/i);
  });
});

describe('CHORE-038 — exclusion mention (sanity)', () => {
  it('expected real skills directory still exists and is not the test target', () => {
    // Sanity: REAL_SKILLS_PATH is a constant referenced for grep semantics.
    // Touching it in a read-only way confirms the path is stable so the
    // offender-detection above is meaningful.
    expect(typeof REAL_SKILLS_PATH).toBe('string');
    const stat = statSync(join(REPO_ROOT, REAL_SKILLS_PATH));
    expect(stat.isDirectory()).toBe(true);
  });
});
