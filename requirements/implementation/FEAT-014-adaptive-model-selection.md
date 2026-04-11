# Implementation Plan: Adaptive Model Selection for Forked Subagents

## Overview

Update the `orchestrating-workflows` skill so each forked subagent step selects its model adaptively based on step baseline demands and work-item complexity signals, rather than silently inheriting the parent conversation's model (typically Opus). The implementation is intentionally scoped to the orchestrator alone — sub-skills (`reviewing-requirements`, `creating-implementation-plans`, `implementing-plan-phases`, `executing-chores`, `executing-bug-fixes`, `finalizing-workflow`) are **not** modified and do not gain `context: fork` frontmatter. All behavioral changes flow from the orchestrator mutating its own fork call sites to pass an explicit `model` parameter plus supporting state-file extensions.

Work spans three artifacts: the orchestrator `SKILL.md` (fork call sites, classification logic, new "Model Selection" section), the companion `workflow-state.sh` shell script (new state fields, `set-complexity` / `get-model` subcommands, backward-compat for pre-existing state files), and a brand-new `references/model-selection.md` document (the `references/` subdirectory does not yet exist under the orchestrator skill and is created as part of this change).

## Features Summary

| Feature ID | GitHub Issue | Feature Document | Priority | Complexity | Status |
|------------|--------------|------------------|----------|------------|--------|
| FEAT-014   | [#130](https://github.com/lwndev/lwndev-marketplace/issues/130) | [FEAT-014-adaptive-model-selection.md](../features/FEAT-014-adaptive-model-selection.md) | High | High | Pending |

## Recommended Build Sequence

### Phase 1: State Schema and Script Helpers
**Feature:** [FEAT-014](../features/FEAT-014-adaptive-model-selection.md) | [#130](https://github.com/lwndev/lwndev-marketplace/issues/130)
**Status:** ✅ Complete

#### Rationale
- Establishes the persistence contract (`complexity`, `complexityStage`, `modelOverride`, `modelSelections`) that every subsequent phase reads and writes. Getting the schema right up front prevents churn when the classification algorithm and fork mutations start depending on it.
- Puts the `set-complexity` and `get-model` subcommands (FR-15) in place early so later phases — and humans running dry-run inspections while testing — can drive state without hand-editing JSON.
- Forces the backward-compatibility decisions (FR-13) to be codified in one place: missing `complexity` → compute-on-resume, missing `modelOverride` → null, missing `modelSelections` → fresh array, and the one-shot parent-model fallback path.
- Shell-script changes are the smallest blast radius in the codebase and can be covered by bats/shell unit tests without touching orchestrator SKILL.md at all, which keeps Phase 1 independently reviewable and mergeable.

#### Implementation Steps
1. Extend `workflow-state.sh` `init` subcommand to write the four new fields with their init defaults: `complexity: null`, `complexityStage: "init"`, `modelOverride: null`, `modelSelections: []`.
2. Add a defensive read path — every subcommand that reads state performs an in-place migration for pre-existing state files missing any of the four fields (FR-13). Migration is silent except for a single debug log line.
3. Implement the `set-complexity <ID> <tier>` subcommand. Validates tier is `low|medium|high`, writes to `complexity` (not `modelOverride`), leaves `complexityStage` untouched (documented behavior: manual override is considered a user edit, not a stage transition).
4. Implement the `get-model <ID> <step-name>` subcommand. This is a pure-bash lookup using the step baselines table (hardcoded in the script for determinism) and the persisted `complexity` + `modelOverride`. It does **not** parse CLI flags (flags are orchestrator-scope, not state-scope) — document that limitation in the subcommand help text.
5. Add a `record-model-selection <ID> <stepIndex> <skill> <mode> <phase> <tier> <complexityStage> <startedAt>` subcommand that appends to the `modelSelections` array. This is the hook Phase 3 calls from the orchestrator.
6. Write unit tests (bats or plain shell) covering: fresh init produces the four fields, migration adds missing fields without clobbering existing data, `set-complexity` round-trips through read, `get-model` returns the step baseline floor, `get-model` honours `complexity` upgrade, `record-model-selection` appends without overwriting earlier entries, and invalid tier values are rejected with a non-zero exit code.

#### Deliverables
- [x] Updated `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh` with four new state fields, `set-complexity`, `get-model`, and `record-model-selection` subcommands
- [x] Backward-compatibility migration path for pre-existing state files in the same script
- [x] Shell script unit tests (extended `scripts/__tests__/workflow-state.test.ts` with 33 new vitest cases covering init defaults, FR-13 migration, `set-complexity`, `get-model`, and `record-model-selection`)

---

### Phase 2: Classification Algorithm
**Feature:** [FEAT-014](../features/FEAT-014-adaptive-model-selection.md) | [#130](https://github.com/lwndev/lwndev-marketplace/issues/130)
**Status:** ✅ Complete

#### Rationale
- Depends on Phase 1 because every signal extractor needs somewhere to persist its result. Running second (not first) keeps the persistence contract stable while the algorithm logic churns.
- This is the highest-risk, highest-signal phase — it contains the FR-2a/FR-2b two-stage classifier, the FR-3 precedence chain walker, and the FR-5 hard-vs-soft override distinction. All three are independently testable in isolation before being wired into fork call sites.
- Building the classifier before mutating fork call sites means Phase 3 can rely on a tested, working `resolve-tier` function and not have its fork mutations blocked on classifier bugs. It also means the unit test matrix for the classifier is authored against synthetic inputs, not against real workflow state.
- Establishes the canonical signal-extractor implementations (markdown regex / section parsing) that live in the orchestrator SKILL.md as documented-in-prose pseudocode — the algorithm must be legible to a human reading the SKILL, not just executable by the orchestrator.

#### Implementation Steps
1. Add work-item signal extractors to the orchestrator SKILL.md (documented as markdown-prose algorithm the orchestrator follows at workflow init). Cover the three chain types:
   - **Chore**: acceptance criteria count → low/medium/high buckets (≤3 / 4–8 / 9+).
   - **Bug**: severity field, RC-N count, category — take `max` of signal tiers, then bump one tier if category is `security` or `performance`.
   - **Feature (init stage)**: FR count → bucket, bump one tier if NFR section mentions security/auth/perf.
   - **Feature (post-plan stage, FR-2b)**: phase count from the implementation plan at `requirements/implementation/{ID}-*.md` → bucket. Apply upgrade-only `max(persisted, phase_count_tier)`.
2. Document the `max` tier helper (`haiku < sonnet < opus`) in pseudocode inside SKILL.md.
3. Document the FR-3 resolution algorithm in SKILL.md as step-by-step pseudocode that mirrors the requirement doc's pseudocode verbatim: start at baseline, apply work-item complexity unless baseline-locked, walk the override chain in FR-5 order (hard=replace, soft=max), first non-null wins.
4. Document the hard-vs-soft override distinction explicitly, including the baseline-locked interaction: hard overrides bypass baseline locks and may downgrade; soft overrides respect baseline locks and are upgrade-only.
5. Document the unparseable-signal fallback (FR-10): missing signals → `sonnet` work-item complexity, **never** `opus`.
6. Add unit tests for every classification scenario (synthetic requirement-doc fixtures under a test fixtures directory). Matrix covers:
   - Every override precedence level (FR-5 #1 through #4 plus computed tier) returning the correct value, including hard-below-baseline and soft-no-downgrade behaviour.
   - Chore signal extractor at each bucket boundary.
   - Bug signal extractor covering every severity value, every category bump, and the `max` of severity+RC count.
   - Feature init-stage extractor with and without the security/auth/perf bump.
   - Feature post-plan upgrade path: init `sonnet` + 4 phases → `opus`; init `opus` + 1 phase → still `opus` (upgrade-only).
   - Baseline-locked steps ignore work-item complexity and soft overrides but honour hard overrides.
   - Unparseable-signal fallback returns `sonnet`.

#### Deliverables
- [x] Work-item signal extractor pseudocode in `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` (documented, not yet wired to fork sites)
- [x] FR-3 tier-resolution algorithm pseudocode in the same SKILL.md
- [x] Synthetic requirement-doc test fixtures (chore, bug, feature × low/medium/high)
- [x] Unit tests covering every precedence level, both baseline-lock behaviors, two-stage upgrade, and unparseable-signal fallback

#### Depends on Phase 1

---

### Phase 3: Fork Call Site Mutations, Console Echo, and Audit Trail
**Feature:** [FEAT-014](../features/FEAT-014-adaptive-model-selection.md) | [#130](https://github.com/lwndev/lwndev-marketplace/issues/130)
**Status:** ✅ Complete

#### Rationale
- Runs after Phase 2 because every fork call site needs the resolution algorithm to hand it a concrete tier. Mutating call sites before the classifier exists would leave the orchestrator in a half-state where some forks have `model` and some don't.
- Ships the user-visible half of the feature — the console echo (FR-14) and the `modelSelections` audit trail (FR-7, NFR-3). Without these, operators cannot answer "why did this run on opus?" without digging into classifier internals.
- Wiring the audit-trail `record-model-selection` call **before** each fork begins (not after it completes) is load-bearing for NFR-3: a mid-fork crash must leave an accurate record of which model was chosen. Phase 3 enforces this ordering contract in every call site.
- Also introduces FR-8's CLI argument parser for `--model`, `--complexity`, `--model-for`. These flags are additive to the existing ID / `#N` / title argument parser and must not regress existing invocation shapes.

#### Implementation Steps
1. Extend the orchestrator's argument parser to recognize `--model <tier>`, `--complexity <tier>`, and `--model-for <step>:<tier>`. Existing argument shapes (ID, `#N`, free-text title) must still work; model flags are additive and positional-independent.
2. At workflow init (after the documenting step creates the requirement artifact), call the Phase 2 classifier to compute initial work-item complexity, persist to state via `workflow-state.sh set-complexity`, and mark `complexityStage: "init"`.
3. Mutate every Agent-tool fork call site in `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` to pass an explicit `model` parameter resolved via the FR-3 algorithm. Expected call sites (line numbers from the requirement doc are approximate and may drift during edits):
   - `~line 320` — `reviewing-requirements` standard mode fork
   - `~line 327` — `creating-implementation-plans` fork
   - `~line 421` — `implementing-plan-phases` per-phase fork
   - `~line 464` — `executing-chores` / `executing-bug-fixes` execution fork
   - `~line 532` — `finalizing-workflow` fork (baseline-locked tier)
   - Plus the inline PR-creation fork (baseline-locked, `haiku`)
   - Plus the `reviewing-requirements` test-plan and code-review reconciliation forks (each must resolve tier independently at its own invocation because post-plan upgrades apply)
4. Immediately before each fork invocation, write a `modelSelections` entry via `workflow-state.sh record-model-selection`. The write happens **before** the fork, not after, so a crashed fork still leaves a trace (NFR-3).
5. Immediately before each fork invocation, emit the FR-14 console echo line. Derivation components (`baseline=`, `wi-complexity=`, `override=`) must match the format in the requirement doc verbatim so operators can grep for them reliably. Baseline-locked forks use the `baseline-locked` tag instead of `wi-complexity`.
6. After step 3 (`creating-implementation-plans`) completes in a feature chain, trigger FR-2b post-plan re-classification: read the implementation plan, compute phase-count tier, apply upgrade-only `max`, persist updated `complexity` and `complexityStage: "post-plan"` to state. This step must run **before** any subsequent fork resolves its tier.
7. Integration tests: drive the orchestrator end-to-end against synthetic chore, bug, and feature work items (fixtures from Phase 2). Assertions cover tier assignment per step, audit trail entries per step, and console echo content per fork. Verify Example A (low chore) produces zero Opus forks, Example B (low bug) produces zero Opus forks, Example C (two-stage feature) shows the stage transition in the audit trail.

#### Deliverables
- [x] Updated CLI argument parser in `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` supporting `--model`, `--complexity`, `--model-for`
- [x] Every Agent-tool fork call site in the orchestrator SKILL.md passes an explicit `model` parameter
- [x] `workflow-state.sh record-model-selection` invoked before every fork (audit trail write precedes fork execution)
- [x] FR-14 console echo line emitted before every fork
- [x] Post-plan re-classification (FR-2b) wired between step 3 and step 4
- [x] Integration tests covering Examples A, B, C from the requirement doc

#### Depends on Phases 1 and 2

---

### Phase 4: Retry, Resume, and Version Compatibility
**Feature:** [FEAT-014](../features/FEAT-014-adaptive-model-selection.md) | [#130](https://github.com/lwndev/lwndev-marketplace/issues/130)
**Status:** ✅ Complete

#### Rationale
- These three concerns (FR-11 retry, FR-12 resume, NFR-6 version compat) all wrap the fork call sites mutated in Phase 3 — they are safest to build on top of a working happy path rather than interleaved with it.
- FR-11's retry-with-tier-upgrade is surgical: it only triggers on classifier-flagged failures (empty artifact, tool-use loop limit), so the implementation must distinguish real under-provisioning from user-authored findings (a `reviewing-requirements` fork returning "found issues" is not a failure). Building this as a separate phase keeps that distinction explicit and testable.
- FR-12's resume path re-enters the classification pipeline from Phase 2 under slightly different rules — stage-aware (don't re-read plan if still in `init`), upgrade-only (never silently downgrade on resume), with an explicit escape-hatch via `set-complexity`. Ties together Phase 1's state fields and Phase 2's classifier into the resume entry point.
- NFR-6 is the production-safety item: the Agent tool's `model` parameter only exists on Claude Code 2.1.72+. The fallback path (retry fork once without `model` parameter, log a warning) is the only place in the post-change codebase where parent-model inheritance is allowed. It must be bulletproof.

#### Implementation Steps
1. Add a Claude Code version check to the orchestrator init path. If version is below 2.1.72 (NFR-6), log the warning and continue — subsequent forks will use parent-model inheritance via the fallback path.
2. Wrap every Agent-tool fork call in the orchestrator SKILL.md with the NFR-6 fallback: if the tool call errors with an unknown-parameter error on `model`, retry once without the `model` parameter and emit the documented warning line. This is a per-call-site wrapper, not a global setting, so it interacts correctly with FR-11's retry-with-upgrade.
3. Implement FR-11 retry-with-tier-upgrade. Failure classifier recognises: empty artifact returned, tool-use loop limit hit. Each fork's retry budget is 1 (matches the requirement doc). Tier escalation: `haiku → sonnet → opus → fail`. A `reviewing-requirements` fork that returns structured findings is **not** classified as a failure. Retries append a new `modelSelections` entry (audit trail preserves both the initial attempt and the retry).
4. Implement FR-12 resume re-computation. On orchestrator re-invocation with an existing state file:
   - Read `complexityStage`.
   - Re-compute init-stage signals from the requirement doc (always).
   - If stage is `post-plan`, also re-read phase count from `requirements/implementation/{ID}-*.md`.
   - Compute `new_tier = max(persisted_complexity, newly_computed_tier)` (upgrade-only).
   - If upgraded, log the one-line info message and persist the new tier. If unchanged, proceed silently.
   - `complexityStage` never regresses on resume.
5. Document the escape hatch: `workflow-state.sh set-complexity {ID} <lower-tier>` between pause and resume is the only way to explicitly downgrade, and is recorded as a user-authored action.
6. Integration tests covering:
   - Fork failure retry: mock an empty-artifact Haiku fork → orchestrator retries on Sonnet, audit trail contains both entries.
   - Retry exhaustion: mock failing Opus fork → orchestrator records `fail` state.
   - `reviewing-requirements` structured findings do **not** trigger retry.
   - Resume with unchanged signals is silent.
   - Resume with upgraded signals logs the one-line message and updates `complexity`.
   - Resume with a manually-downgraded `set-complexity` proceeds at the lower tier.
   - NFR-6 fallback: mock an Agent tool that rejects the `model` parameter → orchestrator retries without `model`, logs the warning, and continues. This must work independently of FR-11.
   - Pre-existing state file without the four new fields (FR-13) resumes cleanly via Phase 1's migration path, then computes complexity on first post-migration fork.

#### Deliverables
- [x] Claude Code version check in orchestrator init path (NFR-6) — `workflow-state.sh check-claude-version` subcommand wired into the Quick Start entry point
- [x] NFR-6 Agent-tool-rejection fallback wrapper around every fork call site — per-call-site prose in the shared Forked Steps procedure (step 7), composes with the FR-11 retry wrapper
- [x] FR-11 retry-with-tier-upgrade logic with failure classifier — `workflow-state.sh next-tier-up` helper + prose in the shared Forked Steps procedure (step 8) defining the classifier (empty artifact, tool-use loop limit) and the `haiku → sonnet → opus → fail` progression
- [x] FR-12 stage-aware, upgrade-only resume re-computation — `workflow-state.sh resume-recompute` subcommand + prose at the top of the Resume Procedure section (step 2), including the `set-complexity` escape hatch
- [x] Integration tests for retry paths, resume paths, and version compatibility — 27 new tests across `scripts/__tests__/workflow-state.test.ts` and `scripts/__tests__/orchestrating-workflows.test.ts` covering `next-tier-up` escalation, retry audit trail, retry exhaustion, reviewing-requirements non-retry, `resume-recompute` silent/upgrade/downgrade-blocked/stage-preserving paths, FR-13 legacy migration + first-post-migration compute, and NFR-6 version check happy/sad/graceful paths

#### Depends on Phase 3

---

### Phase 5: Documentation
**Feature:** [FEAT-014](../features/FEAT-014-adaptive-model-selection.md) | [#130](https://github.com/lwndev/lwndev-marketplace/issues/130)
**Status:** ✅ Complete

#### Rationale
- Documentation runs last so NFR-1's "Model Selection" SKILL.md section reflects the shipped behavior rather than the planned behavior. Writing it alongside Phase 2 or 3 risks doc drift as the algorithm is tuned.
- NFR-2's standalone reference document is longer and more tutorial-style than the in-SKILL section — it belongs in a dedicated references file. This phase also creates the `references/` subdirectory under the orchestrator skill (which does not yet exist).
- Creates the final acceptance-criteria hook for NFR-1 and NFR-2: the review step at phase close can grep for the new section heading and the new file respectively.

#### Implementation Steps
1. Insert a new top-level "Model Selection" section in `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` between the existing "Step Execution" and "Error Handling" sections. Contents:
   - Step baseline matrix (Axis 1 from the requirement doc).
   - Work-item complexity signal matrix (Axis 2).
   - Override precedence documentation (Axis 3) including hard vs soft distinction.
   - Baseline-locked step exceptions.
   - Worked examples for all three chain types at low/medium/high complexity (the requirement doc's Examples A, B, C, D — condensed where appropriate).
2. Create the `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/` subdirectory (does not exist yet).
3. Author `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/model-selection.md` with:
   - Full FR-3 classification algorithm pseudocode.
   - Tuning guidance for per-step baselines if empirical quality differs from theory.
   - How to read the `modelSelections` audit trail (field-by-field).
   - Known limitations (e.g., "Haiku is never selected for `implementing-plan-phases` regardless of signals — the Sonnet baseline floor enforces this").
   - Migration guidance for users who want the old inherit-parent behavior (`--model opus` on every invocation, or a shell wrapper).
   - Cross-reference back to FR-5 for why requirement docs do not gain complexity/model-override frontmatter.
4. Run `npm run validate` — ensures the new references file and the edited SKILL.md still pass schema validation and that the plugin's assets are consistent.

#### Deliverables
- [x] "Model Selection" section added to `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` between "Step Execution" and "Error Handling" (positioned immediately before "Error Handling"; consolidates the Phase 2 prose section and adds the Axis 1 / Axis 2 / Axis 3 matrices, baseline-locked exceptions, and condensed worked Examples A–D)
- [x] New `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/` subdirectory
- [x] New `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/model-selection.md` per NFR-2 (full FR-3 pseudocode, full signal-extractor pseudocode, tuning guidance, audit-trail field reference with `jq` recipes, known limitations, migration guidance, and FR-5 cross-reference)
- [x] `npm run validate` passes (13/13 checks)
- [x] 16 new Phase 5 vitest cases in `scripts/__tests__/orchestrating-workflows.test.ts` asserting the references file exists and contains the required content, and that the SKILL.md "## Model Selection" section is positioned between "## Step Execution" and "## Error Handling" with the required matrices and worked examples

#### Depends on Phases 1–4

---

## Shared Infrastructure

- **Tier helper (`max(a, b)` over `haiku < sonnet < opus`)** — documented once in the SKILL.md algorithm section, referenced by both the classifier and the override chain walker.
- **`workflow-state.sh` as the single source of truth** for state mutations — every orchestrator write to `complexity`, `complexityStage`, `modelOverride`, or `modelSelections` goes through a subcommand. No inline `jq` edits from SKILL.md.
- **Test fixtures directory** for synthetic requirement documents — authored in Phase 2, reused in Phase 3 and Phase 4 integration tests.

## Testing Strategy

- **Shell unit tests** (Phase 1) — cover every `workflow-state.sh` subcommand in isolation, including the backward-compat migration path.
- **Classifier unit tests** (Phase 2) — synthetic requirement-doc fixtures exercise every signal extractor, every override precedence level, and the two-stage feature upgrade path. Must include the unparseable-signal fallback and both baseline-lock semantics.
- **Integration tests** (Phase 3) — end-to-end orchestrator runs against synthetic chore, bug, and feature work items. Assert tier per fork, audit trail contents, console echo format.
- **Retry and resume integration tests** (Phase 4) — inject mock fork failures and re-invocation scenarios. Must cover NFR-6 Agent-tool-rejection fallback as a first-class test case.
- **Manual acceptance tests** — run a real chore workflow on this repo and confirm zero Opus forks in the audit trail; run a real low-severity bug chain and confirm the same; run a synthetic high-complexity feature via `--complexity high` and confirm Opus forks appear for review/plan/phase steps but not for finalize.

## Dependencies and Prerequisites

- **Claude Code ≥ 2.1.72** — per NFR-6, the Agent tool's per-invocation `model` parameter was restored in this version. Older versions degrade gracefully via the NFR-6 fallback, but the feature is not functional without this minimum.
- **Existing `orchestrating-workflows` skill** and its `workflow-state.sh` script — all fork call sites to be mutated are in SKILL.md, all state mutations go through the script.
- **`jq`** — already required by `workflow-state.sh` for JSON manipulation.
- **No new npm dependencies** — the feature is entirely internal to the orchestrator skill.
- **Requirement document templates remain unchanged** — no frontmatter is added (FR-5 / removed FR-6).

## Risk Assessment

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Regression in existing chore/bug/feature chains — fork call site mutations break a currently-working orchestrator path | High | Medium | Phase 3 integration tests cover every existing chain end-to-end against fixtures. Phase 1 is independently mergeable, so any regression is scoped to Phase 3's fork mutations and easily reverted. |
| Claude Code version compatibility — users on < 2.1.72 hit tool-call errors on every fork | High | Low | NFR-6 fallback (Phase 4) catches the `model`-parameter rejection and retries once without `model`, emitting a one-line warning. Version check at orchestrator init emits an advisory warning. |
| Classification edge cases — requirement docs with missing/unparseable signals produce wrong tier | Medium | Medium | FR-10 fallback to `sonnet` (never `opus`) is the hard floor. Phase 2 unit tests exercise unparseable-doc fixtures explicitly. FR-13 backward-compat covers state files with no signals at all. |
| Missing phases on post-plan re-classification — feature chain transitions to `post-plan` stage but the implementation plan file is absent or malformed | Medium | Low | NFR-5 explicit handling: retain init-stage tier, log a warning, do not upgrade. FR-2b is upgrade-only so the failure mode is "stays at current tier" rather than "downgrades silently". |
| Audit trail corruption — concurrent writes to `modelSelections` or partial JSON from a crashed `record-model-selection` subcommand | Medium | Low | `workflow-state.sh` uses `jq` with temp-file-and-rename for atomic writes (existing pattern). Phase 1 unit tests verify `record-model-selection` appends cleanly across multiple invocations. |
| Performance impact of signal parsing on every workflow init and resume | Low | Low | Signal parsing is grep/regex over a single markdown file — tens of milliseconds at worst. FR-12 resume re-reads the doc but bounds the cost to two file reads (doc + optional plan). No network calls. |
| Documentation drift between SKILL.md "Model Selection" section and `references/model-selection.md` | Low | Medium | Phase 5 runs last so both docs are authored against the final implementation. Acceptance criteria check both artifacts exist. Future maintenance should treat the references file as the canonical source and the SKILL.md section as a summary. |
| Hard-override-below-baseline surprise — `--model haiku` on a feature produces visibly worse review output | Medium | Low | Edge Case #11 in the requirement doc mandates a one-line baseline-bypass warning. Phase 3 emits this warning so users cannot downgrade silently. |

## Success Criteria

Mapping to the Acceptance Criteria in the requirement doc:

- **Documentation (NFR-1, NFR-2)** — Phase 5 delivers the SKILL.md "Model Selection" section and `references/model-selection.md`. Both artifacts exist and pass `npm run validate`.
- **Initial and post-plan classification (FR-2a, FR-2b)** — Phase 2 implements the classifier; Phase 3 invokes it at workflow init (init stage) and after step 3 (post-plan upgrade). Chore and bug chains stop at init stage.
- **Chore signal uses acceptance criteria count only** — Phase 2 chore extractor intentionally does not read affected files count.
- **`modelSelections` audit trail as array, written pre-fork (FR-7, NFR-3)** — Phase 1 schema + Phase 3 ordering contract (write precedes fork).
- **Explicit `model` parameter on every fork (FR-9)** — Phase 3 mutates every call site in SKILL.md.
- **Console echo (FR-14)** — Phase 3 emits the one-line echo before each fork.
- **Baseline-locks (FR-4)** — Phase 2 algorithm respects them for work-item complexity and soft overrides; hard overrides bypass them.
- **Sonnet baselines (FR-1, Axis 1)** — Phase 2 tier resolution enforces them as a floor for non-baseline-locked steps.
- **No silent Opus (NFR-4)** — enforced by the combination of FR-10 unparseable-signal fallback (`sonnet` not `opus`) and NFR-6 Agent-tool-rejection fallback (parent inheritance only as last-resort).
- **No requirement-doc frontmatter (removed FR-6)** — by construction; no phase touches requirement document templates.
- **`modelOverride` state field editable between pause and resume (FR-7, FR-12)** — Phase 1 adds the field; Phase 4 resume path honours manual edits.
- **CLI flags (FR-8)** — Phase 3 extends the argument parser.
- **Override precedence chain (FR-5)** — Phase 2 implements the walker; Phase 3 invokes it at every fork site.
- **Hard vs soft override distinction** — Phase 2 unit tests cover both behaviors explicitly.
- **Unparseable-signal fallback to Sonnet (FR-10)** — Phase 2.
- **No auto-downgrade below baseline** — Phase 2 classifier + Phase 4 upgrade-only resume.
- **`set-complexity` / `get-model` subcommands (FR-15)** — Phase 1.
- **Fork failure retry (FR-11)** — Phase 4.
- **Resume re-computation (FR-12)** — Phase 4.
- **Alias-form tier values (NFR-6)** — Phase 3 passes `sonnet`/`opus`/`haiku` verbatim.
- **Minimum Claude Code version enforcement (NFR-6)** — Phase 4.
- **Agent-tool rejection fallback (NFR-6)** — Phase 4.
- **Backward compatibility (FR-13)** — Phase 1 migration path + Phase 4 resume integration test.
- **Acceptance tests for Examples A/B/C/D** — Phase 3 integration tests against the synthetic fixtures authored in Phase 2.
- **`npm run validate` passes** — Phase 5 final gate.

## Code Organization

```
plugins/lwndev-sdlc/skills/orchestrating-workflows/
├── SKILL.md                          # Phase 2 algorithm prose, Phase 3 fork mutations, Phase 5 "Model Selection" section
├── scripts/
│   └── workflow-state.sh             # Phase 1 state fields, set-complexity, get-model, record-model-selection
├── references/                       # NEW (Phase 5) — subdirectory does not exist today
│   └── model-selection.md            # NEW (Phase 5) — NFR-2 reference doc
└── tests/                            # Shell and classifier unit tests + integration fixtures
    ├── workflow-state.test.sh        # Phase 1 — shell unit tests
    ├── classifier.test.*             # Phase 2 — unit tests with synthetic fixtures
    ├── fixtures/                     # Phase 2 — synthetic requirement docs (chore/bug/feature × low/med/high)
    └── integration/                  # Phase 3 & 4 — end-to-end orchestrator runs
```

*(Test file layout is indicative — match the existing test conventions in the orchestrator skill at implementation time.)*
