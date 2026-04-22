---
id: BUG-012
version: 2
timestamp: 2026-04-22T21:03:00Z
persona: qa
---

## User Summary

Resolve Dependabot alert #22 (critical vitest RCE; CVE-2025-24964 / GHSA-9crc-q9x8-hgqq, CVSS 9.7) by pinning the QA integration test fixture's `vitest` devDependency to a non-vulnerable range. The fixture's `"vitest": "*"` declaration in `scripts/__tests__/fixtures/qa-fixture/package.json` currently matches the vulnerable `<= 0.0.125` window even though no vitest is ever actually installed inside the fixture (no local `node_modules`) and the integration test invokes the root-level `vitest@^3.2.3` binary explicitly. The fix changes the fixture's declared range to `^3.2.3` to mirror the root `package.json`, keeping the devDep present as the primary `pkg_has_dep` detection signal for `capability-discovery.sh`. The integration test continues to pass, and the Dependabot alert auto-closes once the vulnerable range no longer matches.

## Capability Report

- Mode: test-framework
- Framework: vitest
- Package manager: npm
- Test command: npm test
- Language: typescript

## Scenarios (by dimension)

### Inputs
- [P0] `capability-discovery.sh` on the updated fixture still resolves `framework: "vitest"` via the `pkg_has_dep "vitest"` path (primary detection signal must keep working after the pin) | mode: test-framework | expected: integration test asserts `report.framework === "vitest"` against the updated fixture
- [P1] Wildcard regression guard: a grep of `scripts/__tests__/fixtures/qa-fixture/package.json` for a bare `"*"` range on `vitest` returns no match | mode: test-framework | expected: lint-style assertion — `grep '"vitest":\s*"\*"'` in the fixture exits non-zero
- [P1] Declared range excludes the vulnerable windows the advisory lists (`<= 0.0.125`, `>= 1.0.0 < 1.6.1`, `>= 2.0.0 < 2.1.9`, `>= 3.0.0 < 3.0.5`) | mode: test-framework | expected: assertion that the pinned semver range, intersected with each vulnerable window via `semver.intersects(range, window)`, returns false for every window
- [P2] Malformed fixture `package.json` (deliberately trailing comma / unterminated string) does not regress — `capability-discovery.sh` exits gracefully and the integration test still produces a capability report | mode: exploratory | expected: manual test — break the fixture, rerun, confirm script does not crash the harness

### State transitions
- [P2] Idempotency: re-running the bug fix (committing an identical change to the fixture a second time) is a no-op — no churn, no additional Dependabot noise | mode: exploratory | expected: second `git diff` shows empty; Dependabot alert status unchanged

### Environment
- [P1] Integration test works from a fresh clone without a pre-existing `node_modules` inside the fixture (the fixture must still not install vitest locally; root `node_modules/.bin/vitest` remains the only install) | mode: exploratory | expected: `rm -rf node_modules && npm ci && npm test -- --testPathPatterns=qa-integration` passes
- [P1] Offline / no-network rerun of `npm test` after `npm ci`: integration test resolves root vitest binary without reaching npm registry for the fixture | mode: exploratory | expected: disable network, rerun `npm test -- --testPathPatterns=qa-integration`, confirm pass
- [P2] Dependabot re-scan on merge: alert #22 auto-closes within one scan cycle (usually < 24h) with reason "fixed" | mode: exploratory | expected: inspect `gh api repos/lwndev/lwndev-marketplace/dependabot/alerts/22` post-merge and confirm `state: fixed` or `state: dismissed`

### Dependency failure
- [P0] `npm test` at repo root still passes `qa-integration.test.ts` end-to-end (capability discovery + fixture vitest run using the root binary) with the fixture's declared range changed | mode: test-framework | expected: `npm test -- --testPathPatterns=qa-integration` exit code 0
- [P1] `^3.2.3` satisfies future patch releases of vitest 3.x (standard semver behavior) and continues to lie outside every vulnerable window declared by the advisory, even if minor bumps ship | mode: test-framework | expected: semver assertion — for each candidate future version (`3.2.3`, `3.2.99`, `3.99.0`), `semver.satisfies(candidate, "^3.2.3")` is true AND `semver.intersects("^3.2.3", vulnerable-window)` is false
- [P2] Transitive `vite` pulled by vitest has no currently-open advisories overlapping with the resolved install tree | mode: exploratory | expected: `npm audit --audit-level=high` in the fixture directory (after optional `npm install`) reports no criticals; advisory surface visible in Dependabot UI is unchanged
- [P2] Root `package.json` vitest range drifts ahead of fixture: fixture and root should stay in lock-step per Notes, but the fix does not introduce an automated enforcement mechanism | mode: exploratory | expected: follow-up guardrail candidate — manual inspection, not a failing test today

### Cross-cutting (a11y, i18n, concurrency, permissions)
- [P2] Contributor affordance: a comment or README note on the fixture's `package.json` makes it discoverable that the devDep range is a detection signal and must stay present — relevant since the bug doc cites "cleanup deletion" as a realistic future regression mode | mode: exploratory | expected: reviewer checks the fix PR for an inline rationale; absence is flagged as an info-level observation during code review

## Non-applicable dimensions

- state-transitions: This change is a one-line static config edit to a test fixture's `package.json`. There is no state machine, no user interaction flow, no cancellation path, no concurrent-write surface. A single P2 idempotency scenario is included above for completeness; every other state-transition probe (cancel mid-flow, double-click, stale tabs, concurrent modification) is meaningless for a declarative config edit.
- cross-cutting (a11y, i18n, concurrency, permissions, beyond the P2 reviewer affordance above): The fixture is consumed only by the integration test suite; it ships no UI, no user-facing text, no locale-sensitive behavior, no permission model, and no concurrent access pattern. Accessibility, internationalization, concurrency semantics, and permission-related probes are structurally inapplicable.
