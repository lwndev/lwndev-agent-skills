# Bug: Critical Severity Fixture

## Bug ID

`BUG-904`

## Category

`logic-error`

## Severity

`critical`

## Description

Synthetic bug fixture exercising the `critical` severity alias (maps to `high`). One root cause keeps RC-count at `low`, but severity wins the `max`. Classifier should return `high`.

## Root Cause(s)

1. Production outage triggered by an off-by-one in the retry backoff loop.

## Acceptance Criteria

- [ ] Retry loop backs off correctly (RC-1)
