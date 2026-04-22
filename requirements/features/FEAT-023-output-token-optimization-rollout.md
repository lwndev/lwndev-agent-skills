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

- [x] Each of the twelve target skills has an `## Output Style` section in `SKILL.md` placed immediately after `## Quick Start` (or the first early-read section if no Quick Start exists).
- [x] Each `## Output Style` section contains the three subsections in the order: Lite narration rules → Load-bearing carve-outs → Fork-to-orchestrator return contract.
- [x] The `## Output Style` section wording (lite-narration rules and load-bearing carve-outs) is consistent across all twelve target skills; any deviations (e.g., main-context skills noting they return to the user, `managing-work-items` noting inline execution) are documented in the Notes section with justification.
- [x] Each forkable target skill documents which canonical return shape(s) it emits (per FR-2).
- [x] Main-context skills (`documenting-features`, `documenting-chores`, `documenting-bugs`, `documenting-qa`, `executing-qa`) note in the return-contract subsection that they return to the user, not a parent orchestrator.
- [x] `managing-work-items` notes inline execution from main context in its return-contract subsection.
- [x] Every forked-step invocation spec in a target skill's `references/` directory has a one-line pointer to `SKILL.md ## Output Style`. (Satisfied as a no-op across all checked skills — see FR-3 no-op registry in Notes; no fork-invocation specs exist in any target skill's `references/` directory.)
- [x] For each of the ten target skills with an `assets/` directory, artifact templates have been reviewed and either compressed or flagged as already-minimal in the Notes section.
- [x] Baseline `wc -l -w -c` measurements have been captured for every target skill's `SKILL.md`, `references/*`, and `assets/*` and appended to the Notes section of this feature document.
- [x] Post-change measurements have been captured in the same format and a delta table appended to the Notes section.
- [x] `npm run validate` passes.
- [x] `npm test` passes.
- [x] No frontmatter fields were changed except where strictly necessary.
- [x] No Fork Step-Name Map entry or step-sequence table in `orchestrating-workflows` was modified.
- [x] A Completion section is appended to this document on PR merge with the PR link.

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

### Phase 4 — documenting-chores

- FR-3 no-op for `references/categories.md`: the file is a reference table of chore categories (dependencies, documentation, refactoring, configuration, cleanup) with common use cases, typical affected files, suggested acceptance criteria, and category notes. It does not describe spawning subagents via the Agent tool. No fork-invocation specs exist to annotate, so no pointer was added.
- FR-4 decision for `assets/chore-document.md`: already-minimal. The template is a pure structural skeleton — headers (`## Chore ID`, `## GitHub Issue`, `## Category`, `## Description`, `## Affected Files`, `## Acceptance Criteria`, `## Completion`, `## Notes`) with bracketed placeholders (`[Brief Title]`, `[1-2 sentences describing the work to be done]`, `[dependencies|documentation|refactoring|configuration|cleanup]`) and HTML-commented author guidance. No preamble prose, no "This document describes..." intro, no procedural narration to compress. The HTML comments carry load-bearing guidance (category choice hints, status progression, example acceptance criteria) and removing them would break the template's self-documentation. No changes applied; recorded as already-minimal per FR-4 and Edge Case 4.
- FR-5 scope: SKILL.md, the references file, and the assets template. `documenting-chores` is a main-context skill (chore chain step 1) — its `## Output Style` section uses the main-context return-contract variant stating it returns to the user, not a parent orchestrator; the `done | ...` / `failed | ...` shapes do not apply. Lite rules and carve-outs still govern. Wording matches Phase 3 (`documenting-features`) exactly except for the one-sentence preamble ("chore chain step 1" vs "feature chain step 1") per NFR-4 consistency.

| File | Lines | Words | Chars |
|---|---:|---:|---:|
| `plugins/lwndev-sdlc/skills/documenting-chores/SKILL.md` (baseline) | 117 | 607 | 4466 |
| `plugins/lwndev-sdlc/skills/documenting-chores/SKILL.md` (post-change) | 149 | 1051 | 7453 |
| **Δ** | +32 | +444 | +2987 |
| `plugins/lwndev-sdlc/skills/documenting-chores/references/categories.md` (baseline) | 198 | 720 | 4785 |
| `plugins/lwndev-sdlc/skills/documenting-chores/references/categories.md` (post-change) | 198 | 720 | 4785 |
| **Δ** | 0 | 0 | 0 |
| `plugins/lwndev-sdlc/skills/documenting-chores/assets/chore-document.md` (baseline) | 109 | 356 | 2456 |
| `plugins/lwndev-sdlc/skills/documenting-chores/assets/chore-document.md` (post-change) | 109 | 356 | 2456 |
| **Δ** | 0 | 0 | 0 |

### Phase 5 — documenting-bugs

- FR-3 no-op for `references/categories.md`: the file is a reference table of bug categories (runtime-error, logic-error, ui-defect, performance, security, regression) with common use cases, typical affected files, suggested acceptance criteria, and category notes. It does not describe spawning subagents via the Agent tool. No fork-invocation specs exist to annotate, so no pointer was added.
- FR-4 decision for `assets/bug-document.md`: already-minimal. The template is a pure structural skeleton — headers (`## Bug ID`, `## GitHub Issue`, `## Category`, `## Severity`, `## Description`, `## Steps to Reproduce`, `## Expected Behavior`, `## Actual Behavior`, `## Root Cause(s)`, `## Affected Files`, `## Acceptance Criteria`, `## Completion`, `## Notes`) with bracketed placeholders (`[Brief Title]`, `[1-2 sentences describing the defect]`, `[runtime-error|logic-error|ui-defect|performance|security|regression]`) and HTML-commented author guidance. No preamble prose, no "This document describes..." intro, no procedural narration to compress. The HTML comments carry load-bearing guidance (category choice hints, severity level definitions, RC-N traceability tagging rules, example acceptance criteria with RC references) and removing them would break the template's self-documentation. No changes applied; recorded as already-minimal per FR-4 and Edge Case 4.
- FR-5 scope: SKILL.md, the references file, and the assets template. `documenting-bugs` is a main-context skill (bug chain step 1) — its `## Output Style` section uses the main-context return-contract variant stating it returns to the user, not a parent orchestrator; the `done | ...` / `failed | ...` shapes do not apply. Lite rules and carve-outs still govern. Wording matches Phases 3 and 4 exactly except for the one-sentence preamble ("bug chain step 1" vs "chore chain step 1" / "feature chain step 1") per NFR-4 consistency.

