# Commit Conventions

Conventional commit format used by every commit produced by SDLC workflow chains. Commits are assembled by `${CLAUDE_PLUGIN_ROOT}/skills/managing-source-control/scripts/commit-work.sh` (Phase 2).

## Format

```
<type>(<scope>): <subject>

<body>

<footer>
```

| Component | Required | Rule |
|-----------|----------|------|
| `<type>` | Yes | One of `feat`, `chore`, `fix`. Selected by work-type, never user-chosen. |
| `<scope>` | Yes | The work-item ID: `FEAT-NNN`, `CHORE-NNN`, or `BUG-NNN`. |
| `<subject>` | Yes | Imperative, present tense (`add`, not `added` / `adds`). No trailing period. Aim for ≤72 chars; the full first line including `<type>(<scope>): ` should fit within `git log --oneline`. |
| `<body>` | Optional | Why, not what -- the diff already shows what. Wrap at ~72 chars. Multi-paragraph allowed. |
| `<footer>` | Optional | Free-form footers: `Refs:`, `Closes:`, `Co-Authored-By:`, etc. Auto-close tokens go in the PR body, not the commit footer. |

## Type → Branch Prefix Mapping

| `<type>` | Branch prefix | Work-item ID prefix |
|----------|--------------|---------------------|
| `feat` | `feat/` | `FEAT-` |
| `chore` | `chore/` | `CHORE-` |
| `fix` | `fix/` | `BUG-` |

The `commit-and-push-phase.sh` script in `implementing-plan-phases` maps `BUG-` → `fix`, `CHORE-` → `chore`, `FEAT-` → `feat` automatically.

## Examples

### Feature Commit

```
feat(FEAT-033): scaffold managing-source-control skill

Add SKILL.md, backend-detect.sh, and reference docs to establish
the skill directory layout (FR-10) before downstream phases land
the PR dispatchers.
```

### Chore Commit

```
chore(CHORE-038): parallelize bats runner

Run `bats --jobs 8` across files via GNU parallel to cut full-suite
runtime by ~60% on the CI runner.
```

### Bug Fix Commit

```
fix(BUG-016): anchor qa-* glob to canonical paths

Restrict the FR-9 safety-net check to tests/unit/qa-*.test.ts,
tests/unit/qa-*.test.js, and tests/bats/qa/qa-*.bats so permanent
infrastructure tests under tests/bats/skills/<skill>/ are not
falsely flagged.
```

### Phase Commit (canonical shape)

`commit-and-push-phase.sh` emits the canonical phase-commit subject:

```
<type>(<ID>): complete phase <N> - <phase-name>
```

Example:

```
feat(FEAT-033): complete phase 1 - Scaffold skill + backend-detect
```

## Staging Rules

- `commit-work.sh` does NOT stage — the caller stages explicit paths with `git add <path>...` before invoking the script, then `commit-work.sh` runs `git commit -m ...` on whatever is already staged.
- Callers MUST stage explicit paths -- no `git add -A` / `git add .`.
- `implementing-plan-phases/scripts/commit-and-push-phase.sh` uses `git add -A` *intentionally* because phase commits sweep every plan-touched file.
- Never include `.env`, credentials, large binaries, or local-only files.

## Pre-Commit Hooks

- Hooks always run -- never pass `--no-verify` / `--no-gpg-sign` unless the user explicitly requests it.
- On hook failure, `commit-work.sh` surfaces the hook stderr verbatim and exits non-zero. The caller fixes the underlying issue, re-stages, and creates a **new** commit (do not `--amend`; the failed commit did not happen).

## Body Guidance

- Focus on **why**, not **what**. The diff covers what changed.
- Reference work-item IDs in the body when the change spans multiple IDs (e.g. `Also touches FEAT-029 backend-detect harness.`).
- Multi-line bodies are encouraged when the change carries non-obvious tradeoffs (e.g. "chose grep over jq for portability with macOS BSD jq < 1.6").

## See Also

- `${CLAUDE_PLUGIN_ROOT}/skills/managing-source-control/scripts/commit-work.sh` -- canonical commit assembler (Phase 2).
- `${CLAUDE_PLUGIN_ROOT}/skills/implementing-plan-phases/scripts/commit-and-push-phase.sh` -- phase-completion wrapper.
- [branch-conventions.md](branch-conventions.md) -- branch prefixes that pair with each commit type.
