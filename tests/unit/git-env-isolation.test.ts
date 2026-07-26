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
//   2. tests/bats/helpers/git-env.bash, loaded by every Bats file. Loading it
//      IS the sanitization — it self-invokes on source, so there is no second
//      line for a fixture to omit and no ordering for a guard to police.
//   3. the GIT_* strip prologue at the top of .husky/pre-push.

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { execFileSync, spawnSync } from 'node:child_process';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';

// Imported from the side-effect-free module on purpose. Importing
// `../setup/git-env` would run the sanitizer, making the "setupFiles ran"
// assertion below pass off this file's own import.
import { stripGitEnv, GIT_ENV_PREFIX, GIT_ENV_SETUP_MARKER } from '../setup/strip-git-env';

const REPO_ROOT = path.resolve(__dirname, '..', '..');
const BATS_DIR = path.join(REPO_ROOT, 'tests', 'bats');
const HELPER = path.join(BATS_DIR, 'helpers', 'git-env.bash');

// Bats child for the end-to-end guard: this feature's own fixture. It shells
// out to git and is owned by the same change as the guard, so it cannot fail
// for reasons unrelated to git-env isolation — the coupling an unrelated
// fixture (a stubbed `gh`/`az` harness, say) would introduce.
const BATS_CHILD = 'tests/bats/shared/git-env.bats';

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
  it('Vitest executed tests/setup/git-env.ts as a setup file', () => {
    // The marker is set only by the setup module, which this file does not
    // import. Asserting on `process.env` alone would be self-satisfying, and
    // would keep passing through a config migration that preserves the
    // `setupFiles` text but loses its effect (e.g. Vitest `projects:`, whose
    // per-project `test` block does not inherit root `test.setupFiles`).
    expect((globalThis as Record<string, unknown>)[GIT_ENV_SETUP_MARKER]).toBe(true);
  });

  it('this worker has no inherited GIT_* vars', () => {
    expect(Object.keys(process.env).filter((k) => k.startsWith('GIT_'))).toEqual([]);
  });

  it('vitest.config.ts registers tests/setup/git-env.ts as a setup file', () => {
    const cfg = fs.readFileSync(path.join(REPO_ROOT, 'vitest.config.ts'), 'utf8');
    expect(cfg).toMatch(/setupFiles:\s*\[[^\]]*['"]tests\/setup\/git-env\.ts['"]/);
  });

  it('.husky/pre-push strips GIT_* before it runs anything', () => {
    // Execute the hook's prologue — everything above its first npm command —
    // under a poisoned env, and confirm nothing GIT_* survives.
    //
    // No assertion on the prologue's TEXT: a maintainer who swaps the
    // `env | sed` pipeline for an equivalent POSIX loop is making a correct
    // change, and a text assertion would fail it — while the failing suite is
    // itself what pre-push runs, so the push carrying the rewrite is blocked.
    const hook = fs.readFileSync(path.join(REPO_ROOT, '.husky', 'pre-push'), 'utf8');
    const lines = hook.split('\n');
    // Slice at the first npm command by shape, not at the literal `npm test`:
    // `indexOf('npm test')` returns -1 after a rename such as
    // `npm run test:unit`, and -1 used as a slice end yields the WHOLE hook,
    // so the probe below would run the entire suite recursively.
    const firstNpm = lines.findIndex((l) => /^\s*npm\b/.test(l));
    expect(firstNpm, 'pre-push runs no npm command').toBeGreaterThan(0);
    const prologue = lines.slice(0, firstNpm).join('\n');
    expect(prologue).not.toMatch(/^\s*npm\b/m);

    const probe = spawnSync('sh', ['-c', `${prologue}\nenv | grep -c '^GIT_' || true`], {
      encoding: 'utf8',
      env: {
        ...process.env,
        GIT_DIR: '/poison/.git',
        GIT_WORK_TREE: '/poison',
        GIT_INDEX_FILE: '/poison/.git/index',
        // A name no list would enumerate. Its removal is what proves the
        // prologue strips by prefix rather than by a fixed name list — which
        // is exactly how this bug stayed hidden.
        GIT_SOME_FUTURE_VAR: 'x',
      },
    });
    expect(probe.status).toBe(0);
    expect(probe.stdout.trim()).toBe('0');
  });
});

// ---------------------------------------------------------------------------
// Guard: every Bats file must load the helper
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

/**
 * Extract the argument of the `load` line that pulls in the git-env helper.
 *
 * Accepts every spelling Bats accepts — single-quoted, double-quoted and bare,
 * with or without a trailing comment — rather than pinning the repo's current
 * habit. A stricter matcher reports a correctly-protected file as an offender,
 * with a message saying the load is missing when it is right there, and then
 * silently skips that file in every downstream check.
 */
