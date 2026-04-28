---
name: documenting-bugs
description: Creates structured bug report documents for tracking defects and issues. Use when the user needs to document a bug, unexpected behavior, regression, UI/UX defect, performance issue, or security vulnerability with root cause analysis and traceable acceptance criteria.
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
argument-hint: "[bug-title]"
---

# Documenting Bugs

Create structured bug reports that capture defects with reproduction steps, severity, root-cause analysis, and acceptance criteria traceable to each underlying cause.

## When to Use This Skill

- Reported bugs or unexpected behavior
- Regressions in previously working functionality
- UI/UX defects or visual glitches
- Performance issues or resource problems
- Security vulnerabilities or auth bypasses
- Any defect that requires root cause analysis before fixing

## Arguments

- **When argument is provided**: use it as a pre-filled bug title.
- **When no argument is provided**: prompt interactively for the bug details.

## Quick Start

1. **Ask for GitHub issue URL** if not provided (optional, recommended for traceability)
2. Identify the bug category (see [references/categories.md](references/categories.md)) and severity
3. **Investigate the codebase** — read files, trace call paths, identify root causes before finalizing
4. Allocate ID, slugify, and render the template in one shot:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/new-requirement.sh" BUG "<bug title>" \
     [--issue <ref>] [--category <name>] [--severity <name>]
   ```

   Composes `next-id.sh` + `slugify.sh` + the BUG template at
   `assets/bug-document.md`. Writes
   `requirements/bugs/BUG-{NNN}-{slug}.md` and prints the path on
   stdout. `--category` and `--severity` are validated against the
   enums below; invalid values fail with exit 2. Re-runs allocate a
   fresh ID monotonically; never overwrites.
5. Fill in description, steps to reproduce, expected/actual behavior, root causes (with `RC-N` IDs), affected files, and acceptance criteria (each tagged `(RC-N)`).

## Output Style

Follow the lite-narration rules below. Load-bearing carve-outs MUST be emitted as specified; they are not narration. This skill runs in the orchestrator's main conversation (bug chain step 1), so its output flows directly to the user.

### Lite narration rules

- No preamble before tool calls. Do not announce "let me check" or "I'll run" -- issue the tool call.
- No end-of-turn summaries beyond one short sentence. Do not recap what the user can read from tool output (e.g., the written requirement document).
- No emoji. ASCII punctuation only.
- No restating what the user just said.
- No status echoes that tools already show (e.g., successful `Write` confirmations).
- Prefer ASCII arrows (`->`) and punctuation over Unicode alternatives in skill-authored prose. Existing Unicode em dashes in tables and reference docs are retained.
- Short sentences over paragraphs. Bullet lists over prose when listing more than two items.

### Load-bearing carve-outs (never strip)

The following MUST always be emitted even when they resemble narration:

- **Error messages from `fail` calls** -- users need the reason the skill halted. Surface script and tool stderr verbatim (e.g., `new-requirement.sh` / `validate-categories.sh` / `validate-rc-traceability.sh` failures, including the embedded `next-id.sh` / `slugify.sh` errors).
- **Security-sensitive warnings** -- destructive-operation confirmations, credential prompts.
- **Interactive prompts** -- any prompt that blocks the workflow and requires user input (e.g., the GitHub issue URL prompt, the bug details prompt when no argument is provided, a re-slug prompt when `slugify.sh` returns empty).
- **Findings display from `reviewing-requirements`** -- N/A for this skill (it does not consume reviewing-requirements findings); bullet retained for consistency with the canonical template.
- **FR-14 console echo lines** -- `[model] step {N} ({skill}) -> {tier} (...)` audit-trail lines emitted by `prepare-fork.sh`. The Unicode `->` is the documented emitter format; do not rewrite to ASCII. (Typically not emitted here since this skill runs in main context, not forked, but retained for cross-skill consistency.)
- **Tagged structured logs** -- any line prefixed `[info]`, `[warn]`, or `[model]` is a structured log, not narration. Emit verbatim.
- **User-visible state transitions** -- pause, advance, and resume announcements (at most one line each).

### Fork-to-orchestrator return contract

`documenting-bugs` runs in **main context** (bug chain step 1), **not** as an Agent fork. It returns its result directly to the user, not to a parent orchestrator. The `done | artifact=<path> | <note>` / `failed | <reason>` shapes do **not** apply to this skill -- there is no subagent boundary. The lite narration rules and load-bearing carve-outs above still govern the skill's output.

**Precedence**: when a load-bearing carve-out (error message, `[warn]` structured log, interactive prompt, etc.) conflicts with a lite-narration rule, the carve-out wins and MUST be emitted verbatim even if it reads like narration.

## File Location

All bug documents live in `requirements/bugs/`. Filename format: `BUG-XXX-{2-4-word-description}.md`. ID and slug are produced by `new-requirement.sh` (Quick Start step 4); on slugify failure (exit 2) prompt for a more descriptive title and retry.

Examples:
- `BUG-001-auth-token-expired.md`
- `BUG-002-broken-csv-export.md`
- `BUG-003-memory-leak-polling.md`

## Template

See [assets/bug-document.md](assets/bug-document.md) for the full template.

### Structure Overview

```
# Bug: [Brief Title]
- Bug ID, GitHub Issue (optional), Category, Severity
- Description (1-2 sentences)
- Steps to Reproduce
- Expected Behavior
- Actual Behavior
- Root Cause(s) — numbered entries with file references
- Affected Files
- Acceptance Criteria — with (RC-N) traceability tags
- Completion (status, date, PR link)
- Notes (optional)
```

## Categories

Six supported categories:

| Category | Use For |
|----------|---------|
| `runtime-error` | Crashes, unhandled exceptions, fatal errors |
| `logic-error` | Incorrect behavior, wrong calculations, bad state |
| `ui-defect` | Visual glitches, layout issues, rendering problems |
| `performance` | Slowness, memory leaks, resource exhaustion |
| `security` | Vulnerabilities, auth bypasses, data exposure |
| `regression` | Previously working functionality that broke |

See [references/categories.md](references/categories.md) for per-category guidance.

## Severity Levels

| Severity | Definition |
|----------|------------|
| `critical` | Application unusable, data loss, security breach |
| `high` | Major feature broken, no workaround |
| `medium` | Feature impaired, workaround exists |
| `low` | Minor issue, cosmetic, edge case |

## Verification Checklist

Before finalizing:

- [ ] Bug ID is unique (`new-requirement.sh` guarantees this; never overwrites)
- [ ] Category validates against the enum:

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/validate-categories.sh" BUG "<category>"
  ```

  Exit 0 = valid, exit 2 + `error: invalid bug category '...'` = invalid (re-prompt).
