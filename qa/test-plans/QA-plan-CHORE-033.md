# QA Test Plan: Fix Skill Permission Prompts

## Metadata

| Field | Value |
|-------|-------|
| **Plan ID** | QA-plan-CHORE-033 |
| **Requirement Type** | CHORE |
| **Requirement ID** | CHORE-033 |
| **Source Documents** | `requirements/chores/CHORE-033-fix-skill-permission-prompts.md` |
| **Date Created** | 2026-04-18 |

## Existing Test Verification

Tests that already exist and must continue to pass (regression baseline):

| Test File | Description | Status |
|-----------|-------------|--------|
| `scripts/__tests__/build.test.ts` | Plugin validation pipeline — ensures `validate()` still accepts the modified SKILL.md files with their trimmed `allowed-tools` lists | PASS |
| `scripts/__tests__/*.test.ts` (all) | Full `vitest` suite — must continue to pass (`fileParallelism: false` per `vitest.config.ts`) | PASS |

## New Test Analysis

No new test files are needed. This chore only edits configuration/settings and frontmatter metadata — existing validation coverage is sufficient.

| Test Description | Target File(s) | Requirement Ref | Priority | Status |
|-----------------|----------------|-----------------|----------|--------|
| — | — | — | — | — |

## Coverage Gap Analysis

| Gap Description | Affected Code | Requirement Ref | Recommendation |
|----------------|---------------|-----------------|----------------|
| AC8 (permission-prompt absence) has no automated test. The Skill-invocation allowlist matching happens inside the Claude Code runtime, not in repo code. | N/A | AC8 | Manual verification: open a fresh Claude Code session in this repo, invoke each skill (or at minimum the two newly-added ones plus one previously-problematic one) via `/<plugin>:<skill-name>`, confirm no `Skill(...)` permission prompt appears. |
| AC2 (Bash syntax migration) has no automated validation of pattern matching — the runtime is the only authority. | `.claude/settings.local.json` | AC2 | Manual verification: after the migration, attempt a representative `Bash(cmd ...)` command (e.g., `gh issue list`) in a fresh session and confirm it auto-approves via the migrated `Bash(gh issue *)` rule. |

## Code Path Verification

One entry per acceptance criterion (CHORE convention):

| Requirement | Description | Expected Code Path | Verification Method | Status |
|-------------|-------------|-------------------|-------------------|--------|
| AC1 | `.claude/settings.local.json` contains `Skill(lwndev-sdlc:orchestrating-workflows)` and `Skill(lwndev-sdlc:managing-work-items)` in `permissions.allow` | `.claude/settings.local.json` → `permissions.allow[]` | `jq -r '.permissions.allow[]' .claude/settings.local.json \| grep -E 'Skill\(lwndev-sdlc:(orchestrating-workflows\|managing-work-items)\)'` must return both lines | PASS |
| AC2 | All command-prefix `Bash(<cmd>:*)` entries migrated to `Bash(<cmd> *)` in settings.local.json (scope: simple command-prefix entries at the top of the file such as `Bash(gh issue:*)`, `Bash(git commit:*)`; path-style entries like `Bash(./scripts/workflow-state.sh init:*)` are OUT of scope and must remain unchanged — see Notes in chore doc for rationale) | `.claude/settings.local.json` → `permissions.allow[]` | `jq -r '.permissions.allow[]' .claude/settings.local.json \| grep -E '^Bash\((gh\|git\|npm\|node\|jq)[^/]*:\*\)$'` must return zero rows; equivalent space-syntax rules must exist | PASS |
| AC3 | Stale `Skill(implementing-plan-phases)` (no `lwndev-sdlc:` prefix) is removed; the prefixed variant `Skill(lwndev-sdlc:implementing-plan-phases)` is retained | `.claude/settings.local.json` → `permissions.allow[]` | `jq -r '.permissions.allow[]' .claude/settings.local.json \| grep -x 'Skill(implementing-plan-phases)'` must return zero rows; `grep -x 'Skill(lwndev-sdlc:implementing-plan-phases)'` must return one row | PASS |
| AC4 | `Agent` removed from `allowed-tools` in `executing-bug-fixes`, `executing-chores`, and `implementing-plan-phases` SKILL.md files | `plugins/lwndev-sdlc/skills/{executing-bug-fixes,executing-chores,implementing-plan-phases}/SKILL.md` → frontmatter `allowed-tools` block | For each file, read the YAML frontmatter and confirm `- Agent` does not appear between `allowed-tools:` and the next top-level key | PASS |
| AC5 | `Glob` removed from `allowed-tools` in `finalizing-workflow/SKILL.md` | `plugins/lwndev-sdlc/skills/finalizing-workflow/SKILL.md` → frontmatter `allowed-tools` block | Read frontmatter, confirm `- Glob` is absent from the `allowed-tools` block | PASS |
| AC6 | `npm run validate` passes | `scripts/build.ts` via the `validate` npm script | Run `npm run validate` from repo root, confirm exit code 0 and no plugin reports errors | PASS |
| AC7 | `npm test` passes | `scripts/__tests__/*.test.ts` via `vitest` | Run `npm test` from repo root, confirm exit code 0 | PASS |
| AC8 | No `Skill(...)` permission prompt appears when invoking any of the 13 skills in `plugins/lwndev-sdlc/skills/` in a fresh Claude Code session | Claude Code runtime permission-matching | Manual — open fresh session; at minimum invoke `/lwndev-sdlc:orchestrating-workflows` and `/lwndev-sdlc:managing-work-items` (the two newly allowed) and confirm no `Skill(...)` prompt; spot-check one other skill (e.g., `/lwndev-sdlc:documenting-features`) | SKIP |

