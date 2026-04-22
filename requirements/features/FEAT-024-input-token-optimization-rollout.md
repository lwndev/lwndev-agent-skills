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

Captured on feature branch `feat/FEAT-024-input-token-optimization-rollout` at HEAD `1a01fc9` (commit `docs(FEAT-024): add feature, plan, and QA documents for input-token optimization rollout`) on 2026-04-22 via `wc -l -w -c`. The `chars / 4` column is the rule-of-thumb input-token estimate from the methodology subsection above, computed only for `SKILL.md` per FR-5 (reference and asset files contribute to baseline measurement totals but are not in the per-invocation instruction surface targeted by the rollout). `ANTHROPIC_API_KEY` was not available in the executor environment for this Phase 0 pre-flight, so the corroborating `/v1/messages/count_tokens` figures are not recorded; per the methodology subsection the `chars / 4` fallback stands.

| Skill | File | Lines | Words | Chars | chars / 4 (SKILL.md only) |
|-------|------|------:|------:|------:|--------------------------:|
| `finalizing-workflow` | `SKILL.md` | 104 | 1004 | 6931 | 1733 |
| `finalizing-workflow` | **subtotal** | **104** | **1004** | **6931** | — |
| `documenting-features` | `SKILL.md` | 154 | 1190 | 8648 | 2162 |
| `documenting-features` | `references/feature-requirements-example-episodes-command.md` | 274 | 1278 | 8512 | — |
| `documenting-features` | `references/feature-requirements-example-search-command.md` | 228 | 1021 | 6872 | — |
| `documenting-features` | `assets/feature-requirements.md` | 94 | 242 | 1715 | — |
| `documenting-features` | **subtotal** | **750** | **3731** | **25747** | — |
| `documenting-chores` | `SKILL.md` | 149 | 1051 | 7453 | 1863 |
| `documenting-chores` | `references/categories.md` | 198 | 720 | 4785 | — |
| `documenting-chores` | `assets/chore-document.md` | 109 | 356 | 2456 | — |
| `documenting-chores` | **subtotal** | **456** | **2127** | **14694** | — |
| `documenting-bugs` | `SKILL.md` | 168 | 1213 | 8411 | 2103 |
| `documenting-bugs` | `references/categories.md` | 236 | 1134 | 7429 | — |
| `documenting-bugs` | `assets/bug-document.md` | 181 | 707 | 4759 | — |
| `documenting-bugs` | **subtotal** | **585** | **3054** | **20599** | — |
| `managing-work-items` | `SKILL.md` | 390 | 3331 | 22857 | 5714 |
| `managing-work-items` | `references/github-templates.md` | 740 | 2315 | 17196 | — |
| `managing-work-items` | `references/jira-templates.md` | 715 | 2079 | 19135 | — |
| `managing-work-items` | **subtotal** | **1845** | **7725** | **59188** | — |
| `creating-implementation-plans` | `SKILL.md` | 139 | 939 | 6812 | 1703 |
| `creating-implementation-plans` | `references/implementation-plan-example.md` | 499 | 2766 | 20322 | — |
| `creating-implementation-plans` | `assets/implementation-plan.md` | 79 | 234 | 1771 | — |
| `creating-implementation-plans` | **subtotal** | **717** | **3939** | **28905** | — |
| `reviewing-requirements` | `SKILL.md` | 434 | 3929 | 27945 | 6986 |
| `reviewing-requirements` | `references/review-example.md` | 95 | 525 | 3897 | — |
| `reviewing-requirements` | `assets/review-findings-template.md` | 98 | 426 | 3178 | — |
| `reviewing-requirements` | **subtotal** | **627** | **4880** | **35020** | — |
| `executing-chores` | `SKILL.md` | 179 | 1527 | 11225 | 2806 |
| `executing-chores` | `references/workflow-details.md` | 277 | 940 | 6249 | — |
| `executing-chores` | `assets/pr-template.md` | 118 | 420 | 2726 | — |
| `executing-chores` | **subtotal** | **574** | **2887** | **20200** | — |
| `executing-bug-fixes` | `SKILL.md` | 212 | 1854 | 13054 | 3263 |
| `executing-bug-fixes` | `references/workflow-details.md` | 338 | 1365 | 8649 | — |
| `executing-bug-fixes` | `assets/pr-template.md` | 180 | 878 | 5825 | — |
| `executing-bug-fixes` | **subtotal** | **730** | **4097** | **27528** | — |
| `documenting-qa` | `SKILL.md` | 200 | 1971 | 13726 | 3431 |
| `documenting-qa` | `assets/test-plan-template-v2.md` | 65 | 334 | 2252 | — |
| `documenting-qa` | `assets/test-plan-template.md` | 65 | 422 | 2575 | — |
| `documenting-qa` | **subtotal** | **330** | **2727** | **18553** | — |
| `executing-qa` | `SKILL.md` | 270 | 2501 | 17396 | 4349 |
| `executing-qa` | `assets/test-results-template-v2.md` | 81 | 380 | 2577 | — |
| `executing-qa` | `assets/test-results-template.md` | 89 | 466 | 2753 | — |
| `executing-qa` | **subtotal** | **440** | **3347** | **22726** | — |
| `implementing-plan-phases` | `SKILL.md` | 178 | 1585 | 11381 | 2845 |
| `implementing-plan-phases` | `references/step-details.md` | 399 | 1488 | 11039 | — |
| `implementing-plan-phases` | `references/workflow-example.md` | 327 | 977 | 8670 | — |
| `implementing-plan-phases` | `assets/pr-template.md` | 163 | 616 | 4088 | — |
| `implementing-plan-phases` | **subtotal** | **1067** | **4666** | **35178** | — |
| **Grand total (all 12 skills, all in-scope files)** | — | **8225** | **44184** | **315269** | **38958** |
| **Grand total (SKILL.md only, in-scope per-invocation surface)** | — | **2577** | **21095** | **149839** | **38958** |

