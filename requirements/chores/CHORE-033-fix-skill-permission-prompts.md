# Chore: Fix Skill Permission Prompts

## Chore ID

`CHORE-033`

## GitHub Issue

[#80](https://github.com/lwndev/lwndev-marketplace/issues/80)

## Category

`configuration`

## Description

Add missing `Skill(...)` allow rules for `orchestrating-workflows` and `managing-work-items` to `.claude/settings.local.json`, align Bash permission entries with the documented settings.json pattern syntax, and remove unused tool declarations from four SKILL.md frontmatters. The root cause of user-visible permission prompts identified in #80 is missing Skill rules, not `allowed-tools` format — the unused-tool and Bash-syntax changes are opportunistic cleanups in the same area.

## Affected Files

- `.claude/settings.local.json` — add two missing `Skill(...)` rules, migrate `Bash(cmd:*)` entries to `Bash(cmd *)`, remove stale `Skill(implementing-plan-phases)` (no plugin prefix)
- `plugins/lwndev-sdlc/skills/executing-bug-fixes/SKILL.md` — remove unused `Agent` from `allowed-tools`
- `plugins/lwndev-sdlc/skills/executing-chores/SKILL.md` — remove unused `Agent` from `allowed-tools`
- `plugins/lwndev-sdlc/skills/implementing-plan-phases/SKILL.md` — remove unused `Agent` from `allowed-tools`
- `plugins/lwndev-sdlc/skills/finalizing-workflow/SKILL.md` — remove unused `Glob` from `allowed-tools`
- `scripts/__tests__/executing-bug-fixes.test.ts` — update allowed-tools assertion to expect `Agent` absent
- `scripts/__tests__/executing-chores.test.ts` — update allowed-tools assertion to expect `Agent` absent
- `scripts/__tests__/implementing-plan-phases.test.ts` — update allowed-tools assertion to expect `Agent` absent

## Acceptance Criteria

- [x] `.claude/settings.local.json` contains `Skill(lwndev-sdlc:orchestrating-workflows)` and `Skill(lwndev-sdlc:managing-work-items)` in `permissions.allow`
- [x] All `Bash(<cmd>:*)` entries in `.claude/settings.local.json` that use the colon-separator convention for a command prefix are migrated to `Bash(<cmd> *)` (space-separated) to match the documented settings.json pattern-matching behavior; allowed-tools frontmatter in SKILL.md files is untouched
- [x] Stale `Skill(implementing-plan-phases)` entry (without the `lwndev-sdlc:` plugin prefix) is removed from `.claude/settings.local.json`
- [x] `Agent` is removed from `allowed-tools` in `executing-bug-fixes/SKILL.md`, `executing-chores/SKILL.md`, and `implementing-plan-phases/SKILL.md` (none of the three reference the Agent tool in their instructions)
- [x] `Glob` is removed from `allowed-tools` in `finalizing-workflow/SKILL.md` (skill does not reference Glob in its instructions)
- [x] `npm run validate` passes after changes
- [x] `npm test` passes after changes
- [ ] Invoking each of the 13 `lwndev-sdlc` skills no longer surfaces a `Skill(...)` permission prompt in a fresh Claude Code session

## Completion

**Status:** `Complete (pending manual AC8 verification)`

**Pull Request:** [#161](https://github.com/lwndev/lwndev-marketplace/pull/161)

## Notes

### Scope changes since issue was filed (2026-03-28)

#80 was written when the plugin had 12 skills and listed 9 skills as missing Skill rules. The repo has since added `orchestrating-workflows` and `managing-work-items` (13 skills total) and the user has added Skill rules for 11 of them during other work. Only the two newest skills are missing rules today. `orchestrating-workflows/SKILL.md` has no `allowed-tools` declaration at all — that is intentional given its Stop-hook and orchestration role and is out of scope for this chore.

### Bash syntax framing

#80 described the colon syntax as "deprecated" but the official `/anthropics/claude-code` docs still show `Bash(cmd:*)` as the canonical format in *skill/command frontmatter* `allowed-tools`. The settings.json permissions docs (`docs/permissions.md`) document space syntax (`Bash(npm run *)`) as the pattern-matching format and explicitly note that space before `*` enforces a word boundary. The migration in this chore applies only to `.claude/settings.local.json`, not to SKILL.md frontmatter.

### Out of scope

- Broader cleanup of one-off ad-hoc `Bash(...)` entries in `.claude/settings.local.json` that were added during prior debugging sessions
- Adding an `allowed-tools` list to `orchestrating-workflows/SKILL.md`
- Rules for skills from other plugins (`Skill(releasing-plugins)`, `Skill(test-auto-fork)`)
- Re-testing `allowed-tools` format variants (YAML array / space-delimited / comma-separated) — #80's own testing already confirmed all three are accepted by the runtime
