// Regression suite for issue #326 — "Running the full test suite writes git
// config into the real repository". Failure mode: CLAUDE.md, "Tests must never
// inherit git environment".
//
// One detail drives the test design: the reported core.bare flip ONLY
// reproduces when the inherited GIT_DIR is a linked worktree gitdir
// (.git/worktrees/<name>). With a plain .git, git infers the work tree from the
// basename and you get the identity leak alone. The sacrificial fixture below
// therefore builds a real linked worktree, or it would under-test the bug.
//
// The fix has three parts, each guarded below:
//   1. tests/setup/git-env.ts, registered as a Vitest `setupFiles` entry.
//   2. tests/bats/helpers/git-env.bash, loaded by every Bats file.
//   3. the GIT_* strip prologue at the top of .husky/pre-push.

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { execFileSync, spawnSync } from 'node:child_process';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';

import { stripGitEnv, GIT_ENV_PREFIX } from '../setup/git-env';

const REPO_ROOT = path.resolve(__dirname, '..', '..');
const BATS_DIR = path.join(REPO_ROOT, 'tests', 'bats');

// A cheap fixture that does `git init` + `git config` against a temp repo —
// the exact shape that leaked. Used as the child process under a poisoned env.
const CHILD_TEST = 'tests/unit/bug-023-adoption-routing.qa.test.ts';

// Two Bats children: one that spells `git init` literally, and one that goes
// through "$REAL_GIT" — the indirect form that leaked past the first version of
// this guard. Both must leave the sacrificial repo untouched.
const BATS_CHILDREN = [
  'tests/bats/shared/new-requirement.bats',
  'tests/bats/skills/managing-source-control/list-pr-comments.bats',
];

// ---------------------------------------------------------------------------
// Unit: the sanitizer itself
// ---------------------------------------------------------------------------
describe('stripGitEnv', () => {
  it('removes every GIT_* key and reports them sorted', () => {
    const env: NodeJS.ProcessEnv = {
      GIT_DIR: '/repo/.git',
      GIT_WORK_TREE: '/repo',
      GIT_INDEX_FILE: '/repo/.git/index',
      PATH: '/usr/bin',
      HOME: '/home/dev',
    };
    expect(stripGitEnv(env)).toEqual(['GIT_DIR', 'GIT_INDEX_FILE', 'GIT_WORK_TREE']);
    expect(env).toEqual({ PATH: '/usr/bin', HOME: '/home/dev' });
  });

  it('leaves non-GIT keys alone and is a no-op on a clean env', () => {
    const env: NodeJS.ProcessEnv = { GITHUB_TOKEN: 'x', DIGIT_COUNT: '3' };
    expect(stripGitEnv(env)).toEqual([]);
    expect(env).toEqual({ GITHUB_TOKEN: 'x', DIGIT_COUNT: '3' });
  });

  it('prefix is the bare GIT_ namespace', () => {
    expect(GIT_ENV_PREFIX).toBe('GIT_');
  });
});

