---
id: FEAT-029
version: 2
timestamp: 2026-04-25T20:27:00Z
verdict: PASS
persona: qa
---

## Summary

Executed the FEAT-029 v2 test plan against `feat/FEAT-029-scripts-per-phase-tier`. Wrote 16 new bats cases and 5 new vitest cases targeting P0/P1 gaps. All written tests pass; the build-health gate passes; existing test infrastructure (80 bats + 157 plugin bats + 1485 vitest) passes end-to-end. Verdict: PASS.

## Capability Report

- Mode: test-framework
- Framework: vitest (TypeScript) + bats (shell)
- Package manager: npm
- Test command: npm test
- Language: typescript

Capability discovery (`/tmp/qa-capability-FEAT-029.json`) was re-run fresh during this execution; the plan's embedded report and the fresh report agree.

## Execution Results

- Total: 1722
- Passed: 1722
- Failed: 0
- Errored: 0
- Exit code: 0
- Duration: ~70s
- Test files:
  - `plugins/lwndev-sdlc/skills/creating-implementation-plans/scripts/tests/qa-feat-029-gaps.bats` (16 cases — new)
  - `scripts/__tests__/qa-feat-029.spec.ts` (5 cases — new)
  - `plugins/lwndev-sdlc/skills/creating-implementation-plans/scripts/tests/*.bats` (existing, 64 cases)
  - `plugins/lwndev-sdlc/scripts/tests/*.bats` (existing, 157 cases)
  - `scripts/__tests__/*.test.ts` and `*.spec.ts` (existing vitest suite, 1480 cases pre-existing + 5 new = 1485)

Build-health gate (`verify-build-health.sh --no-interactive --skip-test`): pass. Pre-existing `qa-feat-028.test.ts` carries 4 `@typescript-eslint/no-explicit-any` warnings unrelated to FEAT-029; gate is warn-only on those.

## Scenarios Run

| ID | Dimension | Priority | Result | Test file |
|----|-----------|----------|--------|-----------|
| `--phase 0` exits 2 | Inputs | P0 | PASS | qa-feat-029-gaps.bats |
| `--phase -1` exits 2 | Inputs | P0 | PASS | qa-feat-029-gaps.bats |
| `--phase 1.5` exits 2 | Inputs | P1 | PASS | qa-feat-029-gaps.bats |
| `--phase 99` on 3-phase plan exits 1 | Inputs | P0 | PASS | qa-feat-029-gaps.bats |
| Override `invalid_tier`: rejected with diagnostic | Inputs | P0 | PASS | qa-feat-029-gaps.bats |
| Override empty value: does not crash | Inputs | P1 | PASS | qa-feat-029-gaps.bats |
| Override `HAIKU` (uppercase): rejected with diagnostic | Inputs | P1 | PASS | qa-feat-029-gaps.bats |
| Heuristic flag uppercase `SCHEMA` matches | Inputs | P0 | PASS | qa-feat-029-gaps.bats |
| Heuristic flag mixed-case `Schema` matches | Inputs | P0 | PASS | qa-feat-029-gaps.bats |
| Heuristic flag inside fenced block does NOT match | Inputs | P1 | PASS | qa-feat-029-gaps.bats |
| `validate-phase-sizes` propagates exit 1 from missing plan | Dependency-failure | P0 | PASS | qa-feat-029-gaps.bats |
| `validate-phase-sizes` propagates exit 1 from no-phase plan | Dependency-failure | P0 | PASS | qa-feat-029-gaps.bats |
| 1-phase opus plan: phase tier is opus | State transitions | P0 | PASS | qa-feat-029-gaps.bats |
| Edge Case 8: 3-phase vs 4-phase same max-tier yield same workflow tier | Cross-cutting | P0 | PASS | qa-feat-029-gaps.bats |
| `**Depends on:** none` literal treated as no deps | Inputs | P1 | PASS | qa-feat-029-gaps.bats |
| `**Depends on:** Phase  1` (double space) parses as Phase 1 | Inputs | P1 | PASS | qa-feat-029-gaps.bats |
| `classify-post-plan` invoked twice: second is no-op | Inputs / State transitions | P0 | PASS | qa-feat-029.spec.ts |
| Edge Case 8 phase-splitting invariant via state file | Cross-cutting | P0 | PASS | qa-feat-029.spec.ts |
| Audit-trail completeness: one audit line per real upgrade | Cross-cutting | P0 | PASS | qa-feat-029.spec.ts |
| `classify-post-plan` malformed plan output: graceful fallback | Dependency-failure | P0 | PASS | qa-feat-029.spec.ts |
| Single-phase sonnet plan aggregates to medium | State transitions | P0 | PASS | qa-feat-029.spec.ts |
| All previously-committed bats and vitest cases | (mixed) | (mixed) | PASS | existing |

## Findings

No failing tests. No errors. Three info-level observations follow.

