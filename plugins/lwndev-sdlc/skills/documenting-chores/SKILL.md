---
name: documenting-chores
description: Creates lightweight documentation for chore tasks and maintenance work. Use when the user needs to document a chore, maintenance task, dependency update, refactoring, or minor fix that doesn't require full feature requirements.
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
argument-hint: "[chore-title]"
---

# Documenting Chores

Create lightweight chore task documents for maintenance work, dependency updates, refactoring, and minor fixes without full feature requirements overhead.

## When to Use This Skill

- Dependency updates or version bumps
- Planned refactoring work
- Documentation fixes or README updates
- Configuration changes
- Dead code or unused file cleanup
- Any maintenance task that doesn't warrant full feature requirements

## Arguments

- **When argument is provided**: use it as a pre-filled chore title.
- **When no argument is provided**: prompt interactively for chore details.

## Quick Start

1. Check `requirements/chores/` for the next Chore ID
2. **Ask for GitHub issue URL** if not provided (optional, recommended for traceability)
3. Identify the chore category (see [references/categories.md](references/categories.md))
4. Create the chore document from the template
5. Save to `requirements/chores/CHORE-XXX-description.md`

## Output Style

Follow the lite-narration rules below. Load-bearing carve-outs MUST be emitted as specified; they are not narration. This skill runs in the orchestrator's main conversation (chore chain step 1), so its output flows directly to the user.

### Lite narration rules

- No preamble before tool calls. Do not announce "let me check" or "I'll run" -- issue the tool call.
- No end-of-turn summaries beyond one short sentence. Do not recap what the user can read from tool output (e.g., the written requirement document).
- No emoji. ASCII punctuation only.
- No restating what the user just said.
- No status echoes that tools already show (e.g., successful `Write` confirmations).
- Prefer ASCII arrows (`->`) and punctuation over Unicode alternatives in skill-authored prose. Existing Unicode em dashes in tables and reference docs are retained.
- Short sentences over paragraphs. Bullet lists over prose when listing more than two items.

### Load-bearing carve-outs (never strip)

The following MUST always be emitted even when they resemble narration:

- **Error messages from `fail` calls** -- users need the reason the skill halted. Surface script and tool stderr verbatim (e.g., `next-id.sh` / `slugify.sh` failures).
- **Security-sensitive warnings** -- destructive-operation confirmations, credential prompts.
- **Interactive prompts** -- any prompt that blocks the workflow and requires user input (e.g., the GitHub issue URL prompt, the chore details prompt when no argument is provided, a re-slug prompt when `slugify.sh` returns empty).
- **Findings display from `reviewing-requirements`** -- N/A for this skill (it does not consume reviewing-requirements findings); bullet retained for consistency with the canonical template.
- **FR-14 console echo lines** -- `[model] step {N} ({skill}) -> {tier} (...)` audit-trail lines emitted by `prepare-fork.sh`. The Unicode `->` is the documented emitter format; do not rewrite to ASCII. (Typically not emitted here since this skill runs in main context, not forked, but retained for cross-skill consistency.)
- **Tagged structured logs** -- any line prefixed `[info]`, `[warn]`, or `[model]` is a structured log, not narration. Emit verbatim.
- **User-visible state transitions** -- pause, advance, and resume announcements (at most one line each).

### Fork-to-orchestrator return contract

`documenting-chores` runs in **main context** (chore chain step 1), **not** as an Agent fork. It returns its result directly to the user, not to a parent orchestrator. The `done | artifact=<path> | <note>` / `failed | <reason>` shapes do **not** apply to this skill -- there is no subagent boundary. The lite narration rules and load-bearing carve-outs above still govern the skill's output.

**Precedence**: when a load-bearing carve-out (error message, `[warn]` structured log, interactive prompt, etc.) conflicts with a lite-narration rule, the carve-out wins and MUST be emitted verbatim even if it reads like narration.

## File Location

All chore documents live in `requirements/chores/`. Filename format: `CHORE-XXX-{2-4-word-description}.md`. Derive the slug:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/slugify.sh" "<chore title>"
```

Lowercases, strips punctuation, drops stopwords (`a`, `an`, `the`, `of`, `for`, `to`, `and`, `or`), keeps the first four remaining tokens joined with `-`. Exit codes: `0` success; `1` empty slug after normalization (prompt for a more descriptive title); `2` missing arg.

Examples:
- `CHORE-001-update-dependencies.md`
- `CHORE-002-fix-readme-typos.md`
- `CHORE-003-cleanup-unused-imports.md`

## Chore ID Assignment

Allocate the next Chore ID:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/next-id.sh" CHORE
```

Scans `requirements/chores/` for `CHORE-NNN-*.md`, returns `max(NNN) + 1` zero-padded to three digits, prints `001` when none exist. Exit codes: `0` success; `2` missing/invalid type arg.

## Template

See [assets/chore-document.md](assets/chore-document.md) for the full template.

### Structure Overview

```
# Chore: [Brief Title]
- Chore ID, GitHub Issue (optional), Category
- Description (1-2 sentences)
- Affected Files
- Acceptance Criteria
- Completion (status, date, PR link)
- Notes (optional)
```

## Categories

Five supported categories:

| Category | Use For |
|----------|---------|
| `dependencies` | Package updates, version bumps, security patches |
| `documentation` | README updates, comment fixes, doc corrections |
| `refactoring` | Code cleanup, restructuring, naming improvements |
| `configuration` | Config file updates, tooling changes, CI/CD modifications |
| `cleanup` | Removing dead code, unused files, deprecated features |

See [references/categories.md](references/categories.md) for per-category guidance.

## Verification Checklist

Before finalizing:

- [ ] Chore ID is unique
- [ ] Category matches the type of work
- [ ] Description clearly explains the work
- [ ] Affected files list is complete
- [ ] Acceptance criteria are testable
- [ ] GitHub issue is linked (if one exists)

## Relationship to Other Skills

| Task Type | Recommended Approach |
|-----------|---------------------|
| New feature with requirements | Use `documenting-features` skill |
| Chore/maintenance task | Use this skill (`documenting-chores`) |
| Quick fix (no tracking needed) | Direct implementation |

After documenting, run `/reviewing-requirements` to verify against codebase and docs, then `/documenting-qa` for the test plan. Optionally run `/reviewing-requirements` again for test-plan reconciliation. Then `/executing-chores` to implement. After PR review, optionally `/reviewing-requirements` for code-review reconciliation, then `/executing-qa` to verify, and `/finalizing-workflow` to merge.
