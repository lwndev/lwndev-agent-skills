# Bug: Performance Category Bump Fixture

## Bug ID

`BUG-905`

## Category

`performance`

## Severity

`low`

## Description

Synthetic fixture exercising the `performance` category bump. Base tier from severity `low` + 1 RC → `low`, bumped one tier by performance category → `medium`. Classifier should return `medium`.

## Root Cause(s)

1. Memoization cache re-hydrates on every render because the key function allocates a fresh object.

## Acceptance Criteria

- [ ] Cache key is stable across renders (RC-1)
