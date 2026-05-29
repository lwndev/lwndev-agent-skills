---
id: BUG-022
version: 2
timestamp: 2026-05-29T16:42:37Z
verdict: PASS
persona: qa
---

## Summary

Verdict PASS: passed=9, failed=0, errored=0.

## Capability Report

```json
{
  "id": "BUG-022",
  "timestamp": "2026-05-29T16:34:09Z",
  "mode": "test-framework",
  "framework": "vitest",
  "packageManager": "npm",
  "testCommand": "npm test",
  "language": "typescript",
  "notes": []
}
```

## Execution Results

- Total: 9
- Passed: 9
- Failed: 0
- Errored: 0
- Exit code: 0

## Scenarios Run

All scenarios run as Bats against the repo working-tree `detect-re-qa-mode.sh`
(the BUG-022 fix copy), graded on `npx bats` exit code. 9 passed, 0 failed, 0 errored.

### Inputs
- [P1] Shell-injection ID `FEAT-$(touch PWNED)` does not execute; stdout is valid JSON; mode=initial | mode: test-framework | expected: exit 0, no command executed, `.mode == "initial"` — PASS
- [P1] Non-existent ID with no state -> exit 0, valid JSON, mode=initial | mode: test-framework | expected: exit 0, valid JSON — PASS
- [P2] Empty/malformed baseline marker ignored; decision keys on per-ID state -> mode=initial | mode: test-framework | expected: `.mode == "initial"` — PASS

### State transitions
- [P0] Same ID across two sequential runs flips `initial` -> `re-qa` only after a genuine prior run is recorded | mode: test-framework | expected: run1 initial, run2 re-qa — PASS

### Environment
- [P1] Invoked outside any git repository -> exit 0, `.files == []`, mode=initial (graceful degradation) | mode: test-framework | expected: exit 0, files empty, initial — PASS

### Dependency failure
- [P1] Malformed state JSON (`get-qa-state` unparseable) fails safe to `initial`, never `re-qa` | mode: test-framework | expected: `.mode == "initial"` — PASS
- [P2] Legacy pre-FEAT-032 state file lacking `qaFixAttempts`/`qaLastVerdict` -> defaults -> `initial` for a fresh ID | mode: test-framework | expected: `.mode == "initial"` — PASS

### Cross-cutting
- [P1] Idempotency: back-to-back invocations yield identical stdout and never mutate the baseline marker | mode: test-framework | expected: identical output, marker hash unchanged — PASS
- [P2] Two IDs on one branch sharing a committed `qa-*` file: fresh stays `initial`, prior-run resolves `re-qa` | mode: test-framework | expected: per-ID isolation — PASS

Non-applicable: a11y (no UI surface) and i18n (machine-readable JSON keyed on fixed ASCII tokens) are not relevant to this shell detection contract, per the test plan.

## Findings

No defects found. All 9 adversarial scenarios across the five dimensions passed
against the repo working-tree `detect-re-qa-mode.sh` (the BUG-022 state-cross-check
fix). The fix correctly resolves `mode=initial` on a fresh ID even with committed
`qa-*` files plus a present baseline marker, resolves `re-qa` only when workflow
state records a genuine prior run (`qaFixAttempts >= 1` OR `qaLastVerdict` set),
and fails safe to `initial` on missing/malformed/legacy state.

- Inputs: no defect — injection ID inert, malformed marker ignored, decision keys on state.
- State transitions: no defect — `initial -> re-qa` flip occurs only after a recorded prior run.
- Environment: no defect — graceful degradation outside a git repo (`files: []`, exit 0).
- Dependency failure: no defect — malformed and legacy state both fail safe to `initial`.
- Cross-cutting: no defect — idempotent, marker untouched, per-ID isolation holds.

Coverage note: `qa-verify-coverage.sh` reports COVERAGE-ADEQUATE across all five
dimensions. Reconciliation `coverage-gap` entries are a text-match artifact of the
heuristic reconciler (AC checkboxes are not literal scenario lines); the acceptance
criteria are exercised by the scenarios above and the permanent regression at
`tests/bats/skills/executing-qa/re-qa-mode.bats`.

Note: `run-framework.sh` parses vitest output only and is blind to Bats; these
deterministic shell scenarios were run directly via `npx bats` and graded on exit
code, per the QA plan's capability note.

## Reconciliation Delta

### Coverage beyond requirements
- Scenario "Ran 9 passing tests, 0 failing tests, 0 errored tests." — not mentioned in spec

### Coverage gaps
- AC-1 "[x] An initial QA run for an ID with `qaFixAttempts == 0 && qaLastVerdict == null` resolves to `mode=initial` even when " — no corresponding scenario in plan
- AC-2 "[x] Re-QA mode is NOT entered solely because unrelated prior-workflow `qa-*` test files are committed on the branch (RC-" — no corresponding scenario in plan
- AC-3 "[x] A genuine prior QA run for the same ID (`qaFixAttempts >= 1` or `qaLastVerdict` set) still resolves to `mode=re-qa` " — no corresponding scenario in plan
- AC-4 "[x] Regression test covers both the false-positive case (fresh ID + committed `qa-*` files -> initial) and the true-posi" — no corresponding scenario in plan

### Summary
- coverage-surplus: 1
- coverage-gap: 4

