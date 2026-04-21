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

Create lightweight chore task documents that capture maintenance work, dependency updates, refactoring, and minor fixes without the overhead of full feature requirements.

## When to Use This Skill

- Documenting dependency updates or version bumps
- Recording planned refactoring work
- Tracking documentation fixes or README updates
- Capturing configuration changes
- Cleaning up dead code or unused files
- Any maintenance task that doesn't warrant full feature requirements

## Arguments

- **When argument is provided**: Use the argument as a pre-filled chore title for the document being created.
- **When no argument is provided**: Prompt the user interactively for the chore details.

## Quick Start

1. Check for existing chores in `requirements/chores/` to determine the next Chore ID
2. **Ask for GitHub issue URL** if not provided (optional but recommended for traceability)
3. Identify the chore category (see [references/categories.md](references/categories.md))
4. Create chore document using the template
5. Save to `requirements/chores/CHORE-XXX-description.md`

## File Location

All chore documents go in: `requirements/chores/`

Naming format: `CHORE-XXX-{2-4-word-description}.md`

Derive the description slug from the chore title by running:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/slugify.sh" "<chore title>"
```

The script lowercases, strips punctuation, drops stopwords (`a`, `an`, `the`, `of`, `for`, `to`, `and`, `or`), and keeps the first four remaining tokens joined with `-`. Exit codes: `0` on success; `1` when the slug is empty after normalization (prompt the user for a more descriptive title); `2` on missing arg.

Examples:
- `CHORE-001-update-dependencies.md`
- `CHORE-002-fix-readme-typos.md`
- `CHORE-003-cleanup-unused-imports.md`

## Chore ID Assignment

Allocate the next Chore ID by running:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/next-id.sh" CHORE
```

The script scans `requirements/chores/` for existing `CHORE-NNN-*.md` files, returns `max(NNN) + 1` zero-padded to three digits, and prints `001` when no chores exist. Exit codes: `0` on success; `2` on missing/invalid type arg.

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

Five supported categories with specific guidance:

| Category | Use For |
|----------|---------|
| `dependencies` | Package updates, version bumps, security patches |
| `documentation` | README updates, comment fixes, doc corrections |
| `refactoring` | Code cleanup, restructuring, naming improvements |
| `configuration` | Config file updates, tooling changes, CI/CD modifications |
| `cleanup` | Removing dead code, unused files, deprecated features |

See [references/categories.md](references/categories.md) for detailed guidance on each category.

## Verification Checklist

Before finalizing, verify:

- [ ] Chore ID is unique (not already used)
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

After documenting a chore, run `/reviewing-requirements` to verify the document against the codebase and docs, then `/documenting-qa` to create a test plan. Optionally run `/reviewing-requirements` again for test-plan reconciliation. Then use `/executing-chores` to implement it. After PR review, optionally run `/reviewing-requirements` for code-review reconciliation, then `/executing-qa` to verify, and `/finalizing-workflow` to merge.
