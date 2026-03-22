# Bug: Service Overloaded During QA Verifier Execution

## Bug ID

`BUG-002`

## GitHub Issue

[#35](https://github.com/lwndev/lwndev-marketplace/issues/35)

## Category

`runtime-error`

## Severity

`medium`

## Description

A "service overloaded" error occurs during `documenting-qa` runs while the `qa-verifier` subagent is active. The error disrupts the verification loop, leaving the test plan in an incomplete state with no recovery path.

## Steps to Reproduce

1. Run the `documenting-qa` skill with a requirement ID (e.g., `FEAT-004`)
2. The skill builds a test plan and spawns the `qa-verifier` subagent (Sonnet model) for completeness verification
3. While the qa-verifier is executing, a "service overloaded" error occurs
4. The skill fails with no retry or recovery mechanism

## Expected Behavior

The `documenting-qa` skill should complete the verification loop successfully, or gracefully handle transient API errors by providing guidance for recovery so the test plan can still be finalized.

## Actual Behavior

The skill encounters a "service overloaded" error during qa-verifier execution and fails without any error handling or recovery guidance. The user must manually re-run the entire skill from scratch.

## Root Cause(s)

1. The `documenting-qa` skill (`plugins/lwndev-sdlc/skills/documenting-qa/SKILL.md`) contains no error handling or retry guidance for transient API errors during the qa-verifier verification loop. When the subagent encounters a "service overloaded" error, there is no instruction for how to recover — the skill simply fails.

2. The iterative verification architecture creates compounding API pressure: the main conversation (parent model) spawns a `qa-verifier` subagent (Sonnet), and upon attempting to finish, the Stop hook fires a prompt evaluation (Haiku). If the Stop hook rejects and the loop iterates multiple times, each iteration generates sequential API calls across three models, increasing the likelihood of hitting rate limits or capacity constraints during periods of elevated API load.

## Affected Files

- `plugins/lwndev-sdlc/skills/documenting-qa/SKILL.md`

## Acceptance Criteria

- [ ] The `documenting-qa` skill includes guidance for handling transient API errors (e.g., "service overloaded") during the qa-verifier verification loop, instructing the agent to retry the subagent delegation rather than failing outright (RC-1)
- [ ] The retry guidance specifies a maximum number of attempts to prevent infinite retry loops (RC-1)
- [ ] The skill documents expected behavior when the qa-verifier subagent fails after retries — e.g., present the test plan to the user as-is with a note that automated verification could not be completed (RC-1)
- [ ] The verification loop guidance acknowledges the multi-model API call pattern and encourages completing verification in as few iterations as possible to reduce cumulative API pressure (RC-2)

## Completion

**Status:** `Completed`

**Completed:** 2026-03-21

**Pull Request:** [#PR](https://github.com/lwndev/lwndev-marketplace/pull/PR)

## Notes

- This error may be transient and not consistently reproducible — it depends on API capacity at the time of execution
- Split from [#32](https://github.com/lwndev/lwndev-marketplace/issues/32); original feature is FEAT-004 / [#23](https://github.com/lwndev/lwndev-marketplace/issues/23)
- The qa-verifier agent (`plugins/lwndev-sdlc/agents/qa-verifier.md`) itself does not need changes — the resilience guidance belongs in the calling skill's instructions
- The Stop hook uses a Haiku prompt evaluator with no tool access, so it is lightweight; the primary API pressure comes from the main conversation + qa-verifier subagent combination
