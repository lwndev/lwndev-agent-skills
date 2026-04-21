---
id: CHORE-035
version: 2
timestamp: 2026-04-21T19:43:15Z
verdict: PASS
persona: qa
---

## Summary

Executed 47 adversarial tests against the CHORE-035 SKILL.md compression + reference-file relocation; every test passed, covering inline-pointer integrity, consolidated-table row preservation, state-file step-index invariance, and CHORE-034 carve-out / fork-return-contract preservation.

## Capability Report

- Mode: test-framework
- Framework: vitest
- Package manager: npm
- Test command: npm test
- Language: typescript

Capability report reused from `/tmp/qa-capability-CHORE-035.json` (mtime 2026-04-21T18:36:23Z, within the one-hour freshness window). No drift from the plan's embedded capability report.

## Execution Results

- Total: 1122
- Passed: 1122
- Failed: 0
- Errored: 0
- Exit code: 0
- Duration: 43.04s
- Test files: [scripts/__tests__/qa-CHORE-035.spec.ts]

The qa-CHORE-035 spec contributes 47 new tests; the remaining 1075 are the pre-existing suite, re-run to confirm the CHORE-035 edits introduced zero regressions (P0 Environment scenario from the plan).

## Scenarios Run

| ID | Dimension | Priority | Result | Test file |
|----|-----------|----------|--------|-----------|
| I-1 | Inputs | P0 | PASS | scripts/__tests__/qa-CHORE-035.spec.ts — "every `references/*.md` link in SKILL.md points to a file that exists" |
| I-2 | Inputs | P0 | PASS | scripts/__tests__/qa-CHORE-035.spec.ts — "both newly created reference files exist and are non-empty" |
| I-3 | Inputs | P1 | PASS | scripts/__tests__/qa-CHORE-035.spec.ts — "SKILL.md dispatcher paragraphs each contain exactly one inline pointer to their target reference" |
| I-4 | Inputs | P0 | PASS | scripts/__tests__/qa-CHORE-035.spec.ts — "no sub-skill SKILL.md absolute-path reference in SKILL.md is broken" |
| I-5 | Inputs | P0 | PASS | scripts/__tests__/qa-CHORE-035.spec.ts — consolidated-table row set (13 assertions, one per original row) |
| I-6 | Inputs | P0 | PASS | scripts/__tests__/qa-CHORE-035.spec.ts — "chore skip-condition for step 2 (complexity == low) is captured in the table" |
| I-7 | Inputs | P0 | PASS | scripts/__tests__/qa-CHORE-035.spec.ts — "per-chain deltas note lists all three chain types with their step-count shape" |
| I-8 | Inputs | P0 | PASS | scripts/__tests__/qa-CHORE-035.spec.ts — "forked-steps.md carries the full seven-step fork recipe" |
| I-9 | Inputs | P0 | PASS | scripts/__tests__/qa-CHORE-035.spec.ts — "forked-steps.md carries the prepare-fork.sh invocation snippet with every documented flag" |
| I-10 | Inputs | P0 | PASS | scripts/__tests__/qa-CHORE-035.spec.ts — "forked-steps.md carries the Fork Step-Name Map with every fork site" |
| I-11 | Inputs | P0 | PASS | scripts/__tests__/qa-CHORE-035.spec.ts — "reviewing-requirements-flow.md carries the full Decision Flow plus auto-fix re-run rules" |
| I-12 | Inputs | P0 | PASS | scripts/__tests__/qa-CHORE-035.spec.ts — "reviewing-requirements-flow.md carries the decision-to-call mapping table" |
| I-13 | Inputs | P2 | PASS | scripts/__tests__/qa-CHORE-035.spec.ts — "Baseline Measurements totals row matches sum of individual file rows" |
| I-14 | Inputs | P2 | PASS | scripts/__tests__/qa-CHORE-035.spec.ts — "Post-Change Measurements totals row matches sum of individual file rows" |
| S-1 | State transitions | P0 | PASS | scripts/__tests__/qa-CHORE-035.spec.ts — "chore chain has exactly 7 fixed steps after init" |
| S-2 | State transitions | P0 | PASS | scripts/__tests__/qa-CHORE-035.spec.ts — "bug chain has exactly 7 fixed steps after init" |
| S-3 | State transitions | P0 | PASS | scripts/__tests__/qa-CHORE-035.spec.ts — "feature chain has 5 steps before phases" |
| S-4 | State transitions | P0 | PASS | scripts/__tests__/qa-CHORE-035.spec.ts — "a pre-CHORE-035 chore state file resumes correctly (step-index numbering invariant)" |
| E-1 | Environment | P0 | PASS | scripts/__tests__/qa-CHORE-035.spec.ts — "SKILL.md starts with valid YAML frontmatter" |
| E-2 | Environment | P0 | PASS | scripts/__tests__/qa-CHORE-035.spec.ts — "SKILL.md body is substantially smaller post-relocation" |
| E-3 | Environment | P0 | PASS | scripts/__tests__/qa-CHORE-035.spec.ts — "Output Style section is placed immediately after Quick Start" |
| E-4 | Environment | P0 | PASS | full `npm test` run (1122 / 1122 tests passing) confirms zero behavioral regressions from the SKILL.md + references edits |
| D-1 | Dependency failure | P1 | PASS | scripts/__tests__/qa-CHORE-035.spec.ts — "workflow-state.sh resolve-tier still resolves a fork tier using the current SKILL.md" |
| C-1 | Cross-cutting | P0 | PASS | scripts/__tests__/qa-CHORE-035.spec.ts — CHORE-034 carve-out bullets (7 assertions) |
| C-2 | Cross-cutting | P0 | PASS | scripts/__tests__/qa-CHORE-035.spec.ts — "FR-14 Unicode arrow is retained in the carve-out example" |
| C-3 | Cross-cutting | P0 | PASS | scripts/__tests__/qa-CHORE-035.spec.ts — "ASCII-arrows lite rule still carves out script-emitted structured logs" |
| C-4 | Cross-cutting | P0 | PASS | scripts/__tests__/qa-CHORE-035.spec.ts — "findings display carve-out still forbids truncation" |
| C-5 | Cross-cutting | P0 | PASS | scripts/__tests__/qa-CHORE-035.spec.ts — "all three canonical fork-return contract shapes are still documented" |
| C-6 | Cross-cutting | P0 | PASS | scripts/__tests__/qa-CHORE-035.spec.ts — "contract-precedence sentence is still present" |
| C-7 | Cross-cutting | P0 | PASS | scripts/__tests__/qa-CHORE-035.spec.ts — "reviewing-requirements no-done-contract disambiguation is still present" |
| C-8 | Cross-cutting | P1 | PASS | scripts/__tests__/qa-CHORE-035.spec.ts — "axis 1/2/3 subsection headings remain distinct" |
| C-9 | Cross-cutting | P1 | PASS | scripts/__tests__/qa-CHORE-035.spec.ts — "override-precedence table is preserved (bounded-table carve-out)" |

