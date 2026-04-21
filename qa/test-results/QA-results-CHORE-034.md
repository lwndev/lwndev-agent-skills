---
id: CHORE-034
version: 2
timestamp: 2026-04-21T17:28:39Z
verdict: PASS
persona: qa
---

## Summary

29/29 adversarial assertions passed against the documentation-contract surface installed by CHORE-034. Full suite regression-clean at 1075/1075. One assertion was refined mid-run after a false-positive on the Edge Case 11 baseline-bypass warning; the tightened regex now matches only FR-14 step-echoes.

## Capability Report

- Mode: test-framework
- Framework: vitest
- Package manager: npm
- Test command: npm test
- Language: typescript

## Execution Results

- Total: 1075
- Passed: 1075
- Failed: 0
- Errored: 0
- Exit code: 0
- Duration: 40.67s
- Test files: [`scripts/__tests__/qa-CHORE-034.spec.ts`]

### New QA file — CHORE-034 suite breakdown

- Inputs: Output Style section documentation integrity — 6/6
- Cross-cutting: load-bearing carve-outs regression guard — 8/8
- Inputs: FR-14 echo documented format matches prepare-fork.sh emitter — 4/4
- Cross-cutting: every fork-invocation spec points to the contract — 4/4
- State transitions: state-file schema backwards compatibility — 2/2
- Inputs: reviewing-requirements findings-summary regex is preserved — 3/3
- Environment: SKILL.md structural integrity — 2/2

## Scenarios Run

| ID | Dimension | Priority | Result | Test file |
|----|-----------|----------|--------|-----------|
| I-P0-findings-regex | Inputs | P0 | PASS | scripts/__tests__/qa-CHORE-034.spec.ts |
| I-P0-fr14-echo-documented | Inputs | P0 | PASS | scripts/__tests__/qa-CHORE-034.spec.ts |
| I-P0-fr14-echo-emitter-static | Inputs | P0 | PASS | scripts/__tests__/qa-CHORE-034.spec.ts |
| I-P0-fr14-echo-emitter-live | Inputs | P0 | PASS | scripts/__tests__/qa-CHORE-034.spec.ts |
| I-P0-contract-shapes | Inputs | P0 | PASS | scripts/__tests__/qa-CHORE-034.spec.ts |
| I-P0-contract-precedence | Inputs | P0 | PASS | scripts/__tests__/qa-CHORE-034.spec.ts |
| I-P0-contract-disambiguation | Inputs | P0 | PASS | scripts/__tests__/qa-CHORE-034.spec.ts |
| I-P0-output-style-placement | Inputs | P0 | PASS | scripts/__tests__/qa-CHORE-034.spec.ts |
| SC-P0-schema-compat-live | State transitions | P0 | PASS | scripts/__tests__/qa-CHORE-034.spec.ts |
| SC-P0-schema-compat-legacy | State transitions | P0 | PASS | scripts/__tests__/qa-CHORE-034.spec.ts |
| E-P0-npm-test | Environment | P0 | PASS | (full suite) 1075/1075 |
| E-P0-npm-validate | Environment | P0 | PASS | `npm run validate` 13/13 plugins |
| E-P0-skillmd-frontmatter | Environment | P0 | PASS | scripts/__tests__/qa-CHORE-034.spec.ts |
| E-P0-chain-procedures-smoke | Environment | P0 | PASS | scripts/__tests__/qa-CHORE-034.spec.ts |
| CX-P0-carveouts-preserved | Cross-cutting | P0 | PASS | scripts/__tests__/qa-CHORE-034.spec.ts (7 sub-tests) |
| CX-P0-findings-no-truncation | Cross-cutting | P0 | PASS | scripts/__tests__/qa-CHORE-034.spec.ts |
| CX-P0-fork-pointers | Cross-cutting | P0 | PASS | scripts/__tests__/qa-CHORE-034.spec.ts (4 sub-tests) |

## Findings

No test failures in the final run. Two notable observations from the authoring process (neither changes the verdict):

### Test-authoring refinement — initial over-generic regex

The first draft of the `prepare-fork.sh emitter uses Unicode →` assertion matched **every** `echo "[model] ..."` line in the script. It failed on the Edge Case 11 baseline-bypass warning (`echo "[model] Hard override ${override_flag_name} ${tier} bypassed baseline ${baseline} for ${skill}. Proceeding at user request."`), which is informational and legitimately has no arrow character. The regex was tightened to `echo "\[model\] step[^"]*"` so it matches only FR-14 step-echoes. This is a test-authoring artefact, not a production issue, but it confirms that `[model]`-prefixed lines are not monolithic — reviewers should not assume any `[model] ...` line is an FR-14 echo.

### Pre-commit hook behavior under lint-staged partial failure