| File | Lines | Words | Chars |
|---|---:|---:|---:|
| `plugins/lwndev-sdlc/skills/documenting-bugs/SKILL.md` (baseline) | 136 | 769 | 5432 |
| `plugins/lwndev-sdlc/skills/documenting-bugs/SKILL.md` (post-change) | 168 | 1213 | 8411 |
| **Δ** | +32 | +444 | +2979 |
| `plugins/lwndev-sdlc/skills/documenting-bugs/references/categories.md` (baseline) | 236 | 1134 | 7429 |
| `plugins/lwndev-sdlc/skills/documenting-bugs/references/categories.md` (post-change) | 236 | 1134 | 7429 |
| **Δ** | 0 | 0 | 0 |
| `plugins/lwndev-sdlc/skills/documenting-bugs/assets/bug-document.md` (baseline) | 181 | 707 | 4759 |
| `plugins/lwndev-sdlc/skills/documenting-bugs/assets/bug-document.md` (post-change) | 181 | 707 | 4759 |
| **Δ** | 0 | 0 | 0 |

### Phase 6 — reviewing-requirements

- FR-3 no-op for `references/review-example.md`: the file is two annotated example review outputs (a Standard Review Example for FEAT-006 and a Test-Plan Reconciliation Example for CHORE-015). It demonstrates the findings-block and fix-summary format produced by the skill; it does NOT describe spawning subagents via the Agent tool. No fork-invocation specs exist to annotate, so no pointer was added. This is noteworthy because `reviewing-requirements` is one of the few target skills whose frontmatter includes `Agent` in `allowed-tools` (for parallelizing targeted searches in Step 3), making it theoretically possible for its `references/` to describe a sub-fork. The actual content does not.
- FR-4 decision for `assets/review-findings-template.md`: already-minimal. The template is a pure structural skeleton in two variants (Standard Review Format and Test-Plan Reconciliation Format) — headers (`## Summary`, `### Errors`, `### Warnings`, `### Info`, `### Fix Summary`, `### Update Summary`), per-severity placeholder rows (`**[E1] {Category} — {Section Reference}**` / `{Description}` / `Suggestion:`), and HTML comments documenting which format to use when and the reconciliation category ordering. Every line is load-bearing: the bracketed placeholders are the format the orchestrator's Decision Flow parses (severity prefixes, `Found **N errors** ...` summary line, `Would you like me to apply ...` prompt), and the HTML comments carry the format-selection guidance. No preamble prose, no "This template describes..." intro, no procedural narration to compress. No changes applied; recorded as already-minimal per FR-4 and Edge Case 4.
- FR-5 scope: SKILL.md, the references file, and the assets template. `reviewing-requirements` is a forked skill (invoked at three points in each chain: standard review, test-plan reconciliation, code-review reconciliation) and is the **one exception** to the `done | artifact=... | <note>` return shape. Its `## Output Style` Fork-to-orchestrator return contract subsection states that on success it emits the full findings block followed by `Found **N errors**, **N warnings**, **N info**` as the final line (or `No issues found in <filename>. ...` on zero counts), and on failure emits `failed | <one-sentence reason>`. The findings-display carve-out is explicitly marked load-bearing for this skill (the orchestrator displays the full block to the user), with a precedence clause confirming the summary line is the LAST line of the response even when a load-bearing findings block precedes it.

| File | Lines | Words | Chars |
|---|---:|---:|---:|
| `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` (baseline) | 393 | 3385 | 24386 |
| `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` (post-change) | 434 | 3929 | 27945 |
| **Δ** | +41 | +544 | +3559 |
| `plugins/lwndev-sdlc/skills/reviewing-requirements/references/review-example.md` (baseline) | 95 | 525 | 3897 |
| `plugins/lwndev-sdlc/skills/reviewing-requirements/references/review-example.md` (post-change) | 95 | 525 | 3897 |
| **Δ** | 0 | 0 | 0 |
| `plugins/lwndev-sdlc/skills/reviewing-requirements/assets/review-findings-template.md` (baseline) | 98 | 426 | 3178 |
| `plugins/lwndev-sdlc/skills/reviewing-requirements/assets/review-findings-template.md` (post-change) | 98 | 426 | 3178 |
| **Δ** | 0 | 0 | 0 |

### Phase 7 — creating-implementation-plans

- FR-3 no-op for `references/implementation-plan-example.md`: the file is a concrete example implementation plan (Podcast Index CLI Features) showing phase structure, rationale prose, implementation steps, deliverables, and risk assessments across five features. It does NOT describe spawning subagents via the Agent tool — `creating-implementation-plans` is itself forked by `orchestrating-workflows` but does not fork further work of its own. No fork-invocation specs exist to annotate, so no pointer was added.
- FR-4 decision for `assets/implementation-plan.md`: already-minimal. The template is a pure structural skeleton — `## Overview`, `## Features Summary` table, `### Phase N` blocks with `#### Rationale` / `#### Implementation Steps` / `#### Deliverables` sub-headers, `## Shared Infrastructure`, `## Testing Strategy`, `## Dependencies and Prerequisites`, `## Risk Assessment` table, `## Success Criteria`, `## Code Organization` code-fence. Every line is a header, a bracketed placeholder, or a one-line hint (e.g., `[1-2 paragraph summary of what's being built and why]`, `[Why build this first]`). No preamble prose, no "This template describes..." intro, no procedural narration to compress. No changes applied; recorded as already-minimal per FR-4 and Edge Case 4.
- FR-5 scope: SKILL.md only (example and template both unchanged). `creating-implementation-plans` is a forked skill (feature chain step 3) with the **standard** `done | artifact=<path> | <note>` return shape — no reviewing-requirements-style findings-display carve-out. The carve-out list is the canonical seven bullets with the findings-display bullet retained as N/A per NFR-4.

