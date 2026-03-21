---
name: releasing-plugins
description: Release a plugin version with automated version bumping, changelog generation, and tagging. Use when the user says "release plugin", "bump version", "prepare a release", "cut a release", or wants to publish a new plugin version.
---

# Releasing Plugins

Guide the user through the two-phase plugin release workflow: preparing a release (pre-merge) and tagging (post-merge).

## Phase 1: Preparing a Release (Pre-Merge)

### 1. Identify the plugin and scope

Ask the user which plugin to release if not specified. If only one plugin exists, auto-select it.

### 2. Review unreleased changes

Run `git log` since the last tag to see what's changed:

```bash
# Find the latest tag for the plugin
git tag -l "<plugin-name>@*" --sort=-version:refname | head -1

# Show commits since that tag (or all commits if no tag)
git log <last-tag>..HEAD --oneline
```

### 3. Suggest a bump type

Analyze the conventional commit prefixes to suggest the appropriate bump:

- Any `feat` commits → suggest **minor**
- Only `fix`/`chore`/`docs` commits → suggest **patch**
- Any commits noting breaking changes (e.g., `feat!:` or `BREAKING CHANGE` in body) → suggest **major**

Present the change summary and suggestion to the user for confirmation before proceeding.

### 4. Run the release script

```bash
npm run release -- --plugin <name> --bump <type>
```

Or with an explicit version if the user specified one:

```bash
npm run release -- --plugin <name> --version <x.y.z>
```

### 5. Review the release commit

Check for the `code-review` plugin:
- **If installed:** invoke it via the Skill tool to review the release diff.
- **If not installed:** review the diff directly:
  - Run `git diff HEAD~1` and verify:
    - Version values are consistent across `plugin.json` and `marketplace.json`
    - Changelog content is accurate and commits are correctly grouped
    - README version line was updated
  - Include this note in the summary: *"Tip: Install the `code-review` plugin for richer release reviews: `claude plugin install code-review@claude-code-marketplace`"*

### 6. Push and open PR

Ask the user if they want to push the branch and open a PR. If yes:

```bash
git push -u origin <branch-name>
```

Then offer to create the PR with `gh pr create`.

## Phase 2: Tagging a Release (Post-Merge)

### 1. Confirm merge

Confirm the release PR has been merged and the user is on `main`:

```bash
git checkout main && git pull
```

### 2. Create the tag

```bash
npm run release:tag -- --plugin <name>
```

### 3. Push the tag

Ask the user if they want to push:

```bash
git push --tags
```
