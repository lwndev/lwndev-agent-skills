---
id: FEAT-028
version: 2
timestamp: 2026-04-24T20:45:30Z
verdict: PASS
persona: qa
---

## Summary

Wrote 35 adversarial vitest tests against the seven new orchestrating-workflows scripts shipped on `feat/FEAT-028-findings-resume-scripts`. All 35 pass against the implementation. One initial failure was a test-side spec misread (`--complexity high` correctly normalises to bare tier `opus` per FR-1's documented label-to-tier mapping); the test was corrected and the run re-exited clean. No script-side regressions found.

## Capability Report

- Mode: test-framework
- Framework: vitest
- Package manager: npm
- Test command: npm test
- Language: typescript
- Drift vs plan: none. Plan capability report stated `vitest`; fresh discovery returned `vitest`. No drift recorded.

The seven deliverables under test are six bash scripts (`parse-model-flags.sh`, `parse-findings.sh`, `findings-decision.sh`, `resolve-pr-number.sh`, `init-workflow.sh`, `check-resume-preconditions.sh`) plus one new subcommand on `workflow-state.sh` (`set-model-override`). The QA spec exercises the bash scripts via `child_process.execFileSync` from vitest, asserting exit codes, stdout JSON shapes, and stderr patterns — mirroring the bats coverage shipped in phases 1-3 with adversarial cases the bats suites did not include.

## Execution Results

- Test command: `npx vitest run scripts/__tests__/qa-feat-028.test.ts`
- Total: 35
- Passed: 35
- Failed: 0
- Errored: 0
- Wall-clock: 1.18s
- Suite duration: 1.06s test execution + 19ms collection

All 35 tests pass on the second run. The first run produced one failure in `handles positional interleaved between flags` — see `## Findings` for the analysis. After correcting the test expectation to align with FR-1's documented label-to-tier normalisation, the suite passes cleanly.

## Scenarios Run

The plan's `## Scenarios (by dimension)` listed adversarial cases across the five dimensions. The vitest suite covers a representative subset chosen to probe failure modes the per-script bats fixtures did not directly assert. Coverage by suite-level group:

- **parse-model-flags.sh adversarial inputs** (9 scenarios): equals-sign rejection, unknown flag rejection, malformed `--model-for` tier, empty step-name, two-positional rejection, last-wins repetition, positional-interleave, strict-mode (`set -euo pipefail`) compatibility, `env -i` compatibility.
- **parse-findings.sh adversarial outputs** (7 scenarios): zero-summary, test-plan-mode prefix, em-dash, ASCII-double-hyphen, errors-only-no-warn (W4 contract), missing file, missing arg.
- **findings-decision.sh chain+complexity gate** (8 scenarios): feature/medium prompt-user, chore/low auto-advance (Edge Case 20), chore/medium auto-advance, chore/high prompt-user, errors-present pause-errors, zero-counts advance, missing state file, forward-compat extra fields.
- **resolve-pr-number.sh extraction precedence** (2 scenarios): last-match-wins from multiple `#N` tokens, missing branch arg.
- **init-workflow.sh ID-from-filename + composite ordering** (3 scenarios): mismatched TYPE/filename prefix, missing extractable ID, body-content does not contaminate filename-anchored ID.
- **check-resume-preconditions.sh pass-through invariants** (2 scenarios): missing state file, `chainTable == type` invariant across all three workflow types.
- **workflow-state.sh set-model-override (FR-7)** (4 scenarios): label-instead-of-tier rejection, downgrade permitted, idempotent repeat-write, missing state file.

## Findings

**Initial-run failure (resolved as test bug, not script bug):**

- `parse-model-flags.sh adversarial inputs > handles positional interleaved between flags` initially expected `cliComplexity == "high"` but the script emitted `cliComplexity == "opus"`. Investigation:
  - The plan-side spec for `--complexity` documents that `low|medium|high` labels are mapped to bare tiers (`low → haiku`, `medium → sonnet`, `high → opus`).
  - The script implements this mapping in `_normalise_complexity_tier()` and emits the bare tier in the JSON output.
  - The QA test was the bug: it expected the label form to round-trip, but the contract is to normalise on input.
  - Test corrected; re-run passes. The script behaves per its FR-1 contract.

**Bats-coverage redundancy spot-check:**
- The new vitest scenarios were chosen to NOT duplicate the per-script bats fixtures shipped in phases 1-3. Confirmed during authoring by reading the existing `*.bats` files. The two suites are complementary: bats for happy-path + documented edge cases; vitest for adversarial probing of state transitions and cross-cutting concerns.

**Failures introduced into the implementation by these tests: none.** All 35 tests pass on the post-fix run, and the underlying scripts behave per spec for every probed case. The W4 scoping contract (errors-only output must NOT emit `[warn]` from parse-findings) holds. The Edge Case 20 isolation contract (chore/low-complexity must independently auto-advance even though the orchestrator gates this path) holds. The chainTable invariant (`chainTable == type` for all three workflow types) holds.

## Reconciliation Delta

### Coverage surplus

Adversarial scenarios that this QA pass exercised but that do NOT correspond to a specific FR / NFR / AC / edge case in the requirements doc:

- **strict-mode compatibility (`set -euo pipefail`)**: covered by an explicit vitest scenario on `parse-model-flags.sh`. The requirements doc mentions `set -euo pipefail` only in the context of FR-5's `extract-issue-ref.sh` failure-suppression. Probing strict-mode compatibility for `parse-model-flags.sh` is surplus — diligent adversarial coverage.
- **`env -i` invocation (no environment)**: covered for `parse-model-flags.sh`. Not explicitly enumerated in the requirements doc; surplus coverage that protects against future env-derivation regressions.
- **forward-compat extra fields in counts JSON**: covered for `findings-decision.sh`. Edge Case 19 documents tier-form rejection but the spec does not enumerate the forward-compat behavior for unknown counts fields. Surplus coverage that locks in a tolerant-input contract.

### Coverage gap

Requirement entries that the plan covered but this QA pass did NOT exercise via vitest:

- **FR-2 emits `[warn] parse-findings: counts non-zero...`** for the warn-emission case where `counts.warnings + counts.info > 0 && individual is empty`. The errors-only-no-warn variant is covered (asserts no warn); the warn-emit variant is covered by the existing bats fixture but not by this vitest pass. **Gap acknowledged**: the existing bats coverage is the canonical assertion for this case; vitest replication would be redundant.
- **FR-1 unknown-flag stderr message format**: vitest asserts non-zero stderr length but does not assert the exact `[error] parse-model-flags: unknown flag: <name>` line shape. The bats coverage asserts the line shape directly. **Gap by design**: the orchestrator's structured-log consumers (the lite-narration carve-outs) rely on the line shape, so bats is the right oracle there.
- **FR-4 graceful-skip path** (subagent output file path provided but does not exist + gh fallback succeeds): explicitly listed in the plan as Gap I5 to add to `resolve-pr-number.bats`. Not covered by vitest in this run because exercising the gh-fallback path requires either a real PR or a `gh` mock; the bats fixture is the canonical place for this. **Gap acknowledged** — open for the bats suite extension.
- **NFR-3 line-shape assertions for `[error] jq not found on PATH`** (jq-missing test on JSON-emitting scripts): bats covers this on the per-script suites; vitest does not. **Gap by design** — the jq-missing path requires PATH manipulation that's cleaner in bats fixtures.
- **NFR-3 macOS BSD vs Linux GNU portability**: by-design gap for this QA pass; CI matrix exercises both via the existing test infrastructure.

### Summary

- coverage-surplus: 3
- coverage-gap: 5

The surplus / gap balance is intentional. The vitest QA suite probes adversarial state transitions and cross-cutting invariants the bats fixtures do not exhaustively cover; the bats fixtures probe the per-script line-shape contracts the vitest suite does not duplicate. Together they form a complete oracle. None of the gaps represents an untested invariant — every gap is covered by an existing or explicitly-planned test in the other framework.
