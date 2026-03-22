---
name: releasing-plugins
description: Release a plugin version with automated version bumping, changelog generation, and tagging. Use when the user says "release plugin", "bump version", "prepare a release", "cut a release", "tag the release", "finish the release", or wants to publish a new plugin version.
allowed-tools: Bash Skill
hooks:
  Stop:
    - hooks:
        - type: prompt
          prompt: "You are evaluating whether Claude should stop. Context: $ARGUMENTS\n\nA prompt hook is a single-turn LLM call with no tool access — you can only evaluate based on the input fields provided, not by reading files.\n\nIf stop_hook_active is true in the input, respond {\"ok\": true} immediately to prevent infinite loops.\n\nOtherwise, examine last_assistant_message to determine which release phase is active:\n\n(1) PHASE 1 — Preparing a release (pre-merge): Claude's message should confirm ALL of the following before stopping:\n  - A release branch was created (not on main)\n  - The release script ran successfully (version bump, changelog, commit)\n  - The release commit was reviewed (version consistency verified)\n  - The branch was pushed to the remote\n  - A PR was opened (with a URL)\n  - Claude told the user to re-invoke this skill after merging for Phase 2 (tagging)\n\n(2) PHASE 2 — Tagging a release (post-merge): Claude's message should confirm ALL of the following before stopping:\n  - Confirmed the release PR was merged and on main\n  - The git tag was created via the release:tag script\n  - The tag was pushed to the remote\n\nRespond {\"ok\": true} if all criteria for the current phase are met, or {\"ok\": false, \"reason\": \"what remains incomplete\"} if not."
          model: haiku
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

### 2. Create a release branch

Before making any changes, create and switch to a release branch:

```bash
git checkout -b release/<plugin-name>-v<version>
```

Note: You won't know the exact version yet. First determine the bump type (step 4), then create the branch with the correct version before running the release script.

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

After the user confirms the bump type and you've created the release branch:

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

**Important**: State all completed steps clearly in your message — the Stop hook evaluates your last message to confirm Phase 2 is complete.
