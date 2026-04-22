---
id: BUG-012
version: 2
timestamp: 2026-04-22T21:19:00Z
verdict: PASS
persona: qa
---

## Summary

All five P0/P1 test-framework scenarios from `qa/test-plans/QA-plan-BUG-012.md` passed against the `fix/BUG-012-vitest-rce-qa-fixture` branch. The fixture `vitest` devDep is pinned to `^3.2.3` (from `"*"`); capability-discovery still detects the fixture as `vitest`, the declared range excludes every advisory vulnerable window, and the full suite (1328 tests) is green.

## Capability Report

- Mode: test-framework
- Framework: vitest
- Package manager: npm
- Test command: npm test
- Language: typescript

## Execution Results

- Total: 5
- Passed: 5
- Failed: 0
- Errored: 0
- Exit code: 0
- Duration: 0.362s
- Test files: [scripts/__tests__/qa-inputs-BUG-012.test.ts, scripts/__tests__/qa-dependency-failure-BUG-012.test.ts]

Scoped command: `npx vitest run scripts/__tests__/qa-inputs-BUG-012.test.ts scripts/__tests__/qa-dependency-failure-BUG-012.test.ts`.

Full-suite control run: `npm test` → `Test Files 39 passed (39), Tests 1328 passed (1328), Duration 44.21s`. No regressions elsewhere in the suite from the QA test additions.

## Scenarios Run

| ID | Dimension | Priority | Result | Test file |
|----|-----------|----------|--------|-----------|
| INP-1 | Inputs | P0 | PASS | scripts/__tests__/qa-inputs-BUG-012.test.ts (capability-discovery resolves the updated fixture as framework "vitest") |
| INP-2 | Inputs | P1 | PASS | scripts/__tests__/qa-inputs-BUG-012.test.ts (wildcard regression guard — no bare "*" vitest range) |
| INP-3 | Inputs | P1 | PASS | scripts/__tests__/qa-inputs-BUG-012.test.ts (declared range does not intersect any advisory vulnerable window) |
| DEP-1 | Dependency failure | P0 | PASS | scripts/__tests__/qa-dependency-failure-BUG-012.test.ts (qa-integration prerequisites hold — file, root vitest bin, fixture detection) |
| DEP-2 | Dependency failure | P1 | PASS | scripts/__tests__/qa-dependency-failure-BUG-012.test.ts (declared range accepts future vitest 3.x releases and excludes every vulnerable window) |

Exploratory/P2 scenarios from the plan not exercised in test-framework mode (intentional — the plan marked them `mode: exploratory`): INP malformed-package-json probe, idempotency rerun, fresh-clone install, offline install rerun, Dependabot re-scan, transitive-`vite` advisory scan, fixture/root lock-step drift guardrail, reviewer-affordance inline comment. These remain exploratory per plan and are not graded in this run.

## Findings

No failing tests. No verdict-blocking findings.

Observational notes (not failures):
- **INP-1 / DEP-1 semantic overlap**: both scenarios exercise the same `capability-discovery.sh` invocation against the real fixture. This was a deliberate design choice to avoid spawning a nested vitest-in-vitest subprocess for the end-to-end DEP-1 check; the static prerequisites (integration test file, root vitest bin, imports) plus the dynamic capability-discovery call together are the load-bearing signal that `qa-integration.test.ts` would still pass. The full-suite run above independently confirms that by actually running `qa-integration.test.ts` to completion.
- **DEP-2 future-version assertion**: the semver-intersect check is an invariant probe, not a runtime probe. It guards against a future edit that tightens the range into a vulnerable window (e.g., re-introducing `<=0.0.125` via a botched pin). If vitest ships a new advisory later, this test will not catch it — a Dependabot rescan would. That limitation is captured in the plan's Dependency-failure P2 exploratory item and is not in scope for this run.

## Reconciliation Delta

### Coverage beyond requirements
- Scenario DEP-2 (future-version semver invariant: `^3.2.3` accepts `3.2.3 / 3.2.99 / 3.3.0 / 3.99.0` AND excludes every vulnerable window) is not a literal acceptance-criterion in BUG-012 — the ACs only require a non-vulnerable pin today. DEP-2 is adversarial reinforcement against a future narrow-range regression.
- Scenario INP-2 (wildcard regression guard) likewise goes beyond the literal AC-1 language — AC-1 requires pinning; INP-2 additionally locks out the `"*"` form from ever reappearing via a static source-level assertion.

### Coverage gaps
- AC-3 ("Dependabot alert #22 auto-closes on the resulting merge, or is manually dismissable as resolved") has no executable test in this run. Dependabot alert state is an external-to-repo event that only resolves post-merge during Dependabot's next scan. The plan explicitly marked this as `mode: exploratory` (Environment P2) and it is correctly deferred. It should be manually verified post-merge by checking `gh api repos/lwndev/lwndev-marketplace/dependabot/alerts/22` for `state: fixed`.
- The plan's P1 exploratory scenarios (fresh-clone install, offline rerun after `npm ci`) are not exercised — they are environmental probes that require reshaping the working tree, outside the scope of a test-framework QA run. No new coverage gap against BUG-012 requirements; they are adversarial rigor beyond the ACs.

### Summary
- coverage-surplus: 2
- coverage-gap: 1

## Exploratory Mode

Not applicable — this run was test-framework mode.