**Notes:**
- `personas/` and `scripts/` directories under `documenting-qa` and `executing-qa` are out of scope for this rollout (only SKILL.md, references, and assets are measured per Phase 0 step 2).
- The `finalizing-workflow/scripts/` directory exists but is also out of scope (no `references/` or `assets/` for that skill).
- The "chars / 4" column for non-SKILL.md rows is intentionally blank — only SKILL.md is the per-invocation instruction surface targeted by FR-1/FR-2/FR-3.
- Phase 0 pre-flight green-baseline tests passed via the pre-commit hook on the `docs(FEAT-024)` commit: `36 test files, 1219 tests, 0 failures`.
- Phase 0 pre-flight `npm run validate` passed: all 13 lwndev-sdlc skills (12 target + `orchestrating-workflows`) validated successfully.

### Post-Change Measurements

Per-phase rows are appended as each phase lands. Format mirrors the Baseline Measurements table.

| Skill | File | Lines | Words | Chars | chars / 4 (SKILL.md only) |
|-------|------|------:|------:|------:|--------------------------:|
| `finalizing-workflow` | `SKILL.md` | 104 | 970 | 6754 | 1689 |
| `finalizing-workflow` | **subtotal** | **104** | **970** | **6754** | — |
| `documenting-features` | `SKILL.md` | 154 | 1109 | 8171 | 2043 |
| `documenting-features` | `references/feature-requirements-example-episodes-command.md` | 274 | 1278 | 8512 | — |
| `documenting-features` | `references/feature-requirements-example-search-command.md` | 228 | 1021 | 6872 | — |
| `documenting-features` | `assets/feature-requirements.md` | 94 | 242 | 1715 | — |
| `documenting-features` | **subtotal** | **750** | **3650** | **25270** | — |
| `documenting-chores` | `SKILL.md` | 145 | 983 | 7067 | 1767 |
| `documenting-chores` | `references/categories.md` | 198 | 720 | 4785 | — |
| `documenting-chores` | `assets/chore-document.md` | 109 | 356 | 2456 | — |
| `documenting-chores` | **subtotal** | **452** | **2059** | **14308** | — |

