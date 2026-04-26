import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { spawnSync } from 'node:child_process';
import {
  mkdtempSync,
  rmSync,
  mkdirSync,
  writeFileSync,
  chmodSync,
  symlinkSync,
  existsSync,
  utimesSync,
} from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

// Adversarial QA test suite for BUG-014 — confirmation-gate hooks.
// Fills coverage gaps not addressed by the existing bats fixtures
// at plugins/lwndev-sdlc/scripts/tests/hooks/.
//
// Scenarios from qa/test-plans/QA-plan-BUG-014.md:
//   * P0 Inputs: future-dated marker mtime passes (>= semantics).
//   * P0 Inputs: merge <ID> outside any workflow (Hook A creates marker;
//     Hook B denies the gh pr merge because .active is missing).
//   * P0 Environment: same-second tie (mtime == pausedAt) passes (>=, not >).
//   * P0 Environment: read-only .sdlc/approvals/ — Hook A no-ops; Hook B denies.
//   * P0 Dependency failure: Hook B with missing jq -> fail-secure (deny).
//   * P1 State transitions: pause-then-pause-with-different-reason updates both.
//   * P1 State transitions: two-pause race (T1 pause, approve T2, advance,
//     re-pause T3 — the T2 marker becomes stale).
//   * P2 Inputs: leading-zero canonical form (BUG-00014 vs BUG-014 distinct).
//   * P2 Inputs: approval-then-decline in one prompt (last shape wins).
//   * P2 Cross-cutting: marker filename collision across workflow types
//     (FEAT-014 marker does not authorize BUG-014).

const REPO_ROOT = process.cwd();
const HOOK_A = join(REPO_ROOT, 'plugins/lwndev-sdlc/scripts/hooks/record-approval.sh');
const HOOK_B = join(REPO_ROOT, 'plugins/lwndev-sdlc/scripts/hooks/guard-state-transitions.sh');
const HOOK_C = join(REPO_ROOT, 'plugins/lwndev-sdlc/scripts/hooks/guard-agent-prompts.sh');
const WORKFLOW_STATE = join(
  REPO_ROOT,
  'plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh'
);

type HookResult = { stdout: string; stderr: string; status: number };

function fireHookA(prompt: string, opts: { cwd: string; env?: NodeJS.ProcessEnv }): HookResult {
  const payload = JSON.stringify({ prompt });
  const r = spawnSync('bash', [HOOK_A], {
    input: payload,
    encoding: 'utf-8',
    cwd: opts.cwd,
    env: opts.env ?? process.env,
  });
  return { stdout: r.stdout ?? '', stderr: r.stderr ?? '', status: r.status ?? -1 };
}

function fireHookB(command: string, opts: { cwd: string; env?: NodeJS.ProcessEnv }): HookResult {
  const payload = JSON.stringify({ tool_name: 'Bash', tool_input: { command } });
  const r = spawnSync('bash', [HOOK_B], {
    input: payload,
    encoding: 'utf-8',
    cwd: opts.cwd,
    env: opts.env ?? process.env,
  });
  return { stdout: r.stdout ?? '', stderr: r.stderr ?? '', status: r.status ?? -1 };
}

function fireHookC(
  prompt: string,
  subagentType: string,
  opts: { cwd: string; env?: NodeJS.ProcessEnv }
): HookResult {
  const payload = JSON.stringify({
    tool_name: 'Task',
    tool_input: { prompt, subagent_type: subagentType },
  });
  const r = spawnSync('bash', [HOOK_C], {
    input: payload,
    encoding: 'utf-8',
    cwd: opts.cwd,
    env: opts.env ?? process.env,
  });
  return { stdout: r.stdout ?? '', stderr: r.stderr ?? '', status: r.status ?? -1 };
}

function decisionOf(stdout: string): 'allow' | 'deny' {
  if (!stdout.trim()) return 'allow';
  try {
    const parsed = JSON.parse(stdout);
    return parsed.hookSpecificOutput?.permissionDecision === 'deny' ? 'deny' : 'allow';
  } catch {
    return 'allow';
  }
}

function writeStateFile(
  cwd: string,
  id: string,
  fields: { pauseReason?: string | null; pausedAt?: string | null; gate?: string | null }
): void {
  mkdirSync(join(cwd, '.sdlc/workflows'), { recursive: true });
  const state = {
    id,
    type: id.startsWith('FEAT') ? 'feature' : id.startsWith('CHORE') ? 'chore' : 'bug',
    status: 'paused',
    currentStep: 0,
    steps: [],
    pauseReason: fields.pauseReason ?? null,
    pausedAt: fields.pausedAt ?? null,
    gate: fields.gate ?? null,
  };
  writeFileSync(join(cwd, '.sdlc/workflows', `${id}.json`), JSON.stringify(state));
}

