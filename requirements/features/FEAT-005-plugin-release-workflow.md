# Feature Requirements: Plugin Release Workflow

## Overview

Add a release script and SDLC skill that automate plugin versioning, changelog generation, and tagging so releases are consistent, traceable, and users receive updates via Claude Code's version-based cache invalidation.

## Feature ID
`FEAT-005`

## GitHub Issue
[#37](https://github.com/lwndev/lwndev-marketplace/issues/37)

## Priority
High - Without version bumps, users don't receive plugin updates (Claude Code uses the version field to detect updates — see [plugins-reference.md L699](docs/shared/docs/anthropic/docs/en/plugins-reference.md))

## User Story

As a plugin maintainer, I want to run a single command that bumps versions across all manifest files, generates a changelog, and prepares a release commit so that I don't forget a file and users reliably receive updates.

## Command Syntax

```bash
npm run release -- [options]
```

### Options

| Option | Required | Values | Description |
|---|---|---|---|
| `--plugin <name>` | No* | Any discovered plugin name | Plugin to release. *Required when multiple plugins exist; auto-selects when only one exists. |
| `--bump <type>` | Yes** | `patch`, `minor`, `major` | Semver bump type. Computes next version from current. |
| `--version <x.y.z>` | Yes** | Valid semver string | Explicit target version. Must be greater than current. |

\* If omitted and multiple plugins exist, the script errors with a list of available plugins.
\** Exactly one of `--bump` or `--version` is required. Providing both is an error. Providing neither is an error.

### Valid Option Combinations

| `--plugin` | `--bump` | `--version` | Result |
|---|---|---|---|
| omitted | `patch` | — | Auto-select plugin, bump patch |
| omitted | — | `2.0.0` | Auto-select plugin, set version |
| `lwndev-sdlc` | `minor` | — | Release specific plugin, bump minor |
| `lwndev-sdlc` | — | `2.0.0` | Release specific plugin, set version |
| omitted | — | — | Error: specify `--bump` or `--version` |
| omitted | `patch` | `2.0.0` | Error: `--bump` and `--version` are mutually exclusive |
| omitted (multi-plugin) | `patch` | — | Error: `--plugin` required when multiple plugins exist |

### Examples

```bash
# Auto-select plugin, bump patch version
npm run release -- --bump patch

# Specify plugin and bump type
npm run release -- --plugin lwndev-sdlc --bump minor

# Set an explicit version
npm run release -- --plugin lwndev-sdlc --version 2.0.0
```

## Functional Requirements

### FR-1: Plugin Discovery and Selection
- Discover plugins using existing `getSourcePlugins()` from `scripts/lib/skill-utils.ts`
- Auto-select when only one plugin exists (consistent with `scaffold.ts` behavior)
- Support `--plugin <name>` flag to select explicitly when multiple plugins exist
- Error if `--plugin` is omitted and multiple plugins exist

### FR-2: Version Computation
- Accept `--bump patch|minor|major` to compute next version from current
- Accept `--version x.y.z` as an explicit override
- Require exactly one of `--bump` or `--version`
- Validate that explicit `--version` is valid semver and greater than the current version
- Read current version from `plugins/<name>/.claude-plugin/plugin.json`

### FR-3: Manifest Updates
- Update `version` in `plugins/<name>/.claude-plugin/plugin.json`
- Update `version` for the matching plugin entry in `.claude-plugin/marketplace.json`
- Note: the docs recommend setting the version in only one place ([plugins-reference.md L312](docs/shared/docs/anthropic/docs/en/plugins-reference.md)), but for relative-path plugin sources the docs advise setting it in the marketplace entry ([plugin-marketplaces.md L657](docs/shared/docs/anthropic/docs/en/plugin-marketplaces.md)). We update both to keep them in sync since `plugin.json` takes priority silently and drift would cause confusion.
- Sync the `description` field from `plugin.json` into `marketplace.json` if they've drifted
- Preserve all other fields and JSON formatting (2-space indent, trailing newline)

### FR-4: Changelog Generation
- Create or append to `plugins/<name>/CHANGELOG.md`
- Generate entries from `git log` since the last tag for this plugin (or since initial commit if no prior tag)
- Group commits by type using conventional commit prefixes (`feat`, `fix`, `chore`, `docs`, etc.)
- Format as a markdown section headed by version and date: `## [x.y.z] - YYYY-MM-DD`
- Newest release at the top of the file (prepend, don't append)
- Include a link to the full diff between tags at the bottom of each section

### FR-5: Plugin README Update
- Add or update a version/release metadata line in `plugins/<name>/README.md`
- Format: `**Version:** x.y.z | **Released:** YYYY-MM-DD`
- Place near the top of the README, after the heading

### FR-6: Git Commit
- Stage all modified files (plugin.json, marketplace.json, CHANGELOG.md, README.md)
- Create commit with message: `release(<plugin-name>): v<new-version>`
- Do NOT create a git tag (tagging happens post-merge — see FR-8)
- Do NOT push to remote

### FR-7: Summary Output
- Print a summary after successful release:
  - Plugin name
  - Version change (old → new)
  - Files modified
  - Next steps reminder (push branch, open PR, tag after merge)

### FR-8: Post-Merge Tagging (`npm run release:tag`)
A separate command to create the git tag after the release PR has been merged to `main`.

- Accept `--plugin <name>` (same auto-select rules as `release`)
- Read the current version from `plugins/<name>/.claude-plugin/plugin.json`
- Verify the current branch is `main`
- Verify the working tree is clean
- Create an annotated git tag: `<plugin-name>@<version>`
- Tag annotation message: `Release <plugin-name> v<version>`
- Print reminder to push the tag: `git push --tags`

## Output Format

### `npm run release` output
```
✔ Plugin:   lwndev-sdlc
✔ Version:  1.1.0 → 1.2.0
✔ Updated:  plugins/lwndev-sdlc/.claude-plugin/plugin.json
✔ Updated:  .claude-plugin/marketplace.json
✔ Updated:  plugins/lwndev-sdlc/CHANGELOG.md
✔ Updated:  plugins/lwndev-sdlc/README.md
✔ Commit:   release(lwndev-sdlc): v1.2.0

Next steps:
  1. Push branch and open a PR for review
  2. After merge, run: npm run release:tag -- --plugin lwndev-sdlc
```

### `npm run release:tag` output
```
✔ Plugin:   lwndev-sdlc
✔ Tag:      lwndev-sdlc@1.2.0

To publish:
  git push --tags
```

## Non-Functional Requirements

### NFR-1: Error Handling

**`npm run release` errors:**
- Plugin not found: `Error: Plugin "<name>" not found. Available plugins: <list>`
- Both `--bump` and `--version` provided: `Error: Specify either --bump or --version, not both`
- Neither provided: `Error: Specify --bump <patch|minor|major> or --version <x.y.z>`
- Invalid semver: `Error: "<value>" is not a valid semver version`
- Version not greater than current: `Error: New version <new> must be greater than current version <current>`
- Dirty working tree: `Error: Working tree has uncommitted changes. Commit or stash them first.`
- Missing plugin entry in marketplace.json: `Error: Plugin "<name>" not found in marketplace.json`

**`npm run release:tag` errors:**
- Not on `main` branch: `Error: Must be on main branch to tag a release. Current branch: <branch>`
- Dirty working tree: `Error: Working tree has uncommitted changes. Commit or stash them first.`
- Tag already exists: `Error: Tag "<plugin-name>@<version>" already exists`
- Plugin not found: `Error: Plugin "<name>" not found. Available plugins: <list>`

### NFR-2: Idempotency
- Script should be safe to re-run if it fails partway (no partial state left behind)
- If the commit or tag step fails, the file changes remain staged so the user can inspect and retry

### NFR-3: Consistency with Existing Scripts
- Use shared utilities from `scripts/lib/` (constants, prompts, skill-utils)
- Follow the same TypeScript conventions as `build.ts` and `scaffold.ts`
- Register as `npm run release` in `package.json`

## Dependencies

- `semver` npm package for version parsing, bumping, and comparison (not currently installed — must be added to `dependencies` in `package.json`)
- Existing `scripts/lib/` utilities (`getSourcePlugins`, `getPluginDir`, `getPluginManifestDir`, `printSuccess`, `printError`)
- Git (for log, commit, tag operations)

## Component 2: Repo-Local Skill (`releasing-plugins`)

### Skill Location
`.claude/skills/releasing-plugins/SKILL.md`

This skill is specific to the marketplace repo's development workflow and is NOT distributed with the `lwndev-sdlc` plugin. It lives in the repo's local `.claude/skills/` directory so it's available to maintainers working in this repo.

### Trigger Description
Use when the user says "release plugin", "bump version", "prepare a release", "cut a release", or wants to publish a new plugin version.

### Skill Behavior

**Preparing a release (pre-merge):**
1. Ask which plugin and what bump type if not provided by the user
2. Review unreleased changes since the last tag using `git log <last-tag>..HEAD`
3. Analyze conventional commit prefixes to suggest the appropriate bump type:
   - Any `feat` commits → suggest `minor`
   - Only `fix`/`chore`/`docs` commits → suggest `patch`
   - Any commits noting breaking changes → suggest `major`
4. Present the change summary and bump suggestion to the user for confirmation
5. Run `npm run release -- --plugin <name> --bump <type>`
6. Review the release commit:
   - **If the `code-review` plugin is installed:** invoke it via the Skill tool to review the release diff (skills can invoke other skills but cannot invoke built-in CLI commands; the built-in `/review` is deprecated per [commands.md L64](docs/shared/docs/anthropic/docs/en/commands.md))
   - **Fallback:** review the diff directly — verify version values are consistent across manifests, changelog content is accurate, and README was updated. Include a note in the summary: *"Tip: Install the `code-review` plugin for richer release reviews: `claude plugin install code-review@claude-code-marketplace`"*
7. Ask if the user wants to push the branch and open a PR

**Tagging a release (post-merge):**
1. Confirm the release PR has been merged and the user is on `main`
2. Run `npm run release:tag -- --plugin <name>`
3. Ask if the user wants to push the tag

## Component 3: Test Fix

### Current Problem
`scripts/__tests__/build.test.ts:50` hardcodes `expect(manifest.version).toBe('1.1.0')`, requiring a manual test update on every release.

### Fix
Replace with dynamic assertions:
- Version is valid semver (use `semver.valid()`)
- Version in `plugin.json` matches version in `marketplace.json` for the same plugin

## Edge Cases

1. **First release (no prior tags)**: Changelog includes all commits; script handles `git log` with no tag range gracefully
2. **Multiple plugins, no `--plugin` flag**: Error with list of available plugins
3. **Marketplace.json plugin entry missing**: Error before modifying any files
4. **Description drift**: Sync description from plugin.json → marketplace.json and note in output
5. **No commits since last tag**: Warn that changelog will be empty, still allow version bump
6. **Non-conventional commit messages**: Include under an "Other" group in changelog
7. **Tag already exists for target version**: Error before modifying any files
8. **`release:tag` run on non-main branch**: Error with message to switch to `main` after merge
9. **`release:tag` run before PR merge**: Tag points at the wrong commit; guard by requiring `main` branch

## Testing Requirements

### Unit Tests
- Version computation (patch/minor/major from various starting versions)
- Changelog generation formatting (grouping, ordering, date, diff links)
- Manifest update logic (version sync, description sync, JSON formatting)
- CLI argument validation (mutual exclusivity, missing args, invalid values)
- Plugin discovery and auto-selection

### Integration Tests

**`npm run release`:**
- Full release flow with `--bump patch` (end-to-end with git operations)
- Full release flow with `--version x.y.z`
- Error cases: dirty working tree, missing plugin, missing marketplace entry
- Verify git commit message format
- Verify all files updated correctly
- Verify no tag is created

**`npm run release:tag`:**
- Full tagging flow on `main` branch
- Error cases: not on `main`, dirty working tree, tag already exists
- Verify annotated tag format and annotation message

### Manual Testing

**`npm run release`:**
- Run release on `lwndev-sdlc` plugin with `--bump patch`
- Verify changelog content is correct
- Verify README updated
- Verify `plugin.json` and `marketplace.json` in sync
- Verify commit message matches convention
- Verify no tag was created

**`npm run release:tag`:**
- Merge release PR, switch to `main`, run `release:tag`
- Verify annotated tag created with correct name and message
- Verify `git push --tags` publishes the tag

## Future Enhancements

- GitHub release creation (via `gh release create`) from the tag
- CI workflow to validate that merged PRs with plugin changes have a corresponding version bump
- `--dry-run` flag to preview all changes without writing
- Multi-plugin batch release

## Acceptance Criteria

### Release Script (`npm run release`)
- [ ] `npm run release -- --plugin lwndev-sdlc --bump patch` bumps version in both manifests, generates changelog, updates README, and commits (no tag)
- [ ] `npm run release -- --plugin lwndev-sdlc --version 2.0.0` works with explicit version
- [ ] Script errors clearly if plugin doesn't exist or version is invalid
- [ ] Script auto-selects plugin when only one exists
- [ ] Script rejects when working tree is dirty
- [ ] Changelog groups commits by conventional commit type
- [ ] Changelog prepends new version section (newest first)
- [ ] Plugin README shows version and release date
- [ ] Description synced from plugin.json to marketplace.json when drifted
- [ ] Git commit follows `release(<plugin-name>): v<version>` convention
- [ ] Output includes next steps pointing to `release:tag`

### Tagging Script (`npm run release:tag`)
- [ ] Creates annotated tag `<plugin-name>@<version>` from current plugin.json version
- [ ] Errors if not on `main` branch
- [ ] Errors if working tree is dirty
- [ ] Errors if tag already exists

### Test Fix
- [ ] Build test no longer hardcodes a version string
- [ ] Build test validates semver format and cross-file version consistency

### Skill
- [ ] `releasing-plugins` skill exists at `.claude/skills/releasing-plugins/SKILL.md` (repo-local, not distributed with plugin)
- [ ] Skill analyzes commit history and suggests appropriate bump type
- [ ] Skill asks for confirmation before running release
- [ ] Skill guides through both phases (prepare pre-merge, tag post-merge)
