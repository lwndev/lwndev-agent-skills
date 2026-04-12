# Bug: Critical Severity Fixture

## Bug ID

`BUG-904`

## Category

`logic-error`

## Severity

`critical`

## Description

Synthetic bug fixture exercising the `critical` severity alias (maps to `high` sev_tier). One root cause keeps RC-count at `low`, and category is `logic-error` (no bump). Under CHORE-031 T1, severity alone cannot promote to `high` — capped at `medium`.

## Root Cause(s)

1. Production outage triggered by an off-by-one in the retry backoff loop.

## Acceptance Criteria

- [ ] Retry loop backs off correctly (RC-1)
