---
id: BUG-023
version: 2
timestamp: 2026-06-01T01:44:23Z
verdict: PASS
persona: qa
---

## Summary

PASS — 12/12 adversarial scenarios passed. The initial-run-PASS adoption fix routes git-visible un-adopted `qa-*` files (initial PASS, `qaFixAttempts=0`) through adopt-phase before finalize, consistently across `qa-dispatch.sh`, `detect-phase.sh`, and the FR-9 `git ls-files` gate, without widening the canonical three-glob set (Edge Case 17 preserved) and without disabling the orphan safety-net.

## Capability Report

```json
{
  "id": "BUG-023",
  "timestamp": "2026-06-01T01:24:53Z",
  "mode": "test-framework",
  "framework": "vitest",
  "packageManager": "npm",
  "testCommand": "npm test",
  "language": "typescript",
  "notes": []
}
```

## Execution Results

- Total: 12
- Passed: 12
- Failed: 0
- Errored: 0
- Exit code: 0

## Scenarios Run

All scenarios drove the REAL `qa-dispatch.sh`, `detect-phase.sh`, and the FR-9 `git ls-files` glob oracle against per-test temporary git repositories (12 tests, all passed). The recurring oracle is the BUG-023 invariant: the adopt trigger, the detect route, and the FR-9 gate set must agree on every file.

### Inputs
- [P0] Canonical tracked `tests/unit/qa-*.test.ts` (mode: test-framework): FR-9 glob flags it AND `qa-dispatch=adopt-phase` AND `detect-phase=adopt`. Three-way agreement.
- [P0] Canonical tracked `tests/bats/qa/qa-*.bats` (mode: test-framework): same three-way agreement on the Bats canonical path.
- [P0] No `qa-*` files present (mode: test-framework): FR-9 clears AND `dispatch=advance` AND `phase=unknown`.
- [P0] pytest `qa-*.py` + go-test `qa-*.go` committed (mode: test-framework): Edge Case 17 — these extensions stay ABSENT from the glob set, so FR-9 ignores them AND `dispatch=advance` AND `phase=unknown` (the fix did not widen the globs).

### State transitions
- [P1] Untracked `qa-*` file (mode: test-framework): `git ls-files` is tracked-only, so the trigger and the gate are consistently blind -> `advance` (no deadlock).
- [P0] `adoptedTests` non-empty with a stray git-visible `qa-*` file (mode: test-framework): loop terminates — `dispatch=advance`, `phase=unknown` (no re-adopt loop).
- [P0] Post-fix PASS, `qaFixAttempts>0`, `adoptedTests` empty, no `qa-*` files (mode: test-framework): pre-existing path unchanged — still routes to adopt (regression guard).

### Environment
- [P1] `qa-*` in a non-canonical subdir `tests/unit/sub/` (mode: test-framework): git pathspec `*` does not cross `/`, so the single-level glob excludes it -> `advance` (consistent with FR-9).
- [P1] Permanent infra `tests/bats/skills/<skill>/qa-*.bats` (mode: test-framework): only `tests/bats/qa/` is canonical-ephemeral; skill-infra Bats stays clear of the gate -> `advance`.

### Dependency failure
- [P1] Mixed canonical set, unit + bats/qa committed together (mode: test-framework): both files flagged by FR-9; a single `adopt-phase` route covers them (no partial-route).
- [P0] Genuine orphan from an abandoned workflow / other ID (mode: test-framework): the downstream FR-9 finalize gate still flags it (safety-net not blanket-disabled), and dispatch routes it to adopt so it is cleaned up rather than deadlocking finalize.

### Cross-cutting
- [P2] Adopted `*.qa.*` sibling with `adoptedTests` empty (mode: test-framework): prefix-vs-infix — the `qa-*` PREFIX glob does not match the `foo.qa.test.ts` INFIX sibling, so no spurious re-adopt -> `advance` (idempotency / re-run safety).

## Findings

No defects found. Verdict PASS. The 12 adversarial scenarios confirm the BUG-023 fix upholds the core deadlock-prevention invariant and does not widen the FR-9 glob set.

Informational notes (do not change the PASS verdict):

