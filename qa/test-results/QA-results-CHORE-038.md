---
id: CHORE-038
version: 2
timestamp: 2026-05-09T21:36:48Z
verdict: ISSUES-FOUND
persona: qa
---

## Summary

Verdict ISSUES-FOUND: passed=1601, failed=1, errored=0.

## Capability Report

```json
{
  "id": "CHORE-038",
  "timestamp": "2026-05-09T20:40:08Z",
  "mode": "test-framework",
  "framework": "vitest",
  "packageManager": "npm",
  "testCommand": "npm test",
  "language": "typescript",
  "notes": []
}
```

## Execution Results

- Total: 1602
- Passed: 1601
- Failed: 1
- Errored: 0
- Exit code: 1

## Scenarios Run

### Inputs
- [P2] Test files referencing PLUGINS_DIR for read-only path lookups remain unaffected by parallelism flip | mode: test-framework | expected: full suite passing 1601/1602 — PASS

### State transitions
- [P0] vitest.config.ts has fileParallelism: true (regression guard) | mode: test-framework | expected: regex-match against config — PASS
- [P0] No test file writes a literal path under plugins/lwndev-sdlc/skills/ as a write target | mode: test-framework | expected: zero offenders detected by writeFileSync/mkdirSync scan — PASS
- [P0] scaffold.test.ts uses mkdtemp for fixture isolation | mode: test-framework | expected: mkdtemp identifier present in source — PASS
- [P0] build.test.ts uses mkdtemp for fixture isolation | mode: test-framework | expected: mkdtemp identifier present in source — PASS
- [P1] validate-test-layout.test.ts already uses mkdtemp (W1 finding) | mode: test-framework | expected: mkdtemp identifier present in source — PASS
- [P0] argument-hint.test.ts filters _-prefixed dirs from skill counts | mode: test-framework | expected: defensive filter against build.test.ts temp-dir injection convention — FAIL (implementer chose mkdtemp isolation instead; see Findings)

### Environment
- [P1] No test file rebinds process.env wholesale (forbidden under parallel runs) | mode: test-framework | expected: zero `process.env = {...}` patterns — PASS
- [P0] AC-3 wall time and AC-5 10-run determinism | mode: exploratory | expected: ~13.45s wall (reference machine) and identical 1534/55 split across 10 runs — PASS (measured by executing-chores fork; recorded in PR description and chore-doc Completion section)

### Dependency failure
- [P1] tsx cold-start contention under parallelism | mode: test-framework | expected: full npm run test:unit completes within testTimeout 15000ms with no new timeout lines — PASS

### Cross-cutting
- [P1] CLAUDE.md no longer asserts tests run sequentially | mode: test-framework | expected: regex non-match against `Tests run sequentially` — PASS
- [P1] CLAUDE.md Key Patterns reflects new parallel + mkdtemp isolation strategy | mode: test-framework | expected: regex match for `parallel` and `mkdtemp|isolat` — PASS
- [P2] Real skills directory still exists (sanity for offender-detection grep semantics) | mode: test-framework | expected: statSync isDirectory true — PASS

## Findings

### State transitions [P0] — Discovery race-safety regression risk

The implementer chose mkdtemp isolation for tests/unit/argument-hint.test.ts (route the test fixture through a temp dir) instead of adding a defensive `_`-prefix filter to the readdir-based skill counts. Functionally equivalent today, but loses defense-in-depth: any future test that injects a `_`-prefixed dir into `plugins/lwndev-sdlc/skills/` (the convention build.test.ts established and the chore doc anticipated) would race the count assertions.

Recommendation: add a one-line `_`-prefix filter to the two readdir filters at `tests/unit/argument-hint.test.ts:31` and `tests/unit/argument-hint.test.ts:98`. Out of scope for QA report-only mode; create as a follow-up chore or fold into a future PR.

Failing test: `CHORE-038 — discovery race-safety (state transitions [P0]) > argument-hint.test.ts filters underscore-prefixed dirs from skill counts`

### Inputs — no findings
No P0/P1 input-class probes surfaced an issue. Read-only path-lookup tests remain unaffected by the parallelism flip.

### Environment — no findings
AC-3 / AC-5 measurements recorded by executing-chores fork (wall ~13.45s, 10-run identical 1534/55). `process.env` wholesale-rebind audit clean across all test files.

### Dependency failure — no findings
`tsx` cold-start contention did not surface a regression at `testTimeout: 15000`; full suite passes within budget.

### Cross-cutting — no findings beyond the discovery race-safety state-transitions item above
CLAUDE.md documentation accuracy passes; permission/path-assertion concerns from the test plan did not surface a violation in the affected test files.

## Reconciliation Delta

### Coverage beyond requirements
- Scenario "Ran 1601 passing tests, 1 failing tests, 0 errored tests." — not mentioned in spec

### Coverage gaps
- AC-1 "[x] `vitest.config.ts:14` set to `fileParallelism: true`" — no corresponding scenario in plan
- AC-2 "[x] The 3 listed test files no longer mutate the real `plugins/` tree concurrently — either rerouted to `mkdtemp` or mar" — no corresponding scenario in plan
- AC-3 "[x] `npm run test:unit` wall time on a clean checkout ≤ 20s" — no corresponding scenario in plan
- AC-4 "[x] `npm run test:unit` pass/fail count is identical to a baseline sequential run on the same commit (no new failures in" — no corresponding scenario in plan
- AC-5 "[x] 10 consecutive `npm run test:unit` runs produce identical results (no new flake)" — no corresponding scenario in plan
- AC-6 "[x] `CLAUDE.md` Key Patterns note no longer claims tests run sequentially; it accurately describes the new isolation str" — no corresponding scenario in plan

### Summary
- coverage-surplus: 1
- coverage-gap: 6

