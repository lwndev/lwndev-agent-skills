# QA Results: Tighten Bug Classifier and Skip Unnecessary Fork Steps

## Metadata

| Field | Value |
|-------|-------|
| **Results ID** | QA-results-CHORE-031 |
| **Requirement Type** | CHORE |
| **Requirement ID** | CHORE-031 |
| **Source Test Plan** | `qa/test-plans/QA-plan-CHORE-031.md` |
| **Date** | 2026-04-12 |
| **Verdict** | PASS |
| **Verification Iterations** | 2 |

## Per-Entry Verification Results

Direct verification of each test plan entry:

| # | Test Description | Target File(s) | Requirement Ref | Result | Notes |
|---|-----------------|----------------|-----------------|--------|-------|
| 1 | Bug classifier suite — 7 tests | `workflow-state.test.ts` | AC-1 | PASS | 7 `it()` entries in describe block confirmed |
| 2 | `${CLAUDE_SKILL_DIR}` ref count = 66 | `orchestrating-workflows.test.ts:70` | AC-3, AC-4 | PASS | `toBe(66)` confirmed |
| 3 | Chore chain lifecycle 9-step | `orchestrating-workflows.test.ts` | AC-3, AC-4 | PASS | Full 9-step advance confirmed |
| 4 | Bug chain lifecycle 9-step | `orchestrating-workflows.test.ts` | AC-3, AC-4 | PASS | Full 9-step advance confirmed |
| 5 | FEAT-014 adaptive model selection A, B, C | `orchestrating-workflows.test.ts` | AC-5 | PASS | All 3 examples present |
| 6 | Feature init classifier — 6 tests | `workflow-state.test.ts` | AC-5 | PASS | 6 tests confirmed (plan corrected from 5) |
| 7 | Chore classifier — 6 tests | `workflow-state.test.ts` | AC-5 | PASS | 6 tests confirmed (plan corrected from 5) |
| 8 | Critical severity caps at medium | `workflow-state.test.ts` + `bug-critical-severity.md` | AC-1 | PASS | Test at line 1116, asserts `medium` |
| 9 | RC count 4 alone caps at medium | `workflow-state.test.ts` + `bug-max-severity-rc.md` | AC-1 | PASS | Test at line 1128, asserts `medium` |
| 10 | High severity + 4 RCs + logic-error → high | `workflow-state.test.ts` + `bug-high-rc-only.md` | AC-1, AC-2 | PASS | Test at line 1135, asserts `high` |
| 11 | High severity + 3 RCs + security → high | `workflow-state.test.ts` + `bug-high.md` | AC-5 | PASS | Test at line 1111, asserts `high` (unchanged) |
| 12 | Ref count assertion = 66 | `orchestrating-workflows.test.ts:70` | AC-3, AC-4 | PASS | Matches 66 SKILL.md references |
| 13 | AC-1: T1 guard at workflow-state.sh:531-540 | `workflow-state.sh` | AC-1 | PASS | Guard logic verified by code inspection |
| 14 | AC-2: BUG-009-equivalent → medium | `workflow-state.sh` | AC-2 | PASS | Logic trace: sev=high, 1 RC, no cat bump → capped to medium |
| 15 | AC-3: Step 2 skip on low complexity | `SKILL.md:637-641, 688-692` | AC-3 | PASS | Skip condition + advance call confirmed in both chains |
| 16 | AC-4: Step 4 skip on low complexity | `SKILL.md:643-647, 694-698` | AC-4 | PASS | Skip condition + advance call confirmed in both chains |
| 17 | AC-5: Feature chain unchanged | `SKILL.md:198-211, 607-632` | AC-5 | PASS | No CHORE-031 annotations in feature chain sections |
| 18-30 | Deliverable verification (13 items) | Various | All ACs | PASS | All deliverables present at expected paths |

### Summary

- **Total entries:** 30
- **Passed:** 30
- **Failed:** 0
- **Skipped:** 0

## Test Suite Results

| Metric | Count |
|--------|-------|
| **Total Tests** | 702 |
| **Passed** | 702 |
| **Failed** | 0 |
| **Errors** | 0 |

## Issues Found and Fixed

| Entry # | Issue | Resolution | Iteration Fixed |
|---------|-------|-----------|-----------------|
| 6 | Test plan stated feature init classifier has 5 tests; actually has 6 | Corrected test plan count to 6 | 2 |
| 7 | Test plan stated chore classifier has 5 tests; actually has 6 | Corrected test plan count to 6 | 2 |

## Reconciliation Summary

### Changes Made to Requirements Documents

| Document | Section | Change |
|----------|---------|--------|
| `requirements/chores/CHORE-031-tighten-classifier-skip-steps.md` | Description | Removed stale "no cross-reference mapping sections" clause — T6 now gates solely on `complexity == low` per code review fix |

### Affected Files Updates

| Document | Files Added | Files Removed |
|----------|------------|---------------|
| `requirements/chores/CHORE-031-tighten-classifier-skip-steps.md` | None (test files, fixtures, and vitest.config.ts are supporting changes, not core affected files) | None |

### Acceptance Criteria Modifications

| AC | Original | Updated | Reason |
|----|----------|---------|--------|
| AC-4 | "Test-plan reconciliation fork is skipped when the plan has no cross-reference mapping sections or `complexity == low`" | "Test-plan reconciliation fork is skipped when `complexity == low`" | Code review found the grep regex `^##+ .*[Mm]apping` matched nothing in any QA plan; condition simplified to complexity-only gate |

## Deviation Notes

| Area | Planned | Actual | Rationale |
|------|---------|--------|-----------|
| T6 skip condition | Gate on `complexity == low` OR no mapping sections in QA plan | Gate on `complexity == low` only | Code review identified that the grep regex for mapping sections matched zero headings in the QA template — the condition was always true, silently disabling step 4 for all complexity levels. Simplified to complexity-only gate. |
| Vitest config | Not planned | Added `.claude/worktrees/**` to vitest exclude | Stale worktree copies were being picked up by vitest glob, causing spurious test failures |