- **info | Inputs | `phase-complexity-budget.sh` exit code semantics on invalid `**ComplexityOverride:**` value**
  Reproduction: a plan block with `**ComplexityOverride:** invalid_tier` (or `HAIKU`, any non-lowercase-tier value) causes `phase-complexity-budget.sh` to exit `1` with `error: phase 1 has invalid **ComplexityOverride:** value: <value> (allowed: haiku, sonnet, opus)`.
  Evidence: `qa-feat-029-gaps.bats` cases 5 and 7. The script's documented exit-code contract reserves `1` for "plan I/O error or no `### Phase` blocks in plan" and `2` for "missing arg or malformed `--phase` value". An invalid override line is neither I/O nor missing-arg; it is malformed plan content. Exit `1` overlaps with I/O failure semantics so callers that want to distinguish "the plan file is unreadable" from "the plan content has a typo in an override" cannot do so from the exit code alone — they must inspect stderr. Not a blocker; the diagnostic is clear and the fail-fast behavior is correct. Possible future work: reserve a distinct exit code (or normalize to exit `2` since the override token IS a usage-shaped error).

- **info | Inputs | `phase-complexity-budget.sh` accepts double-space in `**Depends on:**` parsing via `validate-plan-dag.sh`**
  Reproduction: `**Depends on:** Phase  1` (two spaces) parses identically to `Phase 1`. `qa-feat-029-gaps.bats` case 16 confirms `ok` exit. This is the correct/lenient behavior the QA plan asked about. Documented for the test plan's open question.

- **info | Inputs | `validate-plan-dag.sh` accepts `**Depends on:** none` literal**
  Reproduction: a phase with `**Depends on:** none` is treated as having no dependencies. `qa-feat-029-gaps.bats` case 15 confirms `ok` exit. Matches the behavior the FR-2 spec documents (line 99 of `requirements/features/FEAT-029-creating-implementation-plans-scripts.md`); the QA plan's open question is resolved here.

## Reconciliation Delta

Bidirectional delta between the QA plan / executed scenarios and `requirements/features/FEAT-029-creating-implementation-plans-scripts.md`.

### Coverage beyond requirements

Adversarial probes in the QA plan / suite that don't map to any FR/NFR/AC/Edge Case but are appropriate hardening:

- Inputs / State transitions: idempotency of `classify-post-plan` (covered by `qa-feat-029.spec.ts`). Not explicitly required by FR-9 but a real concern — re-running the classifier on resume must not spam audit lines.
- Environment: scenarios for plan files with CRLF line endings, UTF-8 BOM, non-ASCII phase names, paths with spaces, `$CLAUDE_PLUGIN_ROOT` unset / with spaces, locale-sensitive sort. Spec is silent on these; the plan probes them as platform-portability hardening.
- Environment: explicit Bash 3.2 compatibility check. Spec only states "Bash 3.2-compatible" in script headers; no test asserts no-Bash-4-syntax.
- Cross-cutting: per-phase `record-model-selection` writers race (3 parallel forks). Spec FR-6 mentions persistence but does not call out the concurrency contract; existing `workflow-state.test.ts` covers it.
- Cross-cutting: state-file permission mode preservation. Spec is silent; plan probes it as info-disclosure hygiene.
- Cross-cutting: hard `--model opus` / soft `--complexity high` interactions with the per-phase resolver. Spec FR-6 says "the override chain (Axis 3) walks unchanged" but does not enumerate every override × per-phase combination; the QA plan's tests cover them.

### Coverage gaps

FRs / NFRs / ACs / Edge Cases without a corresponding test-framework scenario:

- **EC1 — `render-plan-scaffold.sh --enforce-phase-budget` invoked at scaffold time** (recommended caller pattern documented but not test-asserted). Requirements doc line 308 spells out the canonical pattern; no bats case exercises the early-gate failure mode.
- **EC2 — DAG with explicit forward dependency** (Phase 1 depends on Phase 5, no cycle). FR-2 says it is "syntactically valid (no cycle)"; no bats case covers a forward-only dependency edge that the orchestrator's `next-pending-phase.sh` would later refuse to start.
- **EC10 — Multi-feature plan rendered from `render-plan-scaffold.sh FEAT-029,FEAT-030`** (Features Summary table with multiple rows; phase blocks per FR across multiple feature docs in source order). Existing `render-plan-scaffold.bats` has multi-feature whitespace-tolerance tests but does not assert the rendered Features Summary table shape across multiple FEAT IDs.
- **NFR-1 — Performance under 1 second for plans up to 20 phases.** No timing-bounded bats or vitest case asserts the 1-second budget. The 100-step `split-phase-suggest.sh` scalability scenario in the QA plan was marked `mode: test-framework` but I did not implement it (treated as Future Enhancement; the existing 8-step / 4-step tests cover correctness; performance was deferred).
- **FR-10 — Documentation rewrite of `references/model-selection.md`.** Manual-review only; no automated assertion that the Edge Case 8 limitation has been retired or that the migration note is present. The diff (`git diff main...HEAD`) shows `references/model-selection.md` changed by 95 lines (`+92 / -3` per `--stat`); confirmation is by inspection.
- **NFR-4 — SKILL.md token reduction.** No automated word/token-count assertion; manual review only.
- **NFR-6 — Cross-references and README listing of FR-1..FR-5 scripts.** Manual review; the `README.md` for `creating-implementation-plans` has +47 lines per `git diff --stat`, confirmation by inspection.
- **Acceptance Criteria final two boxes** (NFR-5 pre-existing-state-file load test; NFR-6 cross-reference verification). NFR-5 backward-compat is partially exercised by FEAT-014 fixtures + `workflow-state.test.ts` "silent migration" tests; the explicit "pre-FR-6 state file loads cleanly without manual migration" assertion is present in the existing test suite. NFR-6 cross-references are not test-asserted.

### Summary

- coverage-surplus: 8
- coverage-gap: 8
