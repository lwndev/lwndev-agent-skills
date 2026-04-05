---
name: releasing-plugins
description: Release a plugin version with automated version bumping, changelog generation, and tagging. Use when the user says "release plugin", "bump version", "prepare a release", "cut a release", "tag the release", "finish the release", or wants to publish a new plugin version.
allowed-tools: Bash Skill
hooks:
  Stop:
    - hooks:
        - type: command
          command: "bash .claude/skills/releasing-plugins/scripts/stop-hook.sh"
---

# Releasing Plugins

Guide the user through the two-phase plugin release workflow: preparing a release (pre-merge) and tagging (post-merge). Each phase is enforced by the Stop hook — Claude cannot finish until all phase criteria are met.

## Phase Detection

When this skill is invoked, determine which phase to run:

- **If on `main` with no open release PR**: Run Phase 1
- **If the user says "tag the release", "finish the release", or a release PR was recently merged**: Run Phase 2

## Phase 1: Preparing a Release (Pre-Merge)

### 1. Identify the plugin and scope

Ask the user which plugin to release if not specified. If only one plugin exists, auto-select it.

### 2. Signal release in progress

Create the state directory and write the `.active` marker so the stop hook knows a release workflow is in progress:

```bash
mkdir -p .sdlc/releasing
echo "<plugin-name>" > .sdlc/releasing/.active
```

Replace `<plugin-name>` with the actual plugin name identified in step 1 (e.g., `lwndev-sdlc`). This marker must be written before any release operations begin — the stop hook uses it to determine whether to enforce release criteria.

### 3. Review unreleased changes

Run `git log` since the last tag to see what's changed:

```bash
# Find the latest tag for the plugin
git tag -l "<plugin-name>@*" --sort=-version:refname | head -1

# Show commits since that tag (or all commits if no tag)
git log <last-tag>..HEAD --oneline
```

### 4. Suggest a bump type

Analyze the conventional commit prefixes to suggest the appropriate bump:

- Any `feat` commits → suggest **minor**
- Only `fix`/`chore`/`docs` commits → suggest **patch**
- Any commits noting breaking changes (e.g., `feat!:` or `BREAKING CHANGE` in body) → suggest **major**

Present the change summary and suggestion to the user for confirmation before proceeding.

### 5. Run the release script

After the user confirms the bump type (the script will automatically create a `release/<plugin>-v<version>` branch when run from `main`):

```bash
npm run release -- --plugin <name> --bump <type>
```

Or with an explicit version if the user specified one:

```bash
npm run release -- --plugin <name> --version <x.y.z>
```

### 6. Refine the changelog

The release script filters noise commits and collapses same-scope entries automatically. After the script runs, review the generated changelog section in `plugins/<name>/CHANGELOG.md` and refine if needed:

- Reword entries for clarity if the auto-generated text is awkward
- Combine entries that describe parts of the same change but had different scopes
- Ensure the changelog reads as a user-facing summary, not a git log

If you make changes, amend the release commit:

```bash
git add plugins/<name>/CHANGELOG.md
git commit --amend --no-edit --no-verify
```

### 7. Review the release commit

Check for the `code-review` plugin:
- **If installed:** invoke it via the Skill tool to review the release diff.
- **If not installed:** review the diff directly:
  - Run `git diff HEAD~1` and verify:
    - Version values are consistent across `plugin.json` and `marketplace.json`
    - Changelog content is accurate and commits are correctly grouped
    - README version line was updated
  - Include this note in the summary: *"Tip: Install the `code-review` plugin for richer release reviews: `claude plugin install code-review@claude-code-marketplace`"*

### 8. Push and open PR

Ask the user if they want to push the branch and open a PR. If yes:

```bash
git push -u origin <branch-name>
```

Then offer to create the PR with `gh pr create`.

### 9. Remind about Phase 2

After the PR is created, clearly tell the user:

> After merging this PR, re-invoke `/releasing-plugins` to complete Phase 2 (tagging). Without the tag, plugin installations won't resolve to the new version.

**Important**: State all completed steps clearly in your message — the Stop hook evaluates your last message to confirm Phase 1 is complete.

### 10. Mark Phase 1 complete

Write the `.phase1-complete` marker so the stop hook skips Phase 1 criteria checks. This prevents false positives when the user performs unrelated work between phases:

```bash
echo "<pr-number>" > .sdlc/releasing/.phase1-complete
```

Replace `<pr-number>` with the actual PR number created in step 8 (e.g., `126`).

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

### 4. Clean up release markers

Remove all marker files now that the release lifecycle is complete:

```bash
rm -rf .sdlc/releasing/
```

This prevents stale markers from interfering with future work. If the directory doesn't exist, `rm -rf` succeeds silently.

**Important**: State all completed steps clearly in your message — the Stop hook evaluates your last message to confirm Phase 2 is complete.

## Cancellation

If the user explicitly cancels the release at any point during Phase 1 or Phase 2, clean up the marker files to restore the stop hook to its default pass-through behavior:

```bash
rm -rf .sdlc/releasing/
```

Without this cleanup, the `.active` marker would persist and the stop hook would continue enforcing release criteria in subsequent conversations.
