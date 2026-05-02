import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { execFileSync, spawn, spawnSync } from 'node:child_process';
// execFileSync is intentionally retained for the post-run `cat` of the npm.log
// stub file (a small filesystem read; spawnSync would be overkill).
import { mkdtempSync, rmSync, mkdirSync, writeFileSync, symlinkSync, chmodSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

// Adversarial QA test suite for BUG-013.
// Probes failure modes of plugins/lwndev-sdlc/scripts/verify-build-health.sh
// from qa/test-plans/QA-plan-BUG-013.md that the bats fixture does not cover:
// script-name exact-match (P1 Inputs), symlinked package.json (P1 Inputs),
// concurrent invocations (P1 State transitions), LANG=C parseability
// (P1 Environment), prettier stderr passthrough (P0 Dependency failure),
// and package-lock stderr-warning does NOT fail (P1 Dependency failure).

const SCRIPT = join(process.cwd(), 'plugins/lwndev-sdlc/scripts/verify-build-health.sh');

type RunResult = { stdout: string; stderr: string; status: number };

function makeNpmStub(binDir: string, body: string): void {
  mkdirSync(binDir, { recursive: true });
  const npmPath = join(binDir, 'npm');
  writeFileSync(npmPath, `#!/usr/bin/env bash\n${body}\n`);
  chmodSync(npmPath, 0o755);
}

function run(
  args: string[],
  opts: {
    cwd: string;
    binDir: string;
    extraEnv?: NodeJS.ProcessEnv;
  }
): RunResult {
  const env = {
    ...process.env,
    PATH: `${opts.binDir}:/usr/bin:/bin`,
    ...(opts.extraEnv ?? {}),
  };
  const r = spawnSync('bash', [SCRIPT, ...args], {
    encoding: 'utf-8',
    stdio: ['pipe', 'pipe', 'pipe'],
    env,
    cwd: opts.cwd,
  });
  return {
    stdout: r.stdout ?? '',
    stderr: r.stderr ?? '',
    status: r.status ?? -1,
  };
}

describe('verify-build-health.sh — script-name exact-match (P1 Inputs)', () => {
  let workDir: string;
  let binDir: string;

  beforeEach(() => {
    workDir = mkdtempSync(join(tmpdir(), 'bug013-exact-'));
    binDir = join(workDir, '_bin');
  });

  afterEach(() => {
    rmSync(workDir, { recursive: true, force: true });
  });

  it('does NOT invoke "lint:fix" or "test:unit" as if they were canonical when the canonical names are absent', () => {
    // Only side-channel scripts present; canonical names absent.
    writeFileSync(
      join(workDir, 'package.json'),
      JSON.stringify({
        name: 'fixture',
        scripts: {
          'lint:fix': 'true',
          'test:unit': 'true',
          'format:check:ci': 'true',
        },
      })
    );

    // Stub npm logs every invocation so we can assert nothing was run.
    const log = join(workDir, 'npm.log');
    makeNpmStub(binDir, `printf "%s\\n" "$*" >> "${log}"\nexit 0\n`);

    const r = run(['--no-interactive'], { cwd: workDir, binDir });

    expect(r.status).toBe(0);
    // The script should detect no canonical scripts and skip gracefully.
    // It must NOT invoke the side-channel scripts.
    let invocations = '';
    try {
      invocations = execFileSync('cat', [log], { encoding: 'utf-8' });
    } catch {
      invocations = '';
    }
    expect(invocations).not.toMatch(/run lint:fix/);
    expect(invocations).not.toMatch(/run test:unit/);
    expect(invocations).not.toMatch(/run format:check:ci/);
  });

  it('detects "test" exactly even when "test:unit" is also present', () => {
    writeFileSync(
      join(workDir, 'package.json'),
      JSON.stringify({
        name: 'fixture',
        scripts: { test: 'true', 'test:unit': 'true' },
      })
    );

    const log = join(workDir, 'npm.log');
    // Match how the existing bats stub dispatches — record the args verbatim.
    makeNpmStub(binDir, `printf "%s\\n" "$*" >> "${log}"\nexit 0\n`);

    const r = run(['--no-interactive'], { cwd: workDir, binDir });

    expect(r.status).toBe(0);
    const invocations = execFileSync('cat', [log], { encoding: 'utf-8' });
    // npm test runs as "npm test" (a literal subcommand), not "npm run test".
    expect(invocations).toMatch(/^test\s*$/m);
    // test:unit must NOT have been invoked.
    expect(invocations).not.toMatch(/run test:unit/);
  });
});

describe('verify-build-health.sh — symlinked package.json (P1 Inputs)', () => {
  let workDir: string;
  let realDir: string;
  let linkDir: string;
  let binDir: string;

  beforeEach(() => {
    workDir = mkdtempSync(join(tmpdir(), 'bug013-symlink-'));
    realDir = join(workDir, 'real');
    linkDir = join(workDir, 'link');
    mkdirSync(realDir, { recursive: true });
    mkdirSync(linkDir, { recursive: true });
    binDir = join(workDir, '_bin');
  });

  afterEach(() => {
    rmSync(workDir, { recursive: true, force: true });
  });

  it("resolves a symlinked package.json and runs the linked file's scripts", () => {
    writeFileSync(
      join(realDir, 'package.json'),
      JSON.stringify({
        name: 'real',
        scripts: { lint: 'true', test: 'true' },
      })
    );
    symlinkSync(join(realDir, 'package.json'), join(linkDir, 'package.json'));

    const log = join(workDir, 'npm.log');
    makeNpmStub(binDir, `printf "%s\\n" "$*" >> "${log}"\nexit 0\n`);

    const r = run(['--no-interactive'], { cwd: linkDir, binDir });

    expect(r.status).toBe(0);
    const invocations = execFileSync('cat', [log], { encoding: 'utf-8' });
    expect(invocations).toMatch(/run lint/);
    expect(invocations).toMatch(/^test\s*$/m);
  });
});

describe('verify-build-health.sh — concurrent invocations (P1 State transitions)', () => {
  let workDir: string;
  let binDir: string;

  beforeEach(() => {
    workDir = mkdtempSync(join(tmpdir(), 'bug013-concurrent-'));
    binDir = join(workDir, '_bin');
  });

  afterEach(() => {
    rmSync(workDir, { recursive: true, force: true });
  });

  it('two concurrent invocations both complete deterministically without corrupting each other', async () => {
    writeFileSync(
      join(workDir, 'package.json'),
      JSON.stringify({
        name: 'fixture',
        scripts: { lint: 'true', 'format:check': 'true', test: 'true' },
      })
    );
    // npm stub: sleep briefly to overlap, then exit 0.
    makeNpmStub(binDir, `sleep 0.05\nprintf "ok %s\\n" "$*" >> "${workDir}/npm.log"\nexit 0\n`);

    const env = {
      ...process.env,
      PATH: `${binDir}:/usr/bin:/bin`,
    };

    const spawnRun = (): Promise<{
      code: number | null;
      stdout: string;
      stderr: string;
    }> =>
      new Promise((resolve) => {
        const child = spawn('bash', [SCRIPT, '--no-interactive'], {
          cwd: workDir,
          env,
          stdio: ['ignore', 'pipe', 'pipe'],
        });
        let so = '';
        let se = '';
        child.stdout.on('data', (d) => (so += d.toString()));
        child.stderr.on('data', (d) => (se += d.toString()));
        child.on('close', (code) => resolve({ code, stdout: so, stderr: se }));
      });

    const [a, b] = await Promise.all([spawnRun(), spawnRun()]);
    expect(a.code).toBe(0);
    expect(b.code).toBe(0);
  });
});

describe('verify-build-health.sh — locale (P1 Environment)', () => {
  let workDir: string;
  let binDir: string;

  beforeEach(() => {
    workDir = mkdtempSync(join(tmpdir(), 'bug013-locale-'));
    binDir = join(workDir, '_bin');
  });

  afterEach(() => {
    rmSync(workDir, { recursive: true, force: true });
  });

  it('emits parseable [info] log lines under LANG=C (no mojibake in tagged structured logs)', () => {
    // No package.json → graceful skip path emits an [info] line.
    const r = run(['--no-interactive'], {
      cwd: workDir,
      binDir,
      extraEnv: { LANG: 'C', LC_ALL: 'C' },
    });

    expect(r.status).toBe(0);
    // The orchestrator's parser keys on the `[info]` prefix — it must survive a C locale.
    expect(r.stderr).toMatch(/^\[info\]/m);
  });
});

describe('verify-build-health.sh — failing-script stderr passthrough (P0 Dependency failure)', () => {
  let workDir: string;
  let binDir: string;

  beforeEach(() => {
    workDir = mkdtempSync(join(tmpdir(), 'bug013-passthru-'));
    binDir = join(workDir, '_bin');
  });

  afterEach(() => {
    rmSync(workDir, { recursive: true, force: true });
  });

  it("surfaces a failing format:check script's stderr verbatim and exits non-zero (no swallowed output)", () => {
    writeFileSync(
      join(workDir, 'package.json'),
      JSON.stringify({
        name: 'fixture',
        scripts: { 'format:check': 'fail-script', test: 'true' },
      })
    );

    // npm stub: `npm run format:check` → emit a recognizable parser-error line and exit 1.
    // Use a sentinel string the orchestrator would expect to see.
    const SENTINEL = 'SyntaxError: Unexpected token ) in fixtures/binary-leak.bin';
    makeNpmStub(
      binDir,
      `if [ "$1" = "run" ] && [ "$2" = "format:check" ]; then
  printf "%s\\n" "${SENTINEL}" 1>&2
  exit 1
fi
exit 0`
    );

    const r = run(['--no-interactive'], { cwd: workDir, binDir });

    expect(r.status).not.toBe(0);
    // stderr (or combined output) should carry the underlying error verbatim.
    expect(r.stderr + r.stdout).toContain(SENTINEL);
  });
});

describe('verify-build-health.sh — package-lock soft warnings (P1 Dependency failure)', () => {
  let workDir: string;
  let binDir: string;

  beforeEach(() => {
    workDir = mkdtempSync(join(tmpdir(), 'bug013-softwarn-'));
    binDir = join(workDir, '_bin');
  });

  afterEach(() => {
    rmSync(workDir, { recursive: true, force: true });
  });

  it('a stderr warning from npm with exit 0 does NOT cause the script to exit non-zero', () => {
    writeFileSync(
      join(workDir, 'package.json'),
      JSON.stringify({
        name: 'fixture',
        scripts: { lint: 'true', test: 'true' },
      })
    );

    // npm stub: emit a soft warning to stderr but exit 0 (the canonical
    // "package-lock.json out of sync" surface).
    makeNpmStub(
      binDir,
      `printf "npm warn package-lock.json: Lockfile is out of sync.\\n" 1>&2\nexit 0\n`
    );

    const r = run(['--no-interactive'], { cwd: workDir, binDir });

    expect(r.status).toBe(0);
  });
});
