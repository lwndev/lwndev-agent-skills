# Bug: QA Skill Audits Coverage Instead of Executing Test Plan

## Bug ID

`BUG-003`

## GitHub Issue

[#74](https://github.com/lwndev/lwndev-marketplace/issues/74)

## Category

`logic-error`

## Severity

`high`

## Description

The `executing-qa` skill does not directly verify test plan entries. Instead, it delegates to the `qa-verifier` subagent which runs `npm test` and audits whether automated test coverage exists for each entry — a developer activity, not QA execution. Test plan entries are never directly checked; they serve only as a guide for what automated tests should exist.

## Steps to Reproduce

1. Create a requirement document (e.g., `FEAT-XXX` or `CHORE-XXX`)
2. Run `documenting-qa` to produce a test plan with entries like "SKILL.md contains PR creation step/section"
3. Run `executing-qa` against that requirement ID
4. Observe that the skill runs `npm test`, checks whether automated tests cover each plan entry, and writes new automated tests for gaps — rather than directly opening files and verifying the conditions described in the test plan

## Expected Behavior

`executing-qa` should iterate through each test plan entry, directly verify the described condition (e.g., read a file to confirm a section exists, run a command to check behavior), and record a discrete PASS/FAIL result per entry. The test plan is the execution artifact — each entry gets verified on its own terms.

## Actual Behavior

The `qa-verifier` subagent:
1. Runs `npm test` (the project's automated test suite)
2. Uses the test plan as a checklist to audit whether automated tests cover the plan's entries
3. Reports coverage gaps back to `executing-qa`
4. `executing-qa` writes missing automated tests to fill gaps, then re-runs

Test plan entries are never directly verified. The entire loop operates through the indirection of automated test coverage.

## Root Cause(s)

1. The `qa-verifier` agent (`plugins/lwndev-sdlc/agents/qa-verifier.md`) is architected as a test runner and coverage auditor. Its Step 1 is "Run `npm test`" (line 29), Step 2 is "Analyze Test Coverage" for new/modified files (line 37), Step 3 maps acceptance criteria to test coverage (line 43), and Step 4 assesses test quality (line 62). Every step is oriented around automated test existence, not direct condition verification.

2. The `executing-qa` skill (`plugins/lwndev-sdlc/skills/executing-qa/SKILL.md`) delegates verification entirely to the qa-verifier subagent (lines 72-75), inheriting the coverage-audit approach. The skill never instructs direct verification of test plan entries — it only evaluates the qa-verifier's coverage verdict.

3. The auto-fix instructions in the `executing-qa` skill (lines 81-85) compound the problem by defining fixes as developer activities: "Write missing tests for uncovered code paths", "Fix broken or failing tests", "Address coverage gaps". These instructions make the skill a test-writing loop rather than a QA execution loop.

## Affected Files

- `plugins/lwndev-sdlc/agents/qa-verifier.md`
- `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md`
- `plugins/lwndev-sdlc/skills/executing-qa/assets/test-results-template.md`
- `scripts/__tests__/qa-verifier.test.ts`
- `scripts/__tests__/executing-qa.test.ts`

## Acceptance Criteria

- [x] The `executing-qa` skill iterates through each entry in the test plan and directly verifies the condition described (RC-2, RC-3)
- [x] Each test plan entry gets a discrete PASS/FAIL result based on direct verification — reading files, checking behavior, running commands — not based on whether an automated test exists (RC-1, RC-2)
- [x] The qa-verifier agent (or replacement mechanism) acts as a direct verification engine that checks conditions rather than running `npm test` and auditing coverage (RC-1)
- [x] QA results document (`qa/test-results/QA-results-{id}.md`) records per-entry PASS/FAIL outcomes from direct verification (RC-2, RC-3)
- [x] Running `npm test` may still occur as one input to verification, but is not the primary verification mechanism (RC-1)

## Completion

**Status:** `Completed`

**Completed:** 2026-03-28

**Pull Request:** [#79](https://github.com/lwndev/lwndev-marketplace/pull/79)

## Deviation Summary

Test files `scripts/__tests__/qa-verifier.test.ts` and `scripts/__tests__/executing-qa.test.ts` were updated to validate the new direct-verification behavior. Five assertions that tested the old coverage-audit patterns were replaced with assertions for the new patterns. These files were not listed in the original affected files since the bug document focused on the skill/agent definitions, but updating them was a natural consequence of the behavioral change.

## Notes

- The three root causes form a reinforcing chain: the agent is a coverage auditor (RC-1), the skill delegates to it without adding direct verification (RC-2), and the fix loop doubles down by writing tests instead of verifying conditions (RC-3).
- `npm test` may still be useful as one verification input (e.g., confirming existing tests pass), but should not be the primary mechanism for executing a test plan.
- The `documenting-qa` skill and test plan format are not affected — the issue is purely in how the plan is executed.
