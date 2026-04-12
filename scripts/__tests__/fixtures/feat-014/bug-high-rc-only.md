# Bug: High via RC Count + Severity (No Category Bump)

## Bug ID

`BUG-907`

## Category

`logic-error`

## Severity

`high`

## Description

Synthetic fixture exercising the `rc_tier=high` branch of the CHORE-031 T1 guard without a category bump. Severity `high` (sev_rank=3) meets the `>= medium` requirement, and 4 root causes push rc_tier to `high`, satisfying the escalation signal. Category is `logic-error` (no bump). Classifier should return `high`.

## Root Cause(s)

1. First independent defect in module A.
2. Second independent defect in module B.
3. Third independent defect in module C.
4. Fourth independent defect in module D.

## Acceptance Criteria

- [ ] Each defect is independently fixed (RC-1, RC-2, RC-3, RC-4)
