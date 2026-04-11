# QA Test Plan: Adaptive Model Selection for Forked Subagents

## Metadata

| Field | Value |
|-------|-------|
| **Plan ID** | QA-plan-FEAT-014 |
| **Requirement Type** | FEAT |
| **Requirement ID** | FEAT-014 |
| **Source Documents** | `requirements/features/FEAT-014-adaptive-model-selection.md`, `requirements/implementation/FEAT-014-adaptive-model-selection.md` |
| **Date Created** | 2026-04-11 |

## Existing Test Verification

Tests that already exist and must continue to pass (regression baseline):

| Test File | Description | Status |
|-----------|-------------|--------|
| `scripts/__tests__/workflow-state.test.ts` | Validates `workflow-state.sh` init/advance/pause/resume/fail/set-pr/phase-count/populate-phases subcommands across feature, chore, bug chains | PASS |
| `scripts/__tests__/orchestrating-workflows.test.ts` | Validates orchestrator SKILL.md frontmatter, hook wiring, `${CLAUDE_SKILL_DIR}` reference patterns, "When to Use", "Quick Start", "Verification Checklist" sections, and existing fork call site references | PASS |
| `scripts/__tests__/build.test.ts` | Validates all plugins pass `npm run validate` (catches schema regressions in modified SKILL.md and new `references/model-selection.md`) | PASS |
| `scripts/__tests__/reviewing-requirements.test.ts` | Sub-skill test must continue passing — orchestrator changes do NOT modify this skill | PASS |
| `scripts/__tests__/creating-implementation-plans.test.ts` | Sub-skill test must continue passing — orchestrator changes do NOT modify this skill | PASS |
| `scripts/__tests__/implementing-plan-phases.test.ts` | Sub-skill test must continue passing — orchestrator changes do NOT modify this skill | PASS |
| `scripts/__tests__/executing-chores.test.ts` | Sub-skill test must continue passing — orchestrator changes do NOT modify this skill | PASS |
| `scripts/__tests__/executing-bug-fixes.test.ts` | Sub-skill test must continue passing — orchestrator changes do NOT modify this skill | PASS |

## New Test Analysis

New or modified tests that should be created or verified during QA execution:

### Phase 1 — State Schema and Script Helpers

| Test Description | Target File(s) | Requirement Ref | Priority | Status |
|-----------------|----------------|-----------------|----------|--------|
| `init` writes the four new fields with init defaults: `complexity: null`, `complexityStage: "init"`, `modelOverride: null`, `modelSelections: []` | `scripts/__tests__/workflow-state.test.ts` | FR-7 | High | PASS |
| Pre-existing state file missing the four new fields receives an in-place migration on next read (silent except for one debug log line) | `scripts/__tests__/workflow-state.test.ts` | FR-13 | High | PASS |
| Migration does not clobber pre-existing data when adding missing fields | `scripts/__tests__/workflow-state.test.ts` | FR-13 | High | PASS |
| `set-complexity {ID} <tier>` writes to `complexity` (not `modelOverride`), validates tier ∈ `low\|medium\|high`, leaves `complexityStage` untouched | `scripts/__tests__/workflow-state.test.ts` | FR-15 | High | PASS |
| `set-complexity` rejects invalid tier values (`foo`) with non-zero exit code | `scripts/__tests__/workflow-state.test.ts` | FR-15, NFR-5 | High | PASS |
| `set-complexity` round-trips through subsequent state read | `scripts/__tests__/workflow-state.test.ts` | FR-15 | High | PASS |
| `get-model {ID} <step-name>` returns the step baseline floor when no complexity is set | `scripts/__tests__/workflow-state.test.ts` | FR-15, FR-1 | High | PASS |
| `get-model` honours `complexity` upgrade and returns the higher tier | `scripts/__tests__/workflow-state.test.ts` | FR-15, FR-3 | High | PASS |
| `get-model` returns baseline-locked tier (haiku) for `finalizing-workflow` regardless of `complexity` | `scripts/__tests__/workflow-state.test.ts` | FR-15, FR-4 | High | PASS |
| `get-model` does NOT parse CLI flags (state-scope only) and documents this in help text | `scripts/__tests__/workflow-state.test.ts` | FR-15 | Medium | PASS |
| `record-model-selection <ID> <stepIndex> <skill> <mode> <phase> <tier> <complexityStage> <startedAt>` appends to `modelSelections` | `scripts/__tests__/workflow-state.test.ts` | FR-7, NFR-3 | High | PASS |
| `record-model-selection` does not overwrite earlier entries across multiple invocations | `scripts/__tests__/workflow-state.test.ts` | FR-7 | High | PASS |
| `record-model-selection` writes use atomic temp-file-and-rename (existing pattern) — no partial JSON on failure | `scripts/__tests__/workflow-state.test.ts` | NFR-3 | Medium | PASS |
| `modelSelections` entries record `stepIndex`, `skill`, `mode`, `phase`, `tier`, `complexityStage`, `startedAt` per FR-7 schema | `scripts/__tests__/workflow-state.test.ts` | FR-7 | High | PASS |
| `cmd_get_model` and `cmd_resolve_tier` produce identical results for matching state-only inputs (cross-walker agreement — guards against resolver divergence after the Issue 1 self-review fix) | `scripts/__tests__/workflow-state.test.ts` | FR-3, FR-15 | High | PASS |
| `record-model-selection` rejects non-numeric `stepIndex` with a clear error message (not a cryptic `jq` failure) | `scripts/__tests__/workflow-state.test.ts` | FR-7, NFR-5 | Medium | PASS |

