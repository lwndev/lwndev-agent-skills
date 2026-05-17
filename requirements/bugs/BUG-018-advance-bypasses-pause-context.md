# Bug: advance bypasses pause-context gates

## Bug ID

`BUG-018`

## GitHub Issue

[#281](https://github.com/lwndev/lwndev-marketplace/issues/281)

## Category

`security`

## Severity

`critical`

## Description

`workflow-state.sh advance` does not enforce pause-context steps: it marks any pending step `complete` and bumps `currentStep` without checking the step's `context` field, allowing the orchestrator to walk straight past plan-approval, PR-review, and other gated pauses with no `pausedAt` stamp and no approval marker. Hook B gates `resume` and `clear-gate` (BUG-014 / #244) but never fires for `advance`, leaving the same class of bypass open through a different call shape. The `record-findings` decision set additionally accepts `auto-fixed` unilaterally, letting the orchestrator apply review fixes without an approval marker.

## Steps to Reproduce

1. Start a feature workflow that reaches step 4 (Plan approval, `context: "pause"`). The bug reproduces for any `currentStep` whose next step has `context: "pause"` — pick this scenario for a concrete trace.
2. After `creating-implementation-plans` returns, run `workflow-state.sh advance {ID}` to mark step 3 complete.
3. Run `workflow-state.sh advance {ID}` a second time for step 4 (Plan approval).
4. Observe step 4 is marked `complete`, `currentStep` advances to step 5, and the workflow's top-level `pauseReason` stays `null`.
5. Observe that no `.approval-plan-approval-{ID}` marker exists in `.sdlc/approvals/`.
6. Observe that no `pausedAt` field is written to the workflow state file — `cmd_pause` was never called.

Reproducer evidence: `.sdlc/workflows/FEAT-034.json` shows step 4 (Plan approval) `status: "complete"`, `completedAt: "2026-05-17T13:50:12Z"`, ~34s after step 3 finished, with top-level `pauseReason: null` and no `pausedAt`. No `.approval-plan-approval-FEAT-034` marker exists.

## Expected Behavior

`workflow-state.sh advance` refuses to walk past a `context: "pause"` step without atomically pausing the workflow in the same operation. After advancing onto a pause-context step, the workflow must have `status: "paused"`, a step-derived `pauseReason`, a stamped `pausedAt`, and require an `.approval-<reason>-<ID>` marker plus `cmd_resume` (already Hook B-gated) before any subsequent advance is accepted. Non-pause-context steps must continue to advance exactly as before — no `pausedAt` is stamped, no `status` change, no behavioral regression.

`record-findings` must remove `auto-fixed` from the valid decision set entirely. The orchestrator's apply-fixes path becomes: user-approved choice in main context → orchestrator applies edits → re-fork `reviewing-requirements` → record the re-run outcome with one of the four remaining decisions (`advanced` / `auto-advanced` / `user-advanced` / `paused`). Marker-gating `auto-fixed` was considered but rejected because it leaves a path where a future "work without stopping" reinterpretation could still write the marker and bypass the gate — removal closes the call shape entirely (consistent with the spirit of this bug and RC-1's atomic-pause fix).

The orchestrator's `Output Style -> Load-bearing carve-outs` section must explicitly state that the "work without stopping for clarifying questions" system reminder does NOT apply to workflow-defined approval gates. The carve-out names all five gate identifiers users encounter in the workflow chain — `plan-approval`, `pr-review`, `findings-decision`, `review-findings`, `merge-approval` — even though they are enforced by three different mechanisms (see Notes on gate-class taxonomy).

## Actual Behavior

