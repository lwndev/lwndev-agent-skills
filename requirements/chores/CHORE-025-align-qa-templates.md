# Chore: Align QA Templates with Execution Lifecycle

## Chore ID

`CHORE-025`

## GitHub Issue

[#83](https://github.com/lwndev/lwndev-marketplace/issues/83)

## Category

`refactoring`

## Description

Align the QA test plan and test results templates with the execution lifecycle. The test plan's Verification Checklist is never checked off after `documenting-qa` completes, test results lack structured per-NTA entry results, and test plan statuses go stale after `executing-qa` runs because it treats the plan as read-only.

## Affected Files

- `plugins/lwndev-sdlc/skills/documenting-qa/assets/test-plan-template.md`
- `plugins/lwndev-sdlc/skills/documenting-qa/SKILL.md`
- `plugins/lwndev-sdlc/skills/executing-qa/assets/test-results-template.md`
- `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md`
- `scripts/__tests__/documenting-qa.test.ts`
- `scripts/__tests__/executing-qa.test.ts`

## Acceptance Criteria

- [x] Test plan template's checklist is renamed to "Plan Completeness Checklist"
- [x] `documenting-qa` checks off plan completeness items as it builds the plan
- [x] Test plan template NTA, CPV, and Deliverable tables include a `Status` column (default `--`)
- [x] Test results template `Per-Entry Verification Results` section is restructured with NTA-mirrored columns (Result and Notes)
- [x] Deliverable Verification table `Exists` column is replaced by `Status` (default `--`, updated to PASS/FAIL/SKIP during execution)
- [x] `executing-qa` updates Existing Test `Status`, and NTA/CPV/Deliverable `Status` columns during verification (PASS/FAIL/SKIP)
- [x] Existing tests updated to reflect template changes
- [x] All tests pass after changes

## Completion

**Status:** `Completed`

**Completed:** 2026-03-28

**Pull Request:** [#84](https://github.com/lwndev/lwndev-marketplace/pull/84)

## Notes

- Observed during FEAT-007 QA execution: the qa-verifier produced detailed 23-entry NTA verification results, but the test plan's Verification Checklist remained unchecked, Deliverable rows stayed `PENDING`, and the test results template had no structured table for per-NTA results
- Four discrete changes (A-D) as described in the issue; all are template/instruction changes with no runtime code modifications
- The test plan becomes a living document updated during both authoring and execution phases