### Phase 2 — Classification Algorithm

| Test Description | Target File(s) | Requirement Ref | Priority | Status |
|-----------------|----------------|-----------------|----------|--------|
| Chore signal extractor: ≤3 ACs → `low`, 4–8 → `medium`, 9+ → `high` (uses ONLY acceptance criteria count, NOT affected files) | `scripts/__tests__/orchestrating-workflows.test.ts` (or new classifier test file) | FR-2a, Axis 2 | High | PASS |
| Bug signal extractor: severity field maps `low`→`low`, `medium`→`medium`, `high`/`critical`→`high` | classifier test fixtures | FR-2a, Axis 2 | High | PASS |
| Bug signal extractor: RC count maps 1→`low`, 2-3→`medium`, 4+→`high` | classifier test fixtures | FR-2a, Axis 2 | High | PASS |
| Bug signal extractor: category `security`/`performance` bumps result one tier; others do not | classifier test fixtures | FR-2a, Axis 2 | High | PASS |
| Bug signal extractor: takes `max` of severity, RC count, and category-bumped tier | classifier test fixtures | FR-2a, Axis 2 | High | PASS |
| Feature init-stage extractor: FR count buckets ≤5 → `low`, 6–12 → `medium`, 13+ → `high` | classifier test fixtures | FR-2a, Axis 2 | High | PASS |
| Feature init-stage extractor: NFR section mentioning `security`/`auth`/`perf` bumps one tier | classifier test fixtures | FR-2a, Axis 2 | High | PASS |
| Feature init-stage extractor: NFR signal matching is word-boundary aware (`author`/`performer`/`performance-test` do NOT match security/auth/perf signals) — negative-path regression after self-review Issue 3 | classifier test fixtures (`feature-nfr-false-positive.md`) | FR-2a, NFR-5 | Medium | PASS |
| Feature init-stage extractor: NFR signals inside fenced code blocks (```) are ignored — negative-path regression after self-review Issue 3 | classifier test fixtures (`feature-nfr-fenced-code.md`) | FR-2a, NFR-5 | Medium | PASS |
| Feature post-plan extractor (FR-2b): phase count buckets 1 → `low`, 2-3 → `medium`, 4+ → `high` | classifier test fixtures | FR-2b, Axis 2 | High | PASS |
| Feature post-plan upgrade is **upgrade-only**: init `sonnet` + 4 phases → `opus`; init `opus` + 1 phase → still `opus` | classifier test fixtures | FR-2b | High | PASS |
| Feature post-plan reads from `requirements/implementation/{ID}-*.md` (not the requirement doc) | classifier test fixtures | FR-2b | High | PASS |
| Chore and bug chains never enter post-plan stage; `complexityStage` stays `"init"` | classifier test fixtures | FR-2a, FR-2b | High | PASS |
| `max` tier helper returns the higher of two tiers across all 9 ordered combinations of `haiku`/`sonnet`/`opus` | classifier test fixtures | FR-3 | High | PASS |
| FR-3 precedence walker: starts at baseline, applies wi-complexity (unless baseline-locked), walks override chain — first non-null wins | classifier test fixtures | FR-3, FR-5 | High | PASS |
| FR-3 precedence walker: `--model-for` (FR-5 #1) takes precedence over `--model` (FR-5 #2) | classifier test fixtures | FR-3, FR-5 | High | PASS |
| FR-3 precedence walker: `--model` (FR-5 #2) takes precedence over `--complexity` (FR-5 #3) | classifier test fixtures | FR-3, FR-5 | High | PASS |
| FR-3 precedence walker: `--complexity` (FR-5 #3) takes precedence over state `modelOverride` (FR-5 #4) | classifier test fixtures | FR-3, FR-5 | High | PASS |
| Hard override (`--model haiku` on a Sonnet-baseline step) replaces tier and downgrades below baseline (logs warning per Edge Case 11) | classifier test fixtures | FR-3, Edge Case 11 | High | PASS |
| Soft override (`--complexity low` on a computed `opus` tier) has no effect (upgrade-only) | classifier test fixtures | FR-3, FR-5 | High | PASS |
| Soft override (state `modelOverride: opus`) on `finalizing-workflow` is ignored — baseline lock prevents upgrade | classifier test fixtures | FR-3, FR-4 | High | PASS |
| Hard override (`--model opus`) on `finalizing-workflow` bypasses baseline lock and forces opus | classifier test fixtures | FR-3, FR-4 | High | PASS |
| Baseline-locked steps (`finalizing-workflow`, PR creation): work-item complexity does NOT apply | classifier test fixtures | FR-4 | High | PASS |
| Baseline-locked steps: soft overrides (state `modelOverride`, `--complexity`) do NOT apply | classifier test fixtures | FR-4 | High | PASS |
| Unparseable signals (malformed doc, no parseable FR/NFR/AC/severity) → fall back to `sonnet`, NEVER `opus` | classifier test fixtures | FR-10, NFR-4, NFR-5 | High | PASS |
| Step baseline floor: even when work-item complexity says `haiku`, `reviewing-requirements` still runs on `sonnet` | classifier test fixtures | FR-1, FR-10 | High | PASS |
| Synthetic chore fixture (5 ACs) classifier returns `medium` → `sonnet` | classifier test fixtures | FR-2a (Example A) | High | PASS |
| Synthetic bug fixture (severity:low, 1 RC, logic-error category) classifier returns `low` → `haiku` (then floored to sonnet by FR-1) | classifier test fixtures | FR-2a (Example B) | High | PASS |
| Synthetic feature fixture (5 FRs, perf NFR) classifier returns init `medium` → `sonnet`; with 4-phase plan returns post-plan `high` → `opus` | classifier test fixtures | FR-2a/FR-2b (Example C) | High | PASS |
| Synthetic feature fixture (12 FRs, security NFR) classifier returns init `high` → `opus`; with 4 phases stays `opus` (no transition) | classifier test fixtures | FR-2a/FR-2b (Example D) | High | PASS |
| Empty requirement doc (no headings, no body) classifier returns `sonnet` (NEVER `opus`) — boundary condition for unparseable-signal fallback | classifier test fixtures | FR-10, NFR-5, Edge Case 5 | High | PASS |

### Phase 3 — Fork Call Site Mutations, Console Echo, and Audit Trail

| Test Description | Target File(s) | Requirement Ref | Priority | Status |
|-----------------|----------------|-----------------|----------|--------|
| CLI argument parser recognizes `--model <tier>` alongside existing ID/`#N`/title forms | `scripts/__tests__/orchestrating-workflows.test.ts` | FR-8 | High | PASS |
| CLI argument parser recognizes `--complexity <tier>` | `scripts/__tests__/orchestrating-workflows.test.ts` | FR-8 | High | PASS |
| CLI argument parser recognizes `--model-for <step>:<tier>` | `scripts/__tests__/orchestrating-workflows.test.ts` | FR-8 | High | PASS |
| Existing argument shapes (positional ID, `#N` issue ref, free-text title) still work after model flags are added | `scripts/__tests__/orchestrating-workflows.test.ts` | FR-8 | High | PASS |
| Model flags are positional-independent (can appear before or after the ID) | `scripts/__tests__/orchestrating-workflows.test.ts` | FR-8 | Medium | PASS |
| Invalid tier value (`--model foo`) aborts with clear error message | `scripts/__tests__/orchestrating-workflows.test.ts` | NFR-5 | High | PASS |
| Invalid `--model-for` step name (`--model-for nonexistent-skill:opus`) logs warning and ignores the flag | `scripts/__tests__/orchestrating-workflows.test.ts` | NFR-5, Edge Case 2 | Medium | PASS |
| Workflow init computes initial work-item complexity after step 1 and persists via `set-complexity` with `complexityStage: "init"` | `scripts/__tests__/orchestrating-workflows.test.ts` (integration) | FR-2a | High | PASS |
| Every Agent fork call site in orchestrator SKILL.md passes an explicit `model` parameter (no implicit inheritance) — verified by grep that every `Agent(` call has an adjacent `model:` arg | `scripts/__tests__/orchestrating-workflows.test.ts` | FR-9 | High | PASS |
| Fork call sites covered: `reviewing-requirements` standard mode, `creating-implementation-plans`, `implementing-plan-phases` per-phase, `executing-chores`/`executing-bug-fixes` execution, `finalizing-workflow`, inline PR creation, `reviewing-requirements` test-plan and code-review reconciliation forks (each independently resolved at invocation time) | `scripts/__tests__/orchestrating-workflows.test.ts` | FR-9 | High | PASS |
| `record-model-selection` is called **before** each fork (not after) — verified by SKILL.md ordering | `scripts/__tests__/orchestrating-workflows.test.ts` | NFR-3 | High | PASS |
| FR-14 console echo line is emitted **before** each fork in the documented format `[model] step N (skill, mode/phase) → tier (baseline=, wi-complexity=, override=)` | `scripts/__tests__/orchestrating-workflows.test.ts` | FR-14 | High | PASS |
| FR-14 console echo for baseline-locked forks uses `baseline-locked` tag instead of `wi-complexity=` | `scripts/__tests__/orchestrating-workflows.test.ts` | FR-14 | High | PASS |
| FR-14 echo derivation components (`baseline=`, `wi-complexity=`, `override=`) match the requirement doc verbatim so operators can grep them | `scripts/__tests__/orchestrating-workflows.test.ts` | FR-14, NFR-7 | High | PASS |
| Post-plan re-classification (FR-2b) runs after step 3 completes and BEFORE step 6 forks resolve their tier | integration test | FR-2b | High | PASS |
| Two-stage feature: steps 2 and 3 resolve at `complexityStage: "init"`; steps 6+ resolve at `complexityStage: "post-plan"` | integration test | FR-2b, Edge Case 10 | High | PASS |
| Audit trail captures the post-plan transition with per-entry `complexityStage` field distinguishing init vs post-plan forks | integration test | FR-7, NFR-3 | High | PASS |
| `reviewing-requirements` runs at up to 3 distinct steps per chain with separate `modelSelections` entries (not overwritten — array preserves entries) | integration test | FR-7 | High | PASS |
| `implementing-plan-phases` produces N `modelSelections` entries (one per phase) keyed by `phase` field | integration test | FR-7 | High | PASS |
| Integration: synthetic chore (Example A, 5 ACs, no overrides) produces ZERO Opus forks; all forks Sonnet + Haiku | integration test | NFR-4, Acceptance Test | High | PASS |
| Integration: synthetic bug (Example B, severity:low, 1 RC) produces ZERO Opus forks; baseline floors at Sonnet | integration test | NFR-4, Acceptance Test | High | PASS |
| Integration: synthetic feature (Example C, 5 FRs + perf NFR + 4 phases) produces Sonnet for steps 2-3, Opus for steps 6+, Haiku for finalize/PR. **Note**: step 5 is `documenting-qa` which runs in main context and is unaffected by fork tier resolution; the first post-plan-affected fork is step 6 (`reviewing-requirements` test-plan reconciliation). The Acceptance Criteria phrase "steps 5+" maps to "from step 5 onward in 1-indexed step numbering, but step 5 is main-context so practically step 6+ in fork-affected steps." | integration test | FR-2b, FR-4, Acceptance Test | High | PASS |
| Integration: `--model-for implementing-plan-phases:opus` routes ONLY the `implementing-plan-phases` forks to Opus while every other fork uses the classified tier (highest-precedence per-step override) | integration test | FR-5, FR-8 | High | PASS |
| All `implementing-plan-phases` forks within a single feature chain use the same feature-level resolved tier — per-phase classification is explicitly NOT implemented in FEAT-014 (in-scope boundary; prevents QA from testing per-phase tier variation) | integration test | Edge Case 8, Future Enhancements | Medium | PASS |
| Edge Case 1 logging: when state `modelOverride` conflicts with the computed tier, the orchestrator emits an info-level line naming BOTH values on the first fork (diagnostic aid) | integration test capturing stdout | FR-5, Edge Case 1 | Medium | PASS |
| Integration: synthetic feature (Example D, 12 FRs + security NFR + 4 phases) produces Opus from step 2 onward (init already at opus, post-plan no transition) | integration test | FR-2a/FR-2b | Medium | PASS |
| Integration: `--model opus` override forces ALL forks (including baseline-locked) to Opus | integration test | FR-5, Acceptance Test | High | PASS |
| Integration: `--complexity high` forces work-item complexity to high but `finalizing-workflow` stays on `haiku` (baseline-locked vs soft override) | integration test | FR-4, FR-5, Acceptance Test | High | PASS |
| Integration: `--model haiku` on a feature downgrades `reviewing-requirements` below Sonnet baseline AND emits the Edge Case 11 warning line | integration test | FR-3, Edge Case 11 | High | PASS |
| Tier alias is passed verbatim (`sonnet`/`opus`/`haiku`), NEVER full model IDs like `claude-opus-4-6` | grep test on SKILL.md fork sites | NFR-6 | High | PASS |

### Phase 4 — Retry, Resume, and Version Compatibility

| Test Description | Target File(s) | Requirement Ref | Priority | Status |
|-----------------|----------------|-----------------|----------|--------|
| Claude Code version check at orchestrator init: < 2.1.72 logs the documented warning and continues | `scripts/__tests__/orchestrating-workflows.test.ts` | NFR-6 | High | PASS |
| NFR-6 fallback wrapper: Agent tool rejects `model` parameter → orchestrator retries fork once without `model` and logs the documented one-line warning | integration test | NFR-6 | High | PASS |
| NFR-6 fallback wrapper exists at every fork call site (per-call-site, not global) so it composes correctly with FR-11 retry | grep test on SKILL.md | NFR-6 | High | PASS |
| FR-11 retry-with-tier-upgrade: Haiku fork returning empty artifact triggers retry on Sonnet | integration test | FR-11 | High | PASS |
| FR-11 retry-with-tier-upgrade: Sonnet fork hitting tool-use loop limit triggers retry on Opus | integration test | FR-11 | High | PASS |
| FR-11 retry-with-tier-upgrade: Opus fork failing records `fail` state, no further retry | integration test | FR-11 | High | PASS |
| FR-11 retry budget is 1 per fork (not cumulative across phases) | integration test | FR-11, Edge Case 7 | High | PASS |
| FR-11 retries append a new `modelSelections` entry — both initial attempt and retry preserved in audit trail | integration test | FR-11, FR-7 | High | PASS |
| FR-11 does NOT trigger on `reviewing-requirements` returning structured findings (user-authored findings ≠ under-provisioning) | integration test | FR-11 | High | PASS |
| FR-12 resume re-computation: stage `init` re-reads init-stage signals from requirement doc only (does NOT consult implementation plan) | integration test | FR-12 | High | PASS |
| FR-12 resume re-computation: stage `post-plan` re-reads init-stage signals AND phase count from `requirements/implementation/{ID}-*.md` | integration test | FR-12 | High | PASS |
| FR-12 resume is upgrade-only: `new_tier = max(persisted, newly_computed)` — never silently downgrades | integration test | FR-12 | High | PASS |
| FR-12 resume with unchanged signals proceeds silently | integration test | FR-12 | High | PASS |
| FR-12 resume with upgraded signals logs the documented one-line info message and persists the new tier | integration test | FR-12 | High | PASS |
| FR-12 `complexityStage` never regresses on resume (init → init or init → post-plan, never post-plan → init) | integration test | FR-12 | High | PASS |
| Escape hatch: `set-complexity {ID} <lower-tier>` between pause and resume produces a downgrade and is recorded as a user-authored action | integration test | FR-12, FR-15 | Medium | PASS |
| FR-13 backward compat: pre-existing state file without four new fields resumes cleanly via Phase 1 migration, then computes complexity on first post-migration fork | integration test | FR-13 | High | PASS |
| FR-13 backward compat: forks with no resolved tier fall back to parent-model inheritance with one-line info message (one-shot migration aid only) | integration test | FR-13, NFR-4 | High | PASS |
| FR-13 backward compat: after one compute-on-resume cycle, subsequent invocations use computed tiers regardless of parent model (Edge Case 9) | integration test | FR-13, Edge Case 9 | High | PASS |
| Missing post-plan signals (implementation plan absent or malformed when post-plan recomputation triggered) → retain init-stage tier, log warning, do NOT upgrade | integration test | NFR-5 | Medium | PASS |

### Phase 5 — Documentation

| Test Description | Target File(s) | Requirement Ref | Priority | Status |
|-----------------|----------------|-----------------|----------|--------|
| `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` contains a top-level `## Model Selection` section between `## Step Execution` and `## Error Handling` | `scripts/__tests__/orchestrating-workflows.test.ts` | NFR-1 | High | PASS |
| `## Model Selection` section contains the step baseline matrix (Axis 1) | `scripts/__tests__/orchestrating-workflows.test.ts` | NFR-1 | High | PASS |
| `## Model Selection` section contains the work-item complexity signal matrix (Axis 2) | `scripts/__tests__/orchestrating-workflows.test.ts` | NFR-1 | High | PASS |
| `## Model Selection` section contains override precedence documentation (Axis 3) including hard vs soft distinction | `scripts/__tests__/orchestrating-workflows.test.ts` | NFR-1 | High | PASS |
| `## Model Selection` section contains baseline-locked step exceptions documentation | `scripts/__tests__/orchestrating-workflows.test.ts` | NFR-1, FR-4 | High | PASS |
| `## Model Selection` section contains worked Examples A, B, C (D may be condensed) | `scripts/__tests__/orchestrating-workflows.test.ts` | NFR-1 | Medium | PASS |
| `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/` directory exists | `scripts/__tests__/orchestrating-workflows.test.ts` | NFR-2 | High | PASS |
| `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/model-selection.md` exists | `scripts/__tests__/orchestrating-workflows.test.ts` | NFR-2 | High | PASS |
| `references/model-selection.md` contains full FR-3 classification algorithm pseudocode | content grep | NFR-2 | High | PASS |
| `references/model-selection.md` contains tuning guidance for per-step baselines | content grep | NFR-2 | Medium | PASS |
| `references/model-selection.md` documents how to read the `modelSelections` audit trail field-by-field | content grep | NFR-2 | Medium | PASS |
| `references/model-selection.md` documents known limitation: Haiku is never selected for `implementing-plan-phases` (Sonnet baseline floor) | content grep | NFR-2 | Medium | PASS |
| `references/model-selection.md` documents migration guidance for users wanting old inherit-parent behavior (`--model opus` invocation or wrapper) | content grep | NFR-2 | Medium | PASS |
| `references/model-selection.md` cross-references FR-5 rationale for why requirement docs do not gain frontmatter | content grep | NFR-2, FR-5 | Low | PASS |
| `npm run validate` passes after all changes | `scripts/__tests__/build.test.ts` | NFR-1, NFR-2 | High | PASS |
| Sub-skill files (`reviewing-requirements`, `creating-implementation-plans`, `implementing-plan-phases`, `executing-chores`, `executing-bug-fixes`, `finalizing-workflow`) frontmatter is UNCHANGED — no `context: fork` added | `scripts/__tests__/orchestrating-workflows.test.ts` (or grep test) | Implementation Plan Overview | High | PASS |
| Requirement document templates (feature, chore, bug) are UNCHANGED — no YAML frontmatter added | grep test on `plugins/lwndev-sdlc/skills/documenting-*/assets/*.md` | FR-5, FR-6 (removed) | High | PASS |

## Coverage Gap Analysis

Code paths and functionality that lack automated test coverage:

| Gap Description | Affected Code | Requirement Ref | Recommendation |
|----------------|---------------|-----------------|----------------|
| End-to-end real workflow against `lwndev-marketplace` itself: run a real chore workflow and verify `modelSelections` audit trail in `.sdlc/workflows/CHORE-NNN.json` shows zero Opus entries | Orchestrator fork sites + state file | NFR-4 (manual acceptance) | Manual testing: pick a small chore, run `/orchestrating-workflows`, inspect `modelSelections` after completion |
| End-to-end real bug chain with `severity: low` against this repo and confirm zero Opus forks | Orchestrator fork sites + state file | NFR-4 (manual acceptance) | Manual testing: pick a low-severity bug document or create a synthetic one, run `/orchestrating-workflows BUG-NNN`, inspect `modelSelections` |
| End-to-end synthetic high-complexity feature via `--complexity high` against this repo confirming Opus forks for review/plan/phase steps but Haiku for finalize | Orchestrator fork sites + state file | FR-4, FR-5, NFR-4 (manual acceptance) | Manual testing: invoke with `--complexity high`, verify the audit trail and console echo lines per fork |
| Manual edit of `modelOverride` in state file between pause and resume — verify new value takes effect on resume per FR-5 precedence chain | State file + resume path | FR-7, FR-12, Edge Case 4 | Manual testing: pause a workflow, edit `.sdlc/workflows/{ID}.json` to set `modelOverride: opus`, resume, verify next forks honour the value |
| `workflow-state.sh set-complexity {ID} high` between pause and resume upgrades all subsequent forks | State script + resume path | FR-12, FR-15 | Manual testing: pause workflow, run `set-complexity`, resume, observe upgraded console echoes |
| Cron-scheduled / autonomous-loop invocation (parent on Haiku) classifies correctly from signals — does NOT floor on parent | Orchestrator init path | Edge Case 9, NFR-4 | Manual testing: invoke from a non-Opus parent context (e.g., a scheduled trigger), verify classification still derives tier from signals |
| Multiple fork retries within one workflow — each fork's retry budget is independent | FR-11 retry path | Edge Case 7 | Integration test recommended; if not feasible, manual test with two adjacent failing forks and verify both attempt their own retry |
| FR-14 console echo grep-ability — operators can grep workflow output for `[model] step N` and find every fork's tier resolution | Console output | FR-14, NFR-7 | Manual test: capture orchestrator stdout/stderr from a real run, grep for `[model]`, verify one line per fork |
| `[1m]` long-context Opus variant cannot be selected via this mechanism (alias `opus` always resolves to standard Opus) | Tier alias passing | NFR-6 | Documentation review: verify `references/model-selection.md` notes this limitation explicitly |
| Documentation drift between SKILL.md "Model Selection" section and `references/model-selection.md` after future tuning | Both docs | NFR-1, NFR-2 | Manual review during code review: confirm both docs describe the same behavior; treat references file as canonical |
| Edge Case 1 manual verification: state `modelOverride` set to a value conflicting with computed tier should produce an info-level log line on the first fork showing BOTH values to aid debugging | Console output + SKILL.md fork wrapper | Edge Case 1, FR-5 | Manual testing: edit `.sdlc/workflows/{ID}.json` to set `modelOverride: opus` after init computes a different tier, resume the workflow, grep stdout for an info line naming both the override and the computed value |

## Code Path Verification

Traceability from requirements to implementation:

| Requirement | Description | Expected Code Path | Verification Method | Status |
|-------------|-------------|-------------------|-------------------|--------|
| FR-1 | Step baseline mapping defined as authoritative table in SKILL.md | `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` `## Model Selection` section, Axis 1 table | Code review + content grep | PASS |
| FR-2a | Initial classification at workflow init computes from init-stage signals and persists with `complexityStage: "init"` | Orchestrator init path in SKILL.md (after step 1) calling `workflow-state.sh set-complexity` | Code review + integration test | PASS |
| FR-2b | Post-plan upgrade for features after step 3, upgrade-only, sets `complexityStage: "post-plan"` | Orchestrator post-step-3 hook in SKILL.md reading `requirements/implementation/{ID}-*.md` and updating state | Code review + integration test | PASS |
| FR-3 | Final tier computation per fork using FR-5 precedence chain (not simple max) | Tier resolution pseudocode in SKILL.md `## Model Selection` section, invoked per fork call site | Code review + classifier unit tests | PASS |
| FR-4 | Baseline-locked steps (`finalizing-workflow`, PR creation) at `haiku`, ignore work-item complexity and soft overrides | SKILL.md baseline table marks them locked; FR-3 walker skips wi-complexity for baseline-locked steps | Code review + classifier unit tests | PASS |
| FR-5 | Override precedence chain: hard `--model-for` > hard `--model` > soft `--complexity` > soft state `modelOverride` > computed | FR-3 pseudocode walks the chain in this order; first non-null wins | Code review + classifier unit tests | PASS |
| FR-6 (removed) | NO YAML frontmatter on requirement docs | Verified by grep on `plugins/lwndev-sdlc/skills/documenting-*/assets/*.md` — no `complexity:` or `model-override:` fields | Grep test | PASS |
| FR-7 | State file gains `complexity`, `complexityStage`, `modelOverride`, `modelSelections` (array) | `workflow-state.sh init` writes new fields; `record-model-selection` appends to `modelSelections` | Shell unit tests + state JSON inspection | PASS |
| FR-8 | CLI flags `--model`, `--complexity`, `--model-for` parsed alongside existing positional args | Orchestrator argument parser in SKILL.md | Code review + parser unit tests | PASS |
| FR-9 | Every Agent fork passes explicit `model` parameter | Every `Agent(...)` call in SKILL.md has adjacent `model:` arg | Grep test on SKILL.md fork sites | PASS |
| FR-10 | Fallback to `sonnet` (never `opus`) when signals unparseable; baseline floor not auto-downgraded | Classifier returns `sonnet` on parse failure; FR-3 walker uses baseline as floor for soft overrides | Classifier unit tests | PASS |
| FR-11 | Fork failure retry-with-tier-upgrade once per fork; classifier-flagged failures only | Per-fork wrapper in SKILL.md detecting empty artifact / tool-use loop limit and re-invoking at next tier | Integration tests | PASS |
| FR-12 | Stage-aware, upgrade-only resume re-computation | Orchestrator resume path in SKILL.md re-reads doc, computes tier, takes `max(persisted, new)` | Integration tests | PASS |
| FR-13 | Backward compatibility for pre-existing state files; one-shot parent-inheritance fallback | `workflow-state.sh` migration on read; orchestrator fallback wrapper for missing tier | Shell unit tests + integration test | PASS |
| FR-14 | Resolved tier console echo per fork with documented format | Orchestrator emits echo line before each fork, including `baseline=`, `wi-complexity=`/`baseline-locked`, `override=` | Integration test capturing stdout | PASS |
| FR-15 | `workflow-state.sh set-complexity` and `get-model` subcommands | New subcommand handlers in `workflow-state.sh` | Shell unit tests | PASS |
| NFR-1 | `## Model Selection` section in SKILL.md between "Step Execution" and "Error Handling" | `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` | Content grep + section ordering check | PASS |
| NFR-2 | `references/model-selection.md` exists with classification algorithm, tuning, audit-trail reading, limitations, migration | `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/model-selection.md` | File existence + content grep | PASS |
| NFR-3 | `modelSelections` written before each fork (not batched) | SKILL.md ordering: `record-model-selection` precedes `Agent(` call at every site | Code review + grep | PASS |
| NFR-4 | Default invocation on chore/low-bug produces ZERO Opus forks | Classifier defaults + baseline floor | Integration test (Examples A, B) | PASS |
| NFR-5 | Error handling for missing/unparseable signals, invalid tier values, missing post-plan signals | FR-10 fallback + tier validation in argument parser + post-plan retain-init logic | Classifier + parser unit tests | PASS |
| NFR-6 | Min Claude Code 2.1.72; alias-form tier values; Agent-tool rejection fallback | Version check at init; fork wrapper handling unknown-parameter error; alias passing in SKILL.md | Integration test + grep | PASS |
| NFR-7 | Audit trail visibility from console echo OR `modelSelections` array | Both FR-14 and FR-7 implementations present | Code review | PASS |

## Deliverable Verification

| Deliverable | Source Phase | Expected Path | Status |
|-------------|-------------|---------------|--------|
| Updated `workflow-state.sh` with four new state fields, `set-complexity`, `get-model`, `record-model-selection` subcommands | Phase 1 | `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh` | PASS |
| Backward-compatibility migration path for pre-existing state files | Phase 1 | Same script — silent in-place migration on read | PASS |
| Shell script unit tests for new subcommands | Phase 1 | `scripts/__tests__/workflow-state.test.ts` (extended) | PASS |
| Work-item signal extractor pseudocode in orchestrator SKILL.md (chore, bug, feature init/post-plan) | Phase 2 | `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` | PASS |
| FR-3 tier-resolution algorithm pseudocode in same SKILL.md | Phase 2 | Same SKILL.md | PASS |
| Synthetic requirement-doc test fixtures (chore × bug × feature × low/medium/high) | Phase 2 | Test fixtures directory matching existing layout (e.g., `scripts/__tests__/fixtures/` or similar) | PASS |
| Classifier unit tests covering every precedence level, baseline-lock behaviors, two-stage upgrade, unparseable-signal fallback | Phase 2 | `scripts/__tests__/orchestrating-workflows.test.ts` (or new classifier test file) | PASS |
| Updated CLI argument parser in SKILL.md supporting `--model`, `--complexity`, `--model-for` | Phase 3 | `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` | PASS |
| Every Agent fork call site in orchestrator SKILL.md passes explicit `model` parameter | Phase 3 | Same SKILL.md (multiple call sites) | PASS |
| `workflow-state.sh record-model-selection` invoked before every fork | Phase 3 | Same SKILL.md | PASS |
| FR-14 console echo line emitted before every fork | Phase 3 | Same SKILL.md | PASS |
| Post-plan re-classification (FR-2b) wired between step 3 and step 6 | Phase 3 | Same SKILL.md | PASS |
| Integration tests covering Examples A, B, C | Phase 3 | `scripts/__tests__/orchestrating-workflows.test.ts` (or integration test file) | PASS |
| Claude Code version check in orchestrator init path | Phase 4 | Same SKILL.md | PASS |
| NFR-6 Agent-tool-rejection fallback wrapper at every fork call site | Phase 4 | Same SKILL.md | PASS |
| FR-11 retry-with-tier-upgrade logic with failure classifier | Phase 4 | Same SKILL.md | PASS |
| FR-12 stage-aware, upgrade-only resume re-computation | Phase 4 | Same SKILL.md | PASS |
| Integration tests for retry paths, resume paths, version compatibility | Phase 4 | `scripts/__tests__/orchestrating-workflows.test.ts` (or integration test file) | PASS |
| `## Model Selection` section in orchestrator SKILL.md between "Step Execution" and "Error Handling" | Phase 5 | Same SKILL.md | PASS |
| New `references/` subdirectory under orchestrator skill | Phase 5 | `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/` | PASS |
| New `references/model-selection.md` per NFR-2 | Phase 5 | `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/model-selection.md` | PASS |
| `npm run validate` passes | Phase 5 | All plugins + new references file | PASS |

## Plan Completeness Checklist

- [x] All existing tests pass (regression baseline) — workflow-state.test.ts, orchestrating-workflows.test.ts, build.test.ts, and unmodified sub-skill tests are listed in Existing Test Verification
- [x] All FR-N / NFR-N / AC entries have corresponding test plan entries — FR-1 through FR-15 (FR-6 removed) and NFR-1 through NFR-7 are mapped in Code Path Verification, with detailed New Test Analysis entries per phase
- [x] Coverage gaps are identified with recommendations — manual acceptance tests, real-workflow validation, and edge cases (cron parent, multi-retry, doc drift) listed in Coverage Gap Analysis
- [x] Code paths trace from requirements to implementation — every FR and NFR has an Expected Code Path entry pointing to either SKILL.md sections, the shell script, the references file, or the test files
- [x] Phase deliverables are accounted for — every deliverable from Phases 1–5 has a Deliverable Verification entry
- [x] New test recommendations are actionable and prioritized — every New Test Analysis row has a Priority field and points to a concrete test file location