function writeMarker(cwd: string, name: string, id: string): string {
  mkdirSync(join(cwd, '.sdlc/approvals'), { recursive: true });
  const path = join(cwd, '.sdlc/approvals', `.approval-${name}-${id}`);
  writeFileSync(path, `timestamp: 2026-04-26T00:00:00Z\nworkflow_id: ${id}\nmessage: test\n`);
  return path;
}

function setActiveWorkflow(cwd: string, id: string): void {
  mkdirSync(join(cwd, '.sdlc/workflows'), { recursive: true });
  writeFileSync(join(cwd, '.sdlc/workflows/.active'), `${id}\n`);
}

let workDir: string;

beforeEach(() => {
  workDir = mkdtempSync(join(tmpdir(), 'qa-bug014-'));
});

afterEach(() => {
  try {
    spawnSync('chmod', ['-R', 'u+w', workDir]);
    rmSync(workDir, { recursive: true, force: true });
  } catch {
    // best-effort cleanup
  }
});

describe('Hook B mtime semantics — future-dated marker (P0 Inputs)', () => {
  it('marker with future-dated mtime passes the >= pausedAt check', () => {
    writeStateFile(workDir, 'BUG-014', {
      pauseReason: 'plan-approval',
      pausedAt: '2026-04-26T00:00:00Z',
    });
    const marker = writeMarker(workDir, 'plan-approval', 'BUG-014');

    // touch -t 209912312359 — far future.
    const future = new Date('2099-12-31T23:59:00Z');
    utimesSync(marker, future, future);

    const r = fireHookB('bash workflow-state.sh resume BUG-014', { cwd: workDir });
    // Future timestamps pass per the documented `>= pausedAt` semantics.
    // Plan acknowledges this as a known limitation.
    expect(decisionOf(r.stdout)).toBe('allow');
  });
});

describe('Hook B mtime semantics — same-second tie (P0 Environment)', () => {
  it('marker mtime exactly equal to pausedAt second passes (>= not >)', () => {
    // Coarse-mtime filesystems (HFS+ 1s, FAT32 2s, NFS lazy) can produce a
    // marker mtime equal to the pausedAt second. The fix uses `>=` so the
    // tie passes. If it were `>`, a fast user gets locked out.
    const sameTs = '2026-04-26T15:00:00Z';
    writeStateFile(workDir, 'BUG-014', {
      pauseReason: 'plan-approval',
      pausedAt: sameTs,
    });
    const marker = writeMarker(workDir, 'plan-approval', 'BUG-014');
    const exact = new Date(sameTs);
    utimesSync(marker, exact, exact);

    const r = fireHookB('bash workflow-state.sh resume BUG-014', { cwd: workDir });
    expect(decisionOf(r.stdout)).toBe('allow');
  });
});

describe('Hook A + Hook B composite — merge outside any workflow (P0 Inputs)', () => {
  it('merge <ID> creates marker via Hook A but Hook B denies the gh pr merge (no .active)', () => {
    // Hook A is workflow-state-agnostic; it writes the merge-approval marker
    // for any "merge <ID>" prompt. Hook B then denies the destructive
    // gh pr merge because .sdlc/workflows/.active is missing.
    const a = fireHookA('merge BUG-014', { cwd: workDir });
    expect(a.status).toBe(0);
    expect(existsSync(join(workDir, '.sdlc/approvals/.approval-merge-approval-BUG-014'))).toBe(
      true
    );

    // Without .active, Hook B fail-secures.
    const b = fireHookB('gh pr merge 1 --squash', { cwd: workDir });
    expect(decisionOf(b.stdout)).toBe('deny');
    expect(b.stdout).toMatch(/\.active/);
  });
});

