# Implementation Plan: Consolidate executing-qa scripted producers, agent replacement, and report-only enforcement

## Overview

FEAT-030 consolidates three overlapping issues against the same `executing-qa` surface (#187 scripted producers, #192 agent script replacement, #208 report-only enforcement) into one feature shipping in six phases that lock the QA return contract first, then build producer scripts to that contract, then replace the legacy agents, then add the stop-hook diff guard, then persist QA findings to workflow-state and parse the contract in the orchestrator, then rewrite SKILL.md so every new script has a caller and the explicit non-remediation rule lands. The data path is single and end-to-end: test-runner output -> producer script -> versioned artifact -> workflow-state findings block -> orchestrator. The contract document (FR-1) is the spine that every subsequent phase satisfies; producers ship contract-shaped from day one, the persister and parser key on the same contract, and SKILL.md adoption (FR-2 + FR-13) wires every Phase-2 script into the skill body so no script ships without a caller.

The build order mirrors issue #242's "Build order" section verbatim. Phase 2 ships six producer scripts with bats coverage in a single phase (intentional clamp via `**ComplexityOverride:** opus` — the contract is locked, the scripts are independent, and splitting them across phases would multiply merge-conflict surface against the same SKILL.md and the same `executing-qa/scripts/` directory). Phase 6 carries SKILL.md rewrites for `executing-qa`, `executing-chores`, `executing-bug-fixes`, plus the regression-test fixture against a known-buggy branch — also a clamped opus phase by intent. The remaining four phases stay inside the standard per-phase budget. The non-remediation rule (FR-2) lands in Phase 6 alongside the SKILL.md rewrite because the rule is a SKILL.md edit and naturally pairs with the prose-replacement work.

## Features Summary

| Feature ID | GitHub Issue | Feature Document | Priority | Complexity | Status |
|------------|--------------|------------------|----------|------------|--------|
| FEAT-030 | [#242](https://github.com/lwndev/lwndev-marketplace/issues/242) | [FEAT-030-consolidate-executing-qa-scripted.md](../features/FEAT-030-consolidate-executing-qa-scripted.md) | High | High | Pending |

## Recommended Build Sequence

### Phase 1: Lock the QA return contract (FR-1)

**Feature:** [FEAT-030](../features/FEAT-030-consolidate-executing-qa-scripted.md) | [#242](https://github.com/lwndev/lwndev-marketplace/issues/242)
**Status:** ✅ Complete
**Depends on:** none

#### Rationale

Issue #242's build-order section mandates the contract land before any producer code. Three downstream surfaces key on it independently: Phase 2's six producer scripts emit artifacts shaped to the contract, Phase 5's `record-qa-findings` persists the contract's findings JSON, Phase 5's orchestrator parser regex-matches the contract's final-message line. Locking the contract first means every downstream phase consumes a stable spec instead of inventing one ad hoc and reconciling later. This phase produces zero executable code by design — the deliverable is a single reference document under `executing-qa/references/qa-return-contract.md` plus an explicit cross-reference from `executing-qa/SKILL.md`'s `## References` section. SKILL.md prose changes beyond that cross-reference are deferred to Phase 6.

The contract has three parts that must all be specified before Phase 2 ships: (1) the artifact frontmatter fields and required sections (already enforced by the existing stop-hook; this requirement formalizes it), (2) the final-message line shape `Verdict: <V> | Passed: <N> | Failed: <N> | Errored: <N>` that the orchestrator parses inline after the skill returns, and (3) the workflow-state `findings` JSON shape `{verdict, passed, failed, errored, summary}` that `record-qa-findings` persists. All three appear in one document so producers, persister, and parser cite a single source of truth.

#### Implementation Steps

1. Write `plugins/lwndev-sdlc/skills/executing-qa/references/qa-return-contract.md` with three top-level sections:
   - `## Artifact Schema` — frontmatter table (`id`, `version: 2`, `timestamp`, `verdict` enum `PASS|ISSUES-FOUND|ERROR|EXPLORATORY-ONLY`, `persona: qa`); required sections list (`## Summary`, `## Capability Report`, `## Execution Results`, `## Scenarios Run`, `## Findings`, `## Reconciliation Delta`, plus `## Exploratory Mode` when verdict is `EXPLORATORY-ONLY`); per-verdict structural rules (`Failed: 0` and empty `## Findings` for PASS, failing-test names listed under `## Findings` for ISSUES-FOUND, stack-trace passthrough for ERROR, `Reason:` line under `## Exploratory Mode` for EXPLORATORY-ONLY).
   - `## Final-Message Line` — exact format `Verdict: <PASS|ISSUES-FOUND|ERROR|EXPLORATORY-ONLY> | Passed: <int> | Failed: <int> | Errored: <int>`; emitted as the **final line** of the `executing-qa` skill response; counts are `Passed: 0 | Failed: 0 | Errored: 0` for `EXPLORATORY-ONLY`; document the regex that the orchestrator parses (`^Verdict: (PASS|ISSUES-FOUND|ERROR|EXPLORATORY-ONLY) \| Passed: ([0-9]+) \| Failed: ([0-9]+) \| Errored: ([0-9]+)$`).
   - `## Workflow-State Findings JSON` — exact JSON shape (`verdict`, `passed`, `failed`, `errored`, `summary` with single-line summary derived from artifact `## Summary` plus an artifact-path pointer); persisted on the QA step entry by `record-qa-findings` (FR-11); document the parent-key location (`steps[<index>].findings`).

2. Add a single cross-reference line to `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md`'s `## References` section (or create the section if absent): `- [QA return contract](references/qa-return-contract.md) — artifact schema, final-message line, workflow-state findings JSON.` Do not edit any other SKILL.md prose this phase.

3. Run `npm run validate` to confirm the new reference file does not break skill validation.

#### Deliverables

- [x] `plugins/lwndev-sdlc/skills/executing-qa/references/qa-return-contract.md`
- [x] `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` — single-line cross-reference under `## References` (no other SKILL.md edits this phase)

---

### Phase 2: Producer scripts (FR-3 through FR-8)

**Feature:** [FEAT-030](../features/FEAT-030-consolidate-executing-qa-scripted.md) | [#242](https://github.com/lwndev/lwndev-marketplace/issues/242)
**Status:** ✅ Complete
**Depends on:** Phase 1
**ComplexityOverride:** opus

#### Rationale

The six producer scripts (FR-3 through FR-8) all live under `plugins/lwndev-sdlc/skills/executing-qa/scripts/`, all consume or emit pieces of the Phase-1 contract, and all replace prose in the same future SKILL.md rewrite (Phase 6). Splitting them across multiple phases would multiply merge-conflict surface against the same directory and the same SKILL.md, and would force Phase 6's prose-replacement to land before all six scripts exist (violating FR-13's "no script ships without a caller in the same PR" guarantee). Bundling them into one clamped opus phase trades a single large review for several rounds of conflicting renames.

Each script is independent in implementation and ships with a `*.bats` sibling. None call each other directly — `executing-qa` SKILL.md (rewritten in Phase 6) is the orchestrator. `qa-reconcile-delta.sh` (FR-6) is the **single shared implementation** also called by `reviewing-requirements` test-plan reconciliation mode (NFR-6); the script lives under `executing-qa/scripts/` and `reviewing-requirements` invokes the same path.

**Implementation choices** (per requirements doc edge case 7 and elsewhere) deferred to plan time and decided here for the producer phase: `qa-reconcile-delta.sh` lives under `executing-qa/scripts/` (single canonical location); `reviewing-requirements` invokes via the absolute `${CLAUDE_PLUGIN_ROOT}/skills/executing-qa/scripts/qa-reconcile-delta.sh` path; no symlink or wrapper indirection.

#### Implementation Steps

1. Write `plugins/lwndev-sdlc/skills/executing-qa/scripts/capability-report-diff.sh` (FR-3): args `<plan-file> <fresh-json>`; emits stdout JSON `{drift: bool, fields: [{field, planValue, freshValue}]}`; exits `0` on success, `2` on missing/invalid args. Compares the capability report embedded in the plan's frontmatter to a fresh capability JSON.

2. Write `plugins/lwndev-sdlc/skills/executing-qa/scripts/check-branch-diff.sh` (FR-4): no args; runs `git diff main...HEAD`; exits `0` non-empty diff, `1` empty diff (caller emits ERROR verdict with `Reason: no changes to test relative to main`).

3. Write `plugins/lwndev-sdlc/skills/executing-qa/scripts/run-framework.sh` (FR-5): args `<capability-json> <test-file-glob>`; runs the framework's `testCommand` with the supplied test files; captures stdout, stderr, exit code, wall-clock duration; emits stdout JSON `{total, passed, failed, errored, failingNames, truncatedOutput, exitCode, durationMs}`; supports vitest, jest, pytest, go test (matching `capability-discovery.sh`); exits `0` runner ran (counts may indicate failures), `1` runner could not start (caller emits ERROR), `2` missing/invalid args.

4. Write `plugins/lwndev-sdlc/skills/executing-qa/scripts/qa-reconcile-delta.sh` (FR-6, also satisfies #192 item 11.2): args `<results-doc> <requirements-doc>`; bidirectional `FR-N` / `NFR-N` / `AC` / edge-case parsing on both sides; matches by substring + identifier; emits the markdown for the `## Reconciliation Delta` section (`### Coverage beyond requirements`, `### Coverage gaps`, `### Summary` with `coverage-surplus: N` / `coverage-gap: N` lines); exits `0` delta produced, `1` requirements doc not found (caller emits skip-with-reason under `### Summary`), `2` missing/invalid args. The `qa-reconciliation-agent.md` reference spec becomes this script's behavioral test matrix.

5. Write `plugins/lwndev-sdlc/skills/executing-qa/scripts/render-qa-results.sh` (FR-7): args `<ID> <verdict> <capability-json> <execution-json>`; writes `qa/test-results/QA-results-{ID}.md` with the Phase-1 contract's frontmatter and required sections; satisfies the per-verdict structural rules by construction (`Failed: 0` for PASS, failing-test names for ISSUES-FOUND, stack-trace passthrough for ERROR, `Reason:` line for EXPLORATORY-ONLY); exits `0` artifact written, `1` invalid verdict / missing required field, `2` missing/invalid args.

6. Write `plugins/lwndev-sdlc/skills/executing-qa/scripts/commit-qa-tests.sh` (FR-8): args `<ID> <test-files...>`; stages and commits the test files with canonical message `qa({ID}): add executable QA tests from executing-qa run`; exits `0` committed, `1` no files to commit (info message; caller continues), `2` missing/invalid args.

7. Write `plugins/lwndev-sdlc/skills/executing-qa/scripts/tests/capability-report-diff.bats`, `check-branch-diff.bats`, `run-framework.bats`, `qa-reconcile-delta.bats`, `render-qa-results.bats`, `commit-qa-tests.bats`. Each covers happy path, every documented exit code, and edge cases (capability drift, empty diff, missing requirements doc, missing test framework, EXPLORATORY-ONLY verdict path for `render-qa-results.sh`, no-files-to-commit for `commit-qa-tests.sh`). Use the PATH-shadowing fixture pattern from `plugins/lwndev-sdlc/scripts/tests/prepare-fork.bats`.

8. Run all six bats fixtures locally (`bats plugins/lwndev-sdlc/skills/executing-qa/scripts/tests/`). Run `npm test -- --testPathPatterns=executing-qa | tail -80` and `npm run validate` to confirm zero regressions. Confirm no SKILL.md edits beyond the Phase-1 cross-reference (Phase 6 owns SKILL.md rewrite).

#### Deliverables

- [x] `plugins/lwndev-sdlc/skills/executing-qa/scripts/capability-report-diff.sh`
- [x] `plugins/lwndev-sdlc/skills/executing-qa/scripts/check-branch-diff.sh`
- [x] `plugins/lwndev-sdlc/skills/executing-qa/scripts/run-framework.sh`
- [x] `plugins/lwndev-sdlc/skills/executing-qa/scripts/qa-reconcile-delta.sh`
- [x] `plugins/lwndev-sdlc/skills/executing-qa/scripts/render-qa-results.sh`
- [x] `plugins/lwndev-sdlc/skills/executing-qa/scripts/commit-qa-tests.sh`
- [x] `plugins/lwndev-sdlc/skills/executing-qa/scripts/tests/capability-report-diff.bats`
- [x] `plugins/lwndev-sdlc/skills/executing-qa/scripts/tests/check-branch-diff.bats`
- [x] `plugins/lwndev-sdlc/skills/executing-qa/scripts/tests/run-framework.bats`
- [x] `plugins/lwndev-sdlc/skills/executing-qa/scripts/tests/qa-reconcile-delta.bats`
- [x] `plugins/lwndev-sdlc/skills/executing-qa/scripts/tests/render-qa-results.bats`
- [x] `plugins/lwndev-sdlc/skills/executing-qa/scripts/tests/commit-qa-tests.bats`

---

### Phase 3: Replace the QA agents (FR-9)

**Feature:** [FEAT-030](../features/FEAT-030-consolidate-executing-qa-scripted.md) | [#242](https://github.com/lwndev/lwndev-marketplace/issues/242)
**Status:** ✅ Complete
**Depends on:** Phase 2

#### Rationale

This phase closes #192 by replacing the two QA-related agents (`qa-verifier`, `qa-reconciliation-agent`) with scripts. `qa-reconcile-delta.sh` is reused from Phase 2 (single shared implementation per NFR-6); the only new script is `qa-verify-coverage.sh` (FR-9). Phase 3 depends on Phase 2 because the agent-replacement decision (delete vs. wrap) and the cross-reference updates downstream require both scripts to exist.

**Implementation choice** (per requirements doc FR-9 deferred decision and edge case 7) decided here at plan time: **delete both agent files**. Rationale: the agents exist only to be invoked from `executing-qa` SKILL.md (rewritten in Phase 6) and from `reviewing-requirements` test-plan reconciliation mode; both call sites move to the scripts in this PR; keeping the agents as wrappers adds an extra indirection layer with no caller benefit, and per the project's "scripts over prose" convention agent prose is the same prose-cost the move-to-scripts is meant to eliminate. SKILL.md and `references/` cross-references to the deleted agents are updated in Phase 6 alongside the SKILL.md rewrite.

#### Implementation Steps

1. Write `plugins/lwndev-sdlc/skills/executing-qa/scripts/qa-verify-coverage.sh` (FR-9): args `<artifact-path>`; parses scenarios per dimension; validates priority (`P0|P1|P2`) and execution mode (`test-framework|exploratory`); checks the empty-findings directive (FR-6, FR-8 of QA reference); checks no-spec drift (`FR-\d+` / `AC-\d+` / `NFR-\d+` tokens in plan `## Scenarios`); emits stdout JSON `{verdict: COVERAGE-ADEQUATE|COVERAGE-GAPS, perDimension: [{dimension, status, scenarioCount}], gaps: [...]}`; exits `0` JSON emitted regardless of verdict, `2` missing/invalid args. The `agents/qa-verifier.md` reference spec becomes this script's bats test matrix.

2. Write `plugins/lwndev-sdlc/skills/executing-qa/scripts/tests/qa-verify-coverage.bats`: happy path COVERAGE-ADEQUATE; happy path COVERAGE-GAPS with named gaps; per-dimension status enumeration (covered / justified / missing); priority enum violation; execution-mode enum violation; empty-findings directive violation; no-spec drift detection; missing artifact path → exit `2`. Use the PATH-shadowing fixture pattern.

3. Delete `plugins/lwndev-sdlc/agents/qa-verifier.md` and `plugins/lwndev-sdlc/agents/qa-reconciliation-agent.md`. Confirm no remaining `executing-qa` SKILL.md or other plugin file references the deleted agents (run `grep -rn 'qa-verifier\|qa-reconciliation-agent' plugins/lwndev-sdlc/` and update any stragglers; SKILL.md cross-reference updates are deferred to Phase 6's rewrite).

4. Run `bats plugins/lwndev-sdlc/skills/executing-qa/scripts/tests/qa-verify-coverage.bats` locally. Run `npm test -- --testPathPatterns=executing-qa | tail -50` and `npm run validate` to confirm zero regressions and that the agent deletions do not break plugin validation.

#### Deliverables

- [x] `plugins/lwndev-sdlc/skills/executing-qa/scripts/qa-verify-coverage.sh`
- [x] `plugins/lwndev-sdlc/skills/executing-qa/scripts/tests/qa-verify-coverage.bats`
- [x] `plugins/lwndev-sdlc/agents/qa-verifier.md` (deleted)
- [x] `plugins/lwndev-sdlc/agents/qa-reconciliation-agent.md` (deleted)

---

### Phase 4: Stop-hook diff guard (FR-10)

**Feature:** [FEAT-030](../features/FEAT-030-consolidate-executing-qa-scripted.md) | [#242](https://github.com/lwndev/lwndev-marketplace/issues/242)
**Status:** ✅ Complete
**Depends on:** Phase 1

#### Rationale

The stop-hook diff guard (FR-10) closes #208 scope item 2 — it blocks the run when `executing-qa` modifies files outside the framework's test root, which is the correctness defect that motivated the entire consolidation. This phase depends on Phase 1 (the contract specifies which artifact paths are always allowed: `qa/test-results/QA-results-{ID}.md` and `qa/test-plans/QA-plan-{ID}.md`) but is **independent of Phases 2 and 3** — the guard reads `git status --porcelain` and the capability JSON, not any of the new producer scripts. Landing it as soon as Phase 1 is in lets the guard catch regressions during Phase 2 / Phase 3 development.

**Implementation choice** (per requirements doc edge case 4) decided here at plan time: capture HEAD at skill start in a session marker file (`.sdlc/qa/.executing-qa-baseline-{ID}`) and compute the diff via `git diff <baseline-commit>` so pre-existing uncommitted changes outside the test root do not produce false positives. Rationale: the marker is the simplest baseline (no `git stash` side effects, no extra commits); the file is per-ID so concurrent QA runs against different IDs do not clobber each other; cleanup happens at hook exit (success or failure).

#### Implementation Steps

1. Extend `plugins/lwndev-sdlc/skills/executing-qa/scripts/stop-hook.sh` per FR-10: derive the framework test root from the capability JSON (e.g., `__tests__/`, `tests/`, `*_test.go` patterns); read `.sdlc/qa/.executing-qa-baseline-{ID}` for the start-of-skill HEAD; compute `git diff <baseline> -- ':!<test-root>' ':!qa/test-results/QA-results-*.md' ':!qa/test-plans/QA-plan-*.md'`; if the diff is non-empty, fail the hook with the FR-10 error message format verbatim:
   ```
   Stop hook: executing-qa modified production files outside the framework test root '<test-root>': <file1>, <file2>. QA is report-only; do not edit production code to make tests pass. Revert these files and add the issue to ## Findings.
   ```
   Pure additions inside the test root, modifications to existing test files inside the test root, and edits to `qa/test-results/QA-results-{ID}.md` / `qa/test-plans/QA-plan-{ID}.md` are always allowed.

2. Add the baseline-marker write at skill start (in `executing-qa/scripts/stop-hook.sh` start-of-session path or a new sibling helper invoked from SKILL.md's setup step — pick the simpler call site; the SKILL.md wiring is finalized in Phase 6). Marker contents: single line containing the output of `git rev-parse HEAD` at skill start. Cleanup: remove the marker at hook exit (both success and failure paths).

3. Write or extend `plugins/lwndev-sdlc/skills/executing-qa/scripts/tests/stop-hook.bats` with the FR-10 cases: pure additions inside test root allowed (new `qa-*.spec.ts`, `test_qa_*.py`, `qa_*_test.go` files); modifications to existing test files inside test root allowed; edits outside test root blocked with the verbatim FR-10 error message; QA artifacts (`qa/test-results/QA-results-{ID}.md`, `qa/test-plans/QA-plan-{ID}.md`) always allowed; pre-existing uncommitted changes outside test root NOT blocked (baseline-marker behavior); missing baseline marker → fail closed with explicit error.

4. Run `bats plugins/lwndev-sdlc/skills/executing-qa/scripts/tests/stop-hook.bats` locally. Run `npm test -- --testPathPatterns=executing-qa | tail -50` and `npm run validate` to confirm zero regressions.

#### Deliverables

- [x] `plugins/lwndev-sdlc/skills/executing-qa/scripts/stop-hook.sh` (extended with FR-10 diff guard + baseline marker)
- [x] `plugins/lwndev-sdlc/skills/executing-qa/scripts/qa-baseline.sh` (Option B sibling script: `init <ID>` / `clear <ID>`)
- [x] `plugins/lwndev-sdlc/skills/executing-qa/scripts/tests/stop-hook.bats` (FR-10 test cases: 9 tests)
- [x] `plugins/lwndev-sdlc/skills/executing-qa/scripts/tests/qa-baseline.bats` (8 tests)

---

### Phase 5: Workflow-state QA findings + orchestrator parser (FR-11, FR-12, FR-14)

**Feature:** [FEAT-030](../features/FEAT-030-consolidate-executing-qa-scripted.md) | [#242](https://github.com/lwndev/lwndev-marketplace/issues/242)
**Status:** 🔄 In Progress
**Depends on:** Phase 1

#### Rationale

This phase closes #208 scope items 3, 4, and the related orchestrator documentation. It depends only on Phase 1 (the contract specifies the JSON shape persisted by FR-11 and the regex parsed by FR-12) — independent of Phases 2, 3, 4. Three deliverables ship together because they are the full persist-and-document loop on the orchestrator side: the state subcommand persists, the orchestrator parses and calls the subcommand, the SKILL.md documents the parse path. Splitting them across phases would leave a half-built path between merges (the contract is parsed but not persisted, or vice versa).

**Implementation choices** decided here at plan time:
- **FR-11 (per requirements doc deferred decision)**: generalize the existing `record-findings` subcommand to accept a `--type qa` flag, rather than adding a new `record-qa-findings` subcommand. Rationale: the `findings` block on the QA step entry has the same structural location (`steps[<index>].findings`) as the `reviewing-requirements` `findings` block, only the inner shape differs; one subcommand with a `--type` discriminator keeps `workflow-state.sh`'s surface narrower and makes the shape-per-type table visible in one place. Existing `record-findings` callers (the `reviewing-requirements` step) continue to work unchanged because `--type` defaults to `review` (the existing shape).
- **FR-12 parse location**: a new sibling script `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/parse-qa-return.sh` owns the regex match and emits the parsed `{verdict, passed, failed, errored, summary}` to stdout as JSON (or fails with a contract-mismatch error). The orchestrator SKILL.md (and any orchestrator-driving script) shells out to this script and pipes the result into `record-findings --type qa`. Keeps the regex testable in bats rather than hidden in SKILL.md prose.

#### Implementation Steps

1. Generalize `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh` `record-findings` subcommand to accept `--type qa|review` (default `review`). For `--type qa`, accept positional args `<ID> <stepIndex> <verdict> <passed> <failed> <errored> <summary>`; validate verdict against the FR-1 enum; validate counts as non-negative integers; persist `{verdict, passed, failed, errored, summary}` to `.sdlc/workflows/{ID}.json` at `steps[<stepIndex>].findings`. Exits `0` recorded, `1` workflow not found / step not a QA step / verdict enum violation, `2` missing/invalid args. NFR-1: must continue to load existing FEAT-029 and earlier workflow state files that lack the `findings` block on QA steps.

2. Write `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/parse-qa-return.sh` (FR-12): args `<final-message-text>` (or `--stdin` to read the full skill response from stdin and grep the final line); applies the FR-1 regex `^Verdict: (PASS|ISSUES-FOUND|ERROR|EXPLORATORY-ONLY) \| Passed: ([0-9]+) \| Failed: ([0-9]+) \| Errored: ([0-9]+)$`; on match, emits stdout JSON `{verdict, passed, failed, errored, summary}` where `summary` is derived from the artifact `## Summary` section (artifact path passed via `--artifact <path>` flag); on mismatch, emits stderr `error: contract mismatch: expected '<regex>'; got: '<actual>'` and exits `1`. Exit codes: `0` parsed, `1` mismatch, `2` missing/invalid args.

3. Add bats coverage:
   - `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/tests/workflow-state-record-findings-qa.bats` — happy-path persist for each verdict enum value; reject malformed verdict; reject non-integer counts; reject missing required arg; NFR-1 backward-compatibility test (load a pre-FEAT-030 fixture lacking the `findings` block; subsequent `record-findings --type qa` adds it without error).
   - `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/tests/parse-qa-return.bats` — happy-path parse for each verdict enum value; rejection on missing pipe separators; rejection on non-numeric counts; rejection on lowercase verdict; rejection on extra trailing text; happy-path with `--artifact` flag deriving `summary` from `## Summary`.

4. Update `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` (FR-14): add a section under `### Main-Context Steps` (or the appropriate existing section) documenting that the `executing-qa` step is a main-context step; immediately after the skill returns, the orchestrator runs `parse-qa-return.sh --stdin --artifact <path>` against the skill output; on success, calls `workflow-state.sh record-findings --type qa <ID> <stepIndex> <verdict> <passed> <failed> <errored> "<summary>"`; on mismatch, halts the workflow with the contract-mismatch error (lite-narration carve-out: surface verbatim). Both calls happen **before** `advance`. Per the FR-12 verbatim text, the orchestrator does not change advance behavior based on verdict — verdict-based gating is out of scope.

5. Run `bats plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/tests/workflow-state-record-findings-qa.bats` and `bats plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/tests/parse-qa-return.bats` locally. Run `npm test -- --testPathPatterns=orchestrating-workflows | tail -60` and `npm run validate` to confirm zero regressions and that NFR-1 backward-compatibility holds.

#### Deliverables

- [x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh` (generalized `record-findings` with `--type qa|review`)
- [x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/parse-qa-return.sh`
- [x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/tests/workflow-state-record-findings-qa.bats`
- [x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/tests/parse-qa-return.bats`
- [x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` (FR-14 parse-path documentation)

---

### Phase 6: SKILL.md adoption + non-remediation rule + regression test (FR-2, FR-13, NFR-5)

**Feature:** [FEAT-030](../features/FEAT-030-consolidate-executing-qa-scripted.md) | [#242](https://github.com/lwndev/lwndev-marketplace/issues/242)
**Status:** Pending
**Depends on:** Phase 2, Phase 3, Phase 4, Phase 5
**ComplexityOverride:** opus

#### Rationale

Phase 6 wires every Phase-2 producer script into `executing-qa` SKILL.md (FR-13's "no script ships without a caller in the same PR" guarantee), adds the explicit non-remediation rule (FR-2), updates Quick Start and verification checklist, updates `executing-chores` / `executing-bug-fixes` and other cross-references to the deleted agents (Phase 3), and ships the regression-test fixture against a known-buggy branch (NFR-5 acceptance criterion). It depends on every prior phase by construction — the SKILL.md rewrite cites scripts shipped in Phases 2, 3, 4, and 5; the regression test exercises the full end-to-end path.

The SKILL.md rewrite carries opus complexity by intent: each of the six existing prose steps is replaced by a script invocation; the verification checklist is updated; the non-remediation rule lands prominently (top of skill body or a dedicated `## Report-Only Mode` section, referenced from Step 4 verdict-derivation and the verification checklist); and three sibling skills (`executing-chores`, `executing-bug-fixes`, `reviewing-requirements`) get cross-reference updates for the agent deletions and the shared `qa-reconcile-delta.sh` invocation. The regression-test fixture sits in this phase rather than Phase 2 because it requires the stop-hook diff guard (Phase 4), the workflow-state persistence (Phase 5), and the rewritten SKILL.md (this phase) all in place.

**Test framework note** (per requirements doc): repo test framework is currently vitest-only. The regression test ships as a vitest test that drives the end-to-end QA workflow against a fixture branch under `tests/fixtures/feat-030-known-buggy/`, asserts the four NFR-5 outcomes (verdict `ISSUES-FOUND`, named failing tests in Findings, no production-file modifications, workflow-state JSON contains the FR-1 `findings` block), and a negative variant that confirms the FR-10 stop-hook blocks a simulated production-file edit.

#### Implementation Steps

1. Rewrite `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` per FR-13: each of the six steps that newly has a Phase-2 script invokes the script and removes the equivalent prose. Step 1 (capability drift) calls `capability-report-diff.sh`; Step 4 (run framework) calls `run-framework.sh` and `commit-qa-tests.sh`; the edge-case-5 clean-branch path calls `check-branch-diff.sh`; Step 6 (reconciliation) calls `qa-reconcile-delta.sh`; Step 7 (artifact emission) calls `render-qa-results.sh`; the agent-equivalent coverage check calls `qa-verify-coverage.sh` (Phase 3). Update `## Quick Start` to reference the scripts. Update the verification checklist to reference the scripts and the FR-2 non-remediation rule. Apply Caveman Lite prose throughout per repo authoring convention; load-bearing carve-outs (error messages, the FR-2 rule body, the final-message-line contract echo) stay verbatim.

2. Add the FR-2 non-remediation rule prominently to `executing-qa` SKILL.md: dedicated `## Report-Only Mode` section near the top of the skill body, containing the verbatim text from FR-2:
   > Do not edit production code to make tests pass. Adversarial QA reports; it does not patch. If a finding suggests a fix, name the fix in `## Findings` and let `executing-bug-fixes` / `executing-chores` handle it in a follow-up run.
   Reference the rule from the Step 4 verdict-derivation step ("see ## Report-Only Mode") and from the verification checklist.

3. Add the FR-1 final-message-line emission instruction to `executing-qa` SKILL.md as the last step of the skill body (analogous to other skills' fork-to-orchestrator return contract): emit the `Verdict: <V> | Passed: <N> | Failed: <N> | Errored: <N>` line as the **final line** of the skill response. Cite `references/qa-return-contract.md`.

4. Update `plugins/lwndev-sdlc/skills/executing-chores/SKILL.md`, `plugins/lwndev-sdlc/skills/executing-bug-fixes/SKILL.md`, and `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` cross-references: any reference to the deleted `qa-verifier` or `qa-reconciliation-agent` agents redirects to the corresponding script (`qa-verify-coverage.sh` or `qa-reconcile-delta.sh`); `reviewing-requirements` test-plan reconciliation mode invokes `qa-reconcile-delta.sh` at its absolute path. No other prose changes to these three skills this phase.

5. Build the regression-test fixture at `tests/fixtures/feat-030-known-buggy/` — a minimal repo snapshot (vitest project, capability JSON, plan + requirements docs, a deliberately failing test, a known-buggy production file) used as input to the regression vitest. Document the fixture's intended verdict and findings in a sibling `README.md`.

6. Write `tests/regression/feat-030-executing-qa.test.ts` (vitest): drives `executing-qa` end-to-end against the Phase-6 fixture; asserts (a) verdict is `ISSUES-FOUND`, (b) `## Findings` names the failing tests from the fixture, (c) `git status` after the run shows no modifications outside the framework test root, (d) `.sdlc/workflows/{ID}.json` `steps[<qa-index>].findings` contains the FR-1 shape, (e) the stop-hook does not block. Negative variant: simulate the pre-FEAT-030 misbehavior (the skill edits a fixture production file) and assert the FR-10 stop-hook blocks with the verbatim error message.

7. Run `bats plugins/lwndev-sdlc/skills/executing-qa/scripts/tests/` and `bats plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/tests/` locally to confirm Phase 2–5 coverage still passes after SKILL.md rewrite. Run `npm test -- --testPathPatterns=feat-030-executing-qa | tail -80` to confirm the regression vitest passes. Run `npm test | tail -120` and `npm run validate` to confirm zero regressions across the repo.

8. Confirm acceptance: every Phase-2 script has a caller in `executing-qa` SKILL.md (grep the SKILL.md for each script name); the FR-2 rule is reachable from Step 4 and the verification checklist; the regression vitest passes; the negative-regression vitest passes (stop-hook blocks the simulated misbehavior).

#### Deliverables

- [ ] `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` (full rewrite per FR-13 + FR-2 non-remediation rule + FR-1 final-message-line emission)
- [ ] `plugins/lwndev-sdlc/skills/executing-chores/SKILL.md` (cross-reference updates for deleted agents)
- [ ] `plugins/lwndev-sdlc/skills/executing-bug-fixes/SKILL.md` (cross-reference updates for deleted agents)
- [ ] `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` (test-plan reconciliation mode cites shared `qa-reconcile-delta.sh`)
- [ ] `tests/fixtures/feat-030-known-buggy/` (regression fixture directory)
- [ ] `tests/fixtures/feat-030-known-buggy/README.md` (fixture intent documentation)
- [ ] `tests/regression/feat-030-executing-qa.test.ts` (vitest regression + negative-regression)

---


## Shared Infrastructure

- `qa-reconcile-delta.sh` (Phase 2) is the single shared implementation called by both `executing-qa` Step 6 (Phase 6 SKILL.md rewrite) and `reviewing-requirements` test-plan reconciliation mode (Phase 6 cross-reference update). NFR-6: no duplication.
- `record-findings --type qa|review` (Phase 5) is the single state subcommand for findings persistence across `reviewing-requirements` (existing `--type review` shape) and `executing-qa` (new `--type qa` shape).
- The Phase-1 contract document is the spine: producers (Phase 2), persister (Phase 5), parser (Phase 5), stop-hook guard (Phase 4 — for the always-allowed artifact paths), and SKILL.md rewrite (Phase 6) all cite it.

## Testing Strategy

**Unit (bats)**: per-script bats sibling alongside every new script (Phase 2: six bats; Phase 3: one bats; Phase 4: extended stop-hook bats; Phase 5: two bats). Coverage targets per NFR-5: happy path, every documented exit code, edge cases the prose used to handle.

**Integration (vitest)**: Phase 6 ships the end-to-end regression test (`tests/regression/feat-030-executing-qa.test.ts`) against a known-buggy fixture branch, plus a negative-regression variant simulating the pre-FEAT-030 misbehavior to confirm the FR-10 stop-hook blocks it. Repo test framework is vitest-only; bats coverage stays at the script-unit layer.

**Backward compatibility (NFR-1)**: Phase 5 bats covers loading a pre-FEAT-030 workflow-state fixture (no `findings` block on the QA step) without error.

## Dependencies and Prerequisites

- Existing scripts: `capability-discovery.sh`, `persona-loader.sh`, `stop-hook.sh` (executing-qa); `workflow-state.sh`, `parse-findings.sh`, `findings-decision.sh` (orchestrating-workflows); `resolve-requirement-doc.sh` (plugin-shared).
- `bats-core` (already in use across the plugin).
- `gh` CLI (already required by the workflow).
- `jq` (already required by `workflow-state.sh`).
- `vitest` (repo test framework; required by the Phase 6 regression test).

No new external dependencies.

## Risk Assessment

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Merge-conflict churn against `executing-qa/scripts/` and `executing-qa/SKILL.md` if anyone touches the directory mid-feature | High | Med | Single-PR packaging (per requirements doc Packaging section); communicate the freeze in the GH issue thread; aim for short cycle time per phase. |
| Phase 2 over-budget (six scripts + six bats in one phase) producing a hard-to-review PR | Med | High | `**ComplexityOverride:** opus` clamp documented; scripts are independent and self-contained; reviewer can inspect script + bats pairs in isolation. |
| Phase 6 SKILL.md rewrite drops a load-bearing prose carve-out (e.g., the FR-2 rule, an error-message verbatim) | High | Med | Verification checklist step 8 (every script name grep-able in SKILL.md; FR-2 rule reachable from Step 4 and the checklist); the regression vitest exercises the full end-to-end path including the FR-2 and FR-10 assertions. |
| Generalized `record-findings --type` flag breaks an existing `reviewing-requirements` caller | High | Low | Phase 5 bats includes a no-flag invocation defaulting to `--type review`; `npm test -- --testPathPatterns=reviewing-requirements` regression check after Phase 5. |
| Stop-hook baseline marker collides across concurrent QA runs against different IDs | Low | Low | Marker filename includes the ID (`.sdlc/qa/.executing-qa-baseline-{ID}`); cleanup happens at hook exit in both success and failure paths. |
| `qa-reconcile-delta.sh` invoked from `reviewing-requirements` via absolute path breaks if `executing-qa/scripts/` moves | Low | Low | Path is resolved via `${CLAUDE_PLUGIN_ROOT}/skills/executing-qa/scripts/qa-reconcile-delta.sh`; both skills live in the same plugin so the variable resolves consistently. |
| Token-cost projection (NFR-4) under-delivered if SKILL.md rewrite leaves residual prose | Med | Low | Verification step 8 grep ensures each script has a SKILL.md caller (caller exists -> the prose it replaced was removed); manual line-count comparison before / after. |

## Success Criteria

- Phase 1: contract document exists at `plugins/lwndev-sdlc/skills/executing-qa/references/qa-return-contract.md` with all three sections (artifact schema, final-message line, workflow-state findings JSON); `executing-qa` SKILL.md `## References` section cites it.
- Phase 2: all six scripts ship with bats coverage; `bats plugins/lwndev-sdlc/skills/executing-qa/scripts/tests/` passes; `npm run validate` clean; no SKILL.md prose changes beyond the Phase-1 cross-reference.
- Phase 3: `qa-verify-coverage.sh` ships with bats coverage; `qa-verifier.md` and `qa-reconciliation-agent.md` deleted; no orphan references in `plugins/lwndev-sdlc/`; `npm run validate` clean.
- Phase 4: stop-hook diff guard rejects edits outside the framework test root with the FR-10 verbatim error; pure additions and existing-file edits inside the test root still allowed; baseline marker prevents false positives from pre-existing uncommitted changes.
- Phase 5: `record-findings --type qa` persists the FR-1 JSON shape on the QA step entry; `parse-qa-return.sh` matches the FR-1 regex on every valid verdict and emits a contract-mismatch error on every malformed input; `orchestrating-workflows` SKILL.md documents the parse path; NFR-1 backward-compatibility holds.
- Phase 6: every Phase-2 script has a caller in `executing-qa` SKILL.md; FR-2 non-remediation rule is reachable from Step 4 and the verification checklist; FR-1 final-message-line is the last line of the skill response; cross-reference skills (`executing-chores`, `executing-bug-fixes`, `reviewing-requirements`) updated; regression vitest passes (verdict `ISSUES-FOUND`, findings list named, no production edits, workflow-state populated, stop-hook does not block); negative-regression vitest passes (stop-hook blocks simulated production edit with FR-10 verbatim error).
- Overall: issues #187, #192, #208 close on merge via `Closes #N` lines in the PR body; per-workflow token cost for `executing-qa` drops by ~2,350–3,450 tokens per NFR-4.
