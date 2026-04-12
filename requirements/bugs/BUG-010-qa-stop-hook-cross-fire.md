# Bug: QA Stop Hook Cross-Fire

## Bug ID

`BUG-010`

## GitHub Issue

[#143](https://github.com/lwndev/lwndev-marketplace/issues/143)

## Category

`logic-error`

## Severity

`medium`

## Description

The `documenting-qa` and `executing-qa` stop hooks fire during unrelated skills (e.g., `/releasing-plugins`, `/executing-chores`, `/implementing-plan-phases`), blocking completion with QA-specific error messages. Claude Code runs all registered stop hooks when any skill attempts to stop, and these two hooks have no mechanism to detect whether their skill is actually active.

## Steps to Reproduce

1. Install the `lwndev-sdlc` plugin (which registers stop hooks for `documenting-qa` and `executing-qa`)
2. Run any unrelated skill such as `/releasing-plugins` or `/executing-chores`
3. Allow the skill to attempt completion (stop)
4. Observe that the `documenting-qa` and `executing-qa` stop hooks fire alongside the intended skill's hooks

## Expected Behavior

Stop hooks for `documenting-qa` and `executing-qa` should only evaluate their completion criteria when their respective skill is the active skill. When an unrelated skill is running, these hooks should exit 0 immediately (allow stop) without evaluating keyword patterns.

## Actual Behavior

Both hooks evaluate keyword patterns against `last_assistant_message` regardless of which skill is active. Since unrelated skills don't produce QA-specific keywords, the hooks block with exit 2:

- `documenting-qa` hook: "Test plan documentation does not appear complete. Ensure the qa-verifier subagent has confirmed completeness and the test plan has been saved."
- `executing-qa` hook: "QA verification has not passed cleanly; documentation reconciliation is not yet complete."

## Root Cause(s)

1. **`documenting-qa/scripts/stop-hook.sh` lacks a state-file gate** — The hook reads stdin JSON and immediately proceeds to keyword matching against `last_assistant_message` (lines 12-58). It has no check for whether the `documenting-qa` skill is the active skill. Unlike the `orchestrating-workflows` hook which gates on `.sdlc/workflows/.active`, this hook always evaluates and blocks when its keyword patterns are absent.

2. **`executing-qa/scripts/stop-hook.sh` lacks a state-file gate** — Same issue: the hook reads stdin JSON and proceeds directly to keyword matching (lines 12-76) with no check for whether `executing-qa` is active. It blocks with exit 2 whenever verification/reconciliation keywords are missing from the assistant message.

3. **Neither `documenting-qa/SKILL.md` nor `executing-qa/SKILL.md` manages state files** — The skill instructions do not create a state marker on start or remove it on completion, so even if a gate were added to the hooks, there would be no state file to gate on.

## Affected Files

- `plugins/lwndev-sdlc/skills/documenting-qa/scripts/stop-hook.sh` — add state-file gate at top of script
- `plugins/lwndev-sdlc/skills/documenting-qa/SKILL.md` — add instructions to create `.sdlc/qa/.documenting-active` at skill start and remove on completion
- `plugins/lwndev-sdlc/skills/executing-qa/scripts/stop-hook.sh` — add state-file gate at top of script
- `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` — add instructions to create `.sdlc/qa/.executing-active` at skill start and remove on completion

## Acceptance Criteria

- [x] `documenting-qa` stop hook exits 0 immediately when `.sdlc/qa/.documenting-active` does not exist (RC-1)
- [x] `executing-qa` stop hook exits 0 immediately when `.sdlc/qa/.executing-active` does not exist (RC-2)
- [x] `documenting-qa` SKILL.md instructs skill to create `.sdlc/qa/.documenting-active` at start and remove on completion (RC-3)
- [x] `executing-qa` SKILL.md instructs skill to create `.sdlc/qa/.executing-active` at start and remove on completion (RC-3)
- [x] Both hooks still enforce their completion criteria when their respective state file IS present (RC-1, RC-2)
- [x] Running `/releasing-plugins` no longer triggers QA stop hook errors (RC-1, RC-2)
- [x] Running `/executing-qa` no longer triggers `documenting-qa` stop hook errors (RC-1)
- [x] Hook itself removes state file on successful completion (exit 0 after keyword match) as cleanup fallback (RC-1, RC-2)

## Completion

**Status:** `Completed`

**Completed:** 2026-04-12

**Pull Request:** [#145](https://github.com/lwndev/lwndev-marketplace/pull/145)

## Notes

- The `orchestrating-workflows` hook gates on `.sdlc/workflows/.active` and the `releasing-plugins` hook gates on `.sdlc/releasing/.active` — both exit 0 immediately when their state file is absent. This is the proven pattern to follow.
- Both hooks can share `.sdlc/qa/` as the state directory with distinct marker files (`.documenting-active` and `.executing-active`) to avoid collision if both skills are invoked in the same session.
- The `orchestrating-workflows` skill already manages main-context QA steps (`documenting-qa` at feature step 5 / chore step 3, `executing-qa` at feature step 6+N+4 / chore step 8). The SKILL.md instructions for state-file creation must work both when the skill is invoked standalone and when run as part of an orchestrated workflow.
