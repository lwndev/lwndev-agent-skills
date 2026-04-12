# Bug: Stop Hook Findings Feedback Loop

## Bug ID

`BUG-011`

## GitHub Issue

[#153](https://github.com/lwndev/lwndev-marketplace/issues/153)

## Category

`logic-error`

## Severity

`high`

## Description

The orchestrating-workflows stop hook fires on every assistant response, including responses where the orchestrator is legitimately waiting for user input at a findings-handling decision point. This creates a feedback loop that pressures the agent into bypassing user confirmation and acting unilaterally.

## Steps to Reproduce

1. Start a feature workflow (e.g., FEAT-015)
2. Reach step 2 (`reviewing-requirements`, standard mode)
3. Have the review return at least 1 error (which blocks progression per the findings-handling Decision Flow)
4. The orchestrator presents findings and asks "Apply fixes or pause?"
5. Observe the stop hook fire on that response: "Workflow FEAT-015 is in-progress. Continue to step 2"
6. The agent responds to the nudge instead of waiting for user input
7. Stop hook fires again, creating a spiral

## Expected Behavior

The stop hook should not emit a "continue" nudge when the orchestrator is blocked on a findings gate that requires user input. The agent should be able to wait for user confirmation without being nudged into acting.

## Actual Behavior

The stop hook repeatedly fires "Continue to step 2" on every assistant response during the findings-handling decision point, creating a spiral that eventually pressures the agent into bypassing the user confirmation prompt and applying fixes unilaterally.

## Root Cause(s)

1. The stop hook (`plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/stop-hook.sh:37-52`) only inspects the top-level workflow `status` field (`in-progress`, `paused`, `complete`, `failed`). When the orchestrator is awaiting user input at a findings gate within an in-progress step, the status remains `in-progress`, so the hook emits a "continue" nudge. The hook has no awareness of sub-step decision gates.

2. The workflow state model (`plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh`) has no concept of a "gate" or "pending input" sub-state. There is no mechanism for the orchestrator to signal that it is legitimately waiting for user input within an in-progress step, so the stop hook cannot distinguish "idle at a step" from "blocked on a user decision within a step".

## Affected Files

- `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/stop-hook.sh`
- `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh`
- `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md`

## Acceptance Criteria

- [x] A gate mechanism exists in the workflow state model that allows the orchestrator to signal "waiting for user input" within an in-progress step (RC-2)
- [x] The stop hook checks for the gate state and suppresses the "continue" nudge when a gate is active (RC-1)
- [x] The orchestrator sets the gate before presenting findings decisions to the user (RC-1, RC-2)
- [x] The orchestrator clears the gate when the user responds (proceed or pause) (RC-2)
- [x] The stop hook still nudges correctly for in-progress workflows that are NOT at a gate (RC-1)
- [x] Existing pause reasons (`plan-approval`, `pr-review`, `review-findings`) continue to work unchanged (RC-1)

## Completion

**Status:** `Complete`

**Completed:** 2026-04-12

**Pull Request:** [#156](https://github.com/lwndev/lwndev-marketplace/pull/156)

## Notes

- Observed during FEAT-015 workflow execution
- The findings-handling Decision Flow has three paths (zero findings, warnings-only, errors present) — the gate is relevant for errors-present and warnings-only paths that prompt the user
- Related to BUG-010 (QA stop hook cross-fire) which addressed a similar stop hook interference pattern in a different context
