# Bug: Max(severity, RC count) Fixture

## Bug ID

`BUG-906`

## Category

`logic-error`

## Severity

`low`

## Description

Synthetic fixture exercising `max(severity, RC count)`. Severity is `low`, four distinct root causes push RC bucket to `high`. Under CHORE-031 T1, severity must be ≥ medium for the result to reach `high` — since severity is `low`, the result is capped at `medium` despite 4 RCs.

## Root Cause(s)

1. First independent defect.
2. Second independent defect.
3. Third independent defect.
4. Fourth independent defect.

## Acceptance Criteria

- [ ] Each defect is independently fixed (RC-1, RC-2, RC-3, RC-4)
