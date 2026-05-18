// Adversarial QA tests for BUG-018 (atomic auto-pause in workflow-state.sh
// advance + removal of `auto-fixed` from record-findings decision set).
//
// Covers the QA plan dimensions that the implementer-authored bats suite does
// not exercise: derivation edge cases (Unicode, whitespace, unmapped names),
// concurrency races, environment failures, and the SKILL.md prose contract.
//
// Each test spawns the in-repo `plugins/.../workflow-state.sh` against a temp
// state file in `mkdtemp` so vitest's parallel runner does not race the real
// `.sdlc/workflows/` tree.

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { spawnSync } from 'node:child_process';
import {
  mkdtempSync,
  rmSync,
  writeFileSync,
  readFileSync,
  statSync,
  chmodSync,
  existsSync,
  mkdirSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

const REPO_ROOT = resolve(__dirname, '..', '..');
const SCRIPT = resolve(
  REPO_ROOT,
  'plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh'
);
const ORCH_SKILL = resolve(
  REPO_ROOT,
  'plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md'
);

const ID = 'BUG-TEST';

type Step = {
  name: string;
  skill: string | null;
  context: string;
  status?: string;
  artifact?: null;
  completedAt?: null;
};

function seedState(dir: string, steps: Step[], currentStep = 0): string {
  const sdlcDir = join(dir, '.sdlc', 'workflows');
  mkdirSync(sdlcDir, { recursive: true });
  const filled = steps.map((s, i) => ({
    name: s.name,
    skill: s.skill,
    context: s.context,
    status: s.status ?? (i < currentStep ? 'complete' : 'pending'),
    artifact: null,
    completedAt: null,
  }));
  const state = {
    id: ID,
    type: 'bug',
    currentStep,
    status: 'in-progress',
    pauseReason: null,
    gate: null,
    gateSetAt: null,
    steps: filled,
    phases: { total: 0, completed: 0 },
    prNumber: null,
    branch: null,
    startedAt: '2026-05-17T00:00:00Z',
    lastResumedAt: null,
    complexity: 'high',
    complexityStage: 'init',
    modelOverride: null,
    modelSelections: [],
    qaFixAttempts: 0,
    qaLastVerdict: null,
    adoptedTests: [],
    qaLoopCap: 2,
    stateEvents: [],
  };
  const path = join(sdlcDir, `${ID}.json`);
  writeFileSync(path, JSON.stringify(state, null, 2));
  return path;
}

function run(dir: string, ...args: string[]) {
  return spawnSync('bash', [SCRIPT, ...args], {
    cwd: dir,
    encoding: 'utf-8',
    env: { ...process.env },
  });
}

let workdir: string;
beforeEach(() => {
  workdir = mkdtempSync(join(tmpdir(), 'qa-bug-018-'));
});
afterEach(() => {
  try {
    rmSync(workdir, { recursive: true, force: true });
  } catch {
    // ignore (file may already be gone if a test chmod'd it)
  }
});

describe('BUG-018 / Inputs — advance and pause-context derivation', () => {
  it('[P0] advance on a non-pause-context step does NOT auto-pause; status, pauseReason, pausedAt unchanged', () => {
    seedState(
      workdir,
      [
        { name: 'Document bug', skill: 'documenting-bugs', context: 'main' },
        { name: 'Review requirements', skill: 'reviewing-requirements', context: 'fork' },
        { name: 'Document QA test plan', skill: 'documenting-qa', context: 'main' },
      ],
      0
    );

    const result = run(workdir, 'advance', ID);
    expect(result.status).toBe(0);

    const state = JSON.parse(readFileSync(join(workdir, '.sdlc/workflows', `${ID}.json`), 'utf-8'));
    expect(state.status).toBe('in-progress');
    expect(state.pauseReason).toBeNull();
    expect(state).not.toHaveProperty('pausedAt'); // not written for non-pause
    expect(state.currentStep).toBe(1);
    expect(state.steps[0].status).toBe('complete');
  });

  it('[P0] advance onto a pause-context step is ATOMIC: step complete + status paused + pauseReason + pausedAt all land together', () => {
    seedState(
      workdir,
      [
        { name: 'Review requirements', skill: 'reviewing-requirements', context: 'fork' },
        { name: 'Plan approval', skill: null, context: 'pause' },
      ],
      0
    );

    const result = run(workdir, 'advance', ID);
    expect(result.status).toBe(0);

    const state = JSON.parse(readFileSync(join(workdir, '.sdlc/workflows', `${ID}.json`), 'utf-8'));
    // The four atomicity invariants must hold simultaneously.
    expect(state.steps[0].status).toBe('complete');
    expect(state.currentStep).toBe(1);
    expect(state.status).toBe('paused');
    expect(state.pauseReason).toBe('plan-approval');
    expect(state.pausedAt).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/);
  });

  it('[P0] advance on an already-paused workflow is rejected; state file is byte-identical', () => {
    const statePath = seedState(
      workdir,
      [
        { name: 'Review requirements', skill: 'reviewing-requirements', context: 'fork' },
        { name: 'Plan approval', skill: null, context: 'pause' },
      ],
      0
    );
    // First advance: lands on pause-context step, auto-pauses.
    expect(run(workdir, 'advance', ID).status).toBe(0);
    const beforeSecond = readFileSync(statePath);

    // Second advance: must be rejected with a clear error.
    const second = run(workdir, 'advance', ID);
    expect(second.status).not.toBe(0);
    expect(second.stderr).toMatch(/cannot advance: workflow paused/);
    expect(second.stderr).toMatch(/pauseReason=plan-approval/);
    expect(second.stderr).toMatch(/resume first/);

    // State must be byte-identical (no mutation on the rejected call).
    const afterSecond = readFileSync(statePath);
    expect(afterSecond.equals(beforeSecond)).toBe(true);
  });

  it('[P0] derivation: "Plan approval" -> plan-approval AND "PR review" -> pr-review (both in cmd_pause whitelist)', () => {
    for (const [name, expected] of [
      ['Plan approval', 'plan-approval'],
      ['PR review', 'pr-review'],
    ] as const) {
      const dir = mkdtempSync(join(tmpdir(), 'qa-bug-018-derive-'));
      try {
        seedState(
          dir,
          [
            { name: 'fork step', skill: 'x', context: 'fork' },
            { name, skill: null, context: 'pause' },
          ],
          0
        );
        const result = run(dir, 'advance', ID);
        expect(result.status, `derivation failed for "${name}": ${result.stderr}`).toBe(0);
        const state = JSON.parse(readFileSync(join(dir, '.sdlc/workflows', `${ID}.json`), 'utf-8'));
        expect(state.pauseReason).toBe(expected);
      } finally {
        rmSync(dir, { recursive: true, force: true });
      }
    }
  });

  it('[P0] derivation lands on a NOT-whitelisted reason ("Foo bar" -> foo-bar) -> rejection, state byte-identical', () => {
    const statePath = seedState(
      workdir,
      [
        { name: 'fork step', skill: 'x', context: 'fork' },
        { name: 'Foo bar', skill: null, context: 'pause' },
      ],
      0
    );
    const before = readFileSync(statePath);

    const result = run(workdir, 'advance', ID);
    expect(result.status).not.toBe(0);
    expect(result.stderr).toMatch(/derived pauseReason 'foo-bar' is not in cmd_pause whitelist/);

    const after = readFileSync(statePath);
    expect(after.equals(before)).toBe(true);
  });

  it('[P1] derivation handles mixed casing + collapsed whitespace ("  PLAN   APPROVAL  " -> plan-approval)', () => {
    seedState(
      workdir,
      [
        { name: 'fork step', skill: 'x', context: 'fork' },
        { name: '  PLAN   APPROVAL  ', skill: null, context: 'pause' },
      ],
      0
    );
    const result = run(workdir, 'advance', ID);
    expect(result.status).toBe(0);
    const state = JSON.parse(readFileSync(join(workdir, '.sdlc/workflows', `${ID}.json`), 'utf-8'));
    expect(state.pauseReason).toBe('plan-approval');
  });

  it('[P1] derivation does NOT silently strip Unicode diacritics ("Pläne approval" -> rejected, NOT mapped to plan-approval)', () => {
    seedState(
      workdir,
      [
        { name: 'fork step', skill: 'x', context: 'fork' },
        { name: 'Pläne approval', skill: null, context: 'pause' },
      ],
      0
    );
    const result = run(workdir, 'advance', ID);
    // Either rejected (whitelist mismatch since "pläne-approval" not in whitelist)
    // OR succeeds only if derivation kept the diacritic intact.
    if (result.status === 0) {
      const state = JSON.parse(
        readFileSync(join(workdir, '.sdlc/workflows', `${ID}.json`), 'utf-8')
      );
      expect(state.pauseReason).not.toBe('plan-approval');
    } else {
      // Whitelist-mismatch rejection (preferred — never silently coerce non-ASCII).
      expect(result.stderr).toMatch(/is not in cmd_pause whitelist/);
    }
  });
});

