---
name: creating-implementation-plans
description: Creates structured implementation plans from feature requirements. Use when planning new features, multi-phase projects, or when the user asks for an implementation plan, build plan, or development roadmap.
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
argument-hint: <requirements-file>
---

# Creating Implementation Plans

Transform feature requirements into actionable implementation plans with clear phases, deliverables, and success criteria.

## When to Use This Skill

- User requests an implementation plan, build plan, or roadmap
- Planning a new feature with multiple components
- Organizing work into logical phases
- Need to identify dependencies between features

## Flexibility

Adapt based on project type:

- **Single feature**: Simplified structure, may skip phases
- **Multi-feature project**: Full phase breakdown with dependencies
- **Refactoring**: Focus on risk assessment and rollback strategy
- **Prototypes**: Lighter on testing, heavier on deliverables

## Arguments

- **When argument is provided**: Match the argument against files in `requirements/features/` by ID prefix (e.g., `FEAT-003` matches `FEAT-003-skill-allowed-tools.md`). If no match is found, inform the user and fall back to interactive selection. If multiple matches are found, present the options and ask the user to choose.
- **When no argument is provided**: Scan `requirements/features/` for requirement documents and prompt the user to select one, or ask for paths.

## Quick Start

1. **Locate feature requirements documents** — when the user provides a `FEAT-NNN` ID, resolve it to a file path with:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-requirement-doc.sh" "<FEAT-NNN>"
   ```

   Exit codes: `0` (one match, path on stdout); `1` (no match — ask the user for a path); `2` (ambiguous — present candidates); `3` (malformed/missing ID). Otherwise check `requirements/features/` or ask the user for paths directly.
2. **Ask for GitHub issue URL(s)** if not provided in context
3. Identify dependencies between features
4. Determine optimal build sequence
5. Create the implementation plan using the template

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

- **Error messages from `fail` calls** -- users need the reason the skill halted. Surface script and tool stderr verbatim (e.g., `resolve-requirement-doc.sh` failures).
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

- `requirements/implementation/` - Implementation plan documents

### Filename Convention

Use the primary Feature ID as the filename prefix:
- Single feature: `FEAT-XXX-feature-name.md` (e.g., `FEAT-001-user-authentication.md`)
- Multiple features: `FEAT-XXX-project-name.md` using the first/primary feature ID (e.g., `FEAT-001-podcast-cli-features.md`)

## Template

See [assets/implementation-plan.md](assets/implementation-plan.md) for the full template.

### Structure Overview

```
# Implementation Plan: [Project Name]
- Overview
- Features Summary (table: ID, Name, Priority, Complexity, Status)
- Recommended Build Sequence
  - Phase N: Rationale, Implementation Steps, Deliverables
- Shared Infrastructure
- Testing Strategy
- Dependencies and Prerequisites
- Risk Assessment (table: Risk, Impact, Probability, Mitigation)
- Success Criteria
- Code Organization
```

### Sequencing Principles

Order features by: **foundation patterns** → **dependencies** → **complexity progression** → **value delivery**

Each phase needs a rationale explaining why it comes at this point and what patterns it introduces.

### Implementation Steps

- Start with CLI/API/interface additions
- Include validation and error handling
- End with tests and documentation
- Be specific enough to execute without ambiguity

## Verification Checklist

Before finalizing:

- [ ] All features from requirements included
- [ ] Build sequence accounts for dependencies
- [ ] Each phase has clear rationale and deliverables
- [ ] Risks identified with mitigations
- [ ] Success criteria are measurable

## Reference

See [implementation-plan-example.md](references/implementation-plan-example.md) for a complete example covering 5 CLI features with full phase breakdowns.