The initial commit of `qa-CHORE-034.spec.ts` (`d28a83d`) landed with unresolved eslint + prettier errors. `lint-staged` auto-fixed the prettier issues then reverted when the two `require()` calls couldn't be auto-fixed, but the commit still completed because lint-staged's exit code did not cause the downstream husky `pre-commit` hook (which runs `npm run lint && npm run format:check && npm test`) to fail the commit — `npm test` passed 1075/1075 so the overall `pre-commit` chain apparently returned zero despite `npm run lint` printing 16 errors. Addressed by a follow-up commit (`83cb5e1`) that replaces the `require()` calls with top-of-file imports and applies prettier formatting. The chore itself does not change hook behavior; this is an environmental observation worth tracking if the rollout chore adds more QA spec files.

## Reconciliation Delta

### Coverage beyond requirements

- **I-P0-fr14-echo-emitter-live** — end-to-end invocation of `prepare-fork.sh` against a disposable tmp state file asserting the FR-14 echo on stderr contains `→`. Not in the original test plan; added during execution as a concrete regression guard for the pre-merge fix that reconciled the SKILL.md documentation with the emitter.
- **I-P0-fr14-echo-emitter-static** — source-level assertion that every `echo "[model] step ..."` line in `prepare-fork.sh` contains `→`. Also not in the original plan; complements the live test with a static check that does not require process spawn.
- **I-P0-output-style-placement** — positional assertion that `## Output Style` lands between `## Quick Start` and `## Feature Chain Step Sequence`. Not in the plan; added because early-read placement is load-bearing (the governance rules must be seen before any chain section).
- **CX-P0-findings-no-truncation** — specific assertion that the carve-out list still says "Do not truncate" for `reviewing-requirements` findings. Not in the plan; added as the single most load-bearing phrase in the carve-out list.

### Coverage gaps

- **I-P0 #1 — Fork subagent returns empty string → classifier-flagged failure**: not tested. The orchestrator's FR-11 classifier treats this as failure already, but no new parser was added by this chore so the scenario is orchestrator-runtime behavior, not chore-under-test behavior.
- **I-P0 #3 — Fork subagent emits extra prose before `done |` marker**: not tested. No parser exists for the new contract shapes; the scenario was written assuming one would be added. The contract is documentation-only for this pilot and parser tests are explicit gap.
- **I-P1 #4 — Fork returns `failed | reason` but artifact exists on disk**: not tested. Same reason as I-P0 #3 — no parser, no enforcement.
- **I-P1 #5 — Fork returns `done | artifact=path/does/not/exist.md`**: not tested. The orchestrator already validates artifact existence via Glob post-fork (pre-existing behavior), but the new `done | artifact=<path>` parsing path is not implemented.
- **I-P1 #6 — Fork returns contract with embedded pipes in the note**: not tested. No parser.
- **I-P2 #7 — Literal `done |` / `failed |` string inside prose preceding the contract line**: not tested. No parser.
- **I-P2 #8 — Unicode / emoji / RTL in chore doc user summary fed to QA plan**: not tested. Unchanged behavior; not specific to this chore.
- **SC-P1 — Fork fails once, FR-11 retry escalates with new contract shape**: not tested. Covered adjacent by existing `qa-FEAT-021.spec.ts`; no new contract-specific retry behavior added.
- **SC-P1 — NFR-6 fallback triggers with contract shape**: not tested. Existing behavior unchanged.
- **SC-P2 — User interrupts mid-fork**: not tested. Speculative scenario; no state-transition changes in this chore.
- **E-P1 — Measurement reproducibility (±5% tolerance)**: not tested. Documented in the chore's Notes section; measurement methodology is a rollout-chore concern.
- **E-P1 — Lite-rules carve-outs hold in real orchestrator run**: partially tested. Carve-out **list** verified present in SKILL.md; live-run behavioral verification (does the orchestrator actually emit each carve-out during a real workflow?) is deferred — the rollout chore's runtime-telemetry methodology will cover this better than static doc inspection.
- **E-P2 — Non-default CLAUDE_PLUGIN_ROOT**: not tested. No path-resolution changes in this chore.
- **DF-P1 — gh CLI unavailable during measurement**: not tested. Exploratory; measurement methodology concern.
- **DF-P2 — Capability discovery non-zero during documenting-qa**: not tested. No fallback-path changes.
- **CX-P1 — Rollout scope drift**: not tested. Reviewer-only concern.
- **CX-P1 — Rollout issue cross-links**: not tested. External state (issue #200 body); not in code.
- **CX-P2 — Permissions**: covered by construction. No settings.json changes.
- **AC6, AC7, AC8, AC9** (measurement tables + learnings + rollout issue): not unit-testable. Artifact-inspection-level verification; chore doc contains all four sections and issue #200 exists.

### Summary

- coverage-surplus: 4
- coverage-gap: 19

The high gap count reflects a deliberate scope boundary: the pilot installs a **documentation-only** contract, and most scenarios in the test plan were authored assuming a parser would be added. The parser is explicitly deferred to the rollout chore (tracked in #200). The gap list here is the authoritative input for what the rollout needs to add — if the rollout keeps the contract advisory (no parser), these scenarios stay descoped; if the rollout adds a parser, these scenarios become the starting acceptance criteria for the parser's tests.
