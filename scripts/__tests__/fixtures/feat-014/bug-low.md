# Bug: Low-Complexity Fixture (FEAT-014 Phase 2)

## Bug ID

`BUG-901`

## Category

`logic-error`

## Severity

`low`

## Description

Synthetic low-complexity bug fixture. Severity `low`, one root cause, plain logic-error category → no bump. Classifier should return `low`.

## Steps to Reproduce

1. Do a thing
2. Observe the unexpected output

## Root Cause(s)

1. A single pure logic typo in one helper. The fix replaces one line with a corrected expression.

## Affected Files

- `src/example.ts`

## Acceptance Criteria

- [ ] The helper returns the correct value (RC-1)
- [ ] Regression test pins the fixed behavior
