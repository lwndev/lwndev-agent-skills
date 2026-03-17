# Chore: Refactor Skills into Claude Code Plugin

## Chore ID

`CHORE-010`

## GitHub Issue

[#24](https://github.com/lwndev/lwndev-agent-skills/issues/24)

## Category

`refactoring`

## Description

Refactor the existing 7 skills from standalone `.claude/skills/` installation (via `ai-skills-manager`) into a Claude Code plugin structure, and host a plugin marketplace in this repository for distribution. This is a prerequisite for FEAT-004 (#23), which will add QA skills, an agent, and hooks that require the plugin structure.

## Affected Files

- `scripts/build.ts` — rewritten to generate plugin directory structure in `dist/`
- `scripts/install.ts` — deleted (replaced by plugin commands)
- `scripts/update.ts` — deleted (replaced by plugin commands)
- `scripts/uninstall.ts` — deleted (replaced by plugin commands)
- `scripts/lib/constants.ts` — added plugin constants, removed scope constants
- `scripts/lib/skill-utils.ts` — removed unused functions, added `pluginBuildExists()`
- `scripts/lib/prompts.ts` — removed unused prompt functions
- `scripts/__tests__/build.test.ts` — rewritten for plugin directory assertions
- `scripts/__tests__/constants.test.ts` — updated for plugin constants
- `scripts/__tests__/skill-utils.test.ts` — updated for new utility functions
- `package.json` — removed install/update/uninstall npm scripts
- `src/plugin/plugin.json` — new plugin manifest source
- `src/plugin/README.md` — new plugin README source
- `.claude-plugin/marketplace.json` — new marketplace manifest at repo root
- `README.md` — updated with plugin installation instructions
- `CLAUDE.md` — updated to reflect plugin distribution model

## Acceptance Criteria

### Plugin
- [ ] Plugin manifest (`plugin.json`) created with name `lwndev-sdlc`, version `1.0.0`
- [ ] Build script generates plugin directory structure in `dist/lwndev-sdlc-plugin/`
- [ ] All 7 skills placed under `dist/lwndev-sdlc-plugin/skills/` with correct structure
- [ ] Skills load and function correctly as plugin components via `--plugin-dir` testing

### Marketplace
- [ ] `.claude-plugin/marketplace.json` created at repository root
- [ ] Marketplace references the plugin in `dist/` with correct metadata
- [ ] Marketplace validates with `claude plugin validate .`
- [ ] Plugin install flow works locally (`/plugin marketplace add` → `/plugin install`)

### Documentation & Cleanup
- [ ] README updated with plugin installation instructions
- [ ] CLAUDE.md updated to reflect plugin distribution model
- [ ] Install/update/uninstall scripts updated or deprecated for plugin workflow
- [ ] Decision documented on whether to keep asm-based `.skill` packaging

## Completion

**Status:** `Completed`

**Completed:** 2026-03-16

**Pull Request:** [#25](https://github.com/lwndev/lwndev-agent-skills/pull/25)

## Notes

- The `src/skills/` source structure remains unchanged — the build step transforms it into plugin layout
- Existing asm scripts may still be useful for validation (`validate()` API works on individual skill directories)
- Skills become namespaced under the plugin: `/lwndev-sdlc:documenting-features`, etc.
- Marketplace uses relative paths (`./dist/...`), which works when users add via GitHub source
- This chore is a prerequisite for FEAT-004 (#23) which adds QA skills, a `qa-verifier` agent, and hooks