**Per-axis outcomes (Phase 1, `finalizing-workflow`):**
- **FR-1**: lite-style prose compression applied to `## When to Use This Skill`, `## Workflow Position` intro, `## Usage` (steps 1–5 + intro), `## Expected output`, and `## Relationship to Other Skills` intro. The `## Output Style` section was preserved verbatim per FR-4 (FEAT-023 carve-out).
- **FR-2**: no-op. No non-dispatcher section exceeded ~25 lines of procedural narrative. The `## Output Style` section is doctrine/rules (a FR-4 preservation target), not procedural narrative subject to FR-2 relocation. The `## Usage` section is ~15 lines after compression. No `references/` directory created.
- **FR-3**: no-op. Only one table exists (`## Relationship to Other Skills` → Task/Recommended Approach matrix). No repeated or near-duplicate tables to collapse.
- **FR-4**: verified. All carve-out items present verbatim: `## Output Style` section intact (lite-narration rules, load-bearing carve-outs list including the FR-14 Unicode `→` echo line, fork-to-orchestrator return contract). `Ready to merge PR` confirmation prompt and `Merge PR and reset to main (and finalize requirement doc)` row preserved.
- **FR-7**: confirmed Phase 0 audit findings. No will-change assertions; all `toHaveLength` / `toBe` calls in the test file are checkbox-flip behavioral tests on synthetic fixtures, not SKILL.md surface. No test assertion updates required.

**Per-axis outcomes (Phase 2, `documenting-features`):**
- **FR-1**: lite-style prose compression applied to `# Documenting Features` intro, `## Flexibility` intro and bullets, `## Arguments` bullets, `## Quick Start`, `## Feature ID Assignment`, `## File Locations`, `## Verification Checklist` intro, and `## Relationship to Other Skills` trailing chain summary. The `## Output Style` section (lines 49-79) was preserved verbatim per FR-4 (FEAT-023 carve-out). The `> **Note:**` paragraph about the `gh` CLI replacement was condensed without removing the substantive guidance about the `managing-work-items` delegation.
- **FR-2**: no-op. No non-dispatcher section exceeded ~25 lines of procedural narrative. The `## Output Style` section (~31 lines) is doctrine/rules (FR-4 preservation target), not procedural narrative subject to relocation. The two existing `references/feature-requirements-example-*.md` files are example requirement documents, not procedural narrative — they remain untouched. No new files added under `references/`.
- **FR-3**: no-op. Only one table exists (`## Relationship to Other Skills` → Task/Recommended Approach matrix, three rows). No repeated or near-duplicate tables to collapse.
- **FR-4**: verified. All carve-out items present verbatim: `## Output Style` section intact (lite-narration rules, load-bearing carve-outs list, fork-to-orchestrator return contract, Precedence note). All FR-7 must-preserve items confirmed: `## When to Use This Skill` and `## Verification Checklist` headings, literal `requirements/features/`, `#14`, `#<number>`, `managing-work-items`, `managing-work-items fetch`, "warn ... continue with manual input" phrasing, no `gh issue view` or `gh api` backticks, frontmatter `allowed-tools` (Read/Write/Edit/Glob/Grep, no Bash/Agent).
- **FR-7**: confirmed Phase 0 audit findings. No will-change assertions in `scripts/__tests__/documenting-features.test.ts`; all assertions are heading/literal/frontmatter checks against load-bearing surface preserved by the compression. No test assertion updates required.

