// QA-BUG-023: adversarial probe of the initial-run-PASS adoption routing fix.
//
// BUG-023 deadlock: an initial-run PASS (qaFixAttempts=0) that left committed,
// un-adopted qa-* tests on the branch advanced straight to finalize, where the
// FR-9 `git ls-files` safety-net blocked the merge — a deadlock. The fix routes
// such a PASS through addressing-qa-findings (adopt phase) FIRST, by teaching
// BOTH qa-dispatch.sh and detect-phase.sh to check for git-visible qa-* files
// using the SAME three canonical globs the FR-9 gate uses.
//
// The existing bats fixtures (qa-dispatch.bats, detect-phase.bats,
// safety-net.bats) already cover the per-script happy-path rows. These QA tests
// attack the INVARIANT those scripts must jointly uphold and the glob-widening
// risk the fix introduces, against REAL git repos:
//
//   * Consistency: qa-dispatch.sh's adopt trigger, detect-phase.sh's adopt
//     route, and the FR-9 `git ls-files` glob set must all key on the SAME
//     file set. Divergence re-introduces the deadlock (gate blocks but no
//     adopt fires) or a spurious adopt (adopt fires but gate would not block).
//   * Glob anchoring / no-widening (Edge Case 17): the fix must NOT start
//     matching pytest (qa-*.py) or go-test (qa-*.go) files, subdir qa-* files,
//     adopted *.qa.* siblings, or permanent infra (tests/bats/skills/.../qa-*.bats).
//   * Tracked-only: both the trigger and the gate use `git ls-files`, so an
//     untracked qa-* file must trip neither (no deadlock, consistent blindness).
//   * Loop termination: once adoptedTests is non-empty, the route is advance
//     even if a stray qa-* file is still git-visible.
//
// Mode: test-framework
// Ref: qa/test-plans/QA-plan-BUG-023.md

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { execFileSync, spawnSync } from 'node:child_process';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';

const REPO_ROOT = path.resolve(__dirname, '..', '..');
const DISPATCH = path.join(
  REPO_ROOT,
  'plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/qa-dispatch.sh'
);
const DETECT = path.join(
  REPO_ROOT,
  'plugins/lwndev-sdlc/skills/addressing-qa-findings/scripts/detect-phase.sh'
);

// The three canonical FR-9 globs — the single source of truth the fix keys on.
const FR9_GLOBS = ['tests/unit/qa-*.test.ts', 'tests/unit/qa-*.test.js', 'tests/bats/qa/qa-*.bats'];

interface RunResult {
  stdout: string;
  stderr: string;
  status: number;
}

function runBashIn(cwd: string, script: string, args: string[]): RunResult {
  const r = spawnSync('bash', [script, ...args], {
    cwd,
    encoding: 'utf8',
    env: { ...process.env, GIT_TERMINAL_PROMPT: '0' },
  });
  return { stdout: r.stdout ?? '', stderr: r.stderr ?? '', status: r.status ?? -1 };
}

function gitInit(cwd: string): void {
  execFileSync('git', ['init', '-q', '-b', 'main'], { cwd });
  execFileSync('git', ['config', 'user.email', 'qa@bug-023.test'], { cwd });
  execFileSync('git', ['config', 'user.name', 'qa-bug-023'], { cwd });
  execFileSync('git', ['config', 'commit.gpgsign', 'false'], { cwd });
}

function gitAddCommit(cwd: string, msg: string): void {
  execFileSync('git', ['add', '-A'], { cwd });
  execFileSync('git', ['commit', '-q', '-m', msg], { cwd });
}

function writeFile(cwd: string, rel: string, body: string): void {
  const abs = path.join(cwd, rel);
  fs.mkdirSync(path.dirname(abs), { recursive: true });
  fs.writeFileSync(abs, body);
}

// The FR-9 oracle: what the merge gate would see as a blocking leak.
function fr9Leaks(cwd: string): string[] {
  const r = spawnSync('git', ['ls-files', ...FR9_GLOBS], { cwd, encoding: 'utf8' });
  return (r.stdout ?? '').split('\n').filter((l) => l.trim().length > 0);
}