describe('Hook B with missing jq (P0 Dependency failure)', () => {
  it('Hook B exits with deny when jq is not on PATH (fail-secure, not fail-open)', () => {
    writeStateFile(workDir, 'BUG-014', {
      pauseReason: 'plan-approval',
      pausedAt: '2026-04-26T00:00:00Z',
    });
    writeMarker(workDir, 'plan-approval', 'BUG-014');

    // Build a minimal PATH without jq.
    const minimalBin = join(workDir, '_bin');
    mkdirSync(minimalBin, { recursive: true });
    for (const bin of [
      'bash',
      'env',
      'grep',
      'sed',
      'tr',
      'cut',
      'wc',
      'mktemp',
      'mv',
      'rm',
      'mkdir',
      'cat',
      'printf',
      'chmod',
      'ls',
      'true',
      'false',
      'test',
      'dirname',
      'basename',
      'date',
      'stat',
      'awk',
      'find',
      'head',
      'tail',
      'sleep',
      'touch',
      'sort',
      'uniq',
    ]) {
      for (const root of ['/bin', '/usr/bin']) {
        const src = join(root, bin);
        if (existsSync(src)) {
          try {
            symlinkSync(src, join(minimalBin, bin));
          } catch {
            // ignore re-create failures
          }
          break;
        }
      }
    }

    const r = fireHookB('bash workflow-state.sh resume BUG-014', {
      cwd: workDir,
      env: { ...process.env, PATH: minimalBin },
    });
    // Fail-secure: missing jq must DENY, not allow. The exact denial channel
    // (stdout JSON or stderr+exit) is not specified by the AC; we accept
    // either as long as the gated tool call is not allowed.
    const denied = decisionOf(r.stdout) === 'deny' || r.status !== 0 || /\bjq\b/i.test(r.stderr);
    expect(denied).toBe(true);
  });
});

describe('Hook A with read-only approvals dir (P0 Environment)', () => {
  it('Hook A handles a non-writable .sdlc/approvals gracefully and Hook B then denies', () => {
    // Pre-create a read-only .sdlc/approvals/ as a different-user shared-box
    // simulation. Hook A may either log a warning and not create the marker
    // (fail-secure) or no-op silently. Either way: Hook B must deny the
    // subsequent resume because no marker exists.
    mkdirSync(join(workDir, '.sdlc/approvals'), { recursive: true });
    chmodSync(join(workDir, '.sdlc/approvals'), 0o555);

    const a = fireHookA('approve plan-approval BUG-014', { cwd: workDir });
    // Either exit 0 or non-zero is acceptable (AC2 silent-skip clause).
    // The invariant: no marker is created.
    const markerPath = join(workDir, '.sdlc/approvals/.approval-plan-approval-BUG-014');
    expect(existsSync(markerPath)).toBe(false);
    // Hook A status: zero (silent-skip) or non-zero (loud) — both are
    // documented-acceptable behaviors. No further assertion on status.
    expect([0, 1, 2]).toContain(a.status);

    writeStateFile(workDir, 'BUG-014', {
      pauseReason: 'plan-approval',
      pausedAt: '2026-04-26T00:00:00Z',
    });
    const b = fireHookB('bash workflow-state.sh resume BUG-014', { cwd: workDir });
    expect(decisionOf(b.stdout)).toBe('deny');

    // Restore permissions so afterEach can clean up.
    chmodSync(join(workDir, '.sdlc/approvals'), 0o755);
  });
});

describe('State transitions — pause-then-different-reason (P1 State transitions)', () => {
  it('second pause with a different pauseReason invalidates marker for the original reason', () => {
    // Workflow paused for plan-approval, user approves, advances. Workflow
    // re-pauses for pr-review (different reason). The original
    // plan-approval marker must NOT authorize a resume of the new pause —
    // the required marker name is keyed off the new pauseReason.
    setActiveWorkflow(workDir, 'BUG-014');
    spawnSync('bash', [WORKFLOW_STATE, 'init', 'BUG-014', 'bug'], { cwd: workDir });
    spawnSync('bash', [WORKFLOW_STATE, 'pause', 'BUG-014', 'plan-approval'], { cwd: workDir });

    fireHookA('approve plan-approval BUG-014', { cwd: workDir });
    spawnSync('bash', [WORKFLOW_STATE, 'resume', 'BUG-014'], { cwd: workDir });

    // Sleep ~1s to ensure new pausedAt is strictly later.
    spawnSync('sleep', ['1']);
    spawnSync('bash', [WORKFLOW_STATE, 'pause', 'BUG-014', 'pr-review'], { cwd: workDir });

    // Resume now requires .approval-pr-review-BUG-014, which doesn't exist.
    // The old plan-approval marker no longer matches the required name.
    const b = fireHookB('bash workflow-state.sh resume BUG-014', { cwd: workDir });
    expect(decisionOf(b.stdout)).toBe('deny');
    expect(b.stdout).toMatch(/approve pr-review BUG-014/);
  });
});

