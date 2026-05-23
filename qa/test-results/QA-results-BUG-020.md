---
id: BUG-020
version: 2
timestamp: 2026-05-23T16:01:26Z
verdict: PASS
persona: qa
---

## Summary

QA suite passed. 1670 tests passed across the full Vitest + Bats suites. Four new QA-prefix files (3 bats + 1 vitest) cover all P0/P1 test-framework scenarios from the BUG-020 plan. 7 exploratory-mode scenarios deferred to manual repro per plan. Reconciler emits substring-only coverage gaps (false positive); every AC is exercised semantically.

## Capability Report

```json
{
  "id": "BUG-020",
  "timestamp": "2026-05-23T15:48:31Z",
  "mode": "test-framework",
  "framework": "vitest",
  "packageManager": "npm",
  "testCommand": "npm test",
  "language": "typescript",
  "notes": []
}
```

## Execution Results

- Total: 1670
- Passed: 1670
- Failed: 0
- Errored: 0
- Exit code: 0

## Scenarios Run

### Inputs

- [P0] `cmd_set_gate <ID> merge-approval` on in-progress workflow writes `.gate` + ISO-8601 `.gateSetAt` | mode: test-framework | result: PASS (qa-BUG-020-set-gate.bats)
- [P0] `cmd_set_gate <ID> findings-decision` regression check | mode: test-framework | result: PASS (qa-BUG-020-set-gate.bats)
- [P0] `cmd_set_gate <ID> <unknown>` rejects with `Expected one of: findings-decision, merge-approval` (bogus / MERGE-APPROVAL / empty) | mode: test-framework | result: PASS (qa-BUG-020-set-gate.bats x3)
- [P0] `[info] auto-paused` line carries all four tokens on a single stderr line | mode: test-framework | result: PASS (qa-BUG-020-audit-line.bats)
- [P1] Audit-line separator is ASCII `- ` hyphen-space, not em/en-dash | mode: test-framework | result: PASS (qa-BUG-020-audit-line.bats)
- [P1] `set-gate merge-approval` idempotency: second call refreshes `gateSetAt` | mode: test-framework | result: PASS (qa-BUG-020-set-gate.bats)
- [P2] Shell-injection arg in gate-type rejected by enum check before expansion | mode: test-framework | result: PASS (qa-BUG-020-set-gate.bats)

### State transitions

- [P0] `stop-hook.sh` exits 0 when `.gate == "merge-approval"` and `status == "in-progress"` | mode: test-framework | result: PASS (existing auto-mode-end-to-end.bats:142 BUG-020 AC9 case)
- [P0] `stop-hook.sh` exits 0 when `.gate == "findings-decision"` (regression) | mode: test-framework | result: PASS (existing auto-mode-end-to-end.bats:158 BUG-020 AC9 regression case)
- [P0] `advance` after `set-gate merge-approval` clears `.gate` and `.gateSetAt` to null | mode: test-framework | result: PASS (qa-BUG-020-gate-clearing.bats)
- [P1] `pause` after `set-gate merge-approval` clears `.gate` and `.gateSetAt` to null | mode: test-framework | result: PASS (qa-BUG-020-gate-clearing.bats)
- [P1] `set-gate merge-approval` on non-in-progress workflow rejects with no-regression error | mode: test-framework | result: PASS (qa-BUG-020-set-gate.bats)
- [P1] Auto-pause on pause-context advance leaves `.gate == null` (no BUG-018 collision) | mode: test-framework | result: PASS (qa-BUG-020-gate-clearing.bats)
- [P2] Rapid set-gate / clear-gate cycles leave state file parseable | mode: test-framework | result: PASS (qa-BUG-020-gate-clearing.bats)

### Environment

- [P0] `### Pause Steps` section contains load-bearing / HALT / surface the pause artifact / work without stopping | mode: test-framework | result: PASS (qa-BUG-020-doc-invariants.test.ts)
- [P0] `step-execution-details.md` contains `set-gate {ID} merge-approval` at least 3 times | mode: test-framework | result: PASS (qa-BUG-020-doc-invariants.test.ts)
- [P0] SKILL.md carve-out paragraph cross-links to `step-execution-details.md` | mode: test-framework | result: PASS (qa-BUG-020-doc-invariants.test.ts)
- [P1] SKILL.md carve-out enumerates all five gate identifiers | mode: test-framework | result: PASS (qa-BUG-020-doc-invariants.test.ts)
- [P1] Read-only mount produces no half-written state file | mode: exploratory | result: not run — exploratory-mode scenario (justification: manual repro per plan, not in adversarial-QA runner scope)
- [P2] LANG=C run produces identical audit-line output | mode: test-framework | result: PASS (qa-BUG-020-audit-line.bats)

