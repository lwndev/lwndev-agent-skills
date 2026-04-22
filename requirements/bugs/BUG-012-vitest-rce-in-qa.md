# Bug: vitest RCE in QA Fixture

## Bug ID

`BUG-012`

## GitHub Issue

[#216](https://github.com/lwndev/lwndev-marketplace/issues/216)

## Category

`security`

## Severity

`critical`

## Description

Dependabot alert #22 flags a critical vitest vulnerability (CVSS 9.7, CVE-2025-24964 / GHSA-9crc-q9x8-hgqq) sourced from the QA integration test fixture. The fixture's `package.json` declares `"vitest": "*"`, which satisfies the vulnerable range `<= 0.0.125` and causes the repository to appear exposed to Cross-Site WebSocket Hijacking leading to arbitrary code execution when the Vitest UI/API is running.

## Steps to Reproduce

1. Visit the repository's Dependabot alerts page (`/security/dependabot/22`).
2. Observe the open alert for `vitest` originating from `scripts/__tests__/fixtures/qa-fixture/package.json`.
3. Inspect `scripts/__tests__/fixtures/qa-fixture/package.json` and note `"vitest": "*"`.

## Expected Behavior

- The fixture's `vitest` devDependency declares a non-vulnerable range.
- Dependabot alert #22 auto-closes (or can be dismissed as resolved).
- `scripts/__tests__/qa-integration.test.ts` continues to pass.

## Actual Behavior

- The unbounded `*` range matches the vulnerable `<= 0.0.125` window (along with several other vulnerable ranges).
- Dependabot flags the repository as critical severity even though no version of vitest is installed inside the fixture and the integration test invokes the root-level `node_modules/.bin/vitest@^3.2.3` binary explicitly.

## Root Cause(s)

1. `scripts/__tests__/fixtures/qa-fixture/package.json:8` declares `"vitest": "*"`. The fixture is shipped only to exercise `capability-discovery.sh`'s framework-detection path (`plugins/lwndev-sdlc/skills/executing-qa/scripts/capability-discovery.sh:101` checks `pkg_has_dep "vitest"`; line 102 additionally accepts `vitest.config.ts` / `.js` / `.mjs` as a secondary signal, and the fixture ships `vitest.config.ts`), so the declared range is intentionally kept as a package-json detection signal — not a resolvable install target — but the wildcard still satisfies the vulnerable ranges Dependabot matches against.

## Affected Files

- `scripts/__tests__/fixtures/qa-fixture/package.json`

## Acceptance Criteria

- [x] Fixture `vitest` devDependency remains declared in `scripts/__tests__/fixtures/qa-fixture/package.json` and is pinned to a non-vulnerable range matching the advisory's safe windows (`>=1.6.1 <2.0.0 || >=2.1.9 <3.0.0 || >=3.0.5`) — preferably `^3.2.3` to mirror the root `package.json`. The devDep is not deleted; it must stay present as the primary `pkg_has_dep`-based detection signal, even though `vitest.config.ts` would redundantly satisfy detection (RC-1)
- [x] `scripts/__tests__/qa-integration.test.ts` continues to pass — `capability-discovery` still resolves the fixture as framework `vitest`, and the end-to-end flow still produces the expected non-zero-exit failure report (RC-1)
- [x] Dependabot alert #22 auto-closes on the resulting merge, or is manually dismissable as resolved because the declared range no longer matches any vulnerable window (RC-1)

## Completion

**Status:** `Completed`

**Completed:** 2026-04-22

**Pull Request:** [#218](https://github.com/lwndev/lwndev-marketplace/pull/218)

## Notes

- Exposure in this repository is low: the fixture has no `node_modules` of its own, and `scripts/__tests__/qa-integration.test.ts:49` explicitly invokes `<repo>/node_modules/.bin/vitest` (root `vitest@^3.2.3`, already patched). The declared range is a detection signal for `capability-discovery.sh`, not an install target.
- No production / plugin consumer code depends on vitest; the fixture is consumed only by the integration suite and is not shipped with any published plugin.
- Root `package.json` already pins `vitest@^3.2.3` — aligning the fixture with the same range keeps future version bumps in lock-step.
