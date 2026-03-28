# QA Results: [Brief Title]

## Metadata

| Field | Value |
|-------|-------|
| **Results ID** | QA-results-{id} |
| **Requirement Type** | FEAT / CHORE / BUG |
| **Requirement ID** | {ID} |
| **Source Test Plan** | `qa/test-plans/QA-plan-{id}.md` |
| **Date** | YYYY-MM-DD |
| **Verdict** | PASS / FAIL |
| **Verification Iterations** | N |

## Per-Entry Verification Results

Direct verification of each test plan entry, mirroring the test plan's NTA structure:

| # | Test Description | Target File(s) | Requirement Ref | Result | Notes |
|---|-----------------|----------------|-----------------|--------|-------|
| <!-- 1 --> | <!-- mirrors NTA entry --> | <!-- file(s) under test --> | <!-- FR-N / RC-N / AC --> | <!-- PASS / FAIL / SKIP --> | <!-- evidence or reason --> |

### Summary

- **Total entries:** N
- **Passed:** N
- **Failed:** N
- **Skipped:** N

## Test Suite Results (if run)

<!-- Optional: automated test results as a secondary verification input. Remove section if not run. -->

| Metric | Count |
|--------|-------|
| **Total Tests** | N |
| **Passed** | N |
| **Failed** | N |
| **Errors** | N |

### Failed Tests

<!-- List any tests that failed. Remove section if all passed. -->

| Test | Failure Reason | Resolution |
|------|---------------|------------|
| <!-- test name --> | <!-- why it failed --> | <!-- how it was fixed --> |

## Issues Found and Fixed

<!-- Entries that initially failed and were fixed during verification iterations -->

| Entry # | Issue | Resolution | Iteration Fixed |
|---------|-------|-----------|-----------------|
| <!-- entry number --> | <!-- what failed --> | <!-- what was done --> | <!-- iteration N --> |

## Reconciliation Summary

### Changes Made to Requirements Documents

<!-- List each change made during reconciliation -->

| Document | Section | Change |
|----------|---------|--------|
| <!-- path/to/doc.md --> | <!-- section name --> | <!-- what was updated --> |

### Affected Files Updates

<!-- Changes to affected files lists in requirements docs -->

| Document | Files Added | Files Removed |
|----------|------------|---------------|
| <!-- path/to/doc.md --> | <!-- new files --> | <!-- removed files --> |

### Acceptance Criteria Modifications

<!-- Any ACs that were modified, added, or descoped -->

| AC | Original | Updated | Reason |
|----|----------|---------|--------|
| <!-- AC text --> | <!-- original state --> | <!-- new state --> | <!-- why changed --> |

## Deviation Notes

<!-- Summary of where implementation diverged from the plan. Remove section if no deviations. -->

| Area | Planned | Actual | Rationale |
|------|---------|--------|-----------|
| <!-- what diverged --> | <!-- what was planned --> | <!-- what was done --> | <!-- why --> |