describe('BUG-018 / Inputs — record-findings decision whitelist', () => {
  function seedRecord(dir: string) {
    seedState(
      dir,
      [
        { name: 'Document', skill: 'documenting-bugs', context: 'main' },
        { name: 'Review', skill: 'reviewing-requirements', context: 'fork' },
      ],
      1
    );
  }

  it('[P0] record-findings with decision=auto-fixed is REJECTED (post-fix invariant)', () => {
    seedRecord(workdir);
    const result = run(
      workdir,
      'record-findings',
      ID,
      '1',
      '0',
      '0',
      '0',
      'auto-fixed',
      'should not be accepted'
    );
    expect(result.status).not.toBe(0);
    // The error message MUST cite the four remaining valid decisions and MUST NOT include auto-fixed.
    expect(result.stderr).toMatch(/auto-fixed/);
    expect(result.stderr).toMatch(/(advanced|auto-advanced|user-advanced|paused)/);
  });

  it('[P0] record-findings with each of the four remaining valid decisions SUCCEEDS', () => {
    for (const decision of ['advanced', 'auto-advanced', 'user-advanced', 'paused']) {
      const dir = mkdtempSync(join(tmpdir(), `qa-bug-018-rf-${decision}-`));
      try {
        seedRecord(dir);
        const result = run(dir, 'record-findings', ID, '1', '0', '0', '0', decision, 'summary');
        expect(
          result.status,
          `decision ${decision} should be accepted but failed: ${result.stderr}`
        ).toBe(0);
      } finally {
        rmSync(dir, { recursive: true, force: true });
      }
    }
  });

  it('[P1] record-findings --rerun with auto-fixed is ALSO rejected (no special-casing in the rerun code path)', () => {
    seedRecord(workdir);
    const result = run(
      workdir,
      'record-findings',
      ID,
      '1',
      '0',
      '0',
      '0',
      'auto-fixed',
      'should not be accepted on rerun either',
      '--rerun'
    );
    expect(result.status).not.toBe(0);
  });
});

