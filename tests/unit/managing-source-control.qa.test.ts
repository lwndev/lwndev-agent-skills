// QA-FEAT-033: adversarial coverage for managing-source-control skill.
//
// Spawns the dispatcher scripts under test with crafted stubs/env to verify
// behavior across the P0/P1 scenarios in qa/test-plans/QA-plan-FEAT-033.md
// that are NOT already covered by tests/bats/skills/managing-source-control/*.
//
// Scope (highest-impact gaps):
//   1. backend-detect.sh: SDLC_SCM_BACKEND=gitlab (unknown override)
//   2. backend-detect.sh: vs-ssh.visualstudio.com legacy SSH (unsupported form)
//   3. create-pr.sh: --closes "" (empty) → exit 2 usage error
//   4. create-pr.sh: --closes "   " (whitespace-only) → behavior gap
//   5. create-pr.sh: summary with shell metachars (`'`, backtick, `$()`)
//      preserved as literal in gh argv
//   6. create-pr.sh: invalid type → exit 2
//   7. validate-no-inline-scm.ts: gh pr inside a heredoc body (false-positive)
//   8. validate-no-inline-scm.ts: gh pr inside single-quoted string is stripped
//      (false-negative is intentional per script comments — assert the behavior)

import { execSync, spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

const REPO_ROOT = execSync('git rev-parse --show-toplevel').toString().trim();
const SCRIPT_DIR = join(REPO_ROOT, 'plugins/lwndev-sdlc/skills/managing-source-control/scripts');
const BACKEND_DETECT = join(SCRIPT_DIR, 'backend-detect.sh');
const CREATE_PR = join(SCRIPT_DIR, 'create-pr.sh');
const VALIDATOR = join(REPO_ROOT, 'scripts/validate-no-inline-scm.ts');

let workDir: string;

function makeTempRepo(originUrl: string): string {
  const dir = mkdtempSync(join(tmpdir(), 'qa-feat-033-'));
  execSync('git init --quiet', { cwd: dir });
  execSync('git config user.email "test@example.com"', { cwd: dir });
  execSync('git config user.name "Test"', { cwd: dir });
  execSync(`git remote add origin "${originUrl}"`, { cwd: dir });
  return dir;
}

function makeStubBin(dir: string): string {
  const bin = join(dir, 'bin');
  mkdirSync(bin, { recursive: true });
  return bin;
}

beforeEach(() => {
  workDir = '';
});

afterEach(() => {
  if (workDir) {
    rmSync(workDir, { recursive: true, force: true });
  }
});

describe('backend-detect.sh adversarial', () => {
  it('SDLC_SCM_BACKEND=gitlab (unknown override) emits null + warn, exit 0', () => {
    workDir = makeTempRepo('https://github.com/owner/repo.git');
    const r = spawnSync('bash', [BACKEND_DETECT], {
      cwd: workDir,
      env: { ...process.env, SDLC_SCM_BACKEND: 'gitlab' },
      encoding: 'utf-8',
    });
    expect(r.status).toBe(0);
    expect(r.stdout.trim()).toBe('null');
    expect(r.stderr).toMatch(/\[warn\].*SDLC_SCM_BACKEND=gitlab.*not recognized/);
  });

  it('vs-ssh.visualstudio.com SSH form (legacy, unsupported) emits null, exit 0', () => {
    // This form is NOT enumerated in backend-detect.sh's accepted patterns.
    // The contract is "graceful skip" via null + exit 0 — assert that.
    workDir = makeTempRepo('git@vs-ssh.visualstudio.com:v3/contoso/proj/repo');
    const r = spawnSync('bash', [BACKEND_DETECT], {
      cwd: workDir,
      env: process.env,
      encoding: 'utf-8',
    });
    expect(r.status).toBe(0);
    expect(r.stdout.trim()).toBe('null');
  });

  it('SDLC_SCM_BACKEND=github with azdo origin (mismatch) emits null + warn, exit 0', () => {
    workDir = makeTempRepo('https://dev.azure.com/contoso/proj/_git/repo');
    const r = spawnSync('bash', [BACKEND_DETECT], {
      cwd: workDir,
      env: { ...process.env, SDLC_SCM_BACKEND: 'github' },
      encoding: 'utf-8',
    });
    expect(r.status).toBe(0);
    expect(r.stdout.trim()).toBe('null');
    expect(r.stderr).toMatch(/\[warn\].*SDLC_SCM_BACKEND=github.*does not match/);
  });

  it('No origin remote → null, exit 0', () => {
    workDir = mkdtempSync(join(tmpdir(), 'qa-feat-033-noorigin-'));
    execSync('git init --quiet', { cwd: workDir });
    execSync('git config user.email "test@example.com"', { cwd: workDir });
    execSync('git config user.name "Test"', { cwd: workDir });
    const r = spawnSync('bash', [BACKEND_DETECT], {
      cwd: workDir,
      env: process.env,
      encoding: 'utf-8',
    });
    expect(r.status).toBe(0);
    expect(r.stdout.trim()).toBe('null');
  });
});

describe('create-pr.sh adversarial', () => {
  function buildGithubStubRepo(): { repo: string; bin: string } {
    const repo = makeTempRepo('https://github.com/owner/repo.git');
    const bin = makeStubBin(repo);
    // Stubs: git push, gh auth status, gh pr create
    const realGit = execSync('command -v git').toString().trim();
    writeFileSync(
      join(bin, 'git'),
      `#!/usr/bin/env bash
case "$1" in
  push) echo "(stub push)"; exit 0 ;;
  rev-parse)
    if [ "$2" = "--abbrev-ref" ] && [ "$3" = "HEAD" ]; then echo "feat/qa-test"; exit 0; fi
    exec "${realGit}" "$@" ;;
  *) exec "${realGit}" "$@" ;;
esac
`,
      { mode: 0o755 }
    );
    writeFileSync(
      join(bin, 'gh'),
      `#!/usr/bin/env bash
case "$1" in
  auth) exit 0 ;;
  pr)
    if [ "$2" = "create" ]; then
      # Record every arg verbatim, one per line, for assertion.
      : > "${bin}/gh.args"
      for a in "$@"; do printf '%s\\n' "$a" >> "${bin}/gh.args"; done
      echo "https://github.com/owner/repo/pull/1"
      exit 0
    fi
    exit 0 ;;
  *) exit 0 ;;
esac
`,
      { mode: 0o755 }
    );
    return { repo, bin };
  }

  it('--closes "" → exit 2 with malformed-arg error', () => {
    const { repo, bin } = buildGithubStubRepo();
    workDir = repo;
    const r = spawnSync('bash', [CREATE_PR, 'feat', 'FEAT-999', 'summary', '--closes', ''], {
      cwd: repo,
      env: { ...process.env, PATH: `${bin}:${process.env.PATH}` },
      encoding: 'utf-8',
    });
    expect(r.status).toBe(2);
    expect(r.stderr).toMatch(/--closes value is malformed/);
  });

  it('--closes "   " (whitespace-only) is accepted (documented gap)', () => {
    // Current behavior: `[ -z "$closes" ]` is false for "   ", so the script
    // does NOT reject. The body would render "Closes    " (malformed). This
    // test asserts current behavior; the gap is recorded in ## Findings.
    const { repo, bin } = buildGithubStubRepo();
    workDir = repo;
    const r = spawnSync('bash', [CREATE_PR, 'feat', 'FEAT-999', 'summary', '--closes', '   '], {
      cwd: repo,
      env: { ...process.env, PATH: `${bin}:${process.env.PATH}` },
      encoding: 'utf-8',
    });
    expect(r.status).toBe(0);
    // The gh stub recorded the args; the body should include "Closes    ".
    const args = readFileSync(join(bin, 'gh.args'), 'utf-8');
    expect(args).toMatch(/Closes {3}/);
  });

  it('invalid type → exit 2 with type error', () => {
    const { repo, bin } = buildGithubStubRepo();
    workDir = repo;
    const r = spawnSync('bash', [CREATE_PR, 'bogus', 'FEAT-999', 'summary'], {
      cwd: repo,
      env: { ...process.env, PATH: `${bin}:${process.env.PATH}` },
      encoding: 'utf-8',
    });
    expect(r.status).toBe(2);
    expect(r.stderr).toMatch(/invalid type 'bogus'/);
  });

  it('summary with shell metacharacters is passed literally to gh argv', () => {
    const { repo, bin } = buildGithubStubRepo();
    workDir = repo;
    const evilSummary = "it's `whoami` and $(date)";
    const r = spawnSync('bash', [CREATE_PR, 'feat', 'FEAT-999', evilSummary], {
      cwd: repo,
      env: { ...process.env, PATH: `${bin}:${process.env.PATH}` },
      encoding: 'utf-8',
    });
    expect(r.status).toBe(0);
    const args = readFileSync(join(bin, 'gh.args'), 'utf-8');
    // The title arg gh receives is `feat(FEAT-999): it's \`whoami\` and $(date)`
    expect(args).toContain("feat(FEAT-999): it's `whoami` and $(date)");
  });

  it('pr-body.tmpl missing → exit 1 with template-not-found error', () => {
    // Move the template aside in a copy of the plugin tree so the stub can't
    // find it, then run create-pr.sh against that tree.
    const fakePluginRoot = mkdtempSync(join(tmpdir(), 'qa-feat-033-noTmpl-'));
    mkdirSync(join(fakePluginRoot, 'plugins/lwndev-sdlc/scripts/assets'), {
      recursive: true,
    });
    const skillScripts = join(
      fakePluginRoot,
      'plugins/lwndev-sdlc/skills/managing-source-control/scripts'
    );
    mkdirSync(skillScripts, { recursive: true });
    // Copy the dispatcher + backend-detect so create-pr.sh's sibling lookup works.
    execSync(`cp "${BACKEND_DETECT}" "${skillScripts}/backend-detect.sh"`);
    execSync(`cp "${CREATE_PR}" "${skillScripts}/create-pr.sh"`);
    // Intentionally do NOT copy pr-body.tmpl.

    // Init a github-origin repo so backend-detect → github.
    execSync('git init --quiet', { cwd: fakePluginRoot });
    execSync('git config user.email "t@e.com"', { cwd: fakePluginRoot });
    execSync('git config user.name "t"', { cwd: fakePluginRoot });
    execSync('git remote add origin https://github.com/owner/repo.git', { cwd: fakePluginRoot });

    const bin = makeStubBin(fakePluginRoot);
    const realGit = execSync('command -v git').toString().trim();
    writeFileSync(
      join(bin, 'git'),
      `#!/usr/bin/env bash
case "$1" in
  push) echo "(stub push)"; exit 0 ;;
  rev-parse)
    if [ "$2" = "--abbrev-ref" ] && [ "$3" = "HEAD" ]; then echo "feat/x"; exit 0; fi
    exec "${realGit}" "$@" ;;
  *) exec "${realGit}" "$@" ;;
esac
`,
      { mode: 0o755 }
    );
    writeFileSync(
      join(bin, 'gh'),
      `#!/usr/bin/env bash
[ "$1" = "auth" ] && exit 0
exit 0
`,
      { mode: 0o755 }
    );
    workDir = fakePluginRoot;
    const r = spawnSync(
      'bash',
      [join(skillScripts, 'create-pr.sh'), 'feat', 'FEAT-999', 'summary'],
      {
        cwd: fakePluginRoot,
        env: { ...process.env, PATH: `${bin}:${process.env.PATH}` },
        encoding: 'utf-8',
      }
    );
    expect(r.status).toBe(1);
    expect(r.stderr).toMatch(/template not found/);
  });
});

describe('validate-no-inline-scm.ts adversarial', () => {
  it('flags inline gh pr at command position in a non-allow-listed .sh', () => {
    workDir = mkdtempSync(join(tmpdir(), 'qa-feat-033-validator-positive-'));
    // We need the validator's CWD to be a fake repo root with the bad file.
    const root = workDir;
    mkdirSync(join(root, 'plugins/lwndev-sdlc/skills/some-other-skill/scripts'), {
      recursive: true,
    });
    writeFileSync(
      join(root, 'plugins/lwndev-sdlc/skills/some-other-skill/scripts/bad.sh'),
      '#!/usr/bin/env bash\ngh pr create --title x\n'
    );
    const r = spawnSync('npx', ['tsx', VALIDATOR], {
      cwd: root,
      env: process.env,
      encoding: 'utf-8',
    });
    expect(r.status).toBe(1);
    expect(r.stdout).toMatch(/bad\.sh:2:.*gh pr create/);
  });

  it('does NOT flag gh pr inside a single-quoted string (documented strip behavior)', () => {
    workDir = mkdtempSync(join(tmpdir(), 'qa-feat-033-validator-strip-'));
    const root = workDir;
    mkdirSync(join(root, 'plugins/lwndev-sdlc/skills/some-other-skill/scripts'), {
      recursive: true,
    });
    writeFileSync(
      join(root, 'plugins/lwndev-sdlc/skills/some-other-skill/scripts/quoted.sh'),
      "#!/usr/bin/env bash\necho 'gh pr create is the wrapped command'\n"
    );
    const r = spawnSync('npx', ['tsx', VALIDATOR], {
      cwd: root,
      env: process.env,
      encoding: 'utf-8',
    });
    expect(r.status).toBe(0);
    expect(r.stdout).toMatch(/No inline SCM calls found/);
  });

  it('FALSE-POSITIVE GAP: flags gh pr inside a heredoc body even though it is data', () => {
    // The line-by-line scanner does not track heredoc context, so a line in
    // the body of `: <<'EOF' ... EOF` that starts with `gh pr` is matched.
    // This is a known gap from the QA test plan (test plan line ~80 — multi-
    // line bash comment / heredoc body false-positive). Asserting current
    // behavior; gap is recorded in ## Findings.
    workDir = mkdtempSync(join(tmpdir(), 'qa-feat-033-validator-heredoc-'));
    const root = workDir;
    mkdirSync(join(root, 'plugins/lwndev-sdlc/skills/some-other-skill/scripts'), {
      recursive: true,
    });
    writeFileSync(
      join(root, 'plugins/lwndev-sdlc/skills/some-other-skill/scripts/heredoc.sh'),
      "#!/usr/bin/env bash\n: <<'EOF'\ngh pr create --title docs-only\nEOF\n"
    );
    const r = spawnSync('npx', ['tsx', VALIDATOR], {
      cwd: root,
      env: process.env,
      encoding: 'utf-8',
    });
    // Current behavior: heredoc body lines are scanned, so this DOES flag.
    expect(r.status).toBe(1);
    expect(r.stdout).toMatch(/heredoc\.sh:3:.*gh pr create/);
  });

  it('passes when bad.sh is inside the managing-source-control allow-list', () => {
    workDir = mkdtempSync(join(tmpdir(), 'qa-feat-033-validator-allow-'));
    const root = workDir;
    mkdirSync(join(root, 'plugins/lwndev-sdlc/skills/managing-source-control/scripts'), {
      recursive: true,
    });
    writeFileSync(
      join(root, 'plugins/lwndev-sdlc/skills/managing-source-control/scripts/inside.sh'),
      '#!/usr/bin/env bash\ngh pr create --title x\n'
    );
    const r = spawnSync('npx', ['tsx', VALIDATOR], {
      cwd: root,
      env: process.env,
      encoding: 'utf-8',
    });
    expect(r.status).toBe(0);
    expect(r.stdout).toMatch(/No inline SCM calls found/);
  });
});