- `cmd_advance` (`plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh:1106-1156`) unconditionally marks any pending step `complete` and bumps `currentStep`, regardless of the step's `context` field. No pause is enforced.
- The orchestrator skipped the explicit `pause` call (`references/step-execution-details.md:97-104`), so `pausedAt` was never written and the workflow proceeded to the next step.
- `cmd_record_findings_review` (`workflow-state.sh:1365-1402`) accepts `auto-fixed` in its decision whitelist (line 1397) without any marker requirement. The FEAT-034 run picked `auto-fixed` to apply 1 error / 9 warnings without user input and `auto-advanced` the rerun.
- The orchestrator's SKILL.md `Load-bearing carve-outs` list (`SKILL.md:78-88`) names plan-approval prompts as load-bearing but does not state that workflow-defined approval gates override the "work without stopping" system reminder.

## Root Cause(s)

1. **`cmd_advance` does not enforce pause-context steps.** `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh:1106-1156` advances any step whose `status == "pending"` to `complete` without checking the step's `context == "pause"` field. The intended sequence at `references/step-execution-details.md:97-104` is `advance` (mark step complete) followed by `pause` (set workflow paused with `pausedAt`); the orchestrator simply skipped the `pause` call. Hook B (`plugins/lwndev-sdlc/scripts/hooks/guard-state-transitions.sh`) gates only `workflow-state.sh resume` and `clear-gate` — it never fires because no `resume` is issued.

2. **`auto-fixed` is an ungated `record-findings` decision.** `cmd_record_findings_review` (`plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh:1365-1402`) accepts `auto-fixed` (line 1397) without an approval marker. Any orchestrator run can pick `auto-fixed` unilaterally to apply review fixes without user input.

3. **No explicit carve-out for the "work without stopping" system reminder.** Claude Code injects a reminder reading approximately *"The user has asked you to work without stopping for clarifying questions. When you'd normally pause to check, make the reasonable call and continue; they'll redirect if needed."* The orchestrator's `Load-bearing carve-outs` section in `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md:78-88` lists plan-approval prompts as load-bearing but nowhere explicitly states the carve-out overrides this reminder. The orchestrator scope-shifted the reminder from *clarifying questions* to *workflow-defined approval gates*.

## Affected Files

- `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh` — `cmd_advance` (`:1106-1156`), `cmd_pause` whitelist (`:1166`), `cmd_record_findings_review` decision set (`:1397`)
- `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/step-execution-details.md` — explicit `advance` + `pause` sequence at `:97-104` becomes atomic in `advance`
- `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` — `Output Style -> Load-bearing carve-outs` section at `:78-88` gains an explicit carve-out statement
- `tests/bats/skills/orchestrating-workflows/workflow-state-advance-pause-context.bats` — new regression covering atomic auto-pause on `context: "pause"` steps and the second-`advance`-rejection invariant (RC-1)
- `tests/bats/skills/orchestrating-workflows/workflow-state-record-findings-qa.bats` — extended (or paired with `workflow-state-record-findings-removed-auto-fixed.bats`) to assert `auto-fixed` is no longer a valid `record-findings` decision (RC-2)
- `tests/bats/skills/orchestrating-workflows/check-resume-preconditions.bats` — companion coverage for the new auto-pause `pauseReason` values flowing through `resume` (RC-1)
- `tests/bats/shared/hooks/auto-mode-end-to-end.bats` — extended to assert that an orchestrator-style `advance` sequence past a `context: "pause"` step is denied and that `record-findings ... auto-fixed` is rejected (RC-1, RC-2)

## Acceptance Criteria

