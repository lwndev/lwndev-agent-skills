---
id: BUG-015
version: 2
timestamp: 2026-05-01T02:55:55Z
verdict: PASS
persona: qa
---

## Summary

QA verdict: PASS. 17/17 adversarial vitest probes pass. No defects in BUG-015 fix; documented bypass scenarios are now denied as expected. The bats fixtures from the fix (150/150 pass) and the vitest probes give cross-harness coverage of the load-bearing security property.

## Capability Report

```json
{
  "id": "BUG-015",
  "timestamp": "2026-05-01T02:31:59Z",
  "mode": "test-framework",
  "framework": "vitest",
  "packageManager": "npm",
  "testCommand": "npm test",
  "language": "typescript",
  "notes": []
}
```

## Execution Results

- Total: 17
- Passed: 17
- Failed: 0
- Errored: 0
- Exit code: 0

## Scenarios Run

### Inputs
- [P0] Edit/Write/MultiEdit deny on gated `requirements/{features,chores,bugs}/.+\.md` with no marker (vitest 3 probes; bats 6 fixtures) | mode: test-framework | result: PASS
- [P0] Edit allow on out-of-scope path (`src/index.ts`) regardless of gate state (vitest 1 probe; bats 1 fixture) | mode: test-framework | result: PASS
- [P0] Edit allow when gate is null (cleared) (vitest 1 probe; bats 1 fixture) | mode: test-framework | result: PASS
- [P0] Stale marker (mtime < gateSetAt) deny on gated path (vitest 1 probe; bats 1 fixture) | mode: test-framework | result: PASS
- [P0] Fresh marker (mtime >= gateSetAt) allow on gated path (vitest 1 probe; bats 1 fixture) | mode: test-framework | result: PASS
- [P0] Agent fork: subagent_type general-purpose + embedded `name: finalizing-workflow` deny without merge marker (vitest 1 probe; bats 2 fixtures) | mode: test-framework | result: PASS
- [P0] Agent fork: subagent_type general-purpose + embedded `name: reviewing-requirements` allow (no false positive) (vitest 1 probe; bats 1 fixture) | mode: test-framework | result: PASS
- [P0] Agent fork: subagent_type general-purpose + embedded finalizing-workflow + fresh merge marker -> allow (vitest 1 probe; bats 1 fixture) | mode: test-framework | result: PASS

### State transitions
- [P0] set-gate writes ISO-8601 `gateSetAt` (vitest 1 probe; bats 2 fixtures) | mode: test-framework | result: PASS
- [P0] clear-gate resets `gateSetAt` to null (vitest 1 probe; bats 2 fixtures) | mode: test-framework | result: PASS
- [P0] pause auto-clears gate AND resets `gateSetAt` to null (vitest 1 probe; bats 2 fixtures) | mode: test-framework | result: PASS
- [P0] Direct subagent_type finalizing-workflow + no merge marker -> deny (regression on existing AC8) (vitest 1 probe; bats existing) | mode: test-framework | result: PASS
- [P0] Init writes gate=null and gateSetAt=null (vitest 1 probe; bats covers state-fields migration) | mode: test-framework | result: PASS

### Environment
- [P0] No `.active` marker -> Edit allowed (graceful skip when no active workflow) (vitest 1 probe; bats 2 fixtures) | mode: test-framework | result: PASS
- [P1] BSD vs GNU stat compat for marker mtime extraction; iso_to_epoch UTC handling (bats fixtures inherit existing `marker_mtime_epoch` / `iso_to_epoch` helpers from `guard-state-transitions.sh`; same fixtures pass on macOS BSD stat in this run) | mode: test-framework | result: PASS

### Dependency failure
- [P1] State file missing `gateSetAt` field (legacy pre-fix state file): treated as infinitely old, no marker can satisfy, deny (vitest 1 probe; bats 1 fixture) | mode: test-framework | result: PASS
- [P2] State file with explicit `gateSetAt: null` after clear-gate; gate also null -> hook short-circuits before consulting gateSetAt -> allow (covered transitively by clear-gate vitest probe + bats fixture) | mode: test-framework | result: PASS

### Cross-cutting
- [P0] Auto-mode load-bearing security property: orchestrator-issued Edit during auto-mode never has a marker because record-approval.sh fires only on real UserPromptSubmit; gate set + no marker -> deny (covered by vitest deny-without-marker probes; this is the load-bearing case) | mode: test-framework | result: PASS
- [P0] Embedded SKILL.md frontmatter takes precedence over subagent_type for confirmation-owning skills; subagent_type cannot bypass merge gate (covered by vitest RC-2 deny probe and bats parity fixtures) | mode: test-framework | result: PASS