// ---------------------------------------------------------------------------
// Wiring: the sanitizer must actually be installed at each entry point
// ---------------------------------------------------------------------------
describe('Sanitizer wiring', () => {
  it('this worker has no inherited GIT_* vars (setupFiles ran)', () => {
    expect(Object.keys(process.env).filter((k) => k.startsWith('GIT_'))).toEqual([]);
  });

  it('vitest.config.ts registers tests/setup/git-env.ts as a setup file', () => {
    const cfg = fs.readFileSync(path.join(REPO_ROOT, 'vitest.config.ts'), 'utf8');
    expect(cfg).toMatch(/setupFiles:\s*\[[^\]]*['"]tests\/setup\/git-env\.ts['"]/);
  });

  it('.husky/pre-push strips the inherited git env before running npm test', () => {
    const hook = fs.readFileSync(path.join(REPO_ROOT, '.husky', 'pre-push'), 'utf8');
    const lines = hook.split('\n');
    const unsetLine = lines.findIndex((l) => /^\s*unset\s+"?\$/.test(l));
    const testLine = lines.findIndex((l) => /^\s*npm\s+test\b/.test(l));
    expect(unsetLine).toBeGreaterThanOrEqual(0);
    expect(testLine).toBeGreaterThanOrEqual(0);
    expect(unsetLine).toBeLessThan(testLine);
    // Prefix-driven, not a name list — an enumerated list silently misses any
    // GIT_* variable added later, which is exactly how this bug stayed hidden.
    expect(hook).toMatch(/GIT_\[A-Za-z0-9_\]\*/);
  });

  it('.husky/pre-push actually strips GIT_* when run under sh', () => {
    // Execute the hook's strip prologue (everything before `npm test`) under a
    // poisoned env and confirm nothing GIT_* survives. Asserting on the text
    // alone would pass on a prologue that does not work.
    const hook = fs.readFileSync(path.join(REPO_ROOT, '.husky', 'pre-push'), 'utf8');
    const prologue = hook.slice(0, hook.indexOf('npm test'));
    const probe = spawnSync('sh', ['-c', `${prologue}\nenv | grep -c '^GIT_' || true`], {
      encoding: 'utf8',
      env: {
        ...process.env,
        GIT_DIR: '/poison/.git',
        GIT_WORK_TREE: '/poison',
        GIT_INDEX_FILE: '/poison/.git/index',
        GIT_SOME_FUTURE_VAR: 'x',
      },
    });
    expect(probe.status).toBe(0);
    expect(probe.stdout.trim()).toBe('0');
  });
});

// ---------------------------------------------------------------------------
// Guard: every Bats file that shells out to git must load the helper
// ---------------------------------------------------------------------------

function listBatsFiles(dir: string): string[] {
  const out: string[] = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const abs = path.join(dir, entry.name);
    if (entry.isDirectory()) out.push(...listBatsFiles(abs));
    else if (entry.name.endsWith('.bats')) out.push(abs);
  }
  return out;
}

// The rule is unconditional: EVERY .bats file loads the helper, whether or not
// it currently shells out to git.
//
// An earlier revision gated this on a regex for literal `git <subcommand>`.
// That missed every indirect invocation — `"$REAL_GIT" init`, `git -C <dir>
// init`, `git -c k=v commit` — and eight fixtures under
// tests/bats/skills/managing-source-control/ leaked through the hole while the
// guard reported green. A subcommand/spelling allowlist is the wrong shape for
// this: it fails open. Requiring the helper everywhere fails closed, and the
// cost to a git-free fixture is three inert lines.
describe('Bats git-env guard', () => {
  const batsFiles = listBatsFiles(BATS_DIR);

  it('finds the Bats tree', () => {
    expect(batsFiles.length).toBeGreaterThan(30);
  });

  it('every Bats file loads the helper and calls sanitize_git_env', () => {
    const offenders: string[] = [];
    for (const abs of batsFiles) {
      const src = fs.readFileSync(abs, 'utf8');
      if (!/^\s*load\s+'.*helpers\/git-env'/m.test(src) || !/^\s*sanitize_git_env\s*$/m.test(src)) {
        offenders.push(path.relative(REPO_ROOT, abs));
      }
    }
    expect(offenders).toEqual([]);
  });

  it('catches indirect git invocations the old subcommand allowlist missed', () => {
    // Regression lock on the guard itself: these files invoke git through a
    // variable, so any spelling-based detector would skip them.
    const indirect = batsFiles.filter((abs) =>
      /"\$REAL_GIT"\s+(init|config)/.test(fs.readFileSync(abs, 'utf8'))
    );
    expect(indirect.length).toBeGreaterThan(0);
    for (const abs of indirect) {
      expect(fs.readFileSync(abs, 'utf8')).toMatch(/^\s*sanitize_git_env\s*$/m);
    }
  });

  it('each helper load path resolves to tests/bats/helpers/git-env.bash', () => {
    const broken: string[] = [];
    for (const abs of batsFiles) {
      const src = fs.readFileSync(abs, 'utf8');
      const m = src.match(/^\s*load\s+'(.*helpers\/git-env)'/m);
      if (!m) continue;
      const resolved = path.resolve(path.dirname(abs), `${m[1]}.bash`);
      if (!fs.existsSync(resolved)) broken.push(`${path.relative(REPO_ROOT, abs)} -> ${m[1]}`);
    }
    expect(broken).toEqual([]);
  });

  it('sanitize_git_env is called at file scope, before any setup() body', () => {
    const late: string[] = [];
    for (const abs of batsFiles) {
      const lines = fs.readFileSync(abs, 'utf8').split('\n');
      const call = lines.findIndex((l) => /^\s*sanitize_git_env\s*$/.test(l));
      if (call < 0) continue;
      const setup = lines.findIndex((l) => /^\s*setup(_file)?\s*\(\)/.test(l));
      if (setup >= 0 && call > setup) late.push(path.relative(REPO_ROOT, abs));
    }
    expect(late).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// End-to-end: a poisoned GIT_DIR must not reach a sacrificial repo
// ---------------------------------------------------------------------------

/**
 * A nested `vitest run` hangs if it inherits the parent suite's VITEST_* worker
 * hints — same constraint tests/unit/feat-030-executing-qa.test.ts works around.
 * Colour is disabled so child output stays greppable on failure.
 */
function childEnvWithoutVitest(): NodeJS.ProcessEnv {
  const env: NodeJS.ProcessEnv = { ...process.env };
  for (const key of Object.keys(env)) {
    if (key.startsWith('VITEST') || key === 'VITE_NODE_DEPS_MODULE_DIRECTORIES') delete env[key];
  }
  env.NO_COLOR = '1';
  env.FORCE_COLOR = '0';
  return env;
}

interface Sacrifice {
  root: string;
  commonConfig: string;
  worktreeGitDir: string;
}

let tmp = '';

/**
 * Build a throwaway repo plus a linked worktree, and return the worktree's
 * gitdir — the poison that reproduces BOTH symptoms (core.bare flip + identity
 * leak). A plain `.git` GIT_DIR only reproduces the identity leak, because git
 * infers the work tree from the `.git` basename.
 */
function makeSacrifice(): Sacrifice {
  const root = path.join(tmp, 'sacrifice');
  fs.mkdirSync(root, { recursive: true });
  const run = (args: string[], cwd = root) =>
    execFileSync('git', args, { cwd, encoding: 'utf8', env: process.env });
  run(['init', '-q', '-b', 'main']);
  run(['config', 'user.email', 'owner@sacrifice.test']);
  run(['config', 'user.name', 'Sacrifice Owner']);
  run(['config', 'commit.gpgsign', 'false']);
  fs.writeFileSync(path.join(root, 'README'), 'placeholder\n');
  run(['add', '-A']);
  run(['commit', '-q', '-m', 'init']);

  const wt = path.join(tmp, 'sacrifice-wt');
  run(['worktree', 'add', '-q', '-b', 'probe', wt]);
  const worktreeGitDir = execFileSync('git', ['rev-parse', '--absolute-git-dir'], {
    cwd: wt,
    encoding: 'utf8',
    env: process.env,
  }).trim();

  return { root, commonConfig: path.join(root, '.git', 'config'), worktreeGitDir };
}

beforeEach(() => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'git-env-isolation-'));
});
afterEach(() => {
  if (tmp && fs.existsSync(tmp)) fs.rmSync(tmp, { recursive: true, force: true });
});

describe('End-to-end: inherited GIT_DIR cannot reach another repository', () => {
  it('oracle — raw git under a poisoned GIT_DIR DOES corrupt the sacrificial repo', () => {
    // Negative control. If this ever stops failing, the regression test below
    // is vacuous and the whole suite is lying.
    const s = makeSacrifice();
    const before = fs.readFileSync(s.commonConfig, 'utf8');
    const elsewhere = fs.mkdtempSync(path.join(tmp, 'cwd-'));
    const poisoned = { ...process.env, GIT_DIR: s.worktreeGitDir };

    execFileSync('git', ['init', '-q'], { cwd: elsewhere, env: poisoned, stdio: 'pipe' });
    execFileSync('git', ['config', 'user.email', 'fixture@leak.test'], {
      cwd: elsewhere,
      env: poisoned,
    });

    const after = fs.readFileSync(s.commonConfig, 'utf8');
    expect(after).not.toBe(before);
    expect(after).toContain('bare = true');
    expect(after).toContain('fixture@leak.test');
  });

  it('a child Vitest run under a poisoned GIT_DIR leaves the sacrificial config byte-identical', () => {
    const s = makeSacrifice();
    const before = fs.readFileSync(s.commonConfig);

    const child = spawnSync('npx', ['vitest', 'run', CHILD_TEST], {
      cwd: REPO_ROOT,
      encoding: 'utf8',
      env: { ...childEnvWithoutVitest(), GIT_DIR: s.worktreeGitDir },
    });
    // The child must run AND pass. `not.toBeNull()` is not enough: if CHILD_TEST
    // is renamed away, vitest exits non-zero having made zero git calls and the
    // byte-identity assertion below passes vacuously.
    expect(child.error).toBeUndefined();
    expect(child.status, `child vitest failed:\n${child.stdout}\n${child.stderr}`).toBe(0);
    expect(fs.existsSync(path.join(REPO_ROOT, CHILD_TEST))).toBe(true);

    expect(fs.readFileSync(s.commonConfig)).toEqual(before);
    // Spell out the two reported symptoms for a readable failure.
    const after = fs.readFileSync(s.commonConfig, 'utf8');
    expect(after).toContain('bare = false');
    expect(after).toContain('owner@sacrifice.test');
  }, 180_000);

  it('a child Bats run under a poisoned GIT_DIR leaves the sacrificial config byte-identical', () => {
    const s = makeSacrifice();
    const before = fs.readFileSync(s.commonConfig);

    const child = spawnSync('npx', ['bats', ...BATS_CHILDREN], {
      cwd: REPO_ROOT,
      encoding: 'utf8',
      env: { ...process.env, GIT_DIR: s.worktreeGitDir },
    });
    expect(child.error).toBeUndefined();
    expect(child.status, `child bats failed:\n${child.stdout}\n${child.stderr}`).toBe(0);
    for (const rel of BATS_CHILDREN) {
      expect(fs.existsSync(path.join(REPO_ROOT, rel))).toBe(true);
    }

    expect(fs.readFileSync(s.commonConfig)).toEqual(before);
    const after = fs.readFileSync(s.commonConfig, 'utf8');
    expect(after).toContain('bare = false');
    expect(after).toContain('owner@sacrifice.test');
  }, 180_000);
});
