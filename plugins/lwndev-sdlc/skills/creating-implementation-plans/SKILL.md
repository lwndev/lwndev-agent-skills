---
name: creating-implementation-plans
description: Creates structured implementation plans from feature requirements. Use when planning new features, multi-phase projects, or when the user asks for an implementation plan, build plan, or development roadmap.
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
argument-hint: <requirements-file>
---

# Creating Implementation Plans

Transform feature requirements into actionable implementation plans with clear phases, deliverables, and success criteria.

## When to Use This Skill

- User requests an implementation plan, build plan, or roadmap.
- Planning a feature with multiple components.
- Organizing work into logical phases.
- Identifying dependencies between features.

## Flexibility

Adapt to project type:

- Single feature: simplified structure, may skip phases.
- Multi-feature project: full phase breakdown with dependencies.
- Refactoring: focus on risk assessment and rollback strategy.
- Prototypes: lighter testing, heavier deliverables.

## Arguments

- **When argument is provided**: Match against files in `requirements/features/` by ID prefix (e.g., `FEAT-003` matches `FEAT-003-skill-allowed-tools.md`). On no match, inform the user and fall back to interactive selection. On multiple matches, present options and ask the user to choose.
- **When no argument is provided**: Scan `requirements/features/` and prompt the user to select one, or ask for paths.

## Quick Start

`$SCRIPTS/` = `${CLAUDE_PLUGIN_ROOT}/skills/creating-implementation-plans/scripts/`. See [README.md](README.md) for the FR-1 through FR-5 script table.

1. Resolve `FEAT-NNN` -> path: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-requirement-doc.sh" "<FEAT-NNN>"`.
2. Ask for GitHub issue URL(s) if not in context.
3. Render scaffold (FR-1): `bash "$SCRIPTS/render-plan-scaffold.sh" "<FEAT-IDs>" [--enforce-phase-budget]`. Author per-phase content into the rendered file.
4. Validate DAG (FR-2): `bash "$SCRIPTS/validate-plan-dag.sh" "<plan-file>"`.
5. Validate phase sizes (FR-5): `bash "$SCRIPTS/validate-phase-sizes.sh" "<plan-file>"`.

## Output Style

Follow the lite-narration rules below. Load-bearing carve-outs MUST be emitted as specified; they are not narration. This skill is forked by `orchestrating-workflows` (feature chain step 3), so its output flows to a parent orchestrator rather than directly to the user.

### Lite narration rules

- No preamble before tool calls. Do not announce "let me check" or "I'll run" -- issue the tool call.
- No end-of-turn summaries beyond one short sentence. Do not recap what the user can read from tool output (e.g., the written implementation plan).
- No emoji. ASCII punctuation only.
- No restating what the user just said.
- No status echoes that tools already show (e.g., successful `Write` confirmations).
- Prefer ASCII arrows (`->`) and punctuation over Unicode alternatives in skill-authored prose. Existing Unicode em dashes in tables and reference docs are retained.
- Short sentences over paragraphs. Bullet lists over prose when listing more than two items.

### Load-bearing carve-outs (never strip)

The following MUST always be emitted even when they resemble narration:

- **Error messages from `fail` calls** -- users need the reason the skill halted. Surface script and tool stderr verbatim (e.g., `resolve-requirement-doc.sh`, `render-plan-scaffold.sh`, `validate-plan-dag.sh`, `validate-phase-sizes.sh` failures).
- **Security-sensitive warnings** -- destructive-operation confirmations, credential prompts.
- **Interactive prompts** -- any prompt that blocks the workflow and requires user input (e.g., the GitHub issue URL prompt, disambiguation when multiple requirement documents match the provided ID).
- **Findings display from `reviewing-requirements`** -- N/A for this skill (it does not consume reviewing-requirements findings); bullet retained for consistency with the canonical template.
- **FR-14 console echo lines** -- `[model] step {N} ({skill}) -> {tier} (...)` audit-trail lines emitted by `prepare-fork.sh`. The Unicode `->` is the documented emitter format; do not rewrite to ASCII.
- **Tagged structured logs** -- any line prefixed `[info]`, `[warn]`, or `[model]` is a structured log, not narration. Emit verbatim.
- **User-visible state transitions** -- pause, advance, and resume announcements (at most one line each).

### Fork-to-orchestrator return contract

This skill is forked by `orchestrating-workflows` as feature chain step 3. Emit `done | artifact=requirements/implementation/<ID>-*.md | <note-of-at-most-10-words>` as the **final line** on success, and `failed | <one-sentence reason>` on failure. The `Found **N errors**, **N warnings**, **N info**` shape is reserved for `reviewing-requirements` only and MUST NOT be emitted here.

**Precedence**: the return contract takes precedence over the lite rules when the two conflict. The subagent MUST emit the contract shape as the final line of the response even if it reads like narration.

## File Locations

- `requirements/implementation/` - Implementation plan documents.

### Filename Convention

Use the primary Feature ID as the prefix:
- Single feature: `FEAT-XXX-feature-name.md` (e.g. `FEAT-001-user-authentication.md`).
- Multi-feature: `FEAT-XXX-project-name.md` using the first/primary feature ID (e.g. `FEAT-001-podcast-cli-features.md`).

## Template

See [assets/implementation-plan.md](assets/implementation-plan.md). FR-1 emits a scaffold matching this structure. Sequencing: foundation -> dependencies -> complexity progression -> value delivery. Each phase needs a rationale. Implementation steps: CLI/API additions -> validation/error handling -> tests/docs.

## Verification Checklist

Before finalizing:

- [ ] All requirement features included.
- [ ] `validate-plan-dag.sh` (FR-2) exits `0` — no cycles, all `Depends on Phase N` references resolve.
- [ ] `validate-phase-sizes.sh` (FR-5) exits `0` — no over-budget phase without `**ComplexityOverride:**` clamp.
- [ ] Each phase has clear rationale and deliverables.
- [ ] Risks identified with mitigations.
- [ ] Success criteria are measurable.

## Reference

See [implementation-plan-example.md](references/implementation-plan-example.md) for a complete example covering 5 CLI features.