- [ ] Severity reflects actual impact
- [ ] Steps to reproduce are clear and complete
- [ ] Root causes are investigated and documented with file references
- [ ] RC <-> AC round-trip enforced (every RC has >= 1 AC; every AC has `(RC-N)` tag):

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/skills/documenting-bugs/scripts/validate-rc-traceability.sh" \
    "requirements/bugs/BUG-{NNN}-{slug}.md"
  ```

  Exit 0 = round-trip satisfied. Exit 1 + JSON `{"missingRCs":[...],"untaggedACs":[...]}` = violations (fix and re-run). Exit 2 = file unreadable or missing required section.
- [ ] Affected files list is complete
- [ ] GitHub issue is linked (if one exists)

## Relationship to Other Skills

| Task Type | Recommended Approach |
|-----------|---------------------|
| New feature with requirements | Use `documenting-features` skill |
| Chore/maintenance task | Use `documenting-chores` skill |
| Bug or defect report | Use this skill (`documenting-bugs`) |
| Quick fix (no tracking needed) | Direct implementation |

After documenting, run `/reviewing-requirements` to verify against codebase and docs, then `/documenting-qa` for the test plan. Optionally run `/reviewing-requirements` again for test-plan reconciliation. Then `/executing-bug-fixes` to implement. After PR review, optionally `/reviewing-requirements` for code-review reconciliation, then `/executing-qa` to verify, and `/finalizing-workflow` to merge.
