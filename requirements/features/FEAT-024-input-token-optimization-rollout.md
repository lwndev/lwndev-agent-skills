# Feature Requirements: Input Token Optimization Rollout

## Overview

Roll out the input-token optimization pattern piloted in CHORE-035 to the remaining twelve `lwndev-sdlc` skills. Each target skill's `SKILL.md` is loaded on every invocation (orchestrator dispatch and forked sub-agent spawn) — the pilot showed the three optimization axes (lite-style prose compression, heavy-narrative relocation to `references/`, natural collapse opportunities like parameterized tables) can reduce the per-invocation instruction surface by ~43% without changing behavior or dropping load-bearing carve-outs. This feature applies the same three-axis template to each of the twelve remaining skills and captures baseline/post/delta measurements per skill.

## Feature ID

`FEAT-024`

## GitHub Issue

[#203](https://github.com/lwndev/lwndev-marketplace/issues/203)

## Priority

Medium — continuation of completed pilot (CHORE-035); mechanical rollout with a well-defined template. Per-invocation input-token savings compound across every orchestrator dispatch and every forked sub-agent spawn in every feature, chore, and bug workflow.

## User Story

As a maintainer of the `lwndev-sdlc` plugin, I want every sub-skill's `SKILL.md` trimmed to the same lite-style dispatcher shape piloted in `orchestrating-workflows` so that the per-invocation instruction surface is reduced consistently across all three workflow chains (feature, chore, bug) and sub-skill authors have one canonical optimization template to follow.

## Scope

Twelve target skills under `plugins/lwndev-sdlc/skills/`:

1. `documenting-features`
2. `documenting-chores`
3. `documenting-bugs`
4. `reviewing-requirements`
5. `creating-implementation-plans`
6. `implementing-plan-phases`
7. `documenting-qa`
8. `executing-qa`
9. `executing-chores`
10. `executing-bug-fixes`
11. `managing-work-items`
12. `finalizing-workflow`

Out of scope: the pilot skill (`orchestrating-workflows`) is already done (CHORE-035). Runtime-telemetry instrumentation is out of scope (static `wc` + char-based input-token estimator are the methodology, matching the pilot). The output-token rollout (FEAT-023) is a separate, already-merged effort that targeted runtime **output**; this feature targets runtime **input** (the static SKILL.md text loaded into context).

## Functional Requirements

### FR-1: Apply lite-style prose compression to each target SKILL.md

For each of the twelve target skills, compress `SKILL.md` prose to *lite* style:

- Remove filler, hedging, and pleasantries
- Keep articles and full sentences (no aggressive pronoun drops that lose antecedents)
- Leave code blocks, command lines, flags, file paths, anchor identifiers, and table headers untouched
- Preserve every load-bearing carve-out established by CHORE-034 (see FR-4)

The `## Output Style` section installed by FEAT-023 is explicitly NOT a compression target — it was written deliberately by CHORE-034 and ships as a runtime-output directive. It must be preserved verbatim in every target skill (FR-4).

### FR-2: Relocate heavy narrative to `references/` per skill

For each target skill, identify sections of `SKILL.md` that are "heavy narrative" (long numbered recipes, multi-step procedures, verbose decision flows that the skill does not need to read in full at dispatch time) and relocate them to the skill's `references/` directory. Each relocated section must retain a single-sentence inline pointer in `SKILL.md` at the location where it previously lived.

**Boundary rule** (from CHORE-035 Learnings): tables, contract shapes, carve-out bullets, and override-precedence rows are *reference material* that stays in `SKILL.md` because the skill indexes them during dispatch. Long numbered recipes and verbose procedural narratives are *procedural narrative* that relocates cleanly. The test is whether `SKILL.md` needs the full text to decide what to do next, or whether a pointer suffices.

**Operationalized threshold**: no non-dispatcher section in `SKILL.md` should exceed roughly 25 lines, excluding the `## Output Style` section (load-bearing and preserved verbatim) and bounded tables.

Three target skills have no `references/` directory today: `documenting-qa`, `executing-qa`, `finalizing-workflow`. For those skills, FR-2 applies by creating a `references/` directory as needed to hold relocated narrative (Edge Case 1). Creation of a new `references/` directory is itself an acceptable optimization outcome.

### FR-3: Apply natural collapse opportunities per skill

For each target skill, look for repeated tables or duplicate step-sequence tables (the pilot collapsed three per-chain step-sequence tables into one parameterized table keyed by chain type, plus a per-chain deltas note). Apply the same pattern where applicable:

- Consolidate near-duplicate tables into one parameterized table plus a lossless deltas note
- Collapse repeated carve-out or contract blocks that appear verbatim in multiple sections into a single definition with pointers elsewhere
- The deltas note must enumerate every difference the original tables conveyed — treat it as a lossless compression, not a summary

Skills without repeated tables (many of the twelve have only a single Functional Requirements table or Acceptance Criteria table) satisfy FR-3 as a no-op; record this in the Notes section.

### FR-4: Preserve all load-bearing carve-outs verbatim

The following established by CHORE-034 must NOT be stripped by the lite rules even if they look like narration, and must be preserved verbatim in every target SKILL.md:

- Error messages from `fail` calls
- Security-sensitive warnings (destructive-operation confirmations, baseline-bypass warnings)
- Interactive prompts (plan-approval pause, findings-decision prompts, review-findings prompts)
- Findings display from `reviewing-requirements`
- FR-14 console echo lines (retain Unicode `→` as the documented emitter format; FR-14 defined in FEAT-014)
- Tagged structured logs (`[info]`, `[warn]`, `[model]`)
- User-visible state transitions (pause, advance, resume)
- Code blocks, command lines, flags, file paths, anchor identifiers, and table headers
- The entire `## Output Style` section installed by FEAT-023

**Correction note for carve-out inheritance**: some currently-deployed carve-out blocks describe the FR-14 emitter format as "Unicode `->`" — this is self-contradictory (`->` is ASCII, not Unicode). The canonical form, deployed in `orchestrating-workflows/SKILL.md` after CHORE-035, is "Unicode `→`". During this rollout, where a target skill's existing carve-out text names the wrong character, the implementation pass MUST correct it to match the canonical form. This correction is classified as a carve-out fidelity fix, not a behavioral change, and does not violate the "preserve verbatim" rule because the pre-existing text was itself a typo relative to the canonical template.

### FR-5: Capture baseline and post-change measurements per skill

For each of the twelve target skills, capture baseline `wc -l -w -c` measurements across:

- `SKILL.md`
- All files under `references/` (if present)
- All files under `assets/` (if present)

Additionally capture a per-skill **input-token estimate for `SKILL.md`** using the same `chars / 4` rule-of-thumb fallback estimator the pilot used (documented explicitly so future rollouts can reproduce). If the `ai-skills-manager` `validate()` body-token estimator is available at the time of measurement, record its figure as a corroborating data point alongside the `chars / 4` number.

Append a measurement table to this feature's Notes section (not CHORE-035's) with rows: per-file baseline, per-skill subtotal, and a grand-total across all twelve skills.

