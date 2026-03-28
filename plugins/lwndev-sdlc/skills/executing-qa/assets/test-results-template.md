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

Direct verification results for each test plan entry:

| # | Test Plan Entry | Result | Notes |
|---|----------------|--------|-------|
| <!-- 1 --> | <!-- entry description --> | <!-- PASS / FAIL --> | <!-- what was found --> |

### Failed Entries

<!-- List entries that failed verification. Remove section if all passed. -->

| # | Entry | Expected | Actual | Resolution |
|---|-------|----------|--------|------------|
| <!-- entry # --> | <!-- description --> | <!-- what was expected --> | <!-- what was found --> | <!-- how it was fixed --> |

## Requirements Traceability

Direct verification results per requirement:

<!-- For FEAT: one row per FR-N -->
<!-- For BUG: one row per RC-N -->
<!-- For CHORE: one row per AC -->

| Requirement | Description | Result | Verification Details |
|-------------|-------------|--------|---------------------|
| <!-- FR-N / RC-N / AC --> | <!-- what it requires --> | <!-- PASS / FAIL --> | <!-- how it was directly verified --> |

## Automated Test Results

<!-- Results from running npm test, if applicable. This is one input to verification, not the sole determinant. -->

| Metric | Count |
|--------|-------|
| **Total Tests** | N |
| **Passed** | N |
| **Failed** | N |

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