**Per-axis outcomes (Phase 3, `documenting-chores`):**
- **FR-1**: lite-style prose compression applied to `# Documenting Chores` intro, `## When to Use This Skill` bullets (removed redundant verb prefixes), `## Arguments` bullets, `## Quick Start`, `## File Location` (collapsed multi-paragraph layout into intro + slug script + examples), `## Chore ID Assignment` (tightened script description), `## Categories` intro, `## Verification Checklist` items, and the `## Relationship to Other Skills` trailing chain summary. The `## Output Style` section (lines 39-69) was preserved verbatim per FR-4 (FEAT-023 carve-out). All `slugify.sh` / `next-id.sh` exit-code documentation, all literal paths (`requirements/chores/`, `CHORE-XXX-...`), and the categories table rows were preserved verbatim.
- **FR-2**: no-op. No non-dispatcher section in SKILL.md exceeded ~25 lines of procedural narrative. The `## Output Style` section (~31 lines) is doctrine/rules (FR-4 preservation target), not procedural narrative subject to relocation. `references/categories.md` is an existing reference table (per-category guidance) — already in `references/`, no relocation source. No new files added under `references/`.
- **FR-3**: no-op. Two tables exist (`## Categories` matrix, `## Relationship to Other Skills` matrix); they have different shapes and purposes (category→use-case vs task-type→approach) and no repetition or near-duplication exists between them. Nothing to collapse.
- **FR-4**: verified. All carve-out items present verbatim: `## Output Style` section intact (lite-narration rules, load-bearing carve-outs list including the FR-14 Unicode `→` echo line, fork-to-orchestrator return contract that documents this skill runs in main context, Precedence note). All FR-7 must-preserve items confirmed: `## When to Use This Skill`, `## Verification Checklist`, `## Relationship to Other Skills` headings, literal `executing-chores`, frontmatter `allowed-tools` (Read/Write/Edit/Glob/Grep, no Bash/Agent), `argument-hint:`.
- **FR-7**: confirmed Phase 0 audit findings for `scripts/__tests__/documenting-chores.test.ts` (all 12 assertions are heading / literal-phrase / frontmatter / template-existence / validate-API checks; all preserved). Additionally identified a cross-skill must-preserve audit gap: `scripts/__tests__/argument-hint.test.ts` requires every skill with `argument-hint` frontmatter to contain the literal phrases `When argument is provided` and `When no argument is provided` in body content. The initial Phase 3 compression shortened the `## Arguments` bullets to `Argument provided` / `No argument` and was reverted to the literal phrases before the final commit. The Phase 0 audit was scoped per-skill and missed this cross-skill assertion file — future phases should treat the literal phrases as must-preserve.

### Delta (post − pre; negative = reduction, positive = growth)

| Skill | File | Lines Δ | Lines % | Words Δ | Words % | Chars Δ | Chars % | chars / 4 Δ |
|-------|------|--------:|--------:|--------:|--------:|--------:|--------:|------------:|
| `finalizing-workflow` | `SKILL.md` | 0 | 0.00% | -34 | -3.39% | -177 | -2.55% | -44 |
| `finalizing-workflow` | **subtotal** | **0** | **0.00%** | **-34** | **-3.39%** | **-177** | **-2.55%** | **-44** |
| `documenting-features` | `SKILL.md` | 0 | 0.00% | -81 | -6.81% | -477 | -5.51% | -119 |
| `documenting-features` | `references/feature-requirements-example-episodes-command.md` | 0 | 0.00% | 0 | 0.00% | 0 | 0.00% | — |
| `documenting-features` | `references/feature-requirements-example-search-command.md` | 0 | 0.00% | 0 | 0.00% | 0 | 0.00% | — |
| `documenting-features` | `assets/feature-requirements.md` | 0 | 0.00% | 0 | 0.00% | 0 | 0.00% | — |
| `documenting-features` | **subtotal** | **0** | **0.00%** | **-81** | **-2.17%** | **-477** | **-1.85%** | **-119** |
| `documenting-chores` | `SKILL.md` | -4 | -2.68% | -68 | -6.47% | -386 | -5.18% | -96 |
| `documenting-chores` | `references/categories.md` | 0 | 0.00% | 0 | 0.00% | 0 | 0.00% | — |
| `documenting-chores` | `assets/chore-document.md` | 0 | 0.00% | 0 | 0.00% | 0 | 0.00% | — |
| `documenting-chores` | **subtotal** | **-4** | **-0.88%** | **-68** | **-3.20%** | **-386** | **-2.63%** | **-96** |

**Phase 1 delta notes:**
- Line count is unchanged at 104 because compression replaced longer phrasings with shorter ones on the same logical lines; no entire blocks were collapsed (FR-2 / FR-3 were both no-ops by design for this small surface).
- The `## Output Style` section (FR-4 carve-out) accounts for ~30 of the SKILL.md's 104 lines and is excluded from FR-1 compression — the achievable reduction is therefore bounded by the ~74 non-carve-out lines.
- Post-change `npm test -- finalizing-workflow` passes (72 tests across 2 files); `npm run validate` passes (13/13 lwndev-sdlc skills).

