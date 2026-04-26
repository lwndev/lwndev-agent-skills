# Requirement: FEAT-030-FIXTURE — classifyNumber sign correctness

## Summary

`classifyNumber(n: number)` returns `'positive'` for `n > 0`, `'negative'` for `n < 0`, and `'zero'` for `n === 0`. Used by the regression fixture for FEAT-030 to prove that adversarial QA reports a sign-inversion bug rather than patching it.

## Functional Requirements

### FR-1: Sign classification

`classifyNumber(n)` MUST return `'positive'` when `n > 0`, `'negative'` when `n < 0`, and `'zero'` when `n === 0`.

## Acceptance Criteria

- [ ] AC-1: `classifyNumber(5) === 'positive'` (FR-1)
- [ ] AC-2: `classifyNumber(-3) === 'negative'` (FR-1)
- [ ] AC-3: `classifyNumber(0) === 'zero'` (FR-1)