### Dependency failure

- [P0] Hook A unavailable → no marker → Hook C denies finalize fork | mode: exploratory | result: not run — exploratory-mode scenario (justification: plugin-unload integration repro out of scope for adversarial QA runner)
- [P0] Hooks B/C uninstalled → managed-settings `permissions.deny` blocks `gh pr merge` | mode: exploratory | result: not run — exploratory-mode scenario (justification: plugin-uninstall integration repro out of scope)
- [P1] QA plan structural conformance preserved (frontmatter + sections) | mode: test-framework | result: PASS (qa-BUG-020-doc-invariants.test.ts)
- [P2] `workflow-state.sh status` returns the gate value immediately after `set-gate` | mode: test-framework | result: PASS (covered indirectly via qa-BUG-020-set-gate.bats jq read of state file)

### Cross-cutting

- [P0] BUG-014 hook coverage no regression: existing markers / Hook B+C checks fire on `merge-approval` value | mode: test-framework | result: PASS (existing auto-mode-end-to-end.bats suite green)
- [P0] BUG-018 atomic auto-pause no regression: `cmd_advance` auto-paused contract intact | mode: test-framework | result: PASS (existing workflow-state-advance-pause-context.bats suite green)
- [P0] BUG-015 `gateSetAt` no regression: `set-gate` stamps it; `advance`/`pause`/`clear-gate` reset it | mode: test-framework | result: PASS (existing + new qa-BUG-020-set-gate.bats coverage)
- [P1] Concurrent `set-gate` writers — second wins, no half-written file | mode: exploratory | result: not run — exploratory-mode scenario (justification: cross-process race repro out of scope)
- [P1] State file permissions: default umask produces 644 | mode: exploratory | result: not run — exploratory-mode scenario (justification: manual stat check out of scope)
- [P2] a11y: no UI surface — justification documented in plan Non-applicable dimensions | mode: exploratory | result: not applicable — no UI surface
- [P2] i18n: load-bearing tokens ASCII-only — justification documented in plan | mode: exploratory | result: not applicable — English-only by design

## Findings

No test failures — all written QA tests passed.

### Coverage notes

- The `qa-reconcile-delta.sh` reconciler emits 10 nominal "coverage gaps" because it does substring-match of AC labels (e.g. "AC-1") against the plan's scenario lines, and the plan uses dimensional naming (Inputs / State transitions / ...) rather than AC-N references. Every AC is exercised semantically by the QA tests; the gap report is a known false-positive.
- 7 exploratory-mode scenarios in the plan (Environment P1, Dependency failure P0+P0, Cross-cutting P1+P1+P2+P2) are explicitly marked `mode: exploratory` in the plan; the adversarial test-framework runner does not execute them and they are documented in `## Scenarios Run` as not-run with justification. These match the plan's own `## Non-applicable dimensions` justifications for a11y / i18n and the integration / cross-process repros that require manual fixture setup.

## Reconciliation Delta

### Coverage beyond requirements

### Coverage gaps
- AC-1 "[x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/step-execution-details.md` "Pause Steps" gains an exp" — no corresponding scenario in plan
- AC-2 "[x] The `[info] auto-paused` line emitted by `cmd_advance` (`plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/" — no corresponding scenario in plan
- AC-3 "[x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` `:89` Load-bearing carve-out gains an explicit cross-r" — no corresponding scenario in plan
- AC-4 "[x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh` `cmd_set_gate` (`:1290`) is extended " — no corresponding scenario in plan
- AC-5 "[x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/step-execution-details.md` Finalize fork-step block (" — no corresponding scenario in plan
- AC-6 "[x] A new test at `tests/unit/orchestrating-workflows-pause-step-docs.test.ts` asserts: (a) `step-execution-details.md` " — no corresponding scenario in plan
- AC-7 "[x] `tests/bats/skills/orchestrating-workflows/workflow-state-advance-pause-context.bats:107-115` is extended with asser" — no corresponding scenario in plan
- AC-8 "[x] `tests/bats/skills/orchestrating-workflows/workflow-state-set-gate.bats` (new or extended) asserts: (a) `cmd_set_gat" — no corresponding scenario in plan
- AC-9 "[x] `tests/bats/shared/hooks/auto-mode-end-to-end.bats` is extended with a regression case asserting that when `.gate ==" — no corresponding scenario in plan
- AC-10 "[x] No regression in existing BUG-014 hook coverage, BUG-018 atomic auto-pause coverage, BUG-015 gateSetAt coverage, or " — no corresponding scenario in plan

### Summary
- coverage-surplus: 0
- coverage-gap: 10