describe('Inputs — leading-zero canonical form (P2 Inputs)', () => {
  it('BUG-00014 and BUG-014 produce distinct marker filenames (no canonicalization)', () => {
    fireHookA('approve plan-approval BUG-00014', { cwd: workDir });
    fireHookA('approve plan-approval BUG-014', { cwd: workDir });

    // The contract: Hook A is byte-faithful to the user's typed ID. Hook B
    // looks up by exact filename. So BUG-00014 and BUG-014 do NOT collide.
    expect(existsSync(join(workDir, '.sdlc/approvals/.approval-plan-approval-BUG-00014'))).toBe(
      true
    );
    expect(existsSync(join(workDir, '.sdlc/approvals/.approval-plan-approval-BUG-014'))).toBe(true);

    // Hook B for BUG-014 with the BUG-00014 marker present (and no BUG-014
    // marker after we delete it) should deny — markers are not aliased.
    rmSync(join(workDir, '.sdlc/approvals/.approval-plan-approval-BUG-014'));
    writeStateFile(workDir, 'BUG-014', {
      pauseReason: 'plan-approval',
      pausedAt: '2026-04-26T00:00:00Z',
    });
    const b = fireHookB('bash workflow-state.sh resume BUG-014', { cwd: workDir });
    expect(decisionOf(b.stdout)).toBe('deny');
  });
});

describe('Inputs — approval-then-decline in one prompt (P2 Inputs)', () => {
  it('two shapes back-to-back create both markers — last-write-wins is irrelevant', () => {
    // The plan asks: "user types approval, then in same turn types pause
    // (decline) — last-write-wins or explicit decline overrides?" The
    // existing record-approval.bats fixture pins the documented behavior
    // for back-to-back approve+approve. This adversarial case verifies the
    // approve+pause shape: Hook A is line-oriented, so both markers
    // co-exist. The orchestrator-level reading of "decline" is out of
    // scope for Hook A — its contract is "regex match -> write marker".
    fireHookA(['approve plan-approval BUG-014', 'pause BUG-014'].join('\n'), { cwd: workDir });

    expect(existsSync(join(workDir, '.sdlc/approvals/.approval-plan-approval-BUG-014'))).toBe(true);
    expect(existsSync(join(workDir, '.sdlc/approvals/.approval-pause-BUG-014'))).toBe(true);
  });
});

describe('Cross-cutting — marker collision across workflow types (P2 Cross-cutting)', () => {
  it('FEAT-014 merge marker does not authorize a BUG-014 spawn or merge', () => {
    setActiveWorkflow(workDir, 'BUG-014');
    writeMarker(workDir, 'merge-approval', 'FEAT-014');

    // Hook C — fork finalizing-workflow with .active=BUG-014 must deny
    // because the marker file name is .approval-merge-approval-BUG-014, not
    // .approval-merge-approval-FEAT-014.
    const c = fireHookC(
      'You are the finalizing-workflow skill. Merge the PR.',
      'finalizing-workflow',
      { cwd: workDir }
    );
    expect(decisionOf(c.stdout)).toBe('deny');
    expect(c.stdout).toMatch(/merge BUG-014/);

    // Hook B — gh pr merge with .active=BUG-014 also denies.
    const b = fireHookB('gh pr merge 1 --squash', { cwd: workDir });
    expect(decisionOf(b.stdout)).toBe('deny');
  });
});

describe('Two-pause race full E2E (P1 State transitions)', () => {
  it('marker created at T2 becomes stale after a re-pause at T3', () => {
    setActiveWorkflow(workDir, 'BUG-014');
    spawnSync('bash', [WORKFLOW_STATE, 'init', 'BUG-014', 'bug'], { cwd: workDir });

    // T1: pause
    spawnSync('bash', [WORKFLOW_STATE, 'pause', 'BUG-014', 'plan-approval'], { cwd: workDir });
    // T2: user approves
    fireHookA('approve plan-approval BUG-014', { cwd: workDir });
    // Verify resume is allowed at T2
    expect(
      decisionOf(fireHookB('bash workflow-state.sh resume BUG-014', { cwd: workDir }).stdout)
    ).toBe('allow');
    // Advance
    spawnSync('bash', [WORKFLOW_STATE, 'resume', 'BUG-014'], { cwd: workDir });

    // T3: re-pause for the same reason (e.g., review reset)
    spawnSync('sleep', ['1']);
    spawnSync('bash', [WORKFLOW_STATE, 'pause', 'BUG-014', 'plan-approval'], { cwd: workDir });

    // The T2 marker is now stale (mtime < pausedAt T3). Resume must deny.
    expect(
      decisionOf(fireHookB('bash workflow-state.sh resume BUG-014', { cwd: workDir }).stdout)
    ).toBe('deny');

    // Fresh approval re-authorizes.
    fireHookA('approve plan-approval BUG-014', { cwd: workDir });
    expect(
      decisionOf(fireHookB('bash workflow-state.sh resume BUG-014', { cwd: workDir }).stdout)
    ).toBe('allow');
  });
});
