# Bug: High-Complexity Fixture (FEAT-014 Phase 2)

## Bug ID

`BUG-903`

## Category

`security`

## Severity

`high`

## Description

Synthetic high-complexity bug fixture. Severity `high`, three root causes, security category → bump one tier. Base tier is already `high`, bump to `high` (ceiling). Classifier should return `high`.

## Steps to Reproduce

1. Trigger the authentication path
2. Observe the session replay vulnerability

## Root Cause(s)

1. First root cause: session token not rotated on refresh.
2. Second root cause: CSRF token validation missing on PUT handlers.
3. Third root cause: cookie `SameSite` default is `None` in dev builds.

## Affected Files

- `src/auth/session.ts`
- `src/auth/csrf.ts`
- `src/cookies/defaults.ts`

## Acceptance Criteria

- [ ] Session tokens rotate on every refresh (RC-1)
- [ ] PUT handlers validate CSRF token (RC-2)
- [ ] Cookies default to `SameSite=Lax` outside dev (RC-3)