Exploratory scenarios from the plan (not addressed by `test-framework` mode because they require human judgement, visual inspection, or external-service interaction): pronoun-drop ambiguity reading (I-P1 #2), relocated-section landed in wrong reference file (I-P1 #3), deltas-note-vs-table contradiction (I-P2 #2), resume-mid-upgrade scenario (S-P1 #1), partial-PR-merge scenario (S-P2 #1), end-to-end orchestrator behavioral equivalence (E-P0 #3), measurement reproducibility (E-P1 #1), Anthropic count_tokens endpoint unavailability (E-P1 #2), non-default CLAUDE_PLUGIN_ROOT (E-P2 #1), markdown-renderer differences (E-P2 #2), gh-CLI unavailability during measurement (D-P1 #1), unreadable sub-skill SKILL.md edge case (D-P2 #1), load-bearing carve-out reference-workflow visual check (C-P0 #1b), rollout-scope-drift reviewer check (C-P1 #1), follow-up issue cross-link check (C-P1 #2), over-parameterized table readability (C-P1 #3), permissions audit (C-P2 #1). These are tracked in the plan's `## Scenarios` section but cannot be exercised through the vitest suite.

## Findings

No failing tests. The run is a clean PASS:

- Every `references/*.md` inline pointer in SKILL.md resolves to an existing file.
- Every row the original three chain-step tables conveyed is reachable from the consolidated parameterized table (13 row-preservation assertions passed, including the chore/bug `complexity == low` skip annotation and the per-chain step-count deltas note).
- Both newly created reference files (`forked-steps.md`, `reviewing-requirements-flow.md`) contain the full numbered-recipe content that was relocated out of SKILL.md, including every documented flag and every fork-step-name in the Fork Step-Name Map.
- The CHORE-034 carve-out list, the Output Style section placement, the fork-return contract three canonical shapes, the contract-precedence sentence, the reviewing-requirements no-done-contract disambiguation, and the FR-14 Unicode-arrow format are all preserved verbatim.
- State-file step-index numbering is invariant across the CHORE-035 edits: `chore` and `bug` chains still initialize with exactly 7 steps in the expected order; `feature` chains still initialize with the first 5 steps; a synthetic pre-CHORE-035 chore state file paused at PR review still resumes at `currentStep: 5` with the Execute QA step at the expected index.
- The Baseline and Post-Change measurement tables in the chore document are internally consistent (totals rows match the sum of individual file rows).

## Reconciliation Delta

Requirements document: `requirements/chores/CHORE-035-input-token-optimization-pilot.md` (resolved via `resolve-requirement-doc.sh`).

### Coverage beyond requirements

- **FR-14 Unicode-arrow carve-out regression guard** — the chore's acceptance criteria require carve-outs to be preserved verbatim, but do not call out the FR-14 arrow specifically. The test (`C-2`) guards the exact U+2192 character in the carve-out example that CHORE-034's code-review fix pinned as a pre-merge blocker; this is additional defensive coverage beyond the spec.
- **State-file step-index invariance under resume** — the plan's `S-P0` row explicitly named this scenario but the chore's acceptance criteria only require "existing workflow state files still resume correctly" implicitly (via "All internal SKILL.md anchors and cross-skill references still resolve" + the "preserved verbatim" clauses). The four `State transitions` tests (`S-1`…`S-4`) are tighter than the AC wording.
- **Model-Selection axis headings** — `C-8` and `C-9` pin the `### Axis 1/2/3` heading text and the override-precedence table. Not called out in the spec's ACs; added because the chore-doc Learnings subsection flagged these as load-bearing test anchors that tripped an early compression pass.
- **Reference-file prepare-fork-flag completeness** — `I-9` asserts that every documented flag (`--mode`, `--phase`, `--cli-model`, `--cli-complexity`, `--cli-model-for`) survives the relocation into `forked-steps.md`. The ACs require "every relocated section retains a single-sentence inline pointer" but do not require flag-level completeness of the relocated content; this is additional confidence that the relocation is lossless.
- **Decision-to-call mapping token completeness** — `I-12` asserts that every decision token (`advanced`, `auto-advanced`, `user-advanced`, `paused`, `auto-fixed`) is present in the relocated mapping table. Same rationale as the prepare-fork-flag test.

### Coverage gaps

- **AC: Learnings subsection structure** — the acceptance criterion requires the Learnings subsection to list (a) mechanical vs judgement edits, (b) carve-outs that mattered, (c) pitfalls, (d) template patterns. The qa suite does not assert the subsection structure. Visual inspection confirms the chore doc contains all four buckets, but no automated guard exists.
- **AC: Follow-up rollout issue cross-links** — the acceptance criterion requires the follow-up issue to cross-link CHORE-035, the Learnings subsection, and the sibling CHORE-034 rollout issue #200. Verification requires a live `gh` call to issue #203; the qa suite does not exercise this (documented as a cross-cutting `C-P1` exploratory in the plan).
- **AC: Delta-table arithmetic** — the chore document's Delta subsection reports per-file `Δ` and `%` columns derived from pre/post differences. The qa suite verifies Baseline and Post totals are internally consistent (sum of rows matches totals row) but does not cross-check the Delta table's arithmetic (e.g., `post_lines - pre_lines == delta_lines`). This is a minor gap; the Baseline and Post checks already guard the underlying numbers.
- **AC: "no non-dispatcher section exceeds ~25 lines"** — the acceptance criterion operationalizes the thin-dispatcher intent as a line-count ceiling. The qa suite asserts overall SKILL.md length (< 30000 chars via `E-2`) but not per-section line counts. Adding a per-section assertion would be fragile (section boundaries shift with edits); the overall size floor is a reasonable proxy.
- **P0 Environment #3 ("Orchestrator behavior unchanged end-to-end for a reference workflow run on both sides of the merge")** — listed explicitly in the plan as `exploratory`. Impossible to automate cleanly from this suite because it requires running a full feature and chore workflow end-to-end on `main` vs the branch and diffing the artifacts. Manual spot-check: the CHORE-035 workflow itself advanced cleanly through every chore-chain step (steps 1 → 5 paused at PR review, now step 6), and the state file at `.sdlc/workflows/CHORE-035.json` shows the expected step names and indices.

### Summary

- coverage-surplus: 5
- coverage-gap: 5

---

*This run was executed from the orchestrator's main context as feature-chain-equivalent step 6 (chore-chain) of CHORE-035 itself — a self-referential QA pass where the skill whose instruction surface was just compressed is exercising its own regression suite. The reference-workflow behavioral equivalence claim in the plan's `P0 Environment #3` is therefore partially demonstrated by this very execution: the orchestrator still resumed from `pr-review`, ran `executing-qa` in main context, and emitted this v2 artifact without structural deviation from prior CHORE runs.*
