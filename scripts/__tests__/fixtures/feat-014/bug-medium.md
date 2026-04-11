# Bug: Medium-Complexity Fixture (FEAT-014 Phase 2)

## Bug ID

`BUG-902`

## Category

`logic-error`

## Severity

`medium`

## Description

Synthetic medium-complexity bug fixture. Severity `medium`, two root causes, logic-error category → no bump. Classifier should return `medium`.

## Steps to Reproduce

1. Reproduce the first failure mode
2. Reproduce the second failure mode

## Root Cause(s)

1. First distinct defect in module A.
2. Second distinct defect in module B that interacts with the first.

## Affected Files

- `src/a.ts`
- `src/b.ts`

## Acceptance Criteria

- [ ] Module A no longer emits the wrong value (RC-1)
- [ ] Module B handles the interaction with A (RC-2)
- [ ] Regression tests cover both RCs