function findGitEnvLoad(src: string): string | null {
  for (const line of src.split('\n')) {
    const m = line.match(/^\s*load\s+(?:'([^']*)'|"([^"]*)"|(\S+))\s*(?:#.*)?$/);
    if (!m) continue;
    const spec = m[1] ?? m[2] ?? m[3];
    if (spec && /helpers\/git-env$/.test(spec)) return spec;
  }
  return null;
}

/**
 * Resolve a load spec the way Bash + Bats would, for a .bats file sitting in
 * `batsDir`. Understands the `${BATS_TEST_DIRNAME%/tests/bats/*}` prefix strip
 * (shortest matching suffix, i.e. the LAST `/tests/bats/` in the path).
 */
function resolveLoadSpec(spec: string, batsDir: string): string {
  const cut = batsDir.lastIndexOf('/tests/bats/');
  const repoRoot = cut < 0 ? batsDir : batsDir.slice(0, cut);
  const expanded = spec
    .replace('${BATS_TEST_DIRNAME%/tests/bats/*}', repoRoot)
    .replace('${BATS_TEST_DIRNAME}', batsDir);
  return path.isAbsolute(expanded) ? expanded : path.resolve(batsDir, expanded);
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
// cost to a git-free fixture is two inert lines.
//
// There is deliberately NO "calls sanitize_git_env at file scope" guard. The
// helper self-invokes on load, so the load line alone is sufficient — and a
// token-matching guard could not police the call honestly anyway: it passed a
// fixture whose only occurrence sat inside a never-called function, and it
// skipped any fixture with no setup() at all.
describe('Bats git-env guard', () => {
  const batsFiles = listBatsFiles(BATS_DIR);

  it('finds the Bats tree', () => {
    expect(batsFiles.length).toBeGreaterThan(30);
  });

  it('every Bats file loads the helper', () => {
    const offenders = batsFiles
      .filter((abs) => findGitEnvLoad(fs.readFileSync(abs, 'utf8')) === null)
      .map((abs) => path.relative(REPO_ROOT, abs));
    expect(offenders, 'these .bats files are missing the git-env helper load').toEqual([]);
  });

  it('every helper load path resolves to tests/bats/helpers/git-env.bash', () => {
    const broken: string[] = [];
    for (const abs of batsFiles) {
      const spec = findGitEnvLoad(fs.readFileSync(abs, 'utf8'));
      if (spec === null) continue;
      const resolved = `${resolveLoadSpec(spec, path.dirname(abs))}.bash`;
      if (resolved !== HELPER) broken.push(`${path.relative(REPO_ROOT, abs)} -> ${spec}`);
    }
    expect(broken).toEqual([]);
  });

  it('every helper load path is depth-independent', () => {
    // adopt-qa-test.sh moves QA Bats files with a bare `git mv` and no load-path
    // rewrite, and the source and target live at different depths
    // (tests/bats/qa/ -> tests/bats/skills/<skill>/). A depth-relative
    // `../helpers/git-env` therefore resolves to nothing after adoption, bats
    // reports `bats_load_safe: Could not find ...`, and the whole adopted file
    // is dead on a branch the QA loop just declared clean.
    //
    // Verifying every real depth in the tree, plus one deeper than any that
    // exists today, keeps that from silently regressing.
    const depths = [
      path.join(BATS_DIR, 'qa'),
      path.join(BATS_DIR, 'shared'),
      path.join(BATS_DIR, 'shared', 'hooks'),
      path.join(BATS_DIR, 'skills', 'executing-qa'),
      path.join(BATS_DIR, 'skills', 'some', 'deeper', 'tree'),
    ];
    const broken: string[] = [];
    for (const abs of batsFiles) {
      const spec = findGitEnvLoad(fs.readFileSync(abs, 'utf8'));
      if (spec === null) continue;
      for (const dir of depths) {
        if (`${resolveLoadSpec(spec, dir)}.bash` !== HELPER) {
          broken.push(
            `${path.relative(REPO_ROOT, abs)} breaks if moved to ${path.relative(REPO_ROOT, dir)}/`
          );
        }
      }
    }
    expect(broken).toEqual([]);
  });

  it('the helper self-invokes, so loading it is sufficient', () => {
    // The property the guard above leans on. If this line is ever dropped, no
    // .bats file sanitizes anything — they only load a function definition.
    const src = fs.readFileSync(HELPER, 'utf8');
    expect(src).toMatch(/^sanitize_git_env\s*$/m);
    // ...and the call must sit below the definition, at file scope.
    const def = src.indexOf('sanitize_git_env() {');
    const call = src.search(/^sanitize_git_env\s*$/m);
    expect(def).toBeGreaterThanOrEqual(0);
    expect(call).toBeGreaterThan(def);
  });

  it('no .bats file sits in tests/bats/helpers/', () => {
    // adopt-qa-test.sh resolves a QA file's `load` targets to find its peer
    // test. The helper's load spec is an unexpanded `${BATS_TEST_DIRNAME...}`
    // string, so it resolves to nothing and cannot be picked as a peer today.
    // A fixture landing at tests/bats/helpers/*.bats would still be wrong: it
    // is not a peer of any SUT and does not belong to a skill.
    const helpersDir = path.join(BATS_DIR, 'helpers');
    const strays = fs.readdirSync(helpersDir).filter((f) => f.endsWith('.bats'));
    expect(strays).toEqual([]);
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

/**
 * Write a self-contained child Vitest project that calls git the way the
 * leaking fixtures did.
 *
 * Purpose-built rather than pointed at an existing suite file: pinning the
 * child to a named test file makes any unrelated failure or rename in that
 * file surface here as a git-env isolation regression, so one defect reports
 * twice and sends the reader to the wrong subsystem.
 *
 * It lives under the gitignored `temp/` inside the repo so `vitest/config` and
 * `vitest` resolve through the repo's node_modules, and it registers the REAL
 * tests/setup/git-env.ts — the module under test.
 */
function writeChildVitestProject(): string {
  const dir = fs.mkdtempSync(path.join(REPO_ROOT, 'temp', 'git-env-child-'));
  const setup = path.join(REPO_ROOT, 'tests', 'setup', 'git-env.ts');
  fs.writeFileSync(
    path.join(dir, 'vitest.config.ts'),
    `import { defineConfig } from 'vitest/config';\n` +
      `export default defineConfig({ test: { setupFiles: [${JSON.stringify(setup)}] } });\n`
  );
  fs.writeFileSync(
    path.join(dir, 'leak.test.ts'),
    `import { it, expect } from 'vitest';\n` +
      `import { execFileSync } from 'node:child_process';\n` +
      `import * as fs from 'node:fs';\n` +
      `import * as os from 'node:os';\n` +
      `import * as path from 'node:path';\n` +
      `it('fixture git calls land in the fixture', () => {\n` +
      `  expect(process.env.GIT_DIR).toBeUndefined();\n` +
      `  const cwd = fs.mkdtempSync(path.join(os.tmpdir(), 'git-env-leak-'));\n` +
      `  execFileSync('git', ['init', '-q'], { cwd });\n` +
      `  execFileSync('git', ['config', 'user.email', 'fixture@leak.test'], { cwd });\n` +
      `  fs.rmSync(cwd, { recursive: true, force: true });\n` +
      `});\n`
  );
  return dir;
}

beforeEach(() => {
  fs.mkdirSync(path.join(REPO_ROOT, 'temp'), { recursive: true });
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'git-env-isolation-'));
});
afterEach(() => {
  if (tmp && fs.existsSync(tmp)) fs.rmSync(tmp, { recursive: true, force: true });
});

describe('End-to-end: inherited GIT_DIR cannot reach another repository', () => {
  it('oracle — raw git under a poisoned GIT_DIR DOES corrupt the sacrificial repo', () => {
    // Negative control. If this ever stops failing, the regression tests below
    // are vacuous and the whole suite is lying.
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
    const project = writeChildVitestProject();

    try {
      const child = spawnSync('npx', ['vitest', 'run', '--root', project], {
        cwd: REPO_ROOT,
        encoding: 'utf8',
        env: { ...childEnvWithoutVitest(), GIT_DIR: s.worktreeGitDir },
      });
      // The child must run AND pass: a child that never started makes the
      // byte-identity assertion below pass vacuously.
      expect(child.error).toBeUndefined();
      expect(child.status, `child vitest failed:\n${child.stdout}\n${child.stderr}`).toBe(0);

      expect(fs.readFileSync(s.commonConfig)).toEqual(before);
      // Spell out the two reported symptoms for a readable failure.
      const after = fs.readFileSync(s.commonConfig, 'utf8');
      expect(after).toContain('bare = false');
      expect(after).toContain('owner@sacrifice.test');
    } finally {
      fs.rmSync(project, { recursive: true, force: true });
    }
  }, 180_000);

  it('a child Bats run under a poisoned GIT_DIR leaves the sacrificial config byte-identical', () => {
    const s = makeSacrifice();
    const before = fs.readFileSync(s.commonConfig);

    // Existence first: if the fixture is renamed away, bats exits non-zero and
    // the status assertion would otherwise report "child bats failed" while the
    // real cause — the file is gone — is never surfaced.
    expect(fs.existsSync(path.join(REPO_ROOT, BATS_CHILD))).toBe(true);

    const child = spawnSync('npx', ['bats', BATS_CHILD], {
      cwd: REPO_ROOT,
      encoding: 'utf8',
      env: { ...process.env, GIT_DIR: s.worktreeGitDir },
    });
    expect(child.error).toBeUndefined();
    expect(child.status, `child bats failed:\n${child.stdout}\n${child.stderr}`).toBe(0);

    expect(fs.readFileSync(s.commonConfig)).toEqual(before);
    const after = fs.readFileSync(s.commonConfig, 'utf8');
    expect(after).toContain('bare = false');
    expect(after).toContain('owner@sacrifice.test');
  }, 180_000);
});