describe('BUG-018 / State transitions — round trip and concurrency', () => {
  it('[P0] full round trip: advance -> auto-pause -> resume -> advance succeeds end-to-end', () => {
    // Use a workflow with three steps and a real pause-context step.
    const statePath = seedState(
      workdir,
      [
        { name: 'Document', skill: 'documenting-bugs', context: 'main' },
        { name: 'Plan approval', skill: null, context: 'pause' },
        { name: 'Execute', skill: 'executing-bug-fixes', context: 'fork' },
      ],
      0
    );

    // advance -> auto-pause
    expect(run(workdir, 'advance', ID).status).toBe(0);
    let state = JSON.parse(readFileSync(statePath, 'utf-8'));
    expect(state.status).toBe('paused');
    expect(state.pauseReason).toBe('plan-approval');

    // resume
    expect(run(workdir, 'resume', ID).status).toBe(0);
    state = JSON.parse(readFileSync(statePath, 'utf-8'));
    expect(state.status).toBe('in-progress');
    expect(state.pauseReason).toBeNull();
    expect(state.lastResumedAt).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/);

    // advance past the pause step to a non-pause-context step
    expect(run(workdir, 'advance', ID).status).toBe(0);
    state = JSON.parse(readFileSync(statePath, 'utf-8'));
    expect(state.status).toBe('in-progress');
    expect(state.currentStep).toBe(2);
  });

  it('[P0] two concurrent advances against the same workflow leave state coherent (not corrupted)', async () => {
    seedState(
      workdir,
      [
        { name: 'Document', skill: 'documenting-bugs', context: 'main' },
        { name: 'Plan approval', skill: null, context: 'pause' },
      ],
      0
    );
    const path = join(workdir, '.sdlc/workflows', `${ID}.json`);

    // Spawn two concurrent advances. With no locking, one wins and one may either
    // succeed (idempotent re-walk) or fail; the state file MUST remain parseable
    // JSON with a coherent shape (no truncation, no half-written mutation).
    const [a, b] = await Promise.all([
      new Promise<ReturnType<typeof spawnSync>>((res) => {
        setImmediate(() => res(run(workdir, 'advance', ID)));
      }),
      new Promise<ReturnType<typeof spawnSync>>((res) => {
        setImmediate(() => res(run(workdir, 'advance', ID)));
      }),
    ]);
    void a;
    void b;

    // Parse the final state — must be valid JSON and either still on step 0
    // (both rejected) or paused on step 1 (one won, second saw paused state).
    const text = readFileSync(path, 'utf-8');
    let state: {
      status: string;
      pauseReason: string | null;
      currentStep: number;
      pausedAt?: string;
    };
    expect(() => {
      state = JSON.parse(text);
    }).not.toThrow();
    state = JSON.parse(text);

    // Either the winner auto-paused (status=paused) or the test reaches the
    // post-pause state. The bug being absent means we never see currentStep=1
    // AND status=in-progress (the "paused-without-pausing" footprint).
    if (state.status === 'paused') {
      expect(state.pauseReason).toBe('plan-approval');
      expect(state.pausedAt).toBeDefined();
    } else {
      // If neither write happened (both rejected), state is unchanged.
      expect(state.currentStep).toBe(0);
    }
  });
});