- **[info] Harness — `run-framework.sh` reports `exitCode: 1` for this repo's compound `testCommand`.** `capability-discovery.sh` returns `testCommand: npm test`, which is `vitest run && bats`. `run-framework.sh` appends the supplied vitest glob as a positional arg; npm forwards it to the trailing `bats` invocation, which errors on a `.test.ts` path. The vitest half passes (1682/1682). Standalone full suites both pass with exit 0: `npx vitest run` (1682, exit 0) and `npx bats -r tests/bats` (1543, exit 0). The QA file in isolation: `npx vitest run tests/unit/qa-BUG-023-adversarial.test.ts` -> 12 passed, exit 0. The execution JSON in this artifact reflects the isolated QA-file run (the accurate signal). Not a product defect; QA tooling artifact only.

- **[info] Overlap vs extension.** The PR already ships per-script row coverage (`qa-dispatch.bats`, `detect-phase.bats`, `safety-net.bats`). These QA tests deliberately do NOT re-derive those rows; they add the independent CROSS-SCRIPT consistency invariant (adopt-trigger == detect-route == FR-9-gate set) and the glob-widening / anchoring probes against real git repos.

- **[info] Known coverage gap (out of BUG-023 scope, no regression).** A `qa-*` file placed in a non-canonical location (subdir, or wrong directory) is invisible to BOTH the adopt trigger and the FR-9 gate. This is consistent (no deadlock) but such a file could accumulate unadopted. This matches the documented Out-of-Scope item "#266 one-time cleanup of accumulated orphans" and is not introduced by this fix.

## Reconciliation Delta

### Coverage beyond requirements
- Scenario "[P0] Canonical tracked `tests/unit/qa-*.test.ts` (mode: test-framework): FR-9 glob flags it AND `qa-dispatch=adopt-phase` AND `detect-phase=adopt`. Three-way ag" — not mentioned in spec
- Scenario "[P0] Canonical tracked `tests/bats/qa/qa-*.bats` (mode: test-framework): same three-way agreement on the Bats canonical path." — not mentioned in spec
- Scenario "[P0] No `qa-*` files present (mode: test-framework): FR-9 clears AND `dispatch=advance` AND `phase=unknown`." — not mentioned in spec
- Scenario "[P0] pytest `qa-*.py` + go-test `qa-*.go` committed (mode: test-framework): Edge Case 17 — these extensions stay ABSENT from the glob set, so FR-9 ignores them " — not mentioned in spec
- Scenario "[P0] `adoptedTests` non-empty with a stray git-visible `qa-*` file (mode: test-framework): loop terminates — `dispatch=advance`, `phase=unknown` (no re-adopt lo" — not mentioned in spec
- Scenario "[P1] `qa-*` in a non-canonical subdir `tests/unit/sub/` (mode: test-framework): git pathspec `*` does not cross `/`, so the single-level glob excludes it -> `ad" — not mentioned in spec
- Scenario "[P1] Permanent infra `tests/bats/skills/<skill>/qa-*.bats` (mode: test-framework): only `tests/bats/qa/` is canonical-ephemeral; skill-infra Bats stays clear of" — not mentioned in spec
- Scenario "[P1] Mixed canonical set, unit + bats/qa committed together (mode: test-framework): both files flagged by FR-9; a single `adopt-phase` route covers them (no par" — not mentioned in spec
- Finding "**[info] Harness — `run-framework.sh` reports `exitCode: 1` for this repo's compound `testCommand`.** `capability-discovery.sh` returns `testCommand: npm test`," — not mentioned in spec
- Finding "**[info] Overlap vs extension.** The PR already ships per-script row coverage (`qa-dispatch.bats`, `detect-phase.bats`, `safety-net.bats`). These QA tests delib" — not mentioned in spec
- Finding "**[info] Known coverage gap (out of BUG-023 scope, no regression).** A `qa-*` file placed in a non-canonical location (subdir, or wrong directory) is invisible " — not mentioned in spec

### Coverage gaps
- AC-2 "[x] The chosen mechanism is documented in the relevant SKILL.md and reference docs." — no corresponding scenario in plan

### Summary
- coverage-surplus: 11
- coverage-gap: 1

