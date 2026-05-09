# Implementation Plan: executing-qa ephemeral tests + addressing-qa-findings dev-fix skill + adoption into dev suite

## Overview

FEAT-032 fixes two structural defects in the SDLC chain: QA-authored tests accumulate in the repo forever (8+ orphaned `qa-*.test.ts` plus the `qa-CHORE-037-husky-hooks.bats` that broke main per #260), and there is no developer-persona skill that consumes QA findings (the orchestrator advances from `ISSUES-FOUND` straight to `finalizing-workflow`, silently dropping findings). The fix has three load-bearing parts: (1) a new developer-persona skill `addressing-qa-findings` that reproduces, fixes, re-validates and **adopts** the QA test into a `*.qa.*` sibling next to the peer test, (2) `executing-qa` gains a re-QA mode that re-runs prior committed QA tests without regenerating them, and (3) the orchestrator branches on QA verdict, loops with cap N=2, and pauses on exhaustion. `finalizing-workflow` adds a safety-net check that blocks merge if any pre-adoption `qa-*` files survive.

The build order is dictated by data-flow dependencies: workflow-state schema and pause-reason enum extensions land first because every later phase reads or writes them; the new `addressing-qa-findings` skill plus its deterministic `adopt-qa-test.sh` ships next as a self-contained surface; `executing-qa` re-QA mode + artifact embedding + artifact commit ownership land third (consumes nothing from later phases); the orchestrator's verdict-branching, loop counter, and new resume flags land fourth, wiring the prior phases into a coherent fix-loop; `finalizing-workflow`'s safety-net check ships fifth as a parallel-subshell sibling in `preflight-checks.sh`; the test-layout audit (FR-10/FR-11) plus CLAUDE.md docs (FR-14) land sixth in parallel; the end-to-end Bats fixture ships last (NFR-4) and validates the entire `ISSUES-FOUND → fix → re-QA → adopt → finalize` path against a known-buggy fixture.

## Features Summary

| Feature ID | GitHub Issue | Feature Document | Priority | Complexity | Status |
|------------|--------------|------------------|----------|------------|--------|
| FEAT-032 | [#267](https://github.com/lwndev/lwndev-marketplace/issues/267) | [FEAT-032-executing-qa-ephemeral-tests.md](../features/FEAT-032-executing-qa-ephemeral-tests.md) | High | High | Pending |

## Recommended Build Sequence

### Phase 1: Workflow-state schema + pauseReason enum + orchestrator resume flags (FR-7a, FR-8 flag scaffold, NFR-3 migration)

**Feature:** [FEAT-032](../features/FEAT-032-executing-qa-ephemeral-tests.md) | [#267](https://github.com/lwndev/lwndev-marketplace/issues/267)
**Status:** ✅ Complete
**Depends on:** none

#### Rationale

Every later phase reads or writes one of the new state fields (`qaFixAttempts`, `qaLastVerdict`, `adoptedTests`) or one of the new pause reasons (`qa-error`, `qa-loop-exhausted`, `fix-suite-failed`, `adoption-failed`) or one of the new resume flags (`--qa-loop-cap`, `--approve-advance`). Landing the foundation first means every downstream phase consumes a stable contract instead of inventing one and reconciling later. The phase has zero behavioral change visible to the user — it is pure schema and validator extension — but it locks the surface that Phases 2–4 build on. NFR-3's in-place migration (defaults at read time, persisted on next mutation) lands here because `workflow-state.sh` is the only writer; deferring it to Phase 4 would mean Phase 2/3 callers race against the migration logic.

The phase is intentionally schema-and-validator only: no orchestrator branching logic, no skill changes, no UI prompts. Branching ships in Phase 4. Resume-flag *parsing* lands here so the parser is testable in isolation; resume-flag *dispatch* (the `--approve-advance` advance path, the `--qa-loop-cap` counter reset) lands in Phase 4 alongside the loop.

#### Implementation Steps

1. Extend `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh` `cmd_pause` allow-list (around L1138) to accept the four new pause reasons in addition to the existing three: `plan-approval`, `pr-review`, `review-findings`, `qa-error`, `qa-loop-exhausted`, `fix-suite-failed`, `adoption-failed`. Update the rejection error message verbatim per FR-7a: `Error: Invalid pause reason '${reason}'. Expected one of: plan-approval, pr-review, review-findings, qa-error, qa-loop-exhausted, fix-suite-failed, adoption-failed.` (load-bearing carve-out — message text is pinned by Bats per FR-7a).

2. Extend `workflow-state.sh` read paths to default missing fields (`qaFixAttempts: 0`, `qaLastVerdict: null`, `adoptedTests: []`) and write the defaults back on next mutation per NFR-3 in-place migration (mirror the FEAT-014 FR-13 precedent). Add subcommands: `set-qa-verdict <ID> <verdict>` (writes `qaLastVerdict`), `inc-qa-fix-attempts <ID>` (returns the new count on stdout), `reset-qa-fix-attempts <ID>` (writes 0), `record-adopted-test <ID> <path>` (appends to `adoptedTests`), `get-qa-state <ID>` (emits `{qaFixAttempts, qaLastVerdict, adoptedTests}` JSON to stdout for FR-4 auto-detection).

3. Extend `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/check-resume-preconditions.sh` resume-dispatch table to recognise the four new pause reasons; each new branch surfaces the pause reason and whatever resume actions the user has on the table (Phase 4 wires the actual resume actions; this phase only ensures the precondition check does not exit-1 on an unknown reason).

4. Extend `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/parse-model-flags.sh` (or its sibling resume-flag parser if separate) to accept `--approve-advance` (boolean) and `--qa-loop-cap <N>` (positive integer). Reject unknown flags with exit 2. Reject the combination `--approve-advance --qa-loop-cap N` with exit 2 and the verbatim message `Error: --approve-advance and --qa-loop-cap are mutually exclusive` per FR-8 (load-bearing carve-out).

5. Update Bats coverage:
   - `tests/bats/skills/orchestrating-workflows/workflow-state-record-findings-qa.bats` (existing per-skill leaf): add positive tests for each of the four new pause reasons; add a negative test confirming an unknown reason exits 1; pin the rejection-message text verbatim per FR-7a.
   - `tests/bats/skills/orchestrating-workflows/workflow-state.bats` (or extend the existing per-skill leaf for state subcommands; new file at canonical leaf if absent): cover `set-qa-verdict` / `inc-qa-fix-attempts` / `reset-qa-fix-attempts` / `record-adopted-test` / `get-qa-state` for happy path, missing-args, and the NFR-3 migration path (read a pre-FEAT-032 fixture lacking the three fields; subsequent mutation persists defaults).
   - `tests/bats/skills/orchestrating-workflows/parse-model-flags.bats` (or the parser's existing per-skill leaf): cover `--approve-advance` parsing, `--qa-loop-cap <N>` parsing for valid integers, rejection of non-integer cap, rejection of unknown flags, and the FR-8 mutual-exclusion exit-2 message verbatim.

6. Run `npx bats tests/bats/skills/orchestrating-workflows/ | tail -50` and `npm test -- --testPathPatterns=workflow-state | tail -40` and `npm run validate` to confirm zero regressions.

#### Deliverables

- [x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh` (pauseReason enum extension, three new state fields with defaults + migration, new subcommands)
- [x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/check-resume-preconditions.sh` (resume branches for four new pause reasons)
- [x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/parse-model-flags.sh` (or sibling resume-flag parser; new `--approve-advance` / `--qa-loop-cap <N>` flags + mutual-exclusion guard)
- [x] `tests/bats/skills/orchestrating-workflows/workflow-state-record-findings-qa.bats` (extended with four new pause-reason cases + verbatim rejection message)
- [x] `tests/bats/skills/orchestrating-workflows/workflow-state.bats` (new subcommand coverage + NFR-3 migration path)
- [x] `tests/bats/skills/orchestrating-workflows/parse-model-flags.bats` (new flag coverage + FR-8 mutual-exclusion message verbatim)

---

### Phase 2: addressing-qa-findings skill + adopt-qa-test.sh (FR-4, FR-5, FR-6, FR-13)

**Feature:** [FEAT-032](../features/FEAT-032-executing-qa-ephemeral-tests.md) | [#267](https://github.com/lwndev/lwndev-marketplace/issues/267)
**Status:** ✅ Complete
**Depends on:** Phase 1
**ComplexityOverride:** opus

#### Rationale

The new `addressing-qa-findings` skill plus its deterministic `adopt-qa-test.sh` ships as a single phase because the skill body and the script are tightly coupled — the skill's adopt phase iterates over committed QA test files calling the script once per file, and the FR-5 partial-success aggregation semantics (single-shot abort-on-error, paths emitted incrementally to stdout for orchestrator consumption) cross the skill/script boundary. Splitting them across phases would either ship a skill body with no executable adoption (Phase 2a useless on its own) or ship a script with no caller (Phase 2b violates the "no script ships without a caller in the same PR" guarantee). Bundling them under a clamped opus phase trades one slightly larger PR for two interdependent PRs that cannot be merged independently.

The skill ships with two auto-detected phases (fix, adopt) per FR-4, dispatched on the `{qaLastVerdict, qaFixAttempts, adoptedTests}` triple read from `workflow-state.sh get-qa-state` (Phase 1 subcommand). No new state field is introduced; no `lastStepKind` is required. The orchestrator (Phase 4) invokes the skill twice per loop attempt (fix, then adopt after a re-QA PASS). FR-13 (deletion ownership) is satisfied by construction — `adopt-qa-test.sh` is the only deletion path in the entire feature, and it deletes via `git mv` (the move IS the deletion). The FR-13 negative test (grep over plugin scripts confirming no other surface deletes `qa-*` files) ships in this phase.

**Implementation choices** decided here at plan time:

- **Per-framework dispatch in `adopt-qa-test.sh`** keys off the framework names already produced by the existing `plugins/lwndev-sdlc/skills/executing-qa/scripts/capability-discovery.sh` (the executing-qa variant per FR-5 — the documenting-qa script of the same name is a different surface). v1 supports Vitest (TS/JS) and Bats per FR-5; pytest and go-test paths emit exit-2 with a structured "framework not supported in v1" reason and are tracked as follow-up issues if the v1 user hits them. Forward-compat globs for `qa-*.py` and `qa-*.go` ship in FR-9 (Phase 5) as no-ops; the lockstep constraint per Edge Case 17 is documented in CLAUDE.md (Phase 6).
- **Skill phase auto-detection** reads the FR-4 triple from `workflow-state.sh get-qa-state` (Phase 1 subcommand); no phase argument is taken from the orchestrator. Pre-checks fail-fast with the FR-4 verbatim messages.
- **Stdout-streamed adopted paths** (FR-4 adopt-phase step 2.2): the skill emits one adopted path per line on stdout immediately after each successful `adopt-qa-test.sh` exit-0, before continuing to the next file. The orchestrator (Phase 4) consumes this stream incrementally via `record-adopted-test` (Phase 1 subcommand) so partial progress survives a subsequent failure. On the first script exit-2, the skill aborts the loop, emits the FR-4 partial-success failure line, and the orchestrator pauses with `adoption-failed`.

#### Implementation Steps

1. Scaffold the new skill at `plugins/lwndev-sdlc/skills/addressing-qa-findings/SKILL.md` with developer persona; argument is a workflow ID; `allowed-tools` matches what the script-driven workflow needs (Bash, Read, Grep — no Write because production fixes go through Edit; the skill calls `adopt-qa-test.sh` and shells `git`). SKILL.md body is lean per repo authoring convention: contract description, the FR-4 triple-based phase auto-detection, and a list of script invocations. Long-form detail goes under `references/`.

2. Write `plugins/lwndev-sdlc/skills/addressing-qa-findings/scripts/adopt-qa-test.sh` per FR-5: takes `<qa-test-path>`; parses `import` / `require` / bats `load` statements; identifies the SUT module from the imports; locates the existing peer test for that SUT; computes the sibling target path `{existing-test-dir}/{base}.qa.{ext}` per FR-6; runs `git mv <qa-test-path> <new-path>`; prints the new path on stdout (single line, trailing newline). Exit codes: `0` success, `1` filesystem / `git mv` failure, `2` SUT cannot be determined (no resolvable imports / multiple plausible peers / no existing peer test). On exit 2, print a structured stderr line naming the QA test path and the reason (load-bearing carve-out — the orchestrator-pause UI surfaces this verbatim per FR-5).

3. Write the per-framework dispatch under `adopt-qa-test.sh`: reuse `${CLAUDE_PLUGIN_ROOT}/skills/executing-qa/scripts/capability-discovery.sh` to determine the project's primary framework; dispatch to a Vitest/Jest path (parse ES `import` / CJS `require`; resolve module against repo's `package.json` `paths`/`baseUrl` with a tsconfig fallback; locate `<base>.test.ts` or `<base>.test.js`) or a Bats path (parse `load '<file>'` and `source '<file>'`; locate `<base>.bats` next to the loaded shell script). pytest/go-test stubs exit 2 with a "framework not supported in v1" structured reason.

4. Write the skill body in `addressing-qa-findings/SKILL.md`:
   - **Phase auto-detect**: shell `workflow-state.sh get-qa-state <ID>`; branch on the FR-4 triple (`fix` iff `qaLastVerdict == ISSUES-FOUND` AND `adoptedTests` empty; `adopt` iff `qaLastVerdict == PASS` AND `qaFixAttempts > 0` AND `adoptedTests` empty; otherwise emit `failed | unable to auto-detect phase from state` and exit).
   - **Fix phase**: pre-check clean working tree (`git diff --quiet` AND `git diff --cached --quiet`); on dirty, fail with the FR-4 verbatim message `failed | working tree dirty; commit or stash before re-running`. Resolve the QA artifact path; bail with `failed | no QA artifact at qa/test-results/QA-results-{ID}.md` if absent (Edge Case 12). Process all findings as a single batch per FR-8: read each embedded QA test source AND locate the committed test file on the branch; execute each QA test locally and confirm it fails at HEAD (sanity check); write production fix(es) via Edit; re-execute each QA test and confirm it passes locally; run the full test suite (build-health gate); on failure, emit `failed | full suite gate failed after fix; reverting commit not implemented in v1, manual intervention required` (Edge Case 13). Commit the production fix with `fix({ID}): <summary>`. Emit `done | phase=fix-committed | awaiting-re-qa`.
   - **Adopt phase**: pre-check `qaLastVerdict == PASS` (orchestrator already validates; double-check). For each committed QA test file on the branch (matched against the FR-3 v1 glob set: `tests/unit/qa-*.test.ts`, `tests/unit/qa-*.test.js`, `tests/bats/qa/qa-*.bats`): call `adopt-qa-test.sh <path>`; on exit 0, print the adopted path to stdout immediately (one line) and continue; on exit 2, abort the loop, leave already-moved files in place, emit `failed | adoption failed for <path>; <N> adopted, <M> remaining` (FR-4 partial-success). On full success, commit the adoption with `qa(adopt): {ID} promote QA tests into regression suite`. Emit `done | phase=adopted | artifact=qa/test-results/QA-results-{ID}.md | adopted=<N>`.

5. Write Bats coverage at the canonical leaves:
   - `tests/bats/skills/addressing-qa-findings/adopt-qa-test.bats` per FR-5: happy path Vitest (TS file with relative import → peer test located → `git mv` succeeds → stdout prints new path); happy path Bats (load directive → peer .bats located → `git mv` succeeds); exit-2 cases (no resolvable imports, multiple plausible peers, no existing peer test, "framework not supported in v1" stub for pytest/go-test); exit-1 case (`git mv` fails because target already exists); structured stderr message format pinned per FR-5.
   - `tests/bats/skills/addressing-qa-findings/skill-fix-phase.bats`: dirty-tree precheck rejects with verbatim message; missing-artifact precheck rejects with verbatim message; happy path single-finding (read embedded test → confirm fails → fix written → confirm passes → suite green → commit → return contract); happy path multi-finding batch; full-suite gate failure → `fix-suite-failed` return contract verbatim; phase auto-detect rejects when triple is in adopt or unrecognised state.
   - `tests/bats/skills/addressing-qa-findings/skill-adopt-phase.bats`: happy-path adopt-all-files (multiple QA test files → all moved → stdout stream emitted → adoption commit → return contract); FR-4 partial-success (first file adopts, second hits exit 2 → loop aborts → prior path emitted to stdout → failure return contract verbatim); pre-check rejects when `qaLastVerdict != PASS`.
   - `tests/bats/skills/addressing-qa-findings/deletion-ownership.bats` (FR-13): grep over `plugins/lwndev-sdlc/` confirming no skill or script other than `addressing-qa-findings/` deletes any `qa-*` file (`grep -rn 'rm.*qa-\|git rm.*qa-\|git mv.*qa-' plugins/lwndev-sdlc/ | grep -v addressing-qa-findings/` returns empty). Negative-control: a deliberately-introduced violation under a temp fixture path triggers the assertion failure as expected.

6. Run `npx bats tests/bats/skills/addressing-qa-findings/ | tail -60` and `npm run validate` to confirm zero regressions and that the new skill validates cleanly.

#### Deliverables

- [x] `plugins/lwndev-sdlc/skills/addressing-qa-findings/SKILL.md`
- [x] `plugins/lwndev-sdlc/skills/addressing-qa-findings/scripts/adopt-qa-test.sh`
- [x] `tests/bats/skills/addressing-qa-findings/adopt-qa-test.bats`
- [x] `tests/bats/skills/addressing-qa-findings/skill-fix-phase.bats`
- [x] `tests/bats/skills/addressing-qa-findings/skill-adopt-phase.bats`
- [x] `tests/bats/skills/addressing-qa-findings/deletion-ownership.bats`

---

### Phase 3: executing-qa re-QA mode + artifact embedding + artifact commit ownership (FR-1, FR-2, FR-3, FR-12)

**Feature:** [FEAT-032](../features/FEAT-032-executing-qa-ephemeral-tests.md) | [#267](https://github.com/lwndev/lwndev-marketplace/issues/267)
**Status:** ✅ Complete
**Depends on:** Phase 2
**ComplexityOverride:** opus

#### Rationale

This phase modifies four surfaces of `executing-qa` that share the same SKILL.md and the same `executing-qa/scripts/` directory: (1) re-QA auto-detection and re-execute path (FR-3), (2) per-finding `## Reproduction` block embedding the QA test source (FR-2), (3) the artifact-overwrite contract for re-QA (FR-12), and (4) the artifact-commit ownership rule that keeps the working tree clean for the FR-4 fix-phase precheck (FR-12). Bundling them under one phase means one SKILL.md edit, one round of `render-qa-results.sh` extension, and one round of `executing-qa` end-to-end Bats updates. Splitting would multiply merge-conflict surface against the same files; the `**ComplexityOverride:** opus` clamp is intentional and justified by the FR coupling (every step edits or extends the same `executing-qa/SKILL.md` + `render-qa-results.sh` pair, and the FR-13 ownership invariant must hold across all four FR landings simultaneously to satisfy the Phase 2 negative test).

Phase 3 depends on Phase 2 because re-QA mode and the artifact-embedding contract are observable by the new `addressing-qa-findings` skill (the fix phase reads the embedded test source from `## Reproduction`; the adopt phase reads the on-disk QA test files), and shipping Phase 3 before the consumer means there is no caller for the new behavior. Also depends on Phase 2 for the FR-13 ownership invariant: this phase's re-QA changes MUST NOT introduce a deletion path for `qa-*` files (FR-13 delete-ownership rule); the FR-13 negative test from Phase 2 catches any such regression at test time.

**Implementation choice**: re-QA mode is a **behavior-mode of the same skill**, NOT a separate `re-executing-qa` skill, per FR-3. Auto-detection inside `executing-qa` SKILL.md branches on the conjunction of the existing `qa-baseline.sh` marker file (`.sdlc/qa/.executing-qa-baseline-{ID}`) AND the v1 glob set (`tests/unit/qa-*.test.ts`, `tests/unit/qa-*.test.js`, `tests/bats/qa/qa-*.bats`). No new marker is introduced.

#### Implementation Steps

1. Extend `plugins/lwndev-sdlc/skills/executing-qa/assets/test-results-template-v2.md` to include a per-finding `## Reproduction` block with a placeholder for the embedded QA test source code (language-aware fenced block plus a path-comment header per FR-2). Update the template's example to demonstrate the embedding shape so downstream renderers stay aligned.

2. Extend `plugins/lwndev-sdlc/skills/executing-qa/scripts/render-qa-results.sh` per FR-2: under each finding's `## Reproduction` section, embed the QA test source code as a fenced code block delimited by language-aware fences (` ```typescript ` for `.ts` / `.tsx`, ` ```javascript ` for `.js`, ` ```bash ` for `.bats` / `.sh`, ` ```python ` for `.py`, ` ```go ` for `.go`); prepend a single-line path-comment header naming the relative path of the source file (per language: `// path/to/file.ts`, `// path/to/file.js`, `# path/to/file.bats`, `# path/to/file.py`, `// path/to/file.go`). Add an `--embed-tests` arg (or always-on if simpler) so existing callers still work; document the toggle in the script header. Verify the embed for each verdict: PASS embeds nothing under findings (no findings); ISSUES-FOUND embeds one block per failing test; ERROR / EXPLORATORY-ONLY paths unchanged.

3. Add the FR-3 auto-detection logic to `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` Step 0 (or wherever the skill currently checks for prior runs): probe both conditions — (a) `[ -f ".sdlc/qa/.executing-qa-baseline-{ID}" ]`, AND (b) at least one file matches `tests/unit/qa-*.test.ts`, `tests/unit/qa-*.test.js`, or `tests/bats/qa/qa-*.bats`. On both true → enter re-QA mode (skip test-generation, skip persona-loaded test-writing, jump straight to `run-framework.sh` against the existing committed tests + `render-qa-results.sh` against the run output). On either false → initial-run path unchanged. Add an inline `[info]` log line `re-QA mode: re-executing N committed QA tests for {ID}` (load-bearing for the Bats fixture's stdout assertion).

4. Add the FR-3 re-QA error path: when auto-detection enters re-QA mode but the framework runner returns no executable tests (the marker exists but the user manually deleted the QA files mid-workflow per Edge Case 8), emit verdict `ERROR` with `Reason: re-QA invoked but no prior QA test files found for {ID}` per NFR-2; the orchestrator (Phase 4) pauses with `qa-error`. Re-QA mode does NOT regenerate; that is a deliberate deviation from initial-run behavior. Re-QA mode CANNOT return `EXPLORATORY-ONLY` per FR-3 (no path from re-execution to that verdict — Edge Case 6); the verdict set for re-QA is `{PASS, ISSUES-FOUND, ERROR}`.

5. Add the FR-12 artifact-commit step to `executing-qa` SKILL.md (both initial and re-QA paths): after `render-qa-results.sh` writes `qa/test-results/QA-results-{ID}.md`, stage and commit it. Initial run: message `qa({ID}): record QA results`. Re-QA run: message `qa({ID}): re-record QA results after fix attempt {N}` where `{N}` is the current `qaFixAttempts` from `workflow-state.sh get-qa-state`. The artifact commit lands alongside the existing QA-tests commit produced by `commit-qa-tests.sh` (initial run) — for re-QA the QA-tests commit is skipped (no new tests to commit); only the artifact is committed. This guarantees the working tree is clean on `addressing-qa-findings` entry per FR-4 fix-phase precheck.

6. Update `executing-qa` SKILL.md to make the FR-13 ownership invariant explicit: the skill (in either initial or re-QA mode) NEVER deletes QA test files; deletion is owned exclusively by `addressing-qa-findings/scripts/adopt-qa-test.sh` via `git mv`. The existing `stop-hook.sh` diff guard (FEAT-030 FR-10) keeps the report-only diff guard semantics; document that `addressing-qa-findings` is the developer-persona skill allowed to MOVE QA files (not edit them) per FR-1.

7. Update `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` `## Quick Start` and verification checklist to reference the re-QA auto-detect, the artifact-embedding, and the artifact-commit steps. Apply Caveman Lite throughout; load-bearing carve-outs (the FR-3 `[info]` log line text, the FR-12 commit message templates, the NFR-2 re-QA-no-tests error reason, the FR-13 ownership rule body) stay verbatim.

8. Update Bats coverage:
   - `tests/bats/skills/executing-qa/render-qa-results.bats` (existing): add cases for FR-2 embedding — language-aware fences for `.ts`, `.bats`, `.py`, `.go` files; path-comment header format per language; multi-finding artifact emits one block per finding.
   - `tests/bats/skills/executing-qa/re-qa-mode.bats` (new): auto-detect happy path (marker + at least one QA file → re-QA entered); auto-detect skip path (marker absent → initial run); auto-detect skip path (marker present but no QA files → initial run); re-QA-no-tests error path emits `ERROR` with the verbatim reason (NFR-2); FR-3 verdict-set restriction (re-QA cannot return `EXPLORATORY-ONLY`); FR-13 negative — re-QA never deletes QA files (post-condition: the QA file count is unchanged after re-QA exit).
   - `tests/bats/skills/executing-qa/artifact-commit.bats` (new): FR-12 initial-run commit message verbatim; FR-12 re-QA commit message with `{N}` interpolation from `workflow-state.sh get-qa-state`; clean-tree post-condition asserted via `git status --porcelain` empty after the commit.

9. Run `npx bats tests/bats/skills/executing-qa/ | tail -60` and `npm test -- --testPathPatterns=executing-qa | tail -50` and `npm run validate` to confirm zero regressions.

#### Deliverables

- [x] `plugins/lwndev-sdlc/skills/executing-qa/assets/test-results-template-v2.md` (per-finding `## Reproduction` block placeholder)
- [x] `plugins/lwndev-sdlc/skills/executing-qa/scripts/render-qa-results.sh` (FR-2 language-aware embedding + path-comment header)
- [x] `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` (FR-3 auto-detect + re-QA branch + FR-12 artifact commit + FR-13 ownership rule body)
- [x] `tests/bats/skills/executing-qa/render-qa-results.bats` (extended with FR-2 embedding cases)
- [x] `tests/bats/skills/executing-qa/re-qa-mode.bats` (FR-3 + FR-13 negative)
- [x] `tests/bats/skills/executing-qa/artifact-commit.bats` (FR-12)

---

### Phase 4: Orchestrator verdict-branching + re-QA loop + resume dispatch (FR-7, FR-8 dispatch)

**Feature:** [FEAT-032](../features/FEAT-032-executing-qa-ephemeral-tests.md) | [#267](https://github.com/lwndev/lwndev-marketplace/issues/267)
**Status:** 🔄 In Progress
**Depends on:** Phase 1, Phase 2, Phase 3

#### Rationale

The orchestrator's QA-step branching is the data-flow consumer of every prior phase: it reads the verdict from `executing-qa` (Phase 3 contract), reads the FR-4 triple from `workflow-state.sh get-qa-state` (Phase 1 subcommand), dispatches `addressing-qa-findings` fix or adopt phase (Phase 2 skill), increments `qaFixAttempts` via `inc-qa-fix-attempts` (Phase 1 subcommand), and pauses on `qa-loop-exhausted` / `qa-error` / `fix-suite-failed` / `adoption-failed` using the Phase 1 enum. Landing it in Phase 4 means every dependency is in place; landing it earlier would require stubs for the consumer surfaces and reconciling later.

The phase encompasses the full FR-7 dispatch table (five rows: initial-run PASS, post-loop PASS, ISSUES-FOUND, ERROR, EXPLORATORY-ONLY) plus the FR-8 loop-cap behavior (counter increment + `qa-loop-exhausted` pause + `--qa-loop-cap <N>` reset + `--approve-advance` advance). Resume-flag *parsing* shipped in Phase 1; this phase wires the *dispatch* — `--approve-advance` advances past the loop with the counter preserved, `--qa-loop-cap <N>` resets the counter to 0 and continues with the elevated cap. Per FR-8 step 5: incrementing the counter records a state event so the loop history remains traceable per Edge Case 15.

This phase also updates the existing comment in `orchestrating-workflows/SKILL.md` ("the orchestrator does NOT change advance behavior based on verdict") to reflect the new gating per FR-7. The advance-behavior comment came from FEAT-030 Phase 5 (FR-12) and is intentionally rewritten here.

**Implementation choice**: the dispatch logic lives in a new sibling script `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/qa-dispatch.sh` rather than inline in SKILL.md prose, per the repo "scripts over prose" convention. The script takes `<ID>` and the most-recent verdict (or reads it from state if not supplied), consults the FR-4 triple via `get-qa-state`, and emits one of: `dispatch=fix-phase`, `dispatch=adopt-phase`, `dispatch=re-qa`, `dispatch=advance`, `dispatch=pause:<reason>`. The orchestrator SKILL.md branches on the script's stdout. This keeps the verdict-branching table testable in Bats (one happy path per dispatch outcome plus the loop-cap pause path) and out of SKILL.md prose.

#### Implementation Steps

1. Write `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/qa-dispatch.sh`: takes `<ID>`; reads `{qaFixAttempts, qaLastVerdict, adoptedTests}` via `workflow-state.sh get-qa-state <ID>`; reads the loop cap from a workflow-state field `qaLoopCap` (default 2, set by `--qa-loop-cap <N>` resume per FR-8); emits one of:
   - `dispatch=advance` — initial-run PASS (`qaFixAttempts == 0` AND verdict == `PASS`) OR `EXPLORATORY-ONLY` (per FR-7 EXPLORATORY-ONLY closure clause — only reachable from initial run because re-QA cannot return that verdict per FR-3) OR post-loop PASS-after-adopt (`qaFixAttempts > 0` AND verdict == `PASS` AND `adoptedTests` non-empty)
   - `dispatch=adopt-phase` — post-fix PASS needing adoption (`qaFixAttempts > 0` AND verdict == `PASS` AND `adoptedTests` empty)
   - `dispatch=fix-phase` — `ISSUES-FOUND` AND `qaFixAttempts < qaLoopCap`
   - `dispatch=re-qa` — fix-phase just returned `done | phase=fix-committed`; orchestrator re-invokes `executing-qa` (note: this dispatch is emitted by the orchestrator's post-fix-phase handling, not by `qa-dispatch.sh` itself; the script handles only verdict-gated branches)
   - `dispatch=pause:qa-loop-exhausted` — `ISSUES-FOUND` AND `qaFixAttempts >= qaLoopCap`
   - `dispatch=pause:qa-error` — verdict == `ERROR`
   - `dispatch=pause:fix-suite-failed` — fix-phase returned `failed | full suite gate failed after fix; ...`
   - `dispatch=pause:adoption-failed` — adopt-phase returned `failed | adoption failed for ...`

   Exit `0` always (stdout is the dispatch); exit `2` on missing args. Add a `--explain` flag for human-readable context emitted to stderr (helps debugging).

2. Update `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` QA-step section to invoke `qa-dispatch.sh <ID>` immediately after the existing `parse-qa-return.sh` + `record-findings --type qa` calls (FEAT-030 FR-12 / FR-14 path), and **before** the existing advance step. Branch on the dispatch token:
   - `advance`: continue to the next step (existing `advance` path).
   - `adopt-phase`: fork `addressing-qa-findings` (the skill auto-detects adopt phase from state per FR-4); on its `done | phase=adopted` return, advance.
   - `fix-phase`: increment `qaFixAttempts` via `workflow-state.sh inc-qa-fix-attempts <ID>`; record the increment as a state event per Edge Case 15; fork `addressing-qa-findings` (auto-detects fix phase); on its `done | phase=fix-committed` return, re-invoke `executing-qa` (which will auto-detect re-QA mode per Phase 3); loop control returns to the dispatch step at the top.
   - `pause:<reason>`: invoke `workflow-state.sh pause <ID> <reason>`; emit the load-bearing pause prompt (lite-narration carve-out — surface the reason and the FR-8 resume options verbatim for `qa-loop-exhausted`).

3. Update `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` resume path to handle the four new pause reasons:
   - `qa-loop-exhausted`: branch on resume flags — `--approve-advance` → advance to the next step (counter preserved per FR-8); `--qa-loop-cap <N>` → write `qaLoopCap=N` to state, reset `qaFixAttempts` to 0 via `reset-qa-fix-attempts`, re-enter the QA dispatch loop; neither flag → workflow stays paused (Abandon path per FR-8 / Edge Case 16). The mutual-exclusion guard from Phase 1 ensures both flags together exit 2 with the verbatim message.
   - `qa-error`: surface the underlying QA `ERROR` verdict reason; user resolves manually then re-invokes the orchestrator (no special flag).
   - `fix-suite-failed`: surface the FR-4 step-4 failure reason; v1 has no auto-revert (Edge Case 13); user resolves manually then re-invokes.
   - `adoption-failed`: surface the FR-5 partial-success reason naming the failing path and the `<N> adopted, <M> remaining` count (`adoptedTests` is preserved across the pause per FR-4 step 2.3); user resolves manually then re-invokes.

4. Rewrite the existing comment in `orchestrating-workflows/SKILL.md` that says "the orchestrator does NOT change advance behavior based on verdict" (introduced by FEAT-030 FR-12) to reflect the new FR-7 gating: "After QA, advance behavior is verdict-gated per `qa-dispatch.sh`. See `references/qa-loop.md` for the dispatch table." Apply Caveman Lite.

5. Write `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/qa-loop.md` (new reference): document the FR-7 dispatch table verbatim (the same five rows from the requirements doc); the FR-8 loop semantics ("attempt = full pass over all findings + 1 re-QA execution"); the resume-flag map (`--approve-advance` / `--qa-loop-cap <N>`); the four pause reasons and their resume actions; cross-reference Edge Cases 5, 13, 14, 15, 16.

6. Update Bats coverage:
   - `tests/bats/skills/orchestrating-workflows/qa-dispatch.bats` (new): one happy-path test per FR-7 dispatch row (5 rows + the post-fix-PASS-needing-adopt row = 6 rows total accounting for FR-7's PASS-after-adopt closure); `qa-loop-exhausted` pause path (`qaFixAttempts >= qaLoopCap` AND verdict == `ISSUES-FOUND`); `qa-error` pause path; `fix-suite-failed` pause path; `adoption-failed` pause path; the `--explain` flag emits to stderr.
   - `tests/bats/skills/orchestrating-workflows/qa-loop-resume.bats` (new): `--approve-advance` resume preserves `qaFixAttempts` and advances; `--qa-loop-cap <N>` resume resets `qaFixAttempts` to 0 AND writes `qaLoopCap=N`; resume with neither flag stays paused; resume with both flags fails per the Phase 1 mutual-exclusion guard (re-asserts the message text for orchestrator-resume context).
   - `tests/bats/skills/orchestrating-workflows/qa-loop-state-events.bats` (new): each `inc-qa-fix-attempts` records a state event (per Edge Case 15) so the loop history is traceable.

7. Run `npx bats tests/bats/skills/orchestrating-workflows/ | tail -80` and `npm test -- --testPathPatterns=orchestrating-workflows | tail -60` and `npm run validate` to confirm zero regressions.

#### Deliverables

- [x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/qa-dispatch.sh`
- [x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` (FR-7 dispatch wiring + FR-8 resume dispatch + comment rewrite)
- [x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/qa-loop.md` (FR-7 dispatch table + FR-8 loop semantics + resume-flag map)
- [x] `tests/bats/skills/orchestrating-workflows/qa-dispatch.bats`
- [x] `tests/bats/skills/orchestrating-workflows/qa-loop-resume.bats`
- [x] `tests/bats/skills/orchestrating-workflows/qa-loop-state-events.bats`

---

### Phase 5: finalizing-workflow safety-net check (FR-9)

**Feature:** [FEAT-032](../features/FEAT-032-executing-qa-ephemeral-tests.md) | [#267](https://github.com/lwndev/lwndev-marketplace/issues/267)
**Status:** Pending
**Depends on:** Phase 2

#### Rationale

The safety-net check is a single new parallel-subshell sibling inside the existing `preflight-checks.sh` (FEAT-030's parallel-subshell pattern), evaluated in precedence order after the build-health gate per FR-9. It depends on Phase 2 only because the FR-9 glob set is defined in concert with the FR-3 v1 glob set and the FR-6 adopted-naming convention — the safety-net glob is `qa-*` prefix only, NOT the `*.qa.*` adopted infix; Phase 2 establishes the adopted naming so this phase can correctly negate it.

The check has zero new script files (writes to `$tmpdir/qa-leakage.reason` per FR-9, follows the existing precedence-order evaluation). The error message format is verbatim per FR-9 (load-bearing carve-out). The check is idempotent and safe to re-run. Untracked `qa-*` files do NOT block merge (they will not reach main); the check uses `git ls-files` per FR-9.

#### Implementation Steps

1. Extend `plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/preflight-checks.sh` per FR-9: add a new parallel subshell sibling alongside the existing clean-tree / branch / PR / build-health checks. The new subshell runs `git ls-files` filtered by the v1 glob set (`qa-*.test.ts`, `qa-*.test.js`, `qa-*.bats`) plus the forward-compat globs (`qa-*.py`, `qa-*.go` — no-ops in v1 per FR-9 / Edge Case 17); writes its status to `$tmpdir/qa-leakage.reason`. The subshell's evaluation order is **after** the build-health gate per FR-9 (it is the last gate before merge). On any match, the gate fails; the merge is blocked; the verbatim error message per FR-9 is emitted (load-bearing carve-out — pinned by Bats):
   ```
   [error] QA test files were not adopted; the addressing-qa-findings skill did not complete cleanly:
     - <path-1>
     - <path-2>
   Resolve by running addressing-qa-findings to adoption, or manually adopting/deleting these files.
   ```

2. Confirm the gate negates `*.qa.*` adopted siblings (Edge Case 9) — only the `qa-*` prefix glob matches; `tests/unit/foo.qa.test.ts` and friends pass. Confirm a manually-named `qa-foo.test.ts` outside the workflow trips the gate (Edge Case 10 — acceptable false positive; the convention is reserved for QA-authored tests).

3. Write Bats coverage at the canonical leaf:
   - `tests/bats/skills/finalizing-workflow/safety-net.bats` (new): trips on a tracked `qa-bash-input.test.ts`; trips on a tracked `qa-error-handling.bats` under `tests/bats/qa/`; passes on a tracked `tests/unit/foo.qa.test.ts` (Edge Case 9 — adopted sibling); passes on an UNtracked `qa-foo.test.ts` (FR-9 explicitly tracked-files only); v1 forward-compat glob is no-op (no false positives) for `qa-foo.py` and `qa-foo.go` paths in v1; trips on a manually-named `qa-foo.test.ts` outside the workflow (Edge Case 10); error message text pinned verbatim per FR-9; the safety-net runs in the parallel subshell ordering after build-health (asserted by inspecting the subshell's `$tmpdir/qa-leakage.reason` file path and ordering of evaluation).

4. Run `npx bats tests/bats/skills/finalizing-workflow/ | tail -40` and `npm test -- --testPathPatterns=finalizing-workflow | tail -40` and `npm run validate` to confirm zero regressions.

#### Deliverables

- [ ] `plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/preflight-checks.sh` (extended with FR-9 safety-net subshell + verbatim error message)
- [ ] `tests/bats/skills/finalizing-workflow/safety-net.bats`

---

### Phase 6: Test-layout audit + length-assertion relaxation + CLAUDE.md docs (FR-10, FR-11, FR-14)

**Feature:** [FEAT-032](../features/FEAT-032-executing-qa-ephemeral-tests.md) | [#267](https://github.com/lwndev/lwndev-marketplace/issues/267)
**Status:** Pending
**Depends on:** Phase 2

#### Rationale

This phase ships three interlocking small tasks that all stem from the `*.qa.*` adopted-sibling convention introduced in Phase 2: (1) the FR-10 fix to `tests/unit/shared-scripts.test.ts` line 102-117 (drop the hard-coded `14` literal at line 107; replace with set-based parity), (2) the FR-11 audit of every `*.test.ts` under `tests/unit/` for length-based assertions over directories that can receive `*.qa.*` siblings (`tests/unit/`, `tests/bats/shared/`, `tests/bats/skills/**`, `tests/fixtures/**`), and (3) the FR-14 CLAUDE.md updates documenting the new QA lifecycle and the `*.qa.*` adoption convention.

The three tasks share a single root cause (the new sibling naming) and a single review surface (test-config + docs); bundling them avoids three separate review cycles for what is essentially "the v1 adoption convention's documentation/test fallout". Phase 6 depends only on Phase 2 (the convention is established there); it does NOT depend on Phase 3, 4, or 5 — the relaxation is mechanical and the docs are forward-looking.

The FR-11 audit is documented as a structured deliverable per the requirements doc: the audit list is recorded in the PR body under a `## Length-Assertion Audit` heading (one row per file/line-range, with treatment `relaxed` / `filtered` / `documented-strict` and a one-sentence rationale). The same list appears as a section in this phase's deliverables so the plan's QA test plan can verify each entry was addressed.

#### Implementation Steps

1. Replace the FR-10 parity assertion in `tests/unit/shared-scripts.test.ts` lines 102-117 (the hard-coded `14` literal at line 107) with set-based parity per FR-10:
   ```ts
   for (const script of CANONICAL_SCRIPTS) {
     const expected = path.join(BATS_SHARED_DIR, `${script}.bats`);
     expect(existsSync(expected)).toBe(true);
   }
   // no length-based assertion; *.qa.bats siblings allowed
   ```
   Confirm the assertion still catches a missing peer .bats (negative-control test).

2. Run the FR-11 audit: `grep -rEn 'expect\([^)]+\)\.toBe\([0-9]+\)|expect\([^)]+\)\.toHaveLength\([0-9]+\)' tests/unit/ tests/integration/ 2>/dev/null` (or equivalent) over `tests/unit/`, `tests/bats/shared/`, `tests/bats/skills/**`, `tests/fixtures/**` and produce a list of every length-based assertion over directories that may receive `*.qa.*` siblings. For each hit, classify as `relaxed` (preferred — replace with set-based assertion), `filtered` (filter out `*.qa.*` files before counting), or `documented-strict` (add a comment explaining why `.qa.` siblings are not expected in that path). Apply each classification.

3. Record the FR-11 audit deliverable as a `## Length-Assertion Audit` table in the eventual PR body and in this implementation plan's deliverables list (one row per source file + line range; columns: `path`, `original`, `treatment`, `rationale`). The table is the single source of truth for what was audited and how each item was handled.

4. Update `CLAUDE.md` per FR-14:
   - Document the QA test lifecycle (ephemeral, committed-during-workflow, deleted-via-adoption); reference `addressing-qa-findings`.
   - Document the `*.qa.*` sibling naming convention with examples (`tests/unit/foo.test.ts` → `tests/unit/foo.qa.test.ts`; `tests/bats/shared/check-acceptance.bats` → `tests/bats/shared/check-acceptance.qa.bats`).
   - Document the safety-net check (FR-9) and its `qa-*` prefix glob set.
   - Reference `addressing-qa-findings` in the chain descriptions (the Existing Skills section's three workflow chains — feature, chore, bug — gain a new step between `executing-qa` and `finalizing-workflow` for the verdict-branch case).
   - Remove any prose that treats `qa-*` accumulation as expected behavior.
   - Document the Edge Case 17 lockstep constraint: enabling FR-9 globs for pytest/go-test must land in lockstep with FR-5 dispatch for those frameworks.
   - Apply Caveman Lite throughout per repo authoring convention.

5. Run `npm test -- --testPathPatterns=shared-scripts | tail -30` and `npm test | tail -120` and `npm run validate` to confirm zero regressions and that the FR-10 set-based assertion still catches missing peer .bats files.

#### Deliverables

- [ ] `tests/unit/shared-scripts.test.ts` (FR-10 set-based parity replacement; hard-coded `14` literal removed)
- [ ] `tests/unit/<files-from-FR-11-audit>.test.ts` (FR-11 audit-driven relaxations / filters / documented-strict comments — exact files determined by the audit run in Step 2; recorded in the `## Length-Assertion Audit` table)
- [ ] `CLAUDE.md` (FR-14 lifecycle + `*.qa.*` convention + safety-net documentation + chain-description updates + Edge Case 17 lockstep note)

---

### Phase 7: End-to-end Bats fixture (NFR-4 acceptance)

**Feature:** [FEAT-032](../features/FEAT-032-executing-qa-ephemeral-tests.md) | [#267](https://github.com/lwndev/lwndev-marketplace/issues/267)
**Status:** Pending
**Depends on:** Phase 1, Phase 2, Phase 3, Phase 4, Phase 5

#### Rationale

The NFR-4 acceptance criterion ("an end-to-end Bats fixture exercises `ISSUES-FOUND → addressing-qa-findings → re-QA PASS → adoption → finalize` no shortcuts") is the integration test that proves the seven-phase build hangs together correctly. It depends on every prior phase by construction — the fixture exercises every dispatch row, the loop counter, the artifact embedding, the artifact-overwrite contract, the safety-net negation, and the orchestrator's resume path. Landing it last means the prior phases ship with their own per-skill Bats fixtures and the integration phase only adds the cross-skill end-to-end. Splitting the fixture across phases would require the fixture to gate-keep against partial implementation, which is harder to test and easier to drift.

The fixture lives under `tests/fixtures/feat-032-known-buggy/` (a minimal repo snapshot: vitest project with a deliberately failing QA scenario, capability JSON, plan + requirements docs, a known-buggy production file, and a peer test that the QA test will adopt next to). The fixture's intended verdict (`ISSUES-FOUND` initially, `PASS` after fix), expected adopted path (`tests/unit/<peer>.qa.test.ts`), and expected workflow-state mutations (`qaFixAttempts == 1`, `qaLastVerdict == "PASS"`, `adoptedTests == [<path>]`) are documented in a sibling `README.md` per the FEAT-030 fixture convention.

The driver Bats test asserts:
- The orchestrator branches to `addressing-qa-findings` on `ISSUES-FOUND` (not directly to `finalizing-workflow`).
- The fix phase commits the production fix; the working tree is clean on re-QA entry per FR-12.
- Re-QA returns `PASS`; the artifact is overwritten in place per FR-12; the artifact commit message contains `re-record QA results after fix attempt 1` per FR-12.
- The adopt phase calls `adopt-qa-test.sh`, prints the new path to stdout, and commits the adoption with the FR-4 verbatim message.
- `finalizing-workflow`'s safety-net (FR-9) does NOT trip because no `qa-*` files remain (the adoption moved them all).
- The full workflow advances through `finalizing-workflow` to merge.

A negative-variant test asserts the safety-net DOES trip when adoption is skipped (simulate user manually deleting the `addressing-qa-findings` invocation): the `qa-*` file remains; finalize blocks with the FR-9 verbatim error message.

#### Implementation Steps

1. Build the fixture at `tests/fixtures/feat-032-known-buggy/`:
   - Minimal vitest project (`package.json`, `vitest.config.ts`, `src/`, `tests/unit/`)
   - A peer test `tests/unit/buggy-fn.test.ts` (the existing test for the SUT)
   - A deliberately-buggy production file `src/buggy-fn.ts` (returns wrong value for one input)
   - A pre-authored QA test `tests/unit/qa-input-validation.test.ts` (imports `../../src/buggy-fn` so the SUT is resolvable; asserts the failing input)
   - A capability JSON snapshot (so `executing-qa` re-QA mode auto-detects correctly)
   - The pre-existing `qa-baseline.sh` marker file `.sdlc/qa/.executing-qa-baseline-FEAT-032-FIXTURE` (so re-QA mode auto-detects correctly per FR-3)
   - A pre-populated workflow-state file `.sdlc/workflows/FEAT-032-FIXTURE.json` (verdict slot empty; orchestrator populates on first run)
   - A sibling `README.md` documenting intended outcomes (per FEAT-030 fixture convention)

2. Write `tests/bats/skills/orchestrating-workflows/qa-loop-end-to-end.bats` (new): drives the full path against the fixture using the existing Bats fixture-runner pattern. Asserts every load-bearing FR-12 / FR-4 / FR-9 contract verbatim. The test runs against a copy of the fixture (does not mutate the source fixture) using a temp-dir setup similar to the existing `prepare-fork.bats` / `feat-030-executing-qa.test.ts` patterns.

3. Write `tests/bats/skills/orchestrating-workflows/qa-loop-end-to-end-safety-net.bats` (negative variant): same fixture; manually skip the adopt-phase invocation; assert the safety-net trips at finalize with the FR-9 verbatim error message naming the un-adopted `qa-*` file.

4. Run `npx bats tests/bats/skills/orchestrating-workflows/qa-loop-end-to-end*.bats | tail -30` and `npm test | tail -120` and `npm run validate` to confirm the entire suite passes including the new end-to-end fixtures.

5. Confirm acceptance: every acceptance-criterion bullet from the requirements doc maps to a passing test from this phase or a prior phase. Compile the mapping in the PR body's `## Acceptance Criteria Coverage` section (one bullet per AC, citing the Bats / Vitest test file that asserts it).

#### Deliverables

- [ ] `tests/fixtures/feat-032-known-buggy/` (fixture directory: vitest project + peer test + buggy SUT + QA test + capability JSON + baseline marker + workflow-state file + README)
- [ ] `tests/bats/skills/orchestrating-workflows/qa-loop-end-to-end.bats` (NFR-4 happy-path integration)
- [ ] `tests/bats/skills/orchestrating-workflows/qa-loop-end-to-end-safety-net.bats` (negative variant — safety-net trips when adoption skipped)

---

## Shared Infrastructure

- **`workflow-state.sh` (Phase 1)** is the single state-mutation surface for the new fields and pause reasons. Phase 2's `addressing-qa-findings` skill reads via `get-qa-state`; Phase 4's `qa-dispatch.sh` reads via `get-qa-state` and writes via `inc-qa-fix-attempts` / `set-qa-verdict` / `record-adopted-test`; the resume path writes via `reset-qa-fix-attempts`.
- **`adopt-qa-test.sh` (Phase 2)** is the **sole** owner of QA-test deletion per FR-13. The FR-13 negative test (Phase 2) ensures no other surface deletes `qa-*` files.
- **The FR-3 v1 glob set** (`tests/unit/qa-*.test.ts`, `tests/unit/qa-*.test.js`, `tests/bats/qa/qa-*.bats`) is the single source of truth for "which QA test files exist". It is consulted by Phase 3 (re-QA auto-detect), Phase 2 (adopt-phase iteration), and Phase 5 (safety-net check). The forward-compat globs (`qa-*.py`, `qa-*.go`) are no-ops in v1 across all three consumers per Edge Case 17 (lockstep constraint).
- **The FR-12 artifact-overwrite contract** is consumed by Phase 2 (`addressing-qa-findings` always reads the current artifact) and Phase 5 (safety-net only sees one canonical artifact file).
- **Caveman Lite prose** applies throughout per repo authoring convention. Load-bearing carve-outs documented at each phase.

## Testing Strategy

**Unit (Bats / Vitest)**: per-script Bats sibling alongside every new script (Phase 1: 3 Bats; Phase 2: 4 Bats; Phase 3: 3 Bats; Phase 4: 3 Bats; Phase 5: 1 Bats; Phase 7: 2 Bats). Phase 6 ships Vitest changes (`shared-scripts.test.ts` plus FR-11 audit-driven changes). Coverage targets per NFR-4: happy path, every documented exit code, edge cases the requirements doc enumerates.

**Integration (Bats end-to-end)**: Phase 7 ships the full `ISSUES-FOUND → fix → re-QA → adopt → finalize` integration against a known-buggy fixture branch, plus a negative-variant asserting the FR-9 safety-net trips when adoption is skipped. Repo test framework is vitest-only for unit tests; the integration test is Bats because it drives shell-script orchestration end-to-end.

**Backward compatibility (NFR-3)**: Phase 1 Bats covers loading a pre-FEAT-032 workflow-state fixture (no `qaFixAttempts` / `qaLastVerdict` / `adoptedTests` fields); subsequent mutation persists defaults without error. Phase 3 confirms initial-run path (no marker, no QA files) is unchanged. Phase 4 confirms PASS-on-first-run (verdict `PASS` AND `qaFixAttempts == 0`) advances directly to `finalizing-workflow` per FR-7 without invoking `addressing-qa-findings`.

## Dependencies and Prerequisites

- Existing scripts: `workflow-state.sh`, `parse-qa-return.sh`, `parse-model-flags.sh`, `check-resume-preconditions.sh` (orchestrating-workflows); `capability-discovery.sh`, `qa-baseline.sh`, `render-qa-results.sh`, `commit-qa-tests.sh`, `run-framework.sh`, `stop-hook.sh` (executing-qa); `preflight-checks.sh`, `finalize.sh` (finalizing-workflow); `resolve-requirement-doc.sh` (plugin-shared).
- `bats-core` (already in use across the plugin).
- `gh` CLI (already required by the workflow).
- `jq` (already required by `workflow-state.sh`).
- `vitest` (repo test framework; required by Phase 6's Vitest changes).
- No new external dependencies.

## Risk Assessment

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Phase 2's `addressing-qa-findings` skill is novel; the fix-phase prose risks drifting into "do whatever the agent thinks" rather than the FR-4 deterministic batch | High | Med | Phase 2 SKILL.md is intentionally lean per repo authoring convention; the load-bearing logic (phase auto-detect, batch processing, return contracts) is in scripts and pinned by Bats; the FR-13 negative test catches deletion-rule violations at test time. |
| `adopt-qa-test.sh` SUT-resolution heuristic is brittle on unusual import patterns (path aliases, relative `../../../` chains) | Med | High | Phase 2 ships exit-2 with a structured stderr message naming the QA test path and the reason; the orchestrator pauses with `adoption-failed` per FR-5 / Edge Case 14 so the user gets a clear failure mode; v2 (issue #265) handles AST-aware rewriting. |
| Loop-counter state persists across resumed sessions but the orchestrator cannot reliably distinguish "fresh fix attempt" from "stale state from a prior failed attempt" | Med | Med | Phase 1 ships `reset-qa-fix-attempts` for the `--qa-loop-cap` resume path; Phase 4 records each increment as a state event per Edge Case 15 so the loop history is traceable; the workflow-state file is the single source of truth. |
| Phase 3's re-QA auto-detect produces a false positive (marker exists from a prior workflow but QA files were manually deleted) | Med | Low | Phase 3 emits verdict `ERROR` with the verbatim NFR-2 reason ("re-QA invoked but no prior QA test files found for {ID}"); orchestrator pauses with `qa-error` per Edge Case 8; user resolves manually. |
| The FR-11 audit misses a length-based assertion that subsequently trips on a `*.qa.*` sibling, breaking CI | Med | Low | The audit is recorded in the PR body's `## Length-Assertion Audit` table per the requirements doc; reviewers can cross-check against the table; if a missed assertion trips later, it is a single-line fix and the table makes it easy to add the new entry. |
| FR-9 safety-net error message text drifts between the script and the Bats assertion | Low | Low | Phase 5 Bats pins the error message verbatim per FR-9 / load-bearing carve-out; any drift is caught at test time. |
| Phase 6's CLAUDE.md edits drop a load-bearing prose item (e.g., the Edge Case 17 lockstep note) | Low | Med | Phase 6 verification step 5 includes a content checklist: lifecycle, convention, safety-net, chain-update, Edge Case 17; reviewer can grep CLAUDE.md for each. |
| Phase 7's end-to-end fixture is brittle to plugin-internal path changes | Low | Med | The fixture uses absolute paths via `${CLAUDE_PLUGIN_ROOT}` (matching the existing `feat-030-executing-qa.test.ts` pattern); any path drift is caught by the integration test failing fast. |
| Per-workflow cost (NFR-1) exceeds the projected ~4× single-pass cost | Med | Low | NFR-1 caps cost via `qaLoopCap=2` default; users can opt into N=3 via `--qa-loop-cap 3` (Phase 1 / Phase 4); manual abandon is always available. |

## Success Criteria

- **Phase 1**: `workflow-state.sh` accepts the four new pause reasons; rejects unknown reasons with the verbatim FR-7a message; the three new state fields default cleanly per NFR-3 migration; `parse-model-flags.sh` accepts `--approve-advance` / `--qa-loop-cap <N>` and rejects the combination per FR-8 verbatim message; all Phase 1 Bats pass.
- **Phase 2**: `addressing-qa-findings/SKILL.md` exists with developer persona; `adopt-qa-test.sh` deterministically adopts Vitest and Bats QA tests per FR-5 / FR-6; FR-13 negative test passes (no other surface deletes `qa-*` files); fix-phase + adopt-phase Bats pass; `npm run validate` clean.
- **Phase 3**: `executing-qa` re-QA mode auto-detects per the FR-3 conjunction; per-finding `## Reproduction` blocks embed language-aware fences per FR-2; FR-12 artifact commit lands with the verbatim message templates; FR-13 ownership invariant holds (re-QA never deletes); all Phase 3 Bats pass.
- **Phase 4**: `qa-dispatch.sh` emits the correct dispatch token for every FR-7 row; loop cap pauses at `qaFixAttempts == 2` per FR-8; resume flags dispatch correctly (`--approve-advance` advances with counter preserved; `--qa-loop-cap <N>` resets counter and continues); Edge Case 15 state events recorded; all Phase 4 Bats pass.
- **Phase 5**: `preflight-checks.sh` safety-net subshell trips on tracked `qa-*` files per FR-9; passes on `*.qa.*` adopted siblings; verbatim error message pinned by Bats; all Phase 5 Bats pass.
- **Phase 6**: `tests/unit/shared-scripts.test.ts` parity assertion is set-based (FR-10 hard-coded `14` removed); FR-11 audit list complete and applied; `CLAUDE.md` documents the FR-14 lifecycle + `*.qa.*` convention + safety-net + chain updates + Edge Case 17 lockstep; full repo test suite green.
- **Phase 7**: End-to-end Bats fixture exercises the full `ISSUES-FOUND → fix → re-QA → adopt → finalize` path no shortcuts; negative variant confirms the FR-9 safety-net trips when adoption is skipped; every acceptance-criterion bullet maps to a passing test (recorded in the PR body's `## Acceptance Criteria Coverage` section).
- **Overall**: issue #267 closes on merge via `Closes #267` in the PR body; #260 and #262 are superseded; #265 (v2 adoption) and #266 (one-time cleanup) are unblocked; per-workflow QA cost stays within the NFR-1 cap (~4× single-pass for N=2).