After the optimization is applied, capture post-change measurements in the same format and a delta table (lines Δ, lines %, words Δ, words %, chars Δ, chars %) per file, per skill, and across the grand total. Mirror the CHORE-035 table format. Call out the SKILL.md input-token delta per skill separately — SKILL.md is the per-invocation instruction surface and is the primary target quantity.

### FR-6: Preserve behavioral correctness

The rollout is a documentation/layout change. It must not:

- Change any skill's frontmatter fields (`name`, `description`, `allowed-tools`, `argument-hint`, etc.) except where absolutely necessary to accommodate relocated content
- Change any script invocation, file path, or artifact path
- Change any verification checklist semantics (items may be reworded for tightness but must not drop criteria)
- Change the Fork Step-Name Map, any step-sequence table semantics, or any canonical fork-return contract in `orchestrating-workflows`
- Break internal SKILL.md anchors or cross-skill references

`npm run validate` and `npm test` must continue to pass. Where a test asserts on narration content that this rollout trims (e.g., hardcoded count assertions, literal heading assertions), update the test to match the new canonical form and call out the change in the PR body (per NFR-3).

### FR-7: Pre-flight test audit per skill

Before starting the edit pass on any given skill, scan that skill's test suite for:

1. Hardcoded counts (e.g., `count == 35` of some reference pattern) — these track layout, not correctness; expect them to shift
2. Literal heading assertions (e.g., `skillMd.toContain('## Feature Chain Step Sequence')`) — these pin section names; plan edits to preserve or rename with migration
3. Literal phrase assertions (e.g., `toContain('Forked Steps')`) — these pin specific strings; verify each during the pass