- [x] `cmd_advance` refuses to advance past a `context: "pause"` step without atomically pausing the workflow in the same operation; `status` becomes `"paused"`, `pauseReason` is derived from the destination step's `name` (lower-case + spaces-to-hyphens; e.g. `"Plan approval"` → `plan-approval`, `"PR review"` → `pr-review`) and validated against the existing `cmd_pause` whitelist (rejected if unmapped), and `pausedAt` is stamped (RC-1)
- [x] Non-pause-context steps continue to advance and bump `currentStep` exactly as before — no `pausedAt` written, no `status` change, no rejection (RC-1)
- [x] A second `cmd_advance` call on a `status: "paused"` workflow is rejected with a clear error unless `cmd_resume` has run (RC-1)
- [x] The explicit `pause` call documented in `references/step-execution-details.md:97-104` is retired in favor of the atomic auto-pause in `advance` (RC-1)
- [x] A Bats regression at `tests/bats/skills/orchestrating-workflows/workflow-state-advance-pause-context.bats` asserts the orchestrator-style sequence `advance` -> `advance` -> `advance` past step 4 of a feature workflow leaves step 4 paused (not skipped) and rejects the third call (RC-1)
- [x] `record-findings` `auto-fixed` decision is removed from the valid set at `workflow-state.sh:1397`; any call passing `auto-fixed` exits non-zero with a clear error message (RC-2)
- [x] A Bats regression asserts `record-findings ... auto-fixed` is rejected and that the orchestrator's apply-fixes path emits one of the remaining valid decisions (`advanced` / `user-advanced` / `paused` / `auto-advanced`) instead (RC-2)
- [x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` `Output Style -> Load-bearing carve-outs` section gains an explicit paragraph that (a) cites the "work without stopping for clarifying questions" reminder phrase verbatim and (b) states the carve-out does NOT apply to workflow-defined approval gates `plan-approval`, `pr-review`, `findings-decision`, `review-findings`, `merge-approval` — both substrings must be present so the prose change is mechanically verifiable via `grep` (RC-3)
- [x] The end-to-end test at `tests/bats/shared/hooks/auto-mode-end-to-end.bats` is extended to assert that an orchestrator-style `advance` attempt past a `context: "pause"` step is denied (auto-pauses) AND that `record-findings ... auto-fixed` is rejected (RC-1, RC-2)

## Completion

**Status:** `Completed`

**Completed:** 2026-05-17

**Pull Request:** [#N](https://github.com/lwndev/lwndev-marketplace/pull/N)

## Notes

- This is the same class of bypass as BUG-014 (#244 — `auto-mode-bypasses-confirmation-gates`) via a different call shape. BUG-014 hardened `resume`, `clear-gate`, and destructive Bash; it did not harden `advance`.
- The fix collapses the two-call ceremony (`advance` then `pause`) into one atomic operation. Once `advance` auto-pauses on `context: "pause"` steps, the orchestrator cannot construct a sequence of tool calls that skips the pause because the pause is implicit in advancing onto a pause-context step.
- **Gate-class taxonomy** (informational, for implementer context): The five identifiers named in AC for RC-3 are enforced by three different mechanisms — RC-3's carve-out paragraph names all five at the prose layer, but only RC-1's `cmd_advance` auto-pause change touches the first two:
  - `plan-approval`, `pr-review`, `review-findings` are `pauseReason` values in the `cmd_pause` whitelist (`workflow-state.sh:1166`). RC-1's atomic auto-pause is the relevant mechanical enforcement.
  - `findings-decision` is a `gate` type (`workflow-state.sh:1223`), separately gated by Hook B's `clear-gate` check.
  - `merge-approval` is enforced by Hook B's destructive-Bash check (`guard-state-transitions.sh:252`) and Hook C's agent-prompt check (`guard-agent-prompts.sh:194`), already hardened by BUG-014.
- **`auto-fixed` removal choice** (RC-2 path selection): removal was preferred over marker-gating because (a) the orchestrator's existing apply-fixes pattern already supports recording the re-fork outcome with the remaining decisions (`advanced` / `user-advanced` / `paused` / `auto-advanced --rerun`), so no information is lost; (b) marker-gating leaves a path where a future "work without stopping" reinterpretation could write the marker and bypass the gate, whereas removal closes the call shape entirely; (c) it aligns with RC-1's spirit of removing call shapes rather than adding guards.
- Reproduced under Claude Opus 4.7 on branch `feat/FEAT-034-ado-pr-comments` (started 2026-05-17). Evidence preserved in `.sdlc/workflows/FEAT-034.json` and `.sdlc/approvals/` (no `FEAT-034` marker present).