| File | Lines | Words | Chars |
|---|---:|---:|---:|
| `plugins/lwndev-sdlc/skills/creating-implementation-plans/SKILL.md` (baseline) | 107 | 529 | 3981 |
| `plugins/lwndev-sdlc/skills/creating-implementation-plans/SKILL.md` (post-change) | 139 | 939 | 6812 |
| **Δ** | +32 | +410 | +2831 |
| `plugins/lwndev-sdlc/skills/creating-implementation-plans/references/implementation-plan-example.md` (baseline) | 499 | 2766 | 20322 |
| `plugins/lwndev-sdlc/skills/creating-implementation-plans/references/implementation-plan-example.md` (post-change) | 499 | 2766 | 20322 |
| **Δ** | 0 | 0 | 0 |
| `plugins/lwndev-sdlc/skills/creating-implementation-plans/assets/implementation-plan.md` (baseline) | 79 | 234 | 1771 |
| `plugins/lwndev-sdlc/skills/creating-implementation-plans/assets/implementation-plan.md` (post-change) | 79 | 234 | 1771 |
| **Δ** | 0 | 0 | 0 |

### Phase 8 — documenting-qa

- FR-3 no-op per Edge Case 1: `documenting-qa` has no `references/` directory. Skill directory contents: `SKILL.md`, `assets/`, `personas/`, `scripts/`. No references files exist to check for fork-invocation specs, so no pointer was added. This skill is exempt from FR-3 and is listed as such for the Phase 13 exempt-skills registry.
- FR-4 decision for `assets/test-plan-template-v2.md` (active template): already-minimal. The template is the structural schema consumed by the skill's Stop hook (`scripts/stop-hook.sh`), which greps for the exact frontmatter keys (`id`, `version`, `timestamp`, `persona`), the required section headers (`## User Summary`, `## Capability Report`, `## Scenarios (by dimension)` with its five dimension subheadings `### Inputs` / `### State transitions` / `### Environment` / `### Dependency failure` / `### Cross-cutting`, and `## Non-applicable dimensions`), and the scenario-line shape (`- [P0|P1|P2] <description> | mode: ... | expected: ...`). The opening HTML comment documents version-1 vs version-2 detection rules and the no-`FR-N` stop-hook guard — load-bearing for parser-maintainer context. The `{...}` placeholder prose inside `## User Summary` and `## Non-applicable dimensions` is guidance the author reads while filling the template; removing it reduces self-documentation without materially reducing artifact-output tokens (placeholders are replaced on use). Every line is either a structural header, a parser-enforced shape, or load-bearing author guidance. No preamble prose unrelated to the schema, no "This template describes..." intro. No changes applied; recorded as already-minimal per FR-4 and Edge Case 4. Changing this template risks false Stop-hook rejections across every future QA plan.
- FR-4 decision for `assets/test-plan-template.md` (legacy v1 template): legacy-preserved, no changes. The template is the pre-FEAT-018 schema (`## Metadata`, `## Existing Test Verification`, `## New Test Analysis`, `## Coverage Gap Analysis`, `## Code Path Verification`, `## Deliverable Verification`, `## Plan Completeness Checklist`) retained alongside v2 so any pre-redesign QA plan file remains parseable and the version-1-vs-version-2 detection rule in the v2 template's opening comment continues to make sense. The skill itself no longer references this file as the plan output target (Step 6 uses v2), so modifying it would risk breaking legacy-artifact compatibility without benefit. Recorded as already-minimal / legacy-preserved per FR-4 and Edge Case 4.
- FR-5 scope: SKILL.md only (both assets templates unchanged). `documenting-qa` is a main-context skill (feature chain step 5, chore/bug chain step 3) — its `## Output Style` section uses the main-context return-contract variant stating it returns to the user, not a parent orchestrator; the `done | ...` / `failed | ...` shapes do not apply. An additional sentence documents that structural conformance of the emitted artifact (`qa/test-plans/QA-plan-{ID}.md`) is enforced by the Stop hook (`scripts/stop-hook.sh`) instead. Lite rules and carve-outs still govern. Wording matches Phases 3–5 (main-context variant) exactly except for the chain-context preamble ("feature chain step 5; chore/bug chain step 3" vs "feature chain step 1" / "chore chain step 1" / "bug chain step 1") and the per-skill error-message examples (capability-discovery.sh / persona-loader.sh / gh pr view / git diff / stop-hook block) and interactive-prompt examples (requirement-ID prompt, user-summary prompt, "what to test" pointer prompt) per NFR-4 consistency.

| File | Lines | Words | Chars |
|---|---:|---:|---:|
| `plugins/lwndev-sdlc/skills/documenting-qa/SKILL.md` (baseline) | 168 | 1461 | 10257 |
| `plugins/lwndev-sdlc/skills/documenting-qa/SKILL.md` (post-change) | 200 | 1971 | 13726 |
| **Δ** | +32 | +510 | +3469 |
| `plugins/lwndev-sdlc/skills/documenting-qa/assets/test-plan-template-v2.md` (baseline) | 65 | 334 | 2252 |
| `plugins/lwndev-sdlc/skills/documenting-qa/assets/test-plan-template-v2.md` (post-change) | 65 | 334 | 2252 |
| **Δ** | 0 | 0 | 0 |
| `plugins/lwndev-sdlc/skills/documenting-qa/assets/test-plan-template.md` (baseline) | 65 | 422 | 2575 |
| `plugins/lwndev-sdlc/skills/documenting-qa/assets/test-plan-template.md` (post-change) | 65 | 422 | 2575 |
| **Δ** | 0 | 0 | 0 |

### Phase 9 — executing-qa