// Seed a fully-migrated state file with explicit QA-loop fields.
function seedState(
  cwd: string,
  id: string,
  opts: { verdict?: string | null; attempts?: number; adopted?: string[]; cap?: number } = {}
): void {
  const verdict = opts.verdict === undefined ? 'PASS' : opts.verdict;
  const attempts = opts.attempts ?? 0;
  const adopted = opts.adopted ?? [];
  const cap = opts.cap ?? 2;
  const verdictJson = verdict === null ? 'null' : `"${verdict}"`;
  const state = {
    id,
    type: 'bug',
    currentStep: 0,
    status: 'in-progress',
    pauseReason: null,
    gate: null,
    gateSetAt: null,
    steps: [
      {
        name: 'Doc',
        skill: 'documenting-bugs',
        context: 'main',
        status: 'in-progress',
        artifact: null,
        completedAt: null,
      },
    ],
    phases: { total: 0, completed: 0 },
    prNumber: null,
    branch: null,
    startedAt: '2026-05-31T00:00:00Z',
    lastResumedAt: null,
    complexity: 'medium',
    complexityStage: 'init',
    modelOverride: null,
    modelSelections: [],
    qaFixAttempts: attempts,
    qaLastVerdict: null as unknown,
    adoptedTests: adopted,
    qaLoopCap: cap,
    stateEvents: [],
  };
  // qaLastVerdict must be raw JSON null or a quoted string — assemble by hand
  // so `null` is not stringified to "null".
  const json = JSON.stringify(state, null, 2).replace(
    '"qaLastVerdict": null',
    `"qaLastVerdict": ${verdictJson}`
  );
  writeFile(cwd, `.sdlc/workflows/${id}.json`, json + '\n');
}

function dispatchOf(cwd: string, id: string): RunResult {
  return runBashIn(cwd, DISPATCH, [id]);
}
function detectOf(cwd: string, id: string): RunResult {
  return runBashIn(cwd, DETECT, [id]);
}

let tmp = '';
beforeEach(() => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'qa-bug-023-'));
  gitInit(tmp);
  // HEAD must exist for git ls-files to behave; commit a placeholder.
  writeFile(tmp, 'README', 'placeholder\n');
  gitAddCommit(tmp, 'init');
});
afterEach(() => {
  if (tmp && fs.existsSync(tmp)) fs.rmSync(tmp, { recursive: true, force: true });
});

const ID = 'BUG-999';

// ---------------------------------------------------------------------------
// Dimension 5 / Dimension 2 — the core BUG-023 consistency invariant
// ---------------------------------------------------------------------------
describe('Cross-script consistency: adopt trigger == detect route == FR-9 gate set', () => {
  it('P0 — canonical tracked qa-*.test.ts: FR-9 would block AND both scripts route to adopt', () => {
    seedState(tmp, ID, { verdict: 'PASS', attempts: 0 });
    writeFile(tmp, 'tests/unit/qa-edge.test.ts', 'export const x = 1;\n');
    gitAddCommit(tmp, 'add qa file');

    expect(fr9Leaks(tmp)).toEqual(['tests/unit/qa-edge.test.ts']);
    const d = dispatchOf(tmp, ID);
    expect(d.status).toBe(0);
    expect(d.stdout.trim()).toBe('dispatch=adopt-phase');
    const p = detectOf(tmp, ID);
    expect(p.status).toBe(0);
    expect(p.stdout.trim()).toBe('phase=adopt');
  });

  it('P0 — canonical tracked qa-*.bats: FR-9 would block AND both scripts route to adopt', () => {
    seedState(tmp, ID, { verdict: 'PASS', attempts: 0 });
    writeFile(tmp, 'tests/bats/qa/qa-edge.bats', '#!/usr/bin/env bats\n@test "x" { true; }\n');
    gitAddCommit(tmp, 'add qa bats file');

    expect(fr9Leaks(tmp)).toEqual(['tests/bats/qa/qa-edge.bats']);
    expect(dispatchOf(tmp, ID).stdout.trim()).toBe('dispatch=adopt-phase');
    expect(detectOf(tmp, ID).stdout.trim()).toBe('phase=adopt');
  });

  it('P0 — no qa-* files at all: FR-9 clears AND both scripts advance/unknown', () => {
    seedState(tmp, ID, { verdict: 'PASS', attempts: 0 });
    expect(fr9Leaks(tmp)).toEqual([]);
    expect(dispatchOf(tmp, ID).stdout.trim()).toBe('dispatch=advance');
    expect(detectOf(tmp, ID).stdout.trim()).toBe('phase=unknown');
  });
});