**Phase 2 delta notes:**
- SKILL.md line count is unchanged at 154 — compression replaced longer phrasings with shorter ones on the same logical lines (FR-2 / FR-3 were no-ops). The reduction shows in word count (-6.81%) and char count (-5.51%).
- The `## Output Style` section (FR-4 carve-out, lines 49-79, ~31 lines) is excluded from FR-1 compression — the achievable reduction is bounded by the ~123 non-carve-out lines plus the frontmatter (which itself is a must-preserve area).
- The two `references/feature-requirements-example-*.md` files and the `assets/feature-requirements.md` template were not edited and contribute zero delta.
- Post-change `npm test -- documenting-features` passes (14 tests across 1 file); `npm run validate` passes (13/13 lwndev-sdlc skills).

**Phase 3 delta notes:**
- SKILL.md drops from 149 to 145 lines (-4, -2.68%) — modest line-count reduction beyond Phase 2's pattern because the `## File Location` section's multi-paragraph slug-script preamble was condensed into a single intro paragraph, collapsing four logical lines.
- Word count drops 6.47% and char count drops 5.18% — within ~0.5 percentage points of Phase 2's documenting-features reduction, confirming the sibling-skill compression pattern transfers cleanly.
- The `## Output Style` section (FR-4 carve-out, lines 39-69, ~31 lines) is excluded from FR-1 compression — the achievable reduction is bounded by the ~118 non-carve-out lines plus the frontmatter.
- `references/categories.md` and `assets/chore-document.md` were not edited and contribute zero delta.
- The `## Arguments` bullets retain the literal phrases `When argument is provided` and `When no argument is provided` verbatim — required by `scripts/__tests__/argument-hint.test.ts` (cross-skill must-preserve assertion not previously inventoried in the Phase 0 audit, surfaced via post-Phase-3 `npm test`).
- Post-change `npm test -- documenting-chores` passes (12/12); cross-skill `npm test -- argument-hint` passes for documenting-chores (4/4 documenting-chores assertions); `npm run validate` passes (13/13 lwndev-sdlc skills).

### Summary (aggregate across all twelve skills)

_(To be populated when all phases complete — compare against the CHORE-035 pilot prediction of `~5 + N` compounded per-workflow savings)_

### Per-skill FR-7 pre-flight audit findings

