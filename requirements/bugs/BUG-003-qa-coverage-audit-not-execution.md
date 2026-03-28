# Bug: QA Executes Coverage Audit Instead of Test Plan

## Bug ID

`BUG-003`

## GitHub Issue

[#74](https://github.com/lwndev/lwndev-marketplace/issues/74)

## Category

`logic-error`

## Severity

`high`

## Description

The `executing-qa` skill does not execute the test plan produced by `documenting-qa`. Instead of directly verifying each test plan entry (reading files, checking conditions, running commands), it delegates to the `qa-verifier` subagent which runs `npm test` and audits whether automated test coverage is sufficient — a developer activity, not a QA activity.

## Steps to Reproduce

1. Document a requirement (e.g., `FEAT-XXX` or `CHORE-XXX`)
2. Run `documenting-qa` to produce a test plan with entries like "SKILL.md contains PR creation step/section"
3. Run `executing-qa` against the requirement ID
4. Observe that the qa-verifier runs `npm test` and checks for automated test coverage instead of directly verifying the test plan entries

## Expected Behavior

The `executing-qa` skill should iterate through each entry in the test plan and directly verify the condition described. For example, a test plan entry "SKILL.md contains PR creation step/section" should be verified by opening the file and confirming the step exists, then marking the entry PASS or FAIL. The test plan itself is the execution artifact.

## Actual Behavior

The `qa-verifier` subagent:
1. Runs `npm test` (the project's automated test suite)
2. Uses the test plan as a checklist to audit whether automated tests cover the plan's entries
3. Reports coverage gaps back to `executing-qa`
4. `executing-qa` writes missing automated tests to fill gaps, then re-runs

Test plan entries are never directly verified — they are used as a guide for what automated tests should exist, adding an unnecessary layer of indirection between the test plan and verification.

## Root Cause(s)

1. The `qa-verifier` agent (`plugins/lwndev-sdlc/agents/qa-verifier.md`) is designed as a test runner and coverage auditor, not a direct test plan executor. Its Step 1 is "Run `npm test`" (lines 29-32), its responsibilities center on running the test suite (#1, line 20), identifying test coverage gaps (#3, line 22), and verifying code paths via test traceability (#4, line 23). It has no mechanism to directly verify test plan entries by reading files or checking conditions.

2. The `executing-qa` skill (`plugins/lwndev-sdlc/skills/executing-qa/SKILL.md`) delegates all verification to the qa-verifier subagent (Step 2, lines 72-75) and instructs it to "run the full test suite, check coverage, and verify code paths against acceptance criteria." The auto-fix loop (lines 82-85) compounds this by writing missing automated tests and fixing broken tests — developer activities that should not be part of QA execution.

3. The Stop hook in `executing-qa` (line 16) gates completion on whether "the qa-verifier returned a clean pass verdict with no remaining issues," tying the QA pass/fail determination to the coverage-audit verdict rather than to direct test plan execution results.

## Affected Files

- `plugins/lwndev-sdlc/agents/qa-verifier.md`
- `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md`
- `plugins/lwndev-sdlc/skills/executing-qa/assets/test-results-template.md`

## Acceptance Criteria

- [x] The `executing-qa` skill iterates through each entry in the test plan and directly verifies the condition described (RC-1, RC-2)
- [x] Each test plan entry receives a discrete PASS/FAIL result based on direct verification (reading files, checking behavior, running commands), not based on whether an automated test exists (RC-1)
- [x] The qa-verifier agent (or a replacement mechanism) acts as the verification engine that directly checks conditions rather than running `npm test` and auditing coverage (RC-1)
- [x] The auto-fix loop in `executing-qa` addresses direct verification failures (e.g., missing file content, unmet conditions) instead of writing automated tests (RC-2)
- [x] The Stop hook evaluates completion based on direct test plan execution results, not coverage-audit verdicts (RC-3)
- [x] QA results document (`qa/test-results/QA-results-{id}.md`) records per-entry PASS/FAIL outcomes from direct verification (RC-1, RC-2)
- [x] Running `npm test` may still occur as one input to verification, but is not the primary verification mechanism (RC-1)

## Completion

**Status:** `Completed`

**Completed:** 2026-03-28

**Pull Request:** [#N](https://github.com/lwndev/lwndev-marketplace/pull/N)

## Notes

- The `documenting-qa` skill produces test plans with entries that describe verifiable conditions (e.g., "file X contains section Y"). These entries are designed to be directly checkable, not to serve as a spec for what automated tests should exist.
- The reconciliation loop in Step 3 of `executing-qa` is unaffected by this bug and should be preserved as-is.
- Related: BUG-002 addressed the qa-verifier being overloaded (service capacity), while this bug addresses its fundamental behavioral design.