// ---------------------------------------------------------------------------
// Dimension 3 — Edge Case 17 lockstep: the fix must NOT widen the glob set
// ---------------------------------------------------------------------------
describe('No glob widening (Edge Case 17 + anchoring)', () => {
  it('P0 — pytest qa-*.py + go-test qa-*.go committed: FR-9 ignores them AND scripts advance (no spurious adopt)', () => {
    seedState(tmp, ID, { verdict: 'PASS', attempts: 0 });
    writeFile(tmp, 'tests/unit/qa-probe.py', 'def test_x():\n    assert True\n');
    writeFile(tmp, 'qa-probe_test.go', 'package main\n');
    gitAddCommit(tmp, 'add pytest+go qa files');

    // Edge Case 17: these extensions are intentionally absent from the glob set.
    expect(fr9Leaks(tmp)).toEqual([]);
    expect(dispatchOf(tmp, ID).stdout.trim()).toBe('dispatch=advance');
    expect(detectOf(tmp, ID).stdout.trim()).toBe('phase=unknown');
  });

  it('P1 — qa-* in a non-canonical subdir (tests/unit/sub/): not matched, scripts advance', () => {
    seedState(tmp, ID, { verdict: 'PASS', attempts: 0 });
    writeFile(tmp, 'tests/unit/sub/qa-deep.test.ts', 'export const x = 1;\n');
    gitAddCommit(tmp, 'add subdir qa file');

    // git pathspec `*` does not cross `/`, so the single-level glob excludes it.
    expect(fr9Leaks(tmp)).toEqual([]);
    expect(dispatchOf(tmp, ID).stdout.trim()).toBe('dispatch=advance');
    expect(detectOf(tmp, ID).stdout.trim()).toBe('phase=unknown');
  });

  it('P1 — permanent infra (tests/bats/skills/<skill>/qa-*.bats): not matched, scripts advance', () => {
    seedState(tmp, ID, { verdict: 'PASS', attempts: 0 });
    writeFile(
      tmp,
      'tests/bats/skills/foo/qa-dispatch.bats',
      '#!/usr/bin/env bats\n@test "x" { true; }\n'
    );
    gitAddCommit(tmp, 'add infra bats');

    // Only tests/bats/qa/ is canonical-ephemeral; skill infra stays clear.
    expect(fr9Leaks(tmp)).toEqual([]);
    expect(dispatchOf(tmp, ID).stdout.trim()).toBe('dispatch=advance');
    expect(detectOf(tmp, ID).stdout.trim()).toBe('phase=unknown');
  });

  it('P2 — adopted *.qa.* sibling (prefix vs infix): not matched, scripts advance even with adoptedTests empty', () => {
    // Adversarial state mismatch: disk has only an adopted-form file, but
    // state.adoptedTests is still empty. The qa-* PREFIX glob must not match the
    // *.qa.* INFIX sibling, so no re-adopt is triggered.
    seedState(tmp, ID, { verdict: 'PASS', attempts: 0, adopted: [] });
    writeFile(tmp, 'tests/unit/foo.qa.test.ts', 'export const x = 1;\n');
    gitAddCommit(tmp, 'add adopted sibling');

    expect(fr9Leaks(tmp)).toEqual([]);
    expect(dispatchOf(tmp, ID).stdout.trim()).toBe('dispatch=advance');
    expect(detectOf(tmp, ID).stdout.trim()).toBe('phase=unknown');
  });
});

