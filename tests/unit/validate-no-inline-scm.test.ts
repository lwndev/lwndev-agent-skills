import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { spawnSync } from 'node:child_process';
import { mkdtemp, mkdir, writeFile, rm, cp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

const REPO_ROOT = resolve(__dirname, '..', '..');
const VALIDATOR = resolve(REPO_ROOT, 'scripts', 'validate-no-inline-scm.ts');

interface RunResult {
  status: number | null;
  stdout: string;
  stderr: string;
}

function runValidator(cwd: string): RunResult {
  const res = spawnSync('npx', ['tsx', VALIDATOR], {
    cwd,
    encoding: 'utf-8',
    env: { ...process.env, NODE_NO_WARNINGS: '1' },
  });
  return { status: res.status, stdout: res.stdout, stderr: res.stderr };
}

/**
 * Build a synthetic worktree under tmp that mirrors the SCAN_ROOTS the
 * validator walks. The validator is copied in so the `tsx` process resolves
 * scripts/ relative to the cwd.
 */
async function buildWorktree(): Promise<string> {
  const dir = await mkdtemp(join(tmpdir(), 'validate-no-inline-scm-'));
  await mkdir(join(dir, 'scripts'), { recursive: true });
  await mkdir(join(dir, 'plugins', 'lwndev-sdlc', 'skills', 'managing-source-control', 'scripts'), {
    recursive: true,
  });
  await mkdir(join(dir, 'plugins', 'lwndev-sdlc', 'skills', 'managing-work-items', 'scripts'), {
    recursive: true,
  });
  await mkdir(join(dir, 'plugins', 'lwndev-sdlc', 'skills', 'finalizing-workflow', 'scripts'), {
    recursive: true,
  });
  await mkdir(join(dir, 'plugins', 'lwndev-sdlc', 'scripts'), { recursive: true });
  await cp(VALIDATOR, join(dir, 'scripts', 'validate-no-inline-scm.ts'));
  return dir;
}

describe('validate-no-inline-scm.ts', () => {
  let cleanTree: string;
  let ghOutsideAllow: string;
  let ghInsideAllow: string;
  let azOutsideAllow: string;

  beforeAll(async () => {
    cleanTree = await buildWorktree();
    ghOutsideAllow = await buildWorktree();
    ghInsideAllow = await buildWorktree();
    azOutsideAllow = await buildWorktree();

    // Case 4: clean tree — a script that calls a dispatcher, plus comment /
    // warning-string references to `gh pr` that must NOT trigger the check.
    await writeFile(
      join(
        cleanTree,
        'plugins',
        'lwndev-sdlc',
        'skills',
        'finalizing-workflow',
        'scripts',
        'finalize.sh'
      ),
      [
        '#!/usr/bin/env bash',
        '# Wraps a call to gh pr merge via the dispatcher.',
        'set -e',
        'bash "$REPO/plugins/lwndev-sdlc/skills/managing-source-control/scripts/merge-pr.sh" "$1"',
        'echo "[error] gh pr merge failed" >&2',
        '',
      ].join('\n')
    );

    // Case 1: `gh pr create` outside allow-list → exit 1.
    await writeFile(
      join(
        ghOutsideAllow,
        'plugins',
        'lwndev-sdlc',
        'skills',
        'finalizing-workflow',
        'scripts',
        'finalize.sh'
      ),
      ['#!/usr/bin/env bash', 'gh pr create --title "test" --body "x"', ''].join('\n')
    );

    // Case 2: `gh pr create` inside `managing-source-control/scripts/` → exit 0.
    await writeFile(
      join(
        ghInsideAllow,
        'plugins',
        'lwndev-sdlc',
        'skills',
        'managing-source-control',
        'scripts',
        'create-pr.sh'
      ),
      ['#!/usr/bin/env bash', 'gh pr create --title "$title" --body "$body"', ''].join('\n')
    );

    // Case 3: `az repos pr create` outside allow-list → exit 1.
    await writeFile(
      join(azOutsideAllow, 'plugins', 'lwndev-sdlc', 'scripts', 'rogue.sh'),
      [
        '#!/usr/bin/env bash',
        'az repos pr create --source-branch "$branch" --title "$title"',
        '',
      ].join('\n')
    );
  }, 30_000);

  afterAll(async () => {
    await rm(cleanTree, { recursive: true, force: true });
    await rm(ghOutsideAllow, { recursive: true, force: true });
    await rm(ghInsideAllow, { recursive: true, force: true });
    await rm(azOutsideAllow, { recursive: true, force: true });
  });

  it('exits 0 with info line on a clean tree (comments + warning strings ignored)', () => {
    const r = runValidator(cleanTree);
    expect(r.status).toBe(0);
    expect(r.stdout).toContain('[info] No inline SCM calls found');
    expect(r.stdout).not.toMatch(/FAIL:/);
  });

  it('exits 1 when `gh pr create` is invoked outside the allow-list', () => {
    const r = runValidator(ghOutsideAllow);
    expect(r.status).toBe(1);
    expect(r.stdout).toMatch(
      /\[validate-no-inline-scm\] FAIL: plugins\/lwndev-sdlc\/skills\/finalizing-workflow\/scripts\/finalize\.sh:\d+:/
    );
    expect(r.stdout).toContain('1 violations');
  });

  it('exits 0 when `gh pr create` lives inside managing-source-control/scripts/', () => {
    const r = runValidator(ghInsideAllow);
    expect(r.status).toBe(0);
    expect(r.stdout).toContain('[info] No inline SCM calls found');
    expect(r.stdout).not.toMatch(/FAIL:/);
  });

  it('exits 1 when `az repos pr create` is invoked outside the allow-list', () => {
    const r = runValidator(azOutsideAllow);
    expect(r.status).toBe(1);
    expect(r.stdout).toMatch(
      /\[validate-no-inline-scm\] FAIL: plugins\/lwndev-sdlc\/scripts\/rogue\.sh:\d+:/
    );
    expect(r.stdout).toContain('1 violations');
  });

  it('passes against the real repo tree (post-Phase-5 layout)', () => {
    const r = runValidator(REPO_ROOT);
    expect(r.status).toBe(0);
    expect(r.stdout).toContain('[info] No inline SCM calls found');
  }, 30_000);
});