The Phase 0 top-level audit walked all twelve `scripts/__tests__/<skill>.test.ts` files and inventoried every (a) hardcoded numeric count assertion (`toHaveLength(N)`, `toBe(N)`, `count == N`), (b) literal `## ` heading assertion (`toContain('## …')` / `not.toContain('## …')`), and (c) literal phrase assertion that constrains SKILL.md prose. Each finding is classified **must-preserve** (the assertion encodes a structural or behavioral invariant the rollout is required not to break — e.g., frontmatter `allowed-tools` checks, fork-return contract phrasing, dispatcher anchors used by the orchestrator) or **will-change** (the assertion may need an update during the per-skill phase if the optimization removes or relocates the asserted text). Per-phase pre-flight steps (each phase's step 1) confirm and refine these findings against the actual edit before any SKILL.md change lands.

#### `finalizing-workflow` (`scripts/__tests__/finalizing-workflow.test.ts`)
- **must-preserve**: `## When to Use This Skill`, `## Workflow Position`, `## Usage`, `## Relationship to Other Skills`, `## Completion` headings; the `not.toContain('## Pre-Flight Checks')` / `'## Pre-Merge Bookkeeping'` / `'## Execution'` / `'## Error Handling'` exclusion guards (these encode the post-CHORE-035 dispatcher shape); literal phrases `Ready to merge PR`, `finalize the requirement document`, `Merge PR and reset to main (and finalize requirement doc)`; `allowed-tools` frontmatter (`- Bash` only, no `- Edit`/`- Glob`/`- Write`).
- **will-change**: none identified at the structural level — all numeric `toHaveLength` / `toBe` calls in this file are checkbox-flip behavioral tests on synthetic fixture markdown, not SKILL.md surface assertions.

#### `documenting-features` (`scripts/__tests__/documenting-features.test.ts`)
- **must-preserve**: `## When to Use This Skill`, `## Verification Checklist` headings; literal phrases `requirements/features/`, `#14`, `managing-work-items`; `allowed-tools` frontmatter (`Read`/`Write`/`Edit`/`Glob`/`Grep`, no `Bash` or `Agent`).
- **will-change**: none — no numeric count assertions on SKILL.md content in this file.

#### `documenting-chores` (`scripts/__tests__/documenting-chores.test.ts`)
- **must-preserve**: `## When to Use This Skill`, `## Verification Checklist`, `## Relationship to Other Skills` headings; literal phrases `executing-chores`; `allowed-tools` frontmatter (`Read`/`Write`/`Edit`/`Glob`/`Grep`, no `Bash` or `Agent`).
- **will-change**: none.

#### `documenting-bugs` (`scripts/__tests__/documenting-bugs.test.ts`)
- **must-preserve**: `## When to Use This Skill`, `## Verification Checklist`, `## Relationship to Other Skills` headings; literal phrases `executing-bug-fixes`, `requirements/bugs/`, `BUG-XXX`; severity-section literals `critical`/`high`/`medium`/`low`; `allowed-tools` frontmatter (no `Bash`/`Agent`).
- **will-change-CANDIDATE**: line 155 `expect(matches!.length).toBe(6)` — this counts something in SKILL.md (severity entries or section markers); per-phase pre-flight in Phase 4 must read the surrounding test code and confirm whether the count is on a load-bearing list or on incidental prose. If the optimization removes any of the matched items, this assertion must be updated in the same commit per FR-7.

#### `managing-work-items` (`scripts/__tests__/managing-work-items.test.ts`)
- **must-preserve**: `## GitHub Issue` heading; references to `Backend Detection`, `#N`, `PROJ-123`, `GitHub Issues Backend`, `gh issue view`, `gh issue comment`, `Comment Type Routing`, comment-type literals (`phase-start`, `phase-completion`, `work-start`, `work-complete`, `bug-start`, `bug-complete`); reference-doc heading assertions on `references/github-templates.md` (`## Commit Messages`, `## Pull Request Templates`, `## Creating New Issues`); `allowed-tools` frontmatter; `argument-hint:`.
- **will-change**: none — the `toContain('## GitHub Issue')` is a SKILL.md heading; reference assertions target unchanged reference files. No numeric count assertions on SKILL.md.

#### `creating-implementation-plans` (`scripts/__tests__/creating-implementation-plans.test.ts`)
- **must-preserve**: `## When to Use This Skill`, `## Verification Checklist` headings; literal phrase `requirements/implementation/`; `allowed-tools` frontmatter (no `Bash`/`Agent`).
- **will-change**: none.

#### `reviewing-requirements` (`scripts/__tests__/reviewing-requirements.test.ts`)
- **must-preserve**: `## When to Use This Skill`, `## Verification Checklist`, `## Relationship to Other Skills`, `## Test-Plan Reconciliation Mode`, `## Code-Review Reconciliation Mode`, `## Step 1.5: Detect Review Mode` headings (all six are dispatcher and mode-routing anchors); literal phrases `FEAT-`, `CHORE-`, `BUG-`, `requirements/features/`, `requirements/chores/`, `requirements/bugs/`, `requirements/implementation/`, `Standard review`, `Steps 2-9`, `Step R1`, `Step R7`, `Step CR1`; mode-list frontmatter literals `standard review`, `test-plan reconciliation`, `code-review reconciliation`.
- **will-change**: none — all assertions are structural anchors that the three-axis template explicitly preserves.

#### `executing-chores` (`scripts/__tests__/executing-chores.test.ts`)
- **must-preserve**: `## When to Use This Skill`, `## Quick Start`, `## Verification Checklist`, `## Relationship to Other Skills` headings; literal phrases `documenting-chores`, `chore/CHORE-XXX`, `Closes #N`, `managing-work-items`; PR-template assertion `Closes #N`; `not.toContain('github-templates.md')` exclusion guard (per managing-work-items extraction); `allowed-tools` frontmatter (`Bash` allowed, `Agent` excluded).
- **will-change**: none.

#### `executing-bug-fixes` (`scripts/__tests__/executing-bug-fixes.test.ts`)
- **must-preserve**: `## When to Use This Skill`, `## Quick Start`, `## Verification Checklist`, `## Relationship to Other Skills` headings; literal phrases `documenting-bugs`, `fix/BUG-XXX`, `Root Cause Driven Execution`, `Redeclare root causes`, `Address root causes systematically`, `Verify per root cause`, `Closes #N`, `managing-work-items`; PR-template assertion `Root Cause(s)`; `allowed-tools` frontmatter.
- **will-change**: none — Root-Cause-Driven-Execution literals are FR-4 carve-outs.

#### `documenting-qa` (`scripts/__tests__/documenting-qa.test.ts`)
- **must-preserve**: `## When to Use This Skill`, `## Verification Checklist`, `## Relationship to Other Skills` headings on SKILL.md; literal phrases `executing-qa`, `FEAT-`, `CHORE-`, `BUG-`, `requirements/features/`, `requirements/chores/`, `requirements/bugs/`, `qa/test-plans/QA-plan-`, `capability-discovery.sh`, `persona-loader.sh`, `test-plan-template-v2.md`, `version: 2`, `not.toContain('qa-verifier')` exclusion guard; v1 and v2 template heading assertions on the asset files (`## Metadata`, `## Existing Test Verification`, `## New Test Analysis`, `## Coverage Gap Analysis`, `## Code Path Verification`, `## Plan Completeness Checklist`, `## User Summary`, `## Capability Report`, `## Scenarios (by dimension)`, `## Non-applicable dimensions`); frontmatter literals `type: command`, `not.toContain('type: prompt')`; CLI-arg parser exit-code assertions (these are behavioral, not SKILL.md surface).
- **will-change**: none — all CLI exit-code assertions are on the script binary, not on SKILL.md surface; template heading assertions target asset files which are NOT in the FR-2 relocation set.

#### `executing-qa` (`scripts/__tests__/executing-qa.test.ts`)
- **must-preserve**: `## When to Use This Skill`, `## Verification Checklist`, `## Relationship to Other Skills`, `## Reconciliation Delta` headings on SKILL.md; literal phrases `documenting-qa`, `FEAT-`, `CHORE-`, `BUG-`, `qa/test-plans/QA-plan-`, `qa/test-results/QA-results-`, `capability-discovery.sh`, `persona-loader.sh`, `test-results-template-v2.md`, verdict literals `PASS`, `ISSUES-FOUND`, `ERROR`, `EXPLORATORY-ONLY`, `not.toContain('qa-verifier')` exclusion guard; v1 and v2 template heading assertions on the asset files (`## Metadata`, `## Test Suite Results`, `## Summary`, `## Capability Report`, `## Execution Results`, `## Scenarios Run`, `## Findings`, `## Reconciliation Delta`, `## Exploratory Mode`); CLI exit-code assertions (behavioral, not SKILL.md surface); `allowed-tools` frontmatter (`Bash` allowed, `Agent` excluded).
- **will-change**: none — same rationale as documenting-qa.

#### `implementing-plan-phases` (`scripts/__tests__/implementing-plan-phases.test.ts`)
- **must-preserve**: `## When to Use`, `## Quick Start`, `## Verification` headings; literal phrases `feat/{Feature ID}`, `🔄 In Progress`, `✅ Complete`, `**After all phases complete:** Create pull request`, `Closes #N`, `not.toContain('gh issue comment')` exclusion guard, `managing-work-items`, `not.toContain('github-templates.md')` exclusion guard; `not.toContain('GitHub issue comments')` frontmatter exclusion guard; PR-template assertion `Implementation Plan`; `allowed-tools` frontmatter (no `Agent`).
- **will-change**: none — all assertions encode structural invariants that FR-1/FR-2/FR-3 preserve by design.

#### Audit summary
- Across all 12 test files, only **one** numeric-count assertion (`documenting-bugs.test.ts:155`, `expect(matches!.length).toBe(6)`) was flagged as a possible **will-change** candidate. Per-phase pre-flight in Phase 4 will inspect the surrounding test code and decide whether to update the literal `6` if the optimization removes any matched item.
- Every other assertion across the twelve files encodes either a structural invariant (heading anchor, frontmatter, fork-return contract phrase, dispatcher anchor) or a behavioral exit code — both classes of assertion the three-axis template (FR-1 lite-prose / FR-2 narrative relocation / FR-3 natural-collapse) explicitly preserves per FR-4 carve-outs and the "no semantics changes" guard.