// ---------------------------------------------------------------------------
// Dimension 2 / Dimension 4 — tracked-only + loop termination
// ---------------------------------------------------------------------------
describe('Tracked-only triggering and loop termination', () => {
  it('P1 — untracked qa-* file: git ls-files blind, FR-9 clears AND scripts advance (no deadlock)', () => {
    seedState(tmp, ID, { verdict: 'PASS', attempts: 0 });
    // Written but NOT committed.
    writeFile(tmp, 'tests/unit/qa-untracked.test.ts', 'export const x = 1;\n');

    expect(fr9Leaks(tmp)).toEqual([]);
    expect(dispatchOf(tmp, ID).stdout.trim()).toBe('dispatch=advance');
    expect(detectOf(tmp, ID).stdout.trim()).toBe('phase=unknown');
  });

  it('P0 — loop termination: adoptedTests non-empty forces advance even with a stray git-visible qa-* file', () => {
    seedState(tmp, ID, { verdict: 'PASS', attempts: 0, adopted: ['tests/unit/foo.qa.test.ts'] });
    writeFile(tmp, 'tests/unit/qa-stray.test.ts', 'export const x = 1;\n');
    gitAddCommit(tmp, 'add stray qa file');

    // FR-9 would still flag the stray, but the orchestrator already adopted —
    // dispatch must return advance so the loop terminates (the stray is a
    // separate orphan handled by the FR-9 gate, not by re-looping adopt).
    expect(fr9Leaks(tmp)).toEqual(['tests/unit/qa-stray.test.ts']);
    expect(dispatchOf(tmp, ID).stdout.trim()).toBe('dispatch=advance');
    // detect-phase: PASS + adoptedTests non-empty → not adopt again.
    expect(detectOf(tmp, ID).stdout.trim()).toBe('phase=unknown');
  });

  it('P1 — mixed canonical set (unit + bats/qa together): both flagged, single adopt route', () => {
    seedState(tmp, ID, { verdict: 'PASS', attempts: 0 });
    writeFile(tmp, 'tests/unit/qa-a.test.ts', 'export const x = 1;\n');
    writeFile(tmp, 'tests/bats/qa/qa-b.bats', '#!/usr/bin/env bats\n@test "x" { true; }\n');
    gitAddCommit(tmp, 'add two qa files');

    expect(fr9Leaks(tmp).sort()).toEqual(['tests/bats/qa/qa-b.bats', 'tests/unit/qa-a.test.ts']);
    expect(dispatchOf(tmp, ID).stdout.trim()).toBe('dispatch=adopt-phase');
    expect(detectOf(tmp, ID).stdout.trim()).toBe('phase=adopt');
  });
});

// ---------------------------------------------------------------------------
// Dimension 2 — regression guard on the pre-existing post-fix path
// ---------------------------------------------------------------------------
describe('Regression: pre-existing post-fix adoption path unchanged', () => {
  it('P0 — post-fix PASS (attempts>0, adoptedTests empty, no qa-* files): still routes to adopt', () => {
    seedState(tmp, ID, { verdict: 'PASS', attempts: 1, adopted: [] });
    expect(dispatchOf(tmp, ID).stdout.trim()).toBe('dispatch=adopt-phase');
    expect(detectOf(tmp, ID).stdout.trim()).toBe('phase=adopt');
  });

  it('P0 — FR-9 still catches a genuine orphan from an abandoned workflow', () => {
    // A different workflow ID left an orphan; the current PASS chain has no
    // such files in state, yet the gate set still sees it (the safety-net is
    // not blanket-disabled by the fix).
    seedState(tmp, ID, { verdict: 'PASS', attempts: 0 });
    writeFile(tmp, 'tests/unit/qa-orphan-from-other.test.ts', 'export const x = 1;\n');
    gitAddCommit(tmp, 'orphan');
    expect(fr9Leaks(tmp)).toEqual(['tests/unit/qa-orphan-from-other.test.ts']);
    // And consistently, dispatch routes it to adopt (so it WOULD be cleaned up
    // before finalize rather than deadlocking) — the BUG-023 guarantee.
    expect(dispatchOf(tmp, ID).stdout.trim()).toBe('dispatch=adopt-phase');
  });
});