## Deliverable Verification

Key output artifacts of this chore:

| Deliverable | Source Phase | Expected Path | Status |
|-------------|-------------|---------------|--------|
| Updated permission settings | Implementation | `.claude/settings.local.json` (allow array modified) | PASS |
| Trimmed SKILL.md frontmatters (×4) | Implementation | `plugins/lwndev-sdlc/skills/{executing-bug-fixes,executing-chores,implementing-plan-phases,finalizing-workflow}/SKILL.md` | PASS |
| Updated allowed-tools test assertions (×3) | Implementation | `scripts/__tests__/{executing-bug-fixes,executing-chores,implementing-plan-phases}.test.ts` | PASS |

## Scope Boundary Verification

CHORE-specific: confirm no unrelated changes are introduced.

| Boundary | Verification |
|----------|--------------|
| No SKILL.md body changes | `git diff plugins/lwndev-sdlc/skills/{executing-bug-fixes,executing-chores,implementing-plan-phases,finalizing-workflow}/SKILL.md` must show only frontmatter `allowed-tools` edits (a single removed line per file). No edits outside the `---` frontmatter block. |
| No other SKILL.md files modified | `git diff --name-only -- 'plugins/lwndev-sdlc/skills/**/SKILL.md'` must match exactly the 4 files listed in AC4/AC5 |
| Test file changes limited to the 3 expected files | `git diff --name-only -- 'scripts/**'` must list exactly `scripts/__tests__/{executing-bug-fixes,executing-chores,implementing-plan-phases}.test.ts` — updates to allowed-tools assertions consistent with AC4. `git diff --name-only -- '*.json' ':!.claude/settings.local.json'` must be empty. |
| Path-style `Bash(...:*)` entries preserved | After AC2 migration, entries like `Bash(./scripts/workflow-state.sh init:*)` and `Bash(/Users/leif/.claude/plugins/cache/...:*)` must remain unchanged (AC2 explicitly scopes them out) |
| `orchestrating-workflows/SKILL.md` untouched | `git diff plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` must be empty — adding `allowed-tools` is explicitly out of scope per chore doc Notes |

## Plan Completeness Checklist

- [x] All existing tests pass (regression baseline)
- [x] All FR-N / RC-N / AC entries have corresponding test plan entries
- [x] Coverage gaps are identified with recommendations
- [x] Code paths trace from requirements to implementation
- [x] Phase deliverables are accounted for (if applicable)
- [x] New test recommendations are actionable and prioritized
