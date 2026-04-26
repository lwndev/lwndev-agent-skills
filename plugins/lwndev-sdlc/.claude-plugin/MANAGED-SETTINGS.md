# Hook D — Managed-Settings Defense in Depth

## What this is

`managed-settings.example.json` ships a `permissions.deny` list covering the
destructive Bash patterns guarded by Hook B (`guard-state-transitions.sh`).
Hook D is the defense-in-depth backstop: if a session disables the
`lwndev-sdlc` plugin (or hooks A-C are otherwise unloaded), the destructive
patterns remain blocked at the Claude Code permission layer.

## Why managed-settings scope (not user / project)

Per [Claude Code's settings documentation](https://docs.claude.com/en/docs/claude-code/settings), managed
settings are installed by an administrator (org IT, team lead, repo owner) at
a path that **users cannot override** from their own `.claude/settings.json`
or project `.claude/settings.local.json`. This survives:

- A user disabling the `lwndev-sdlc` plugin mid-session (hooks A-C unload;
  Hook D remains).
- A user adding a permissive `permissions.allow` entry in their personal
  settings (managed-settings deny rules win over user-settings allow rules).
- An in-session agent attempting to write into the user's settings file.

User-scope or project-scope deny lists are bypassable by the same in-session
agent we are trying to constrain, so they do NOT satisfy AC10.

## Install paths

Per Claude Code conventions:

- **macOS**: `/Library/Application Support/ClaudeCode/managed-settings.json`
- **Linux / WSL**: `/etc/claude-code/managed-settings.json`
- **Windows**: `C:\ProgramData\ClaudeCode\managed-settings.json`

Copy `managed-settings.example.json` to the appropriate path with admin
privileges. Verify the file is owned by root (or Administrator on Windows)
and is not writable by the unprivileged user.

## What this does NOT cover

- Per AC6 the prefix-glob list documents what is in scope. Patterns NOT
  guarded here:
  - `rm -rf` (general filesystem) — too broad to gate at this layer.
  - Database drops, container teardown, etc. — project-specific; add to
    your local managed-settings file as needed.
- Hook D enforces the deny list every time, but it does NOT distinguish
  authorized merges from unauthorized merges. A legitimate `gh pr merge`
  invoked by `finalizing-workflow` after the user typed `merge <ID>` will
  also be blocked at this layer.
- Therefore Hook D is **opt-in**: install only if your team's policy is "no
  destructive Bash from Claude Code, ever". Most teams will rely on Hook B's
  marker-based guard alone, with Hook D reserved for high-value repos.

## Rollout checklist

1. Review the prefix-glob list in `managed-settings.example.json` and add
   project-specific patterns if needed.
2. Install at the managed-settings path on every developer workstation that
   runs Claude Code against this repo.
3. Verify enforcement: try `gh pr merge <N>` from a Claude Code session
   without an active workflow; it should be denied at the permission layer
   even with `lwndev-sdlc` disabled.
4. Document the install in the team's onboarding runbook; new developers
   need the managed-settings file installed before their first Claude Code
   session.
