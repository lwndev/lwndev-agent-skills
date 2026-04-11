# Bug: Max(severity, RC count) Fixture

## Bug ID

`BUG-906`

## Category

`logic-error`

## Severity

`low`

## Description

Synthetic fixture exercising `max(severity, RC count)`. Severity is `low`, but four distinct root causes push RC bucket to `high`. `max(low, high) = high`. Category is logic-error so no bump. Classifier should return `high`.

## Root Cause(s)

1. First independent defect.
2. Second independent defect.
3. Third independent defect.
4. Fourth independent defect.

## Acceptance Criteria

- [ ] Each defect is independently fixed (RC-1, RC-2, RC-3, RC-4)