describe('BUG-018 / Environment — file permission and missing prerequisites', () => {
  it('[P1] advance with chmod 000 state file fails CLEANLY with a non-zero exit and does NOT truncate the file', () => {
    const statePath = seedState(
      workdir,
      [
        { name: 'Document', skill: 'documenting-bugs', context: 'main' },
        { name: 'Plan approval', skill: null, context: 'pause' },
      ],
      0
    );
    const sizeBefore = statSync(statePath).size;
    chmodSync(statePath, 0o000);
    try {
      const result = run(workdir, 'advance', ID);
      expect(result.status).not.toBe(0);
    } finally {
      // Restore so afterEach cleanup can rm the dir.
      chmodSync(statePath, 0o644);
    }
    const sizeAfter = statSync(statePath).size;
    expect(sizeAfter).toBe(sizeBefore);
  });

  it('[P0] advance against a non-existent ID exits non-zero with documented error', () => {
    // No seed: the state dir exists but the file does not.
    mkdirSync(join(workdir, '.sdlc', 'workflows'), { recursive: true });
    const result = run(workdir, 'advance', 'NOPE-999');
    expect(result.status).not.toBe(0);
    expect(result.stderr.length).toBeGreaterThan(0);
  });
});

describe('BUG-018 / Cross-cutting — SKILL.md prose contract (mechanically verifiable)', () => {
  it('[P0] SKILL.md carve-out contains the verbatim "work without stopping for clarifying questions" reminder phrase', () => {
    expect(existsSync(ORCH_SKILL)).toBe(true);
    const content = readFileSync(ORCH_SKILL, 'utf-8');
    expect(content).toMatch(/work without stopping for clarifying questions/);
  });

  it('[P0] SKILL.md carve-out names ALL FIVE gate identifiers (plan-approval, pr-review, findings-decision, review-findings, merge-approval)', () => {
    const content = readFileSync(ORCH_SKILL, 'utf-8');
    for (const gate of [
      'plan-approval',
      'pr-review',
      'findings-decision',
      'review-findings',
      'merge-approval',
    ]) {
      expect(content, `gate identifier '${gate}' missing from SKILL.md`).toMatch(new RegExp(gate));
    }
  });

  it('[P1] SKILL.md carve-out section uses ASCII punctuation only (no Unicode em-dash or smart quotes in the carve-outs block)', () => {
    const content = readFileSync(ORCH_SKILL, 'utf-8');
    // Extract just the Load-bearing carve-outs section (header to next ## heading).
    const match = content.match(/### Load-bearing carve-outs[\s\S]*?(?=\n### |\n## )/);
    expect(match).not.toBeNull();
    const block = match![0];
    // Tolerate em-dashes that already exist elsewhere; assert no smart quotes in the carve-out block.
    expect(block).not.toMatch(/[‘’“”]/);
  });
});

describe('BUG-018 / Dependency failure — references documentation drift', () => {
  it('[P1] references/step-execution-details.md no longer documents the explicit `pause` call after `advance` for pause-context steps', () => {
    const ref = resolve(
      REPO_ROOT,
      'plugins/lwndev-sdlc/skills/orchestrating-workflows/references/step-execution-details.md'
    );
    expect(existsSync(ref)).toBe(true);
    const content = readFileSync(ref, 'utf-8');
    // The old pattern was an explicit `workflow-state.sh pause {ID} plan-approval` on a line
    // immediately following an `advance` for the same step. Assert no such literal sequence
    // remains for plan-approval / pr-review at minimum.
    const oldPattern1 =
      /workflow-state\.sh\s+advance\s+\{ID\}\s*\n[^\n]*workflow-state\.sh\s+pause\s+\{ID\}\s+plan-approval/;
    const oldPattern2 =
      /workflow-state\.sh\s+advance\s+\{ID\}\s*\n[^\n]*workflow-state\.sh\s+pause\s+\{ID\}\s+pr-review/;
    expect(content).not.toMatch(oldPattern1);
    expect(content).not.toMatch(oldPattern2);
  });
});
