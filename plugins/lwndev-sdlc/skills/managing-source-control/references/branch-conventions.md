# Branch Conventions

Canonical branch naming used by every SDLC workflow chain. Branches are produced by `${CLAUDE_PLUGIN_ROOT}/skills/managing-source-control/scripts/build-branch-name.sh` (Phase 2) and checked out idempotently by `ensure-branch.sh`.

## Branch Prefix Table

| Prefix | Work Type | Source Workflow | Example |
|--------|-----------|-----------------|---------|
| `feat/` | Feature implementation | `documenting-features` → `implementing-plan-phases` | `feat/FEAT-033-managing-source-control` |
| `chore/` | Maintenance, refactor, dep update, minor fix | `documenting-chores` → `executing-chores` | `chore/CHORE-040-bump-vitest` |
| `fix/` | Bug fix | `documenting-bugs` → `executing-bug-fixes` | `fix/BUG-018-flaky-bats` |

## Naming Format

```
<prefix>/<WORK-ID>-<slug>
```

| Component | Rule |
|-----------|------|
| `<prefix>` | One of `feat`, `chore`, `fix` -- selected by work-type, never user-chosen. |
| `<WORK-ID>` | The full upper-case ID: `FEAT-NNN`, `CHORE-NNN`, or `BUG-NNN`. The `BUG-` prefix maps to a `fix/` branch (conventional commits use `fix(BUG-NNN)`). |
| `<slug>` | 2-3 word kebab-case summary of the work. Built via `slugify.sh`: lowercase, ASCII letters + digits + hyphens, max ~50 chars. No leading/trailing hyphens. |

### Slug Rules

- Lowercase only.
- Hyphens separate words; no underscores, no spaces, no camelCase.
- Drop articles (`a`, `the`) and filler words when they push the slug over ~50 chars.
- Numbers are allowed (e.g. `feat/FEAT-033-bump-node-22`).
- If `build-branch-name.sh` produces an empty slug (the summary parsed down to nothing), it exits `1`; the caller re-prompts the user for a more descriptive summary.

## Backend-Agnostic

Branch naming is identical on GitHub and Azure DevOps. The only backend-specific concern is the push target (`origin` URL), which `ensure-branch.sh` does not need to know.

## Idempotency

`ensure-branch.sh` is idempotent:

- Branch does not exist → create it from the current `HEAD` (typically the default branch).
- Branch exists locally → check it out.
- Branch exists locally and is already current → no-op (`on <branch>`).
- Working tree is dirty → exit `3` with `[warn]` describing the dirty paths; the caller must stash or commit first and retry.

## Examples

```
feat/FEAT-001-scaffold-skill-command
feat/FEAT-007-chore-task-skill
chore/CHORE-038-parallel-bats-runner
fix/BUG-016-qa-glob-anchor
```

## See Also

- `${CLAUDE_PLUGIN_ROOT}/skills/managing-source-control/scripts/build-branch-name.sh` -- canonical assembler.
- `${CLAUDE_PLUGIN_ROOT}/skills/managing-source-control/scripts/ensure-branch.sh` -- idempotent create/checkout.
- [commit-conventions.md](commit-conventions.md) -- the conventional-commit format that pairs with each branch prefix.