Record each finding as "will-change" or "must-preserve" in the per-skill phase notes before touching `SKILL.md`. This is a mechanical pre-flight step added to the rollout explicitly because CHORE-035 surfaced the pattern as a template-worth-replicating.

## Non-Functional Requirements

### NFR-1: Measurement methodology parity with pilot

Use the same static-`wc` + `chars / 4` input-token estimator methodology CHORE-035 used. Runtime telemetry is out of scope for this rollout. The methodology section at the top of the Notes section must state this explicitly and must name the estimator(s) used.

### NFR-2: Per-skill atomicity

Each skill's edits should be a logical unit that can be reviewed independently. The implementation plan (produced by `creating-implementation-plans`) should split work into phases of one skill per phase, or group small skills together only where each phase is still reviewable in isolation. Each phase produces one commit on the feature branch and is verifiable in isolation (`npm run validate` + targeted tests).

### NFR-3: No behavioral regressions

The rollout must not alter the runtime behavior of any skill. All existing tests must pass. If a test asserts on narration content or layout that this rollout changes (per FR-7's pre-flight audit), update the test in the same phase PR — do not leave failing tests across phase boundaries.

### NFR-4: Consistency across skills

The same three-axis template (lite-style prose compression, heavy-narrative relocation, natural collapse opportunities), the same carve-out preservation list (FR-4), and the same measurement format (FR-5) must apply to every target skill. Deviations are allowed only when justified by the skill's shape (e.g., a skill with no repeated tables is FR-3 no-op; a skill with no `references/` directory creates one if relocation is needed).

### NFR-5: Documentation of rollout outcome

After all twelve skills are complete, append a Summary subsection to this feature's Notes that aggregates the rollout measurements:

- Total SKILL.md chars/input-tokens saved across all twelve skills
- Total per-workflow savings (derived: a feature chain with N phases forks ~`4 + N` sub-agents; each fork reads one SKILL.md in full)
- Comparison against the CHORE-035 pilot prediction (the pilot predicted the rollout would compound roughly `5 + N` times per workflow)

## Dependencies

- CHORE-035 (pilot) — merged; its Learnings subsection in `requirements/chores/CHORE-035-input-token-optimization-pilot.md` is the source of truth for the three-axis template and the pre-flight test audit pattern
- CHORE-034 (sibling output-token pilot) — merged; established the load-bearing carve-out list that FR-4 preserves
- FEAT-023 (sibling output-token rollout) — merged; every target skill already has the `## Output Style` section, which is a FR-4 preservation target
- FEAT-014 (adaptive model selection) — indirect dependency via the carve-out chain; FR-14 (the console echo line format using Unicode `→`) is defined in `requirements/features/FEAT-014-adaptive-model-selection.md` and is the direct source of the FR-14 bullet in the FR-4 carve-out list
- `orchestrating-workflows/SKILL.md` — the canonical post-pilot example of the three-axis template; the rollout replicates its structural pattern
- No external tooling beyond `wc`, the `chars / 4` estimator, and the existing `npm run validate` / `npm test`

## Edge Cases

1. **Skill with no `references/` directory** (`documenting-qa`, `executing-qa`, `finalizing-workflow`): FR-2 applies by creating the directory if heavy narrative is being relocated. If no heavy narrative needs relocating, FR-2 is a no-op for that skill; record in Notes.
2. **Skill with no `assets/` directory** (`managing-work-items`, `finalizing-workflow`): FR-5 measurements cover `SKILL.md` and `references/` only (or `SKILL.md` only for `finalizing-workflow`, which has neither `references/` nor `assets/`).
3. **Skill with no repeated tables to collapse**: FR-3 is satisfied as a no-op; record in the Notes section with a brief justification.
4. **Skill already lite enough**: if the baseline measurement shows `SKILL.md` is already well below the pilot's post-optimization char count and has no repeated tables or heavy narrative, FR-1/FR-2/FR-3 can all be no-ops. Record the baseline, skip the edit pass, and note the skill in the Summary subsection.
5. **Heading-anchor tests** (from CHORE-035 Learnings): some skills may have tests that assert on literal `##` heading names. Detect these in the FR-7 pre-flight audit; preserve the heading text or co-update the test in the same phase PR.
6. **Hardcoded-count tests** (from CHORE-035 Learnings): when a test asserts on a hardcoded count of some reference pattern, convert to a lower-bound assertion in the same phase PR and document the reason in a test comment referencing FEAT-024.
7. **Pronoun-drop close calls**: compression must not drop the antecedent of a pronoun or the enumeration in a parenthetical that documents user-facing phrases. The pilot's Learnings flag this explicitly; treat such constructs as load-bearing.
8. **Mid-section pointer placement**: inline pointers must appear at the *end* of the dispatcher paragraph (not the start), so readers get the summary before the jump.
9. **Skill with `assets/` but no `references/`** (`documenting-qa`, `executing-qa`): FR-5 baseline measurements cover `SKILL.md` and all files under `assets/` (no `references/` row in the per-skill subtotal table). Record this combination explicitly in the per-skill measurement subsection so future editors don't reintroduce a missing-directory warning.
10. **Carve-out says "Unicode `->`" instead of "Unicode `→`"**: at least three target skills (`implementing-plan-phases`, `executing-chores`, `executing-bug-fixes`) currently contain the self-contradictory form in their FR-14 carve-out. Per FR-4's Correction note, the rollout pass corrects the text to match the canonical "Unicode `→`" form. Apply the correction in the same phase as that skill's other edits; call it out explicitly in the phase PR body.

## Testing Requirements

### Unit Tests

- `npm run validate` must pass for every plugin change (SKILL.md frontmatter valid, references resolve, no broken anchors).

### Integration Tests

- `npm test` must pass end-to-end across the monorepo after each skill's edits land.
- Per-skill test suites (e.g., `scripts/__tests__/<skill-name>.test.ts`) must pass after each phase.

### Manual Testing

- Spot-check three representative skill edits (one forked sub-skill, one main-context sub-skill, one cross-cutting skill) by rendering `SKILL.md` in a markdown preview and confirming the dispatcher paragraphs read cleanly and the reference files resolve.
- Run one full feature workflow chain (resume or new) to confirm no dispatch regressions from heavy-narrative relocation.
- Run one full chore workflow chain to confirm no dispatch regressions for non-feature chain types.

## Future Enhancements

- Runtime-telemetry methodology (actual input-token measurement via Anthropic's `/v1/messages/count_tokens` endpoint with `ANTHROPIC_API_KEY` configured in CI) — would replace the `chars / 4` fallback with a tokenizer-exact count
- Lint rule that flags any `SKILL.md` with a non-dispatcher section exceeding the FR-2 operationalized threshold (~25 lines) so future skills can't accidentally regrow
- Cross-skill anchor-resolution linter (already partially covered by `npm run validate`) extended to detect relocated-content anchors and surface broken inline pointers

## Acceptance Criteria

- [ ] Each of the twelve target skills has had its `SKILL.md` prose compressed to lite style per FR-1, with filler/hedging removed and load-bearing carve-outs preserved verbatim
- [ ] Each target skill has had heavy-narrative sections relocated to `references/` per FR-2, with an inline pointer left at each relocation site
- [ ] Each target skill has had natural collapse opportunities applied per FR-3, or the skill is recorded as an FR-3 no-op in the Notes section
- [ ] All load-bearing carve-outs established by CHORE-034 (error messages, security warnings, interactive prompts, findings display, FR-14 echoes, tagged structured logs, state transitions, code/paths/flags, Output Style section) are preserved verbatim in every target SKILL.md
- [ ] The `## Output Style` section installed by FEAT-023 is preserved character-for-character in every target skill
- [ ] Baseline `wc -l -w -c` measurements and `chars / 4` input-token estimates have been captured per target skill and appended to this feature's Notes section, and the Notes → Measurement Methodology subsection names the estimator(s) used (per NFR-1)
- [ ] Post-change measurements have been captured in the same format and a delta table appended to the Notes section
- [ ] A Summary subsection in the Notes aggregates total SKILL.md chars/input-tokens saved across all twelve skills and compares against the CHORE-035 prediction
- [ ] A pre-flight test audit (FR-7) has been recorded per skill before that skill's edit pass began; any tests that required updates are called out in the relevant phase PR
- [ ] Each skill's optimization was committed as an independent phase commit per NFR-2; the feature-branch commit history and the PR body call out any phase that grouped multiple skills and justify the grouping
- [ ] The same three-axis template (FR-1/FR-2/FR-3), carve-out list (FR-4), and measurement format (FR-5) were applied consistently to every target skill per NFR-4; any approved deviations are documented in the Notes section with justification
- [ ] No skill's frontmatter fields, script invocations, file paths, artifact paths, verification checklist semantics, Fork Step-Name Map, step-sequence table semantics, or fork-return contract have changed
- [ ] All internal SKILL.md anchors and cross-skill references still resolve after the rollout
- [ ] `npm run validate` passes
- [ ] `npm test` passes
- [ ] This feature document's GitHub Issue section links to [#203](https://github.com/lwndev/lwndev-marketplace/issues/203)

## Completion

**Status:** `In Progress`

**Completed:** _(set on merge)_

**Pull Request:** _(set on PR creation)_

## Notes

### Scope boundary with CHORE-035 and FEAT-023

CHORE-035 piloted the three-axis input-token compression on `orchestrating-workflows/SKILL.md` only. This feature rolls the same three-axis template out to the remaining twelve skills. FEAT-023 (the sibling output-token rollout, already merged) installed the `## Output Style` section in every target skill; that section is a FR-4 preservation target for this feature, never a compression target. The two rollouts are orthogonal — FEAT-023 targeted runtime **output**, this feature targets the **instruction surface** loaded on every invocation.

### Measurement methodology

Measurements are captured via `wc -l -w -c` against the files in scope, matching the CHORE-035 approach. An estimated input-token count is additionally captured for each target skill's `SKILL.md` using the `chars / 4` rule-of-thumb fallback estimator the pilot used (Anthropic's `/v1/messages/count_tokens` endpoint is preferred if `ANTHROPIC_API_KEY` is available in the executor environment; if not, the `chars / 4` fallback is documented and reused). The `ai-skills-manager` `validate()` body-token estimator may be recorded as a corroborating data point. Both measurements are taken on `main` before any edits land, and again after all edits are applied per skill.

### Baseline Measurements

_(To be populated in Phase 0 / before Phase 1 begins)_

### Post-Change Measurements

_(To be populated per phase; final aggregate on last phase)_

### Delta (post − pre; negative = reduction, positive = growth)

_(To be populated per phase; final aggregate on last phase)_

### Summary (aggregate across all twelve skills)

_(To be populated when all phases complete — compare against the CHORE-035 pilot prediction of `~5 + N` compounded per-workflow savings)_

### Per-skill FR-7 pre-flight audit findings

_(To be populated per phase before that phase's edit pass begins)_
