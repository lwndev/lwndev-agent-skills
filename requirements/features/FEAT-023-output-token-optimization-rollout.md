# Feature Requirements: Output Token Optimization Rollout

## Overview

Roll out the output-token optimization pattern piloted in CHORE-034 to the remaining twelve `lwndev-sdlc` skills. Each target skill gains an `## Output Style` section (lite narration rules + load-bearing carve-outs + fork-to-orchestrator return contract), its fork-invocation specs gain a one-line pointer to that section, and its `assets/` artifact templates are compressed to inherit the target style. Baseline and post-change measurements are captured per skill.

## Feature ID

`FEAT-023`

## GitHub Issue

[#200](https://github.com/lwndev/lwndev-marketplace/issues/200)

## Priority

Medium — continuation of completed pilot (CHORE-034); mechanical rollout with well-defined template. Runtime payoff compounds across every fork and orchestrator turn in every feature, chore, and bug workflow.

## User Story

As a maintainer of the `lwndev-sdlc` plugin, I want every sub-skill to follow the same output-style discipline piloted in `orchestrating-workflows` so that runtime output tokens are reduced consistently across all three workflow chains (feature, chore, bug) and sub-skill authors have one canonical contract to implement.

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

Ten of these have an `assets/` directory. `managing-work-items` and `finalizing-workflow` do not — FR-4 does not apply to those two.

Three skills have no `references/` directory: `documenting-qa`, `executing-qa`, and `finalizing-workflow`. FR-3 does not apply to these three (Edge Case 1 applies) and their FR-5 measurement scope excludes `references/`. In particular, `finalizing-workflow` has neither `references/` nor `assets/` — its FR-5 scope is `SKILL.md` only.

Out of scope: the pilot skill (`orchestrating-workflows`) is already done. Runtime-telemetry instrumentation is out of scope (static `wc` measurements are the methodology, matching the pilot).

## Functional Requirements

### FR-1: Add `## Output Style` section to each target SKILL.md

For each of the twelve target skills, add an `## Output Style` section to its `SKILL.md`, placed immediately after `## Quick Start` (or, if the skill has no Quick Start, after the first early-read section — typically `## When to Use This Skill` or `## Arguments`).

The section must contain three subsections in this order:

1. **Lite narration rules** — bulleted list covering:
   - No preamble before tool calls
   - No end-of-turn summaries beyond one sentence
   - No emoji
   - No restating the user
   - No status echoes that tools already show
   - ASCII punctuation (ASCII arrows `->` in skill-authored prose; existing Unicode em dashes in tables and reference docs are retained)
   - Short sentences over paragraphs; bullet lists over prose when listing more than two items
2. **Load-bearing carve-outs (never strip)** — bulleted list covering:
   - Error messages from `fail` calls
   - Security-sensitive warnings
   - Interactive prompts (plan-approval, findings-decision, etc.)
   - Findings display from `reviewing-requirements` (for review skills only)
   - FR-14 console echo lines (retain Unicode `→` as documented emitter format)
   - Tagged structured logs (`[info]`, `[warn]`, `[model]`)
   - User-visible state transitions (pause, advance, resume)
3. **Fork-to-orchestrator return contract** — names the three canonical return shapes and the precedence rule:
   - `done | artifact=<path> | <≤10-word note>` — success
   - `failed | <one-sentence reason>` — failure
   - `Found **N errors**, **N warnings**, **N info**` — retained shape for `reviewing-requirements` only
   - Precedence clause: the return contract takes precedence over the lite rules when they conflict; subagents must emit the contract shape as the final line of their response even if it reads like narration.

The section may be omitted for skills that are **never** invoked as a fork — but of the twelve, only `managing-work-items` is explicitly documented as a cross-cutting inline skill. Even for `managing-work-items`, the lite narration rules and load-bearing carve-outs still apply; the fork-return contract subsection may be replaced with a note that the skill is invoked inline from main context.

### FR-2: Formalize the fork-to-orchestrator return contract per skill

For each target skill that is invoked as a forked step by `orchestrating-workflows`, the `## Output Style` section MUST explicitly state which return shape(s) the skill emits:

- `reviewing-requirements` — emits the `Found **N errors**, **N warnings**, **N info**` summary line as the final line, preceded by the full findings block.
- `creating-implementation-plans`, `implementing-plan-phases`, `executing-chores`, `executing-bug-fixes`, `finalizing-workflow`, the inline PR-creation step, and any other forked step — emit `done | artifact=<path> | <note>` on success and `failed | <reason>` on failure.
- `documenting-features`, `documenting-chores`, `documenting-bugs`, `documenting-qa`, `executing-qa` — run in main context, not as forks. Their `## Output Style` section still includes the lite rules and carve-outs, but the return-contract subsection notes that they return to the user (not to a parent orchestrator) and therefore the `done | ...` shape is not required.
- `managing-work-items` — cross-cutting inline skill; the contract subsection notes inline execution from main context.

### FR-3: Add reference-file pointers to each fork-invocation spec

**Scope clarification**: The canonical fork-invocation specs for the twelve target skills live in `orchestrating-workflows/references/step-execution-details.md`, and CHORE-034 already added the return-contract pointers there. FR-3 is therefore a forward-looking rule for the rollout: if a target skill's own `references/` directory already contains (or gains during this work) an inline fork-invocation spec — for example, a reference file that documents a sub-fork spawned via the `Agent` tool from within the skill — add a one-line pointer immediately under that invocation spec:

```
Subagent must return the canonical contract shape; see SKILL.md `## Output Style`.
```

Reference files that do not describe fork invocations do not need this pointer. If no target skill's references contain fork-invocation specs at implementation time, FR-3 is satisfied as a no-op and this must be recorded in the Notes section (listing which skills were checked). Three target skills have no `references/` directory and are exempt: `documenting-qa`, `executing-qa`, `finalizing-workflow` (Edge Case 1).

### FR-4: Compress artifact templates under `assets/`

For each of the ten target skills with an `assets/` directory, review the artifact templates (e.g., `feature-requirements.md`, `chore-template.md`, `bug-template.md`, `qa-plan-template.md`, `qa-results-template.md`, `implementation-plan-template.md`, etc.) and apply the lite-narration rules to generated output:

- Remove preamble text that templates may contain (intros, "This document describes...", etc.)
- Keep load-bearing sections intact (all the numbered/labelled requirement blocks, verification checklists, acceptance criteria tables)
- Tighten procedural prose where it is safely compressible (aim for a floor of ~3% char reduction in prose-heavy templates; do not force aggressive cuts on load-bearing procedural content per CHORE-034 Learnings)

Templates whose entire body is a structural skeleton (headers + placeholders) may already be minimal — in that case, no changes are required and this is recorded in the Notes section of the chore.

### FR-5: Capture baseline and post-change measurements per skill

For each of the twelve target skills, capture baseline `wc -l -w -c` measurements across:

- `SKILL.md`
- All files under `references/`
- All files under `assets/` (where present)

Append a measurement table to this feature's Notes section (not the pilot's) with rows: per-file baseline, per-skill subtotal, and a grand-total across all twelve skills.

After the optimization is applied, capture post-change measurements in the same format and a delta table (lines Δ, lines %, words Δ, words %, chars Δ, chars %) per file, per skill, and across the grand total. Mirror the CHORE-034 table format.

### FR-6: Preserve behavioral correctness

The rollout is a documentation/style change. It must not:

- Change any skill's frontmatter fields (`name`, `description`, `allowed-tools`, `argument-hint`, etc.) except where absolutely necessary to accommodate the new section
- Change any script invocation, file path, or artifact path
- Change any verification checklist semantics (items may be reworded for tightness but must not drop criteria)
- Change the Fork Step-Name Map or any step-sequence table in `orchestrating-workflows`

`npm run validate` and `npm test` must continue to pass unchanged.

## Non-Functional Requirements

### NFR-1: Measurement methodology parity with pilot

Use the same static-`wc` methodology CHORE-034 used. Runtime telemetry is out of scope for this rollout. The methodology section at the top of the Notes section must state this explicitly.

### NFR-2: Per-skill atomicity

Each skill's edits should be a logical unit that can be reviewed independently. The implementation plan (produced by `creating-implementation-plans`) should split work into phases of one skill per phase (or group small skills where each phase is still reviewable in isolation).

### NFR-3: No behavioral regressions

The rollout must not alter the runtime behavior of any skill. All existing tests must pass. If a test asserts on narration content that this rollout trims, update the test to match the new canonical narration — and call it out in the PR body.

### NFR-4: Consistency across skills

The same `## Output Style` section structure (three subsections in the pilot's order), the same lite-rule wording, and the same carve-out list must appear in every target skill. Deviations are allowed only when justified by the skill's role (e.g., main-context skills note that the `done | ...` shape is not required).

## Dependencies

- CHORE-034 (pilot) — merged; its Learnings subsection in `requirements/chores/CHORE-034-output-token-optimization-pilot.md` is the source of truth for the template.
- `orchestrating-workflows/SKILL.md` — the canonical example of the `## Output Style` section; the rollout replicates its structure.
- No external tooling beyond `wc` and the existing `npm run validate` / `npm test`.

## Edge Cases

1. **Skill with no `references/` directory** (`documenting-qa`, `executing-qa`, `finalizing-workflow`): FR-3 does not apply; record this in the Notes section.
2. **Skill with no `assets/` directory**:
   - `managing-work-items`: FR-4 does not apply; FR-5 measurements cover `SKILL.md` and `references/`.
   - `finalizing-workflow`: FR-4 does not apply and the skill has no `references/` directory either; FR-5 measurements cover `SKILL.md` only (the measurement table's "per-skill subtotal" row degenerates to a single file — acceptable).
3. **Skill that is both forked AND main-context** (none exist today among the twelve, but if one surfaces during implementation): document both return shapes in FR-2.
4. **Template already minimal** (no prose to compress): record in Notes and mark FR-4 satisfied by inspection.
5. **Test asserts on trimmed narration**: update the test; call out the change in the PR body (per NFR-3).
6. **Reference file describes multiple fork invocations**: add one pointer per invocation (FR-3).
7. **Skill's Quick Start section is absent**: place the `## Output Style` section after the first early-read section (`## When to Use This Skill` or `## Arguments`).
8. **Ambiguous placement — `## Output Style` collides with existing section name**: no current skill has one; if it surfaces, rename the existing section or merge content.

## Testing Requirements

### Unit Tests

- `npm run validate` must pass for every plugin change (SKILL.md frontmatter valid, references resolve).

### Integration Tests

- `npm test` must pass end-to-end across the monorepo after each skill's edits land.

### Manual Testing

- Spot-check three representative skill edits (one forked sub-skill, one main-context sub-skill, one cross-cutting skill) by rendering SKILL.md in a markdown preview and confirming the `## Output Style` section reads cleanly.
- Run one full feature workflow chain (resume or new) to confirm no fork-return regressions.
- Run one full chore workflow chain to confirm no fork-return regressions.

## Future Enhancements

- Runtime-telemetry methodology (`tokensOut` accounting across Agent-tool results) once Claude Code exposes it — would replace the static `wc` proxy with end-to-end token measurement.
- Lint rule that checks every forkable skill's SKILL.md for an `## Output Style` section and a return-contract subsection.

## Acceptance Criteria

- [ ] Each of the twelve target skills has an `## Output Style` section in `SKILL.md` placed immediately after `## Quick Start` (or the first early-read section if no Quick Start exists).
- [ ] Each `## Output Style` section contains the three subsections in the order: Lite narration rules → Load-bearing carve-outs → Fork-to-orchestrator return contract.
- [ ] The `## Output Style` section wording (lite-narration rules and load-bearing carve-outs) is consistent across all twelve target skills; any deviations (e.g., main-context skills noting they return to the user, `managing-work-items` noting inline execution) are documented in the Notes section with justification.
- [ ] Each forkable target skill documents which canonical return shape(s) it emits (per FR-2).
- [ ] Main-context skills (`documenting-features`, `documenting-chores`, `documenting-bugs`, `documenting-qa`, `executing-qa`) note in the return-contract subsection that they return to the user, not a parent orchestrator.
- [ ] `managing-work-items` notes inline execution from main context in its return-contract subsection.
- [ ] Every forked-step invocation spec in a target skill's `references/` directory has a one-line pointer to `SKILL.md ## Output Style`.
- [ ] For each of the ten target skills with an `assets/` directory, artifact templates have been reviewed and either compressed or flagged as already-minimal in the Notes section.
- [ ] Baseline `wc -l -w -c` measurements have been captured for every target skill's `SKILL.md`, `references/*`, and `assets/*` and appended to the Notes section of this feature document.
- [ ] Post-change measurements have been captured in the same format and a delta table appended to the Notes section.
- [ ] `npm run validate` passes.
- [ ] `npm test` passes.
- [ ] No frontmatter fields were changed except where strictly necessary.
- [ ] No Fork Step-Name Map entry or step-sequence table in `orchestrating-workflows` was modified.
- [ ] A Completion section is appended to this document on PR merge with the PR link.

## Notes

Measurements will be appended here by the implementation phases.

### Phase 1 — finalizing-workflow

- FR-3 no-op: `finalizing-workflow` has no `references/` directory; no fork-invocation specs to annotate (Edge Case 1).
- FR-4 no-op: `finalizing-workflow` has no `assets/` directory; no artifact templates to compress.
- FR-5 scope: SKILL.md only (per Scope clarification and Edge Case 2).

| File | Lines | Words | Chars |
|---|---:|---:|---:|
| `plugins/lwndev-sdlc/skills/finalizing-workflow/SKILL.md` (baseline) | 72 | 564 | 3982 |
| `plugins/lwndev-sdlc/skills/finalizing-workflow/SKILL.md` (post-change) | 104 | 1004 | 6931 |
| **Δ** | +32 | +440 | +2949 |

Per NFR-3, the `scripts/__tests__/finalizing-workflow.test.ts` "should be under 80 lines after the collapse" assertion (originally set by FEAT-022 after the skill was collapsed to ~72 lines) was updated to a 120-line ceiling to accommodate the rollout-wide `## Output Style` section. No other tests required changes.

### Phase 2 — managing-work-items

- `[input]` FR-3 no-op for `github-templates.md` and `jira-templates.md`: both reference files are API-interaction templates (`gh issue view` / `gh issue comment` / Rovo MCP ADF / `acli` commands). They document external API call patterns, not Agent-tool subagent spawning, so no fork-invocation specs exist to annotate.
- FR-4 no-op: `managing-work-items` has no `assets/` directory; no artifact templates to compress.
- FR-5 scope: SKILL.md only. `managing-work-items` is a cross-cutting inline skill — invoked directly from the orchestrator's main context per `orchestrating-workflows/references/issue-tracking.md`, NOT forked via the Agent tool. The `## Output Style` section's return-contract subsection was replaced with an "Inline execution note" stating the `done | artifact=...` / `failed | ...` shapes do not apply; tool-call results are consumed directly. WARNING-level mechanism-failure lines remain load-bearing.

| File | Lines | Words | Chars |
|---|---:|---:|---:|
| `plugins/lwndev-sdlc/skills/managing-work-items/SKILL.md` (baseline) | 358 | 2811 | 19210 |
| `plugins/lwndev-sdlc/skills/managing-work-items/SKILL.md` (post-change) | 390 | 3331 | 22857 |
| **Δ** | +32 | +520 | +3647 |
| `plugins/lwndev-sdlc/skills/managing-work-items/references/github-templates.md` (baseline) | 740 | 2315 | 17196 |
| `plugins/lwndev-sdlc/skills/managing-work-items/references/github-templates.md` (post-change) | 740 | 2315 | 17196 |
| **Δ** | 0 | 0 | 0 |
| `plugins/lwndev-sdlc/skills/managing-work-items/references/jira-templates.md` (baseline) | 715 | 2079 | 19135 |
| `plugins/lwndev-sdlc/skills/managing-work-items/references/jira-templates.md` (post-change) | 715 | 2079 | 19135 |
| **Δ** | 0 | 0 | 0 |

### Phase 3 — documenting-features

- FR-3 no-op for `references/feature-requirements-example-search-command.md` and `references/feature-requirements-example-episodes-command.md`: both are example requirement documents (prose feature specs / CLI specs) that document user-facing command behavior, not Agent-tool subagent spawning. No fork-invocation specs exist to annotate, so no pointer was added.
- FR-4 decision for `assets/feature-requirements.md`: already-minimal. The template is a pure structural skeleton — headers (`## Overview`, `## Feature ID`, `## Priority`, `## User Story`, `## Command Syntax`, `## Functional Requirements`, etc.) with bracketed placeholders (`[1-2 sentence description ...]`, `[Feature Name]`, `[High/Medium/Low] - [Brief justification]`) and `...` continuation markers. No preamble prose, no "This document describes..." intro, no procedural narration to compress. Bracketed placeholder hints are load-bearing (they carry the author's guidance on what each section should contain) and removing them would break the template's purpose. No changes applied; recorded as already-minimal per FR-4 and Edge Case 4.
- FR-5 scope: SKILL.md, both references files, and the assets template. `documenting-features` is a main-context skill (feature chain step 1) — its `## Output Style` section uses the main-context return-contract variant stating it returns to the user, not a parent orchestrator; the `done | ...` / `failed | ...` shapes do not apply. Lite rules and carve-outs still govern.

| File | Lines | Words | Chars |
|---|---:|---:|---:|
| `plugins/lwndev-sdlc/skills/documenting-features/SKILL.md` (baseline) | 122 | 746 | 5655 |
| `plugins/lwndev-sdlc/skills/documenting-features/SKILL.md` (post-change) | 154 | 1190 | 8648 |
| **Δ** | +32 | +444 | +2993 |
| `plugins/lwndev-sdlc/skills/documenting-features/references/feature-requirements-example-search-command.md` (baseline) | 228 | 1021 | 6872 |
| `plugins/lwndev-sdlc/skills/documenting-features/references/feature-requirements-example-search-command.md` (post-change) | 228 | 1021 | 6872 |
| **Δ** | 0 | 0 | 0 |
| `plugins/lwndev-sdlc/skills/documenting-features/references/feature-requirements-example-episodes-command.md` (baseline) | 274 | 1278 | 8512 |
| `plugins/lwndev-sdlc/skills/documenting-features/references/feature-requirements-example-episodes-command.md` (post-change) | 274 | 1278 | 8512 |
| **Δ** | 0 | 0 | 0 |
| `plugins/lwndev-sdlc/skills/documenting-features/assets/feature-requirements.md` (baseline) | 94 | 242 | 1715 |
| `plugins/lwndev-sdlc/skills/documenting-features/assets/feature-requirements.md` (post-change) | 94 | 242 | 1715 |
| **Δ** | 0 | 0 | 0 |