- FR-3 no-op per Edge Case 1: `executing-qa` has no `references/` directory. Skill directory contents: `SKILL.md`, `assets/`, `personas/`, `scripts/`. No references files exist to check for fork-invocation specs, so no pointer was added. This skill is exempt from FR-3 and is listed as such for the Phase 13 exempt-skills registry.
- FR-4 decision for `assets/test-results-template-v2.md` (active template): already-minimal. The template is the structural schema consumed by the skill's Stop hook (`scripts/stop-hook.sh`), which greps for the exact frontmatter keys (`id`, `version`, `timestamp`, `verdict`, `persona`), the verdict enum (`PASS | ISSUES-FOUND | ERROR | EXPLORATORY-ONLY`), the required section headers (`## Summary`, `## Capability Report`, `## Execution Results`, `## Scenarios Run`, `## Findings`, `## Reconciliation Delta`, `## Exploratory Mode`), the per-verdict structural rules (`Failed: 0` for PASS, failing-test name for ISSUES-FOUND, stack trace for ERROR, `Reason:` for EXPLORATORY-ONLY), and the Execution-Results `Total/Passed/Failed/Errored/Exit code` count lines. The opening HTML comment documents version-1 vs version-2 detection rules and the NFR-3 legacy-preservation contract — load-bearing for parser-maintainer context. The `{...}` placeholder prose inside `## Summary`, `## Findings`, and `## Exploratory Mode` is guidance the author reads while filling the template; removing it reduces self-documentation without materially reducing artifact-output tokens (placeholders are replaced on use). Every line is either a structural header, a parser-enforced shape, or load-bearing author guidance. No preamble prose unrelated to the schema, no "This template describes..." intro. No changes applied; recorded as already-minimal per FR-4 and Edge Case 4. Changing this template risks false Stop-hook rejections across every future QA results artifact.
- FR-4 decision for `assets/test-results-template.md` (legacy v1 template): legacy-preserved, no changes. The template is the pre-FEAT-018 schema (`## Metadata`, `## Per-Entry Verification Results`, `## Test Suite Results`, `## Issues Found and Fixed`, `## Reconciliation Summary`, `## Deviation Notes`) retained alongside v2 so any pre-redesign QA results file remains parseable and the version-1-vs-version-2 detection rule in the v2 template's opening comment continues to make sense (NFR-3 preserves 34 legacy artifacts unmodified). The skill itself no longer references this file as the results output target (Step 7 uses v2), so modifying it would risk breaking legacy-artifact compatibility without benefit. Recorded as already-minimal / legacy-preserved per FR-4 and Edge Case 4.
- FR-5 scope: SKILL.md only (both assets templates unchanged). `executing-qa` is a main-context skill (feature chain step 5+N+3; chore/bug chain step 6) — its `## Output Style` section uses the main-context return-contract variant stating it returns to the user, not a parent orchestrator; the `done | ...` / `failed | ...` shapes do not apply. An additional sentence documents that structural conformance of the emitted artifact (`qa/test-results/QA-results-{ID}.md`) is enforced by the Stop hook (`scripts/stop-hook.sh`) instead, including per-verdict rules (`Failed: 0` for PASS, failing-test names for ISSUES-FOUND, stack trace for ERROR, `Reason:` for EXPLORATORY-ONLY). Lite rules and carve-outs still govern. Wording matches Phase 8 (main-context variant with stop-hook sentence) exactly except for the chain-context preamble ("feature chain step 5+N+3; chore/bug chain step 6" vs Phase 8's "feature chain step 5; chore/bug chain step 3"), the per-skill error-message examples (capability-discovery.sh / persona-loader.sh / git diff / testCommand / stop-hook block), and the interactive-prompt examples (requirement-ID prompt, missing-test-plan error pointing to `documenting-qa`, pointer prompt when there are no branch changes to test) per NFR-4 consistency.

| File | Lines | Words | Chars |
|---|---:|---:|---:|
| `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` (baseline) | 238 | 1986 | 13831 |
| `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` (post-change) | 270 | 2501 | 17396 |
| **Δ** | +32 | +515 | +3565 |
| `plugins/lwndev-sdlc/skills/executing-qa/assets/test-results-template-v2.md` (baseline) | 81 | 380 | 2577 |
| `plugins/lwndev-sdlc/skills/executing-qa/assets/test-results-template-v2.md` (post-change) | 81 | 380 | 2577 |
| **Δ** | 0 | 0 | 0 |
| `plugins/lwndev-sdlc/skills/executing-qa/assets/test-results-template.md` (baseline) | 89 | 466 | 2753 |
| `plugins/lwndev-sdlc/skills/executing-qa/assets/test-results-template.md` (post-change) | 89 | 466 | 2753 |
| **Δ** | 0 | 0 | 0 |

### Phase 10 — implementing-plan-phases

- FR-3 no-op for `references/step-details.md`: the file is per-step guidance for the ten-step phase-implementation workflow (locate plan, identify target phase, update status, branch strategy, load todos, execute, verify, commit/push, update status, create PR). It does NOT describe spawning subagents via the Agent tool — `implementing-plan-phases` is itself forked by `orchestrating-workflows` (one fork per phase) but does not fork further work of its own. A `grep -in "agent\|fork\|subagent\|spawn"` on the file returned no matches. No fork-invocation specs exist to annotate, so no pointer was added.
- FR-3 no-op for `references/workflow-example.md`: the file is an annotated end-to-end example of implementing Phase 2 of a validate-command plan (update status, read plan, verify prerequisites, create branch, load todos, execute each step, verify, commit/push, update status, update issue). Same `grep` returned no matches. It describes sequential step execution by the skill's own runtime, not Agent-tool sub-forks, so no pointer was added.
- FR-4 decision for `assets/pr-template.md`: already-minimal. The template is the PR-body shape consumed by `scripts/create-pr.sh` (Template / Filled Example / Usage with gh CLI / Section Guidelines). The sole non-structural prose is the 5-line preamble ("Copy and customize this template when creating a PR after all implementation plan phases are complete.") and the brief `Important:` reminder about `Closes #N`. Every other line is either a structural header, a fenced code-block body used as the literal substitution source, a `gh CLI` command example, or author-facing section guidelines. No repetitive narration, no "This template describes..." intro. The body fenced blocks (Template and Filled Example) are load-bearing because `create-pr.sh` substitutes into the PR body template (`scripts/assets/pr-body.tmpl`) whose shape this file documents — compressing structural sections here risks drift between documentation and the actual PR body downstream consumers read. No changes applied; recorded as already-minimal per FR-4 and Edge Case 4.
- FR-5 scope: SKILL.md only (both references and the asset file unchanged). `implementing-plan-phases` is a forked skill (feature chain steps 6…5+N, one fork per phase) with the **standard** `done | artifact=<path> | <note>` return shape — no reviewing-requirements-style findings-display carve-out. The carve-out list is the canonical seven bullets with the findings-display bullet retained as N/A per NFR-4. Wording matches Phase 7 (forked-skill variant) exactly except for the chain-context preamble ("feature chain steps 6…5+N, one invocation per `### Phase N` block" vs Phase 7's "feature chain step 3"), the per-skill error-message examples (`resolve-requirement-doc.sh` / `build-branch-name.sh` / `ensure-branch.sh` / `check-acceptance.sh` / `create-pr.sh` failures, plus `npm test` / `npm run build` failing output) and interactive-prompt examples (plan-file disambiguation, phase-selection when phase number exceeds plan's phase count, summary re-prompt on empty slug) per NFR-4 consistency.
- Additional Phase 10 deviation: the fork-return-contract subsection includes two extra paragraphs not present in Phase 7. (1) An artifact-path guidance clause, since a phase typically produces commits across multiple files — the contract states `artifact=` points to the most-representative single path (main source/skill file when focused, or the implementation plan document when deliverables span many files). Example line embedded. (2) An **Orchestrator-side contract** clause documenting that `orchestrating-workflows` appends the literal instruction "Do NOT create a pull request at the end -- the orchestrator handles PR creation separately. Skip Step 10 (Create Pull Request) entirely." to the fork prompt. The subagent MUST honor that carve-out while the SKILL.md itself still documents Step 10 in full for standalone (non-orchestrated) invocations. Both additions are load-bearing for correct orchestrator-vs-standalone behavior and could not be omitted without ambiguity.

| File | Lines | Words | Chars |
|---|---:|---:|---:|
| `plugins/lwndev-sdlc/skills/implementing-plan-phases/SKILL.md` (baseline) | 142 | 974 | 7118 |
| `plugins/lwndev-sdlc/skills/implementing-plan-phases/SKILL.md` (post-change) | 178 | 1585 | 11381 |
| **Δ** | +36 | +611 | +4263 |
| `plugins/lwndev-sdlc/skills/implementing-plan-phases/references/step-details.md` (baseline) | 399 | 1488 | 11039 |
| `plugins/lwndev-sdlc/skills/implementing-plan-phases/references/step-details.md` (post-change) | 399 | 1488 | 11039 |
| **Δ** | 0 | 0 | 0 |
| `plugins/lwndev-sdlc/skills/implementing-plan-phases/references/workflow-example.md` (baseline) | 327 | 977 | 8670 |
| `plugins/lwndev-sdlc/skills/implementing-plan-phases/references/workflow-example.md` (post-change) | 327 | 977 | 8670 |
| **Δ** | 0 | 0 | 0 |
| `plugins/lwndev-sdlc/skills/implementing-plan-phases/assets/pr-template.md` (baseline) | 163 | 616 | 4088 |
| `plugins/lwndev-sdlc/skills/implementing-plan-phases/assets/pr-template.md` (post-change) | 163 | 616 | 4088 |
| **Δ** | 0 | 0 | 0 |

### Phase 11 — executing-chores

- FR-3 no-op for `references/workflow-details.md`: the file is per-phase guidance for the chore execution workflow (initialization / execution / completion, plus error-recovery and common-git-commands appendices). It documents branch creation, acceptance-criterion check-off, commit formatting (`chore(category): description`), test/build verification, and PR creation. It does NOT describe spawning subagents via the Agent tool — `executing-chores` is itself forked by `orchestrating-workflows` (chore chain step 4) but does not fork further work of its own. A `grep -in "agent\|fork\|subagent\|spawn"` on the file returned no matches. No fork-invocation specs exist to annotate, so no pointer was added.
- FR-4 decision for `assets/pr-template.md`: already-minimal. The template is the PR-body shape consumed by `scripts/create-pr.sh` (Template / Filled Example / Usage with gh CLI / Section Guidelines). The sole non-structural prose is the 2-line preamble ("Copy and customize this template when creating a chore PR.") and the brief `Important:` reminder about `Closes #N`. Every other line is either a structural header, a fenced code-block body used as the literal substitution source, a `gh CLI` command example, or author-facing section guidelines (Chore Link / Summary / Changes / Testing / Related). No repetitive narration, no "This template describes..." intro. The body fenced blocks (Template and Filled Example) are load-bearing because `create-pr.sh` substitutes into the PR body template (`scripts/assets/pr-body.tmpl`) whose shape this file documents — compressing structural sections here risks drift between documentation and the actual PR body downstream consumers read. No changes applied; recorded as already-minimal per FR-4 and Edge Case 4. Consistent with Phase 10's FR-4 decision for the sibling `implementing-plan-phases/assets/pr-template.md`.
- FR-5 scope: SKILL.md only (references and assets file unchanged). `executing-chores` is a forked skill (chore chain step 4, one fork per chore) with the **standard** `done | artifact=<path> | <note>` return shape — no reviewing-requirements-style findings-display carve-out. The carve-out list is the canonical seven bullets with the findings-display bullet retained as N/A per NFR-4. Wording matches Phase 10 (forked-skill variant) exactly except for the chain-context preamble ("chore chain step 4" vs Phase 10's "feature chain steps 6…5+N, one invocation per `### Phase N` block"), the per-skill error-message examples (`resolve-requirement-doc.sh` / `build-branch-name.sh` / `ensure-branch.sh` / `check-acceptance.sh` / `commit-work.sh` / `create-pr.sh` failures; `npm test` / `npm run build` / `npm run lint` failing output), and interactive-prompt examples (chore-file disambiguation, description re-prompt on empty slug, chore selection when no argument supplied) per NFR-4 consistency.
- Phase 11 deviation from Phase 10: the fork-return-contract subsection includes an artifact-path guidance clause (since a chore spans source edits + chore-document checkmark edits and finishes with a PR, `artifact=` points to the PR URL or feature branch name when PR creation succeeds, or the chore document path when no PR-identifying artifact is available) **but does NOT include the orchestrator-side skip-PR clause** that appears in Phase 10. This is intentional: unlike `implementing-plan-phases`, `executing-chores` is NOT asked to skip PR creation when orchestrated — the chore chain has no separate PR-creation fork, so this skill's Step 8 (Create Pull Request) runs in both orchestrated and standalone invocations. An explicit paragraph documents this divergence ("PR creation is this skill's responsibility") so future maintainers do not accidentally port the Phase 10 skip-PR clause here by pattern-matching. The orchestrator extracts the PR number from this subagent's output or falls back to `gh pr list --head <branch>` for downstream chain steps.

| File | Lines | Words | Chars |
|---|---:|---:|---:|
| `plugins/lwndev-sdlc/skills/executing-chores/SKILL.md` (baseline) | 143 | 935 | 7104 |
| `plugins/lwndev-sdlc/skills/executing-chores/SKILL.md` (post-change) | 179 | 1527 | 11225 |
| **Δ** | +36 | +592 | +4121 |
| `plugins/lwndev-sdlc/skills/executing-chores/references/workflow-details.md` (baseline) | 277 | 940 | 6249 |
| `plugins/lwndev-sdlc/skills/executing-chores/references/workflow-details.md` (post-change) | 277 | 940 | 6249 |
| **Δ** | 0 | 0 | 0 |
| `plugins/lwndev-sdlc/skills/executing-chores/assets/pr-template.md` (baseline) | 118 | 420 | 2726 |
| `plugins/lwndev-sdlc/skills/executing-chores/assets/pr-template.md` (post-change) | 118 | 420 | 2726 |
| **Δ** | 0 | 0 | 0 |

### Phase 12 — executing-bug-fixes

- FR-3 no-op for `references/workflow-details.md`: the file is per-phase guidance for the bug-fix execution workflow (initialization / execution / completion, plus error-recovery and common-git-commands appendices). It documents root-cause redeclaration, per-RC fix-and-verify cycles, reproduction-step verification, commit formatting (`fix(category): description`), test/build verification, and PR creation. It does NOT describe spawning subagents via the Agent tool — `executing-bug-fixes` is itself forked by `orchestrating-workflows` (bug chain step 4) but does not fork further work of its own. A `grep -in "agent\|fork\|subagent\|spawn"` on the file returned no matches. No fork-invocation specs exist to annotate, so no pointer was added.
- FR-4 decision for `assets/pr-template.md`: already-minimal. The template is the PR-body shape consumed by `scripts/create-pr.sh` (Template / Filled Example / Usage with gh CLI / Section Guidelines). The sole non-structural prose is the 2-line preamble ("Copy and customize this template when creating a bug fix PR.") and the brief `Important:` reminder about `Closes #N`. Every other line is either a structural header, a fenced code-block body used as the literal substitution source, a `gh CLI` command example, or author-facing section guidelines (Bug Link / Summary / Root Cause(s) / How Each Root Cause Was Addressed / Changes / Testing / Related). The Template, Filled Example, and `gh CLI` usage blocks are load-bearing because `create-pr.sh` substitutes into the PR body template (`scripts/assets/pr-body.tmpl`) whose shape this file documents; the bug-specific root-cause traceability table and per-RC testing checklist items are structural load-bearing content that ties PR back to RC-N acceptance criteria and must not be compressed. No changes applied; recorded as already-minimal per FR-4 and Edge Case 4. Consistent with Phase 10 and Phase 11 FR-4 decisions for sibling `pr-template.md` files.
- FR-5 scope: SKILL.md only (references and assets file unchanged). `executing-bug-fixes` is a forked skill (bug chain step 4, one fork per bug) with the **standard** `done | artifact=<path> | <note>` return shape — no reviewing-requirements-style findings-display carve-out. The carve-out list is the canonical seven bullets with the findings-display bullet retained as N/A per NFR-4. Wording matches Phase 11 (forked-skill variant) exactly except for the chain-context preamble ("bug chain step 4" vs "chore chain step 4"), the per-skill error-message examples (same script set: `resolve-requirement-doc.sh` / `build-branch-name.sh` / `ensure-branch.sh` / `check-acceptance.sh` / `commit-work.sh` / `create-pr.sh` failures; `npm test` / `npm run build` / `npm run lint` failing output), and interactive-prompt examples (bug-file disambiguation, description re-prompt on empty slug, bug selection when no argument supplied) per NFR-4 consistency.
- Phase 12 deviation from Phase 11: same shape as Phase 11 (artifact-path guidance clause included, no orchestrator-side skip-PR clause). The explicit "PR creation is this skill's responsibility" paragraph documents this divergence from Phase 10's `implementing-plan-phases` skip-PR clause so future maintainers do not accidentally port Phase 10 wording here. Step reference points to Step 10 (Create Pull Request) — the bug-fix workflow has additional steps (root-cause redeclaration, per-RC fix, reproduction-step verification) compared to the chore workflow (Step 8), so the step number differs from Phase 11 while the orchestrator's PR-number extraction behavior is identical.

| File | Lines | Words | Chars |
|---|---:|---:|---:|
| `plugins/lwndev-sdlc/skills/executing-bug-fixes/SKILL.md` (baseline) | 176 | 1260 | 8958 |
| `plugins/lwndev-sdlc/skills/executing-bug-fixes/SKILL.md` (post-change) | 212 | 1854 | 13054 |
| **Δ** | +36 | +594 | +4096 |
| `plugins/lwndev-sdlc/skills/executing-bug-fixes/references/workflow-details.md` (baseline) | 338 | 1365 | 8649 |
| `plugins/lwndev-sdlc/skills/executing-bug-fixes/references/workflow-details.md` (post-change) | 338 | 1365 | 8649 |
| **Δ** | 0 | 0 | 0 |
| `plugins/lwndev-sdlc/skills/executing-bug-fixes/assets/pr-template.md` (baseline) | 180 | 878 | 5825 |
| `plugins/lwndev-sdlc/skills/executing-bug-fixes/assets/pr-template.md` (post-change) | 180 | 878 | 5825 |
| **Δ** | 0 | 0 | 0 |

### Grand Total

Aggregates all twelve rolled-out skills. Per-skill SKILL.md post-change measurements were re-taken fresh for this phase to catch any drift (e.g., Phase 1's `finalizing-workflow.test.ts` ceiling relaxation, Phase 3+ prose-compression decisions) — zero drift was observed against the per-phase Notes tables. References and assets have not been modified in any phase (Δ 0/0/0 for every touched file per Phases 2–12), so the fresh re-measurement yields the same totals as the baselines.

**Baseline totals** (sum across all twelve skills' `SKILL.md` + touched references + touched assets):

| File set | Lines | Words | Chars |
|---|---:|---:|---:|
| SKILL.md (12 skills) | 2172 | 16027 | 114380 |
| References (touched only, 12 files) | 4326 | 16608 | 122755 |
| Assets (touched only, 12 files) | 1322 | 5481 | 36675 |
| **Grand total** | **7820** | **38116** | **273810** |

**Post-change totals** (fresh `wc -l -w -c` on 2026-04-21):

| File set | Lines | Words | Chars |
|---|---:|---:|---:|
| SKILL.md (12 skills) | 2577 | 22095 | 155839 |
| References (touched only, 12 files) | 4326 | 16608 | 122755 |
| Assets (touched only, 12 files) | 1322 | 5481 | 36675 |
| **Grand total** | **8225** | **44184** | **315269** |

**Delta** (post − baseline; negative = reduction, positive = growth):

| File set | Lines Δ | Lines % | Words Δ | Words % | Chars Δ | Chars % |
|---|---:|---:|---:|---:|---:|---:|
| SKILL.md (12 skills) | +405 | +18.65% | +6068 | +37.86% | +41459 | +36.25% |
| References (touched only, 12 files) | 0 | 0.00% | 0 | 0.00% | 0 | 0.00% |
| Assets (touched only, 12 files) | 0 | 0.00% | 0 | 0.00% | 0 | 0.00% |
| **Grand total** | **+405** | **+5.18%** | **+6068** | **+15.92%** | **+41459** | **+15.14%** |

#### Interpretation

The static-file delta is net-positive by design: the instruction surface grew by ~41.5 KB of characters (~15% across the twelve-skill surface) because each skill's `## Output Style` section installs the lite-narration rules, load-bearing carve-outs, and a role-appropriate return-contract subsection. This matches the pilot's (CHORE-034) direction — the rollout trades a fixed one-time SKILL.md cost against a per-invocation runtime payoff.

The runtime payoff is paid back on every invocation, not on install:

- **Every fork response** (forked skills: `reviewing-requirements`, `creating-implementation-plans`, `implementing-plan-phases`, `executing-chores`, `executing-bug-fixes`, `finalizing-workflow`) loses preamble/postamble narration and collapses to the canonical `done | artifact=... | <note>` / `failed | <reason>` / `Found **N errors**, **N warnings**, **N info**` final-line shapes.
- **Every main-context skill session** (`documenting-features`, `documenting-chores`, `documenting-bugs`, `documenting-qa`, `executing-qa`) loses end-of-turn recaps beyond one sentence.
- **Every `reviewing-requirements` response** uses the structured findings-display shape followed by its summary line, instead of freeform narration.
- **Every `managing-work-items` inline invocation** loses narration while preserving its WARNING-level mechanism-failure carve-outs.

Per-phase decisions that shaped the total:

- **Phase 1 (`finalizing-workflow`)** — SKILL.md-only scope (no `references/`, no `assets/`); the FEAT-022 `scripts/__tests__/finalizing-workflow.test.ts` "should be under 80 lines" assertion was relaxed to a 120-line ceiling per NFR-3 to accommodate the rollout-wide `## Output Style` section. The updated test currently passes at 104 lines.
- **Phase 2 (`managing-work-items`)** — inline-execution variant: the return-contract subsection was replaced with an "Inline execution note" because the skill is invoked directly from main context (not as a forked step). WARNING-level mechanism-failure lines are explicitly load-bearing.
- **Phases 3, 4, 5 (`documenting-features`/`-chores`/`-bugs`)** — main-context variant; three identical per-skill sections differing only in the chain-step preamble ("feature/chore/bug chain step 1"). All three `assets/` templates (`feature-requirements.md`, `chore-document.md`, `bug-document.md`) were flagged already-minimal per FR-4 + Edge Case 4: pure structural skeletons with bracketed/HTML-commented author guidance that is load-bearing. Reference files are example requirement docs / category tables — not fork-invocation specs — so FR-3 no-op.
- **Phase 6 (`reviewing-requirements`)** — the exception variant: emits `Found **N errors**, **N warnings**, **N info**` as the final line (not `done | ...`), preceded by the full findings block. The findings-display carve-out is explicitly load-bearing for this skill. `assets/review-findings-template.md` is the structural schema the orchestrator's Decision Flow parses; flagged already-minimal.
- **Phase 7 (`creating-implementation-plans`)** — forked-skill standard variant (first one in the feature chain). `references/implementation-plan-example.md` and `assets/implementation-plan.md` are both example/template skeletons — FR-3/FR-4 no-op.
- **Phases 8, 9 (`documenting-qa`, `executing-qa`)** — main-context variant with an additional sentence documenting that structural conformance of the emitted artifact is enforced by the Stop hook (`scripts/stop-hook.sh`), not by the return contract. Both skills have no `references/` directory (Edge Case 1 exempt). Both v2 and v1 templates for each skill were flagged already-minimal — the v2 templates are parser-load-bearing (Stop-hook greps for exact keys/headers), and the v1 templates are legacy-preserved to keep pre-FEAT-018 artifacts parseable.
- **Phase 10 (`implementing-plan-phases`)** — forked-skill variant with two extra paragraphs in the return-contract subsection: (1) artifact-path guidance (point `artifact=` at the most-representative file when phase deliverables span many), and (2) an **Orchestrator-side contract** clause documenting that `orchestrating-workflows` appends "Do NOT create a pull request..." to the fork prompt, so Step 10 is skipped under orchestration while retained in SKILL.md for standalone invocations. `assets/pr-template.md` flagged already-minimal (consumed by `scripts/create-pr.sh`; drift here risks PR-body divergence).
- **Phase 11 (`executing-chores`)** — forked-skill variant with the artifact-path guidance clause but **without** the orchestrator-side skip-PR clause (chore chain has no separate PR-creation fork; Step 8 runs in both orchestrated and standalone modes). An explicit "PR creation is this skill's responsibility" paragraph prevents future maintainers from accidentally porting Phase 10 wording here. `assets/pr-template.md` flagged already-minimal.
- **Phase 12 (`executing-bug-fixes`)** — forked-skill variant identical in shape to Phase 11 (artifact-path guidance included, no skip-PR clause), with per-skill error-message examples and interactive-prompt examples adjusted for the bug-fix workflow (root-cause redeclaration, per-RC fix-and-verify cycles, reproduction-step verification). Step number differs from Phase 11 (Step 10 vs Step 8) reflecting the longer bug-fix workflow. `assets/pr-template.md` flagged already-minimal — the bug-specific root-cause traceability table and per-RC testing checklist are load-bearing content tied to RC-N acceptance criteria.

Across the twelve phases: all reference files with a fork-invocation check returned zero matches for `agent|fork|subagent|spawn` — no FR-3 pointers needed (confirmed no-op). All ten `assets/` directories were reviewed and every template (twelve files) was flagged already-minimal per Edge Case 4 — no FR-4 compression was applied. The full payoff of this rollout is therefore in the SKILL.md lite-narration rules and the canonical return-contract shapes, not in template compression.

#### FR-3 no-op registry

All nine skills with a `references/` directory were checked; none contained fork-invocation specs requiring a pointer.

| Skill | Reference files checked | Outcome |
|---|---|---|
| `managing-work-items` | `github-templates.md`, `jira-templates.md` | No fork-invocation specs (API-interaction templates only); no pointer added |
| `documenting-features` | `feature-requirements-example-search-command.md`, `feature-requirements-example-episodes-command.md` | No fork-invocation specs (example requirement documents); no pointer added |
| `documenting-chores` | `categories.md` | No fork-invocation specs (category reference table); no pointer added |
| `documenting-bugs` | `categories.md` | No fork-invocation specs (category reference table); no pointer added |
| `reviewing-requirements` | `review-example.md` | No fork-invocation specs (annotated review output examples); no pointer added |
| `creating-implementation-plans` | `implementation-plan-example.md` | No fork-invocation specs (concrete example plan); no pointer added |
| `implementing-plan-phases` | `step-details.md`, `workflow-example.md` | No fork-invocation specs (per-step guidance; annotated workflow example); no pointer added |
| `executing-chores` | `workflow-details.md` | No fork-invocation specs (per-phase workflow guidance); no pointer added |
| `executing-bug-fixes` | `workflow-details.md` | No fork-invocation specs (per-phase workflow guidance); no pointer added |

Three skills are exempt from FR-3 per Edge Case 1 (no `references/` directory): `documenting-qa`, `executing-qa`, `finalizing-workflow`.

#### FR-4 outcomes registry

All ten skills with an `assets/` directory were reviewed. Every artifact template (twelve files across the ten skills) was flagged already-minimal per Edge Case 4; no compression was applied.

| Skill | Asset file(s) | Outcome |
|---|---|---|
| `documenting-features` | `feature-requirements.md` | already-minimal (structural skeleton with bracketed placeholders) |
| `documenting-chores` | `chore-document.md` | already-minimal (structural skeleton; HTML-comment author guidance is load-bearing) |
| `documenting-bugs` | `bug-document.md` | already-minimal (structural skeleton; RC-N traceability author guidance is load-bearing) |
| `reviewing-requirements` | `review-findings-template.md` | already-minimal (structural schema parsed by orchestrator Decision Flow) |
| `creating-implementation-plans` | `implementation-plan.md` | already-minimal (structural skeleton; placeholders + one-line hints) |
| `documenting-qa` | `test-plan-template-v2.md`, `test-plan-template.md` | v2 already-minimal (Stop-hook-parsed schema); v1 legacy-preserved |
| `executing-qa` | `test-results-template-v2.md`, `test-results-template.md` | v2 already-minimal (Stop-hook-parsed schema); v1 legacy-preserved (NFR-3: 34 legacy artifacts) |
| `implementing-plan-phases` | `pr-template.md` | already-minimal (consumed by `scripts/create-pr.sh`) |
| `executing-chores` | `pr-template.md` | already-minimal (consumed by `scripts/create-pr.sh`) |
| `executing-bug-fixes` | `pr-template.md` | already-minimal (RC-traceability and per-RC checklist are load-bearing) |

Two skills are N/A for FR-4 (no `assets/` directory): `managing-work-items`, `finalizing-workflow`.

#### Main-context vs forked deviation record

| Skill | Return-contract variant | Justification |
|---|---|---|
| `finalizing-workflow` | Forked standard (`done \| ... \| ...` / `failed \| ...`) | Feature/chore/bug chain final step; forked by `orchestrating-workflows` |
| `managing-work-items` | Inline execution note | Cross-cutting inline skill invoked from orchestrator's main context, not as an Agent fork |
| `documenting-features` | Main-context | Feature chain step 1; returns to user |
| `documenting-chores` | Main-context | Chore chain step 1; returns to user |
| `documenting-bugs` | Main-context | Bug chain step 1; returns to user |
| `reviewing-requirements` | **Exception** (`Found **N errors**, **N warnings**, **N info**` final line) | Forked skill but emits findings-display block + structured summary line rather than `done \| ...` shape (preserved from CHORE-034 pilot) |
| `creating-implementation-plans` | Forked standard | Feature chain step 3 |
| `documenting-qa` | Main-context + Stop-hook note | Feature chain step 5 / chore/bug chain step 3; returns to user; artifact shape enforced by `scripts/stop-hook.sh` |
| `executing-qa` | Main-context + Stop-hook note | Feature chain step 5+N+3 / chore/bug chain step 6; returns to user; artifact shape enforced by `scripts/stop-hook.sh` (per-verdict rules) |
| `implementing-plan-phases` | Forked standard + artifact-path + orchestrator skip-PR clause | Feature chain steps 6…5+N; orchestrator appends skip-PR instruction to fork prompt |
| `executing-chores` | Forked standard + artifact-path (no skip-PR) | Chore chain step 4; PR creation is this skill's responsibility |
| `executing-bug-fixes` | Forked standard + artifact-path (no skip-PR) | Bug chain step 4; PR creation is this skill's responsibility |

Variant distribution: 5 main-context (incl. 2 with Stop-hook note), 1 inline-execution, 1 exception (`reviewing-requirements`), 5 forked-standard (3 with per-skill additional clauses).

#### Test-update callout (NFR-3)

One test was updated during the rollout to match canonical narration:

- `scripts/__tests__/finalizing-workflow.test.ts` — the "should be under 80 lines after the collapse" assertion (originally set by FEAT-022 after the skill was collapsed to ~72 lines) was relaxed to a 120-line ceiling in Phase 1 to accommodate the rollout-wide `## Output Style` section. Final post-change line count: 104. No other tests required narration-content updates.

#### Manual spot-check

Spot-checked in Phase 13 by re-reading the three representative SKILL.md files end-to-end:

- `plugins/lwndev-sdlc/skills/executing-chores/SKILL.md` (forked skill) — `## Output Style` section reads cleanly, three subsections in correct order, forked-standard variant with artifact-path clause and "PR creation is this skill's responsibility" paragraph present.
- `plugins/lwndev-sdlc/skills/documenting-qa/SKILL.md` (main-context skill) — `## Output Style` section reads cleanly, main-context variant present with the Stop-hook structural-conformance sentence.
- `plugins/lwndev-sdlc/skills/managing-work-items/SKILL.md` (cross-cutting inline skill) — `## Output Style` section reads cleanly, inline-execution note replaces the fork-return subsection; WARNING-level mechanism-failure carve-out retained.

#### Verification summary

- `npm run validate`: PASS (13/13 plugins) on 2026-04-21.
- `npm test`: PASS (1130/1130 tests) on 2026-04-21.

## Completion

**Status:** `Complete`

**Completed:** 2026-04-22

**Pull Request:** [#210](https://github.com/lwndev/lwndev-marketplace/pull/210)
