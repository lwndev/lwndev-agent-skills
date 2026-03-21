# Implementation Plan: Plugin Release Workflow

## Overview

Implement an automated plugin release workflow consisting of a release script (`npm run release`), a tagging script (`npm run release:tag`), a repo-local skill for guided releases, and a test fix to remove hardcoded version assertions. The release script bumps versions across manifests, generates a changelog, updates the plugin README, and commits. Tagging is a separate post-merge step.

## Features Summary

| Feature ID | GitHub Issue | Feature Document | Priority | Complexity | Status |
|------------|--------------|------------------|----------|------------|--------|
| FEAT-005 | [#37](https://github.com/lwndev/lwndev-marketplace/issues/37) | [FEAT-005-plugin-release-workflow.md](../features/FEAT-005-plugin-release-workflow.md) | High | Medium | Pending |

## Recommended Build Sequence

### Phase 1: Shared Infrastructure and Test Fix
**Feature:** [FEAT-005](../features/FEAT-005-plugin-release-workflow.md) | [#37](https://github.com/lwndev/lwndev-marketplace/issues/37)
**Status:** ✅ Complete

#### Rationale
- **Foundation first**: Install `semver` dependency and add shared helpers that both scripts will use
- **Remove fragile test**: The hardcoded version assertion in `build.test.ts` will break during Phase 2 when the version changes — fix it first
- **Low risk**: Changes are isolated to test assertions and a new utility module, no functional workflow changes yet

#### Implementation Steps
1. Install `semver` as a dependency:
   ```bash
   npm install semver && npm install -D @types/semver
   ```
2. Add shared helper `scripts/lib/plugin-manifest.ts` with functions:
   - `readPluginManifest(pluginName: string)` — reads and parses `plugins/<name>/.claude-plugin/plugin.json`
   - `readMarketplaceManifest()` — reads and parses `.claude-plugin/marketplace.json`
   - `writePluginManifest(pluginName: string, manifest: object)` — writes with 2-space indent + trailing newline
   - `writeMarketplaceManifest(manifest: object)` — writes with 2-space indent + trailing newline
   - `getMarketplacePluginEntry(marketplace, pluginName)` — finds matching plugin entry in marketplace plugins array
3. Add shared helper `scripts/lib/git-utils.ts` with functions:
   - `isWorkingTreeClean()` — returns boolean via `git status --porcelain`
   - `getCurrentBranch()` — returns branch name via `git rev-parse --abbrev-ref HEAD`
   - `getTagsForPlugin(pluginName)` — returns tags matching `<pluginName>@*` pattern
   - `getLatestTagForPlugin(pluginName)` — returns most recent tag or null
   - `getCommitsSinceTag(tag: string | null)` — returns parsed commit list (hash, type, scope, message)
   - `tagExists(tagName)` — returns boolean
4. Update `scripts/__tests__/build.test.ts` line 50:
   - Replace `expect(manifest.version).toBe('1.1.0')` with:
     - `expect(semver.valid(manifest.version)).toBeTruthy()` (valid semver)
     - Read marketplace.json and assert `marketplace.plugins[matching].version === manifest.version` (cross-file consistency)
5. Run `npm test` to verify test fix passes

#### Deliverables
- [x] `semver` and `@types/semver` installed
- [x] `scripts/lib/plugin-manifest.ts` — manifest read/write utilities
- [x] `scripts/lib/git-utils.ts` — git operation utilities
- [x] `scripts/__tests__/build.test.ts` — updated version assertion (dynamic semver + cross-file check)
- [x] All existing tests pass (237/237)

---

### Phase 2: Release Script (`npm run release`)
**Feature:** [FEAT-005](../features/FEAT-005-plugin-release-workflow.md) | [#37](https://github.com/lwndev/lwndev-marketplace/issues/37)
**Status:** ✅ Complete

#### Rationale
- **Core deliverable**: The release script is the primary value of this feature
- **Depends on Phase 1**: Uses `plugin-manifest.ts`, `git-utils.ts`, and `semver`
- **Establishes patterns**: CLI argument parsing and output formatting that `release:tag` will reuse

#### Implementation Steps
1. Create `scripts/release.ts` with the following flow:
   - Parse CLI arguments using `node:util` `parseArgs` (consistent with `scaffold.ts`):
     - `--plugin <name>` (string, optional)
     - `--bump <type>` (string, optional, values: patch/minor/major)
     - `--version <x.y.z>` (string, optional)
   - Validate argument combinations per FR-2 (exactly one of `--bump`/`--version`, mutual exclusivity)
   - Check working tree is clean via `isWorkingTreeClean()`
   - Discover and select plugin via `getSourcePlugins()` (same auto-select logic as `scaffold.ts`)
   - Read current version from plugin manifest via `readPluginManifest()`
   - Compute new version: `semver.inc(current, bump)` or validate explicit `--version` with `semver.valid()` and `semver.gt()`
   - Verify plugin exists in marketplace manifest via `getMarketplacePluginEntry()`
2. Implement manifest updates (FR-3):
   - Update version in plugin manifest and write via `writePluginManifest()`
   - Update version in marketplace entry and write via `writeMarketplaceManifest()`
   - Sync description from plugin.json → marketplace.json if different
3. Implement changelog generation (FR-4):
   - Get commits since last tag via `getCommitsSinceTag(getLatestTagForPlugin())`
   - Parse conventional commit prefixes to group by type (feat, fix, chore, docs, other)
   - Format as markdown section: `## [x.y.z] - YYYY-MM-DD`
   - Prepend to `plugins/<name>/CHANGELOG.md` (create if doesn't exist)
   - Add diff link at bottom: `[x.y.z]: https://github.com/lwndev/lwndev-marketplace/compare/<old-tag>...<new-tag>`
4. Implement README update (FR-5):
   - Read `plugins/<name>/README.md`
   - Insert or replace version line after first heading: `**Version:** x.y.z | **Released:** YYYY-MM-DD`
5. Implement git commit (FR-6):
   - Stage modified files: `git add <list of files>`
   - Commit with message: `release(<plugin-name>): v<new-version>`
6. Implement summary output (FR-7):
   - Print each action with `printSuccess()` using `✔` prefix
   - Print next steps pointing to `release:tag`
7. Register in `package.json`:
   ```json
   "release": "tsx scripts/release.ts"
   ```
8. Write tests in `scripts/__tests__/release.test.ts`:
   - Unit tests for argument validation
   - Unit tests for version computation
   - Unit tests for changelog formatting
   - Integration tests using a temporary git repo (init, commit, run release, verify outputs)

#### Deliverables
- [x] `scripts/release.ts` — release script implementation
- [x] `scripts/__tests__/release.test.ts` — 17 tests (argument validation, full workflow, error handling)
- [x] `package.json` updated with `release` script
- [x] All error messages match NFR-1 specifications
- [x] All tests pass (254/254)

---

### Phase 3: Tagging Script (`npm run release:tag`)
**Feature:** [FEAT-005](../features/FEAT-005-plugin-release-workflow.md) | [#37](https://github.com/lwndev/lwndev-marketplace/issues/37)
**Status:** ✅ Complete

#### Rationale
- **Completes the release workflow**: Without tagging, changelog diff links and version history tracking don't work
- **Simple scope**: Mostly guards (branch check, clean tree, tag exists) plus one git operation
- **Depends on Phase 1**: Uses `git-utils.ts` and `plugin-manifest.ts`

#### Implementation Steps
1. Create `scripts/release-tag.ts`:
   - Parse `--plugin <name>` argument (same auto-select logic)
   - Verify current branch is `main` via `getCurrentBranch()`
   - Verify working tree is clean via `isWorkingTreeClean()`
   - Read current version from plugin manifest
   - Construct tag name: `<plugin-name>@<version>`
   - Verify tag doesn't already exist via `tagExists()`
   - Create annotated tag: `git tag -a <tag> -m "Release <plugin-name> v<version>"`
   - Print summary with `printSuccess()` and push reminder
2. Register in `package.json`:
   ```json
   "release:tag": "tsx scripts/release-tag.ts"
   ```
3. Write tests in `scripts/__tests__/release-tag.test.ts`:
   - Branch check enforcement
   - Clean working tree enforcement
   - Duplicate tag prevention
   - Successful tag creation and annotation message

#### Deliverables
- [x] `scripts/release-tag.ts` — tagging script implementation
- [x] `scripts/__tests__/release-tag.test.ts` — 6 tests (branch check, clean tree, duplicate tag, plugin not found, successful tagging, explicit --plugin)
- [x] `package.json` updated with `release:tag` script
- [x] All error messages match NFR-1 specifications
- [x] All tests pass (260/260)

---

### Phase 4: Releasing Skill
**Feature:** [FEAT-005](../features/FEAT-005-plugin-release-workflow.md) | [#37](https://github.com/lwndev/lwndev-marketplace/issues/37)
**Status:** ✅ Complete

#### Rationale
- **Build last**: The skill wraps the scripts from Phases 2-3, so those must exist first
- **No code risk**: This phase only creates a markdown file — no functional code changes
- **Immediate value**: Once created, maintainers can use it in the next release

#### Implementation Steps
1. Create directory `.claude/skills/releasing-plugins/`
2. Create `.claude/skills/releasing-plugins/SKILL.md` with:
   - Frontmatter: `name: releasing-plugins`, `description` covering trigger phrases (release plugin, bump version, prepare a release, cut a release)
   - Instructions for two-phase workflow:
     - **Pre-merge**: plugin selection → commit analysis → bump suggestion → run `npm run release` → review diff (check for `code-review` plugin, fallback to manual review) → push/PR
     - **Post-merge**: confirm on `main` → run `npm run release:tag` → push tag
3. Verify the skill is discovered by Claude Code:
   - Run `claude --print-skills` or check `/skills` in a session to confirm it appears

#### Deliverables
- [x] `.claude/skills/releasing-plugins/SKILL.md` — repo-local release skill
- [ ] Skill appears in `/skills` listing when working in this repo (verify after `/reload-plugins`)

---

## Shared Infrastructure

### New Utility Modules (Phase 1)

```
scripts/lib/
├── constants.ts          # Existing — PLUGINS_DIR, getPluginDir, etc.
├── skill-utils.ts        # Existing — getSourcePlugins, getSourceSkills
├── prompts.ts            # Existing — printSuccess, printError, etc.
├── plugin-manifest.ts    # NEW — manifest read/write for plugin.json and marketplace.json
└── git-utils.ts          # NEW — git operations (branch, tags, commits, clean check)
```

### Reused Patterns from Existing Scripts

- **Plugin discovery and `--plugin` flag**: Reuse `getSourcePlugins()` and the auto-select/flag pattern from `scaffold.ts` lines 28-54
- **CLI argument parsing**: Use `node:util` `parseArgs` (same as `scaffold.ts` line 16)
- **Output formatting**: Use `printSuccess`, `printError`, `printInfo` from `prompts.ts`
- **Error handling**: Follow `build.ts` pattern — try/catch in main, `process.exit(1)` on failure
- **Shebang and module format**: `#!/usr/bin/env tsx` with ESM imports (`.js` extensions)

## Testing Strategy

### Unit Tests
- **Version computation**: Parameterized tests for `semver.inc` with all bump types from various starting versions
- **Changelog formatting**: Given a list of parsed commits, assert correct markdown output (grouping, ordering, date format, diff links)
- **Manifest updates**: Read → modify → write round-trip preserves formatting and updates correct fields
- **Argument validation**: All 7 combinations from the options table (4 valid, 3 error)

### Integration Tests
- **Temporary git repos**: Create a temp directory, `git init`, add files, commit, then run the release script and verify:
  - Files were modified correctly
  - Commit was created with correct message
  - No tag was created (for `release`)
  - Tag was created (for `release:tag`)
- **Error paths**: Dirty working tree, wrong branch, duplicate tag, missing plugin

### Test Configuration
- Tests run sequentially (`maxWorkers: 1` per existing `jest.config.js`) to prevent race conditions with git operations
- Integration tests should use `os.tmpdir()` for isolated git repos, not the real repo

## Dependencies and Prerequisites

### New Dependencies
- `semver` (runtime) — version parsing, bumping, comparison
- `@types/semver` (dev) — TypeScript type definitions

### Existing Dependencies Used
- `chalk` — output formatting (via `prompts.ts`)
- `gray-matter` — only used by `skill-utils.ts`, not needed here
- `tsx` — TypeScript script execution

### Prerequisites
- Git available on PATH (for `execSync` calls in `git-utils.ts`)
- Existing `scripts/lib/` modules working

## Risk Assessment

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Git operations in tests affect real repo | High | Low | Use `os.tmpdir()` for all integration test git repos |
| Changelog generation misses commits | Medium | Medium | Integration test verifies commit count matches git log |
| JSON formatting drift after write | Low | Low | Round-trip test: read → write → read, assert equality |
| `execSync` git commands fail silently | Medium | Low | Check exit codes, capture stderr, throw on failure |
| Skill not discovered by Claude Code | Low | Low | Verify with `/skills` listing after creation |

## Success Criteria

### Per-Phase
- Phase 1: `semver` installed, tests pass with dynamic version assertion, utility modules have full test coverage
- Phase 2: `npm run release -- --bump patch` completes full workflow successfully on `lwndev-sdlc` plugin
- Phase 3: `npm run release:tag` creates correct annotated tag on `main`
- Phase 4: Skill appears in `/skills` and guides through both release phases

### Overall
- Full end-to-end workflow works: `release` → PR → merge → `release:tag` → push tags
- All acceptance criteria from FEAT-005 requirements pass
- No regressions in existing `validate`, `scaffold`, or `test` scripts
- Existing CI pipeline passes

## Code Organization

```
scripts/
├── release.ts                    # Phase 2 — release script
├── release-tag.ts                # Phase 3 — tagging script
├── build.ts                      # Existing — validation
├── scaffold.ts                   # Existing — skill scaffolding
├── lib/
│   ├── constants.ts              # Existing
│   ├── skill-utils.ts            # Existing
│   ├── prompts.ts                # Existing
│   ├── plugin-manifest.ts        # Phase 1 — manifest read/write
│   └── git-utils.ts              # Phase 1 — git operations
└── __tests__/
    ├── build.test.ts             # Phase 1 — updated version assertion
    ├── release.test.ts           # Phase 2 — release script tests
    └── release-tag.test.ts       # Phase 3 — tagging script tests

.claude/
└── skills/
    └── releasing-plugins/
        └── SKILL.md              # Phase 4 — repo-local release skill
```