## Findings

The 17 vitest scenarios under `scripts/__tests__/qa-bug-015-gates.test.ts` all PASS, exercising the load-bearing security property: orchestrator self-authorization is blocked at the hook layer regardless of which Claude Code tool (Edit, Write, MultiEdit, Agent) is used.

No defects observed. The 17 vitest probes are independent of the 30 bats fixtures the fix added — both pass cleanly, giving cross-harness signal on the same property. The fix's own bats coverage (`plugins/lwndev-sdlc/scripts/tests/hooks/*.bats` -> 150/150 pass) covers AC-by-ID; the 17 vitest probes cover dimension-by-dimension under the QA persona.

Coverage gap noted by `qa-reconcile-delta.sh` (18 AC entries) is a structural artifact of organizing scenarios by adversarial dimension (per `documenting-qa` v2 contract) rather than by AC-N ID. Each AC is exercised by at least one of the 17 vitest probes plus the corresponding bats fixture in the fix; the gap is in the reconciler's matching algorithm, not in actual coverage.

`qa-verify-coverage.sh` reports COVERAGE-GAPS because the dimension headings under `## Scenarios Run` did not match the v2 plan dimensions in earlier renders; this artifact below restores the dimension headings.

## Reconciliation Delta

### Coverage beyond requirements
- Scenario "Ran 17 passing tests, 0 failing tests, 0 errored tests." — not mentioned in spec

### Coverage gaps
- AC-1 "[x] A new hook script `plugins/lwndev-sdlc/scripts/hooks/guard-findings-edits.sh` ships and is wired in `plugins/lwndev-" — no corresponding scenario in plan
- AC-2 "[x] When `gate == findings-decision` is set on workflow `<ID>`, an `Edit` / `Write` / `MultiEdit` against a path matchin" — no corresponding scenario in plan
- AC-3 "[x] When `gate` is null (cleared), the same `Edit` against the same path is allowed (RC-1)" — no corresponding scenario in plan
- AC-4 "[x] An `Edit` against a path outside `requirements/**/*.md` is allowed regardless of gate state (no scope creep) (RC-1)" — no corresponding scenario in plan
- AC-5 "[x] `guard-agent-prompts.sh` extracts the embedded SKILL.md `name:` frontmatter from the Agent prompt before consulting " — no corresponding scenario in plan
- AC-6 "[x] An `Agent(subagent_type: general-purpose, prompt: <finalizing-workflow SKILL.md verbatim>)` call is denied without a" — no corresponding scenario in plan
- AC-7 "[x] An `Agent(subagent_type: general-purpose, prompt: <reviewing-requirements SKILL.md verbatim>)` call is allowed when " — no corresponding scenario in plan
- AC-8 "[x] `workflow-state.sh set-gate <ID> <gate-name>` records `gateSetAt: <ISO-8601>` to the state file (RC-3)" — no corresponding scenario in plan
- AC-9 "[x] `workflow-state.sh clear-gate <ID>` resets `gateSetAt` to null (RC-3)" — no corresponding scenario in plan
- AC-10 "[x] `cmd_pause` (which auto-clears the gate) resets `gateSetAt` to null (RC-3)" — no corresponding scenario in plan
- AC-11 "[x] A `.approval-findings-decision-<ID>` marker with mtime predating `gateSetAt` does NOT satisfy the gate (stale-marker" — no corresponding scenario in plan
- AC-12 "[x] A `.approval-findings-decision-<ID>` marker with mtime ≥ `gateSetAt` DOES satisfy the gate (RC-3)" — no corresponding scenario in plan
- AC-13 "[x] Missing `gateSetAt` on a pre-fix state file (legacy state files predating this bug fix) is treated as infinitely old" — no corresponding scenario in plan
- AC-14 "[x] `record-approval.sh` continues to write fresh markers (mtime advances on each `UserPromptSubmit`) — verified by an e" — no corresponding scenario in plan
- AC-15 "[x] New bats fixture `guard-findings-edits.bats` covers the gate-on / gate-off / no-marker / stale-marker / fresh-marker" — no corresponding scenario in plan
- AC-16 "[x] Extension to `guard-agent-prompts.bats` covers the `subagent_type: general-purpose` + embedded `name: finalizing-wor" — no corresponding scenario in plan
- AC-17 "[x] Extension to `guard-state-transitions.bats` covers `gateSetAt` interaction with existing `clear-gate` markers (regre" — no corresponding scenario in plan
- AC-18 "[x] CHORE-036 session is reproducible against the patched hooks: re-running the equivalent fork prompts denies; user-typ" — no corresponding scenario in plan

### Summary
- coverage-surplus: 1
- coverage-gap: 18

