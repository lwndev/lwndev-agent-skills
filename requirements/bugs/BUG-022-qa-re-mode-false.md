# Bug: QA re-mode false positive on initial run

## Bug ID

`BUG-022`

## GitHub Issue

[#302](https://github.com/lwndev/lwndev-marketplace/issues/302)

## Category

`logic-error`

## Severity

`high`

## Description

`executing-qa` falsely resolves `mode=re-qa` on the first QA run for a fresh
requirement ID whenever the branch carries committed `qa-*` test files. The
skill then skips test-writing and runs unrelated prior-workflow QA tests,
emitting a misleading PASS that never exercises the feature under QA.

## Steps to Reproduce

Precondition: the current branch carries at least one committed file matching
`tests/unit/qa-*.test.ts`, `tests/unit/qa-*.test.js`, or `tests/bats/qa/qa-*.bats`.
(On this repo `main` is normally clean of these because the FR-9 finalize gate
blocks merges that retain `qa-*` files — see Notes. The precondition holds on a
feature branch mid-workflow, or on any branch where the gate was bypassed.)

1. Start a new workflow with a fresh ID (e.g. FEAT-NNN / BUG-NNN). Workflow
   state shows `qaFixAttempts: 0`, `qaLastVerdict: null` — no prior QA run for
   this ID.
2. Drive the chain to the Execute QA step.
3. Quick Start step 1 runs `qa-baseline.sh init <ID>`, then step 2 runs
   `detect-re-qa-mode.sh <ID>`.
4. Observe: `{"mode":"re-qa","files":[<unrelated prior-workflow qa-*.test.ts>]}`.
5. Expected: `{"mode":"initial","files":[...]}` — `qaFixAttempts` is 0 and no
   prior QA run for this ID exists.

## Expected Behavior

On an initial QA run for an ID with no prior QA history
(`qaFixAttempts == 0 && qaLastVerdict == null`), detection resolves to
`mode=initial` regardless of committed `qa-*` test files on the branch. The
skill writes fresh adversarial tests for the feature under QA. Re-QA mode is
entered only when a genuine prior QA run for the same ID has occurred.

## Actual Behavior

Detection returns `mode=re-qa` on the first run. `executing-qa` skips the
test-writing phase, runs unrelated prior-workflow `qa-*` tests as the
fix-grade signal, and emits a PASS verdict with no adversarial coverage of the
feature under QA. The orchestrator advances and the workflow finalizes — the
change merges to main without QA having exercised it.

## Root Cause(s)

1. `detect-re-qa-mode.sh` infers "a prior QA run exists for this ID" from the
   conjunction of (a) baseline-marker presence and (b) any committed `qa-*`
   test file on the branch (`plugins/lwndev-sdlc/skills/executing-qa/scripts/detect-re-qa-mode.sh:76`).
   Neither condition is a reliable per-ID prior-run signal, and the
   authoritative state (`qaFixAttempts` / `qaLastVerdict`, available via
   `workflow-state.sh get-qa-state <ID>`) is never consulted:
   - The baseline marker is written unconditionally by `qa-baseline.sh init`
     (`plugins/lwndev-sdlc/skills/executing-qa/scripts/qa-baseline.sh:33-36`,
     `git rev-parse HEAD > "$MARKER_PATH"`, no existence check), and the
     executing-qa Quick Start runs that `init` (step 1) *before*
     `detect-re-qa-mode.sh` (step 2). So the marker the detector reads always
     belongs to the current run, never a prior one.
   - The committed-file condition matches `qa-*` tests from *any* prior
     workflow, not just QA runs for the ID under test.

   Both halves of the conjunction therefore hold on every initial run whenever
   the branch carries committed `qa-*` files, and the detector reports `re-qa`.

## Affected Files

- `plugins/lwndev-sdlc/skills/executing-qa/scripts/detect-re-qa-mode.sh` — re-QA decision (conjunction at line 76); primary fix surface.
- `plugins/lwndev-sdlc/skills/executing-qa/scripts/qa-baseline.sh` — unconditional `init` marker write (lines 33-36); mechanism context.
- `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` — Quick Start step 1/step 2 ordering and the "State File Management" section; update in lockstep with any chosen fix.
- `tests/bats/skills/executing-qa/` — regression coverage for the detection contract.

## Acceptance Criteria

- [x] An initial QA run for an ID with `qaFixAttempts == 0 && qaLastVerdict == null` resolves to `mode=initial` even when committed `qa-*` test files exist on the branch and the baseline marker is present (RC-1)
- [x] Re-QA mode is NOT entered solely because unrelated prior-workflow `qa-*` test files are committed on the branch (RC-1)
- [x] A genuine prior QA run for the same ID (`qaFixAttempts >= 1` or `qaLastVerdict` set) still resolves to `mode=re-qa` when committed `qa-*` files exist — the real re-QA path does not regress (RC-1)
- [x] Regression test covers both the false-positive case (fresh ID + committed `qa-*` files -> initial) and the true-positive case (prior run + committed `qa-*` files -> re-qa) (RC-1)

## Completion

**Status:** `Pending`

## Notes

- Detection runs in a workflow's executing-qa step from the **cached** plugin
  copy, not this repo's working tree. A repo-side fix is not live for an
  in-flight workflow until the plugin is re-released and the cache updated.
- Tension with FR-9: the finalize preflight blocks merges that retain tracked
  `qa-*` files, so `main` is normally clean of them. The repro precondition
  (committed `qa-*` files present) is reached on feature branches mid-workflow
  or when the gate is bypassed — not on a clean `main`.
- Interim operator workaround (issue #302): on initial runs, if
  `detect-re-qa-mode.sh` reports `re-qa` while `qaFixAttempts`/`qaLastVerdict`
  are zero/null, `qa-baseline.sh clear <ID>` -> re-detect -> `qa-baseline.sh init <ID>`.
- Issue #302 proposes three fix options (re-order Quick Start; idempotent
  `init`; cross-check state inside the detector). The fix surface is deferred
  to the implementation step; the acceptance criteria above are behavioral and
  satisfiable by any of them.
