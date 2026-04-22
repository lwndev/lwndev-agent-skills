---
name: documenting-features
description: Creates structured feature requirement documents for software features. Use when defining new features, writing requirements, specifying CLI commands, API endpoints, or when the user asks for feature documentation, requirements, specs, or PRDs.
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
argument-hint: "[feature-name or #issue-number]"
---

# Documenting Features

Create feature requirement documents capturing user stories, functional requirements, edge cases, and acceptance criteria.

## When to Use This Skill

- User requests feature requirements or specifications
- Defining a new CLI command or API endpoint
- Documenting expected behavior for implementation
- Creating acceptance criteria for a feature

## Flexibility

Adapt sections to feature type:

- **CLI commands**: full Command Syntax with arguments, options, examples
- **API endpoints**: API Integration section; skip Command Syntax
- **UI features**: user flows and interactions; skip command syntax
- **Internal features**: may skip user-facing sections

## Arguments

- **When argument is provided**: use it as a pre-filled feature name. If it uses `#<number>` syntax (e.g., `#14`) or Jira format (e.g., `PROJ-123`), delegate to the orchestrator or `managing-work-items fetch #N` (or `managing-work-items fetch PROJ-123`) to retrieve issue data, then pre-fill the template with the returned title and body. On fetch failure (missing issue, network error, auth failure), warn and continue with manual input.
- **When no argument is provided**: prompt interactively for scope, purpose, and details.

> **Note:** Direct `gh` CLI usage for issue fetch is replaced by `managing-work-items`, which handles GitHub Issues (`#N`) and Jira (`PROJ-123`) with auto-detection and graceful degradation. This skill lacks Bash in allowed-tools, so issue fetching must be delegated.

## Quick Start

1. Identify scope and purpose
2. **Ask for GitHub issue URL** if not provided (optional, recommended for traceability)
3. Define user story and priority
4. Document command syntax / API interface (if applicable)
5. List functional and non-functional requirements
6. Specify output format, edge cases, testing requirements

## Output Style

Follow the lite-narration rules below. Load-bearing carve-outs MUST be emitted as specified; they are not narration. This skill runs in the orchestrator's main conversation (feature chain step 1), so its output flows directly to the user.

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

- **Error messages from `fail` calls** -- users need the reason the skill halted. Surface script and tool stderr verbatim (e.g., `next-id.sh` / `slugify.sh` failures).
- **Security-sensitive warnings** -- destructive-operation confirmations, credential prompts.
- **Interactive prompts** -- any prompt that blocks the workflow and requires user input (e.g., the GitHub issue URL prompt, the feature scope prompt when no argument is provided, a re-slug prompt when `slugify.sh` returns empty).
- **Findings display from `reviewing-requirements`** -- N/A for this skill (it does not consume reviewing-requirements findings); bullet retained for consistency with the canonical template.
- **FR-14 console echo lines** -- `[model] step {N} ({skill}) -> {tier} (...)` audit-trail lines emitted by `prepare-fork.sh`. The Unicode `->` is the documented emitter format; do not rewrite to ASCII. (Typically not emitted here since this skill runs in main context, not forked, but retained for cross-skill consistency.)
- **Tagged structured logs** -- any line prefixed `[info]`, `[warn]`, or `[model]` is a structured log, not narration. Emit verbatim.
- **User-visible state transitions** -- pause, advance, and resume announcements (at most one line each).

### Fork-to-orchestrator return contract

`documenting-features` runs in **main context** (feature chain step 1), **not** as an Agent fork. It returns its result directly to the user, not to a parent orchestrator. The `done | artifact=<path> | <note>` / `failed | <reason>` shapes do **not** apply to this skill -- there is no subagent boundary. The lite narration rules and load-bearing carve-outs above still govern the skill's output.

**Precedence**: when a load-bearing carve-out (error message, `[warn]` structured log, interactive prompt, etc.) conflicts with a lite-narration rule, the carve-out wins and MUST be emitted verbatim even if it reads like narration.

## Feature ID Assignment

Allocate the next Feature ID:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/next-id.sh" FEAT
```

The script scans `requirements/features/` for `FEAT-NNN-*.md`, returns `max(NNN) + 1` zero-padded to three digits, and prints `001` when none exist. Exit codes: `0` success; `2` missing/invalid type arg.

## File Locations

- `requirements/features/` - Feature requirement documents
- `requirements/implementation/` - Implementation plans
- `docs/features/` - User-facing feature documentation

Filename format: `FEAT-XXX-{2-4-word-description}.md`. Derive the slug:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/slugify.sh" "<feature title>"
```

Lowercases, strips punctuation, drops stopwords (`a`, `an`, `the`, `of`, `for`, `to`, `and`, `or`), keeps the first four remaining tokens joined with `-`. Exit codes: `0` success; `1` empty slug after normalization (prompt for a more descriptive title); `2` missing arg.

## Template

See [assets/feature-requirements.md](assets/feature-requirements.md) for the full template.

### Structure Overview

```
# Feature Requirements: [Feature Name]
- Overview, Feature ID, GitHub Issue (optional), Priority
- User Story
- Command Syntax (for CLI) or API Integration (for APIs)
- Functional Requirements (FR-1, FR-2, ...)
- Output Format
- Non-Functional Requirements (NFR-1, NFR-2, ...)
- Dependencies
- Edge Cases
- Testing Requirements
- Acceptance Criteria
```

### Numbering Conventions

- **FR-1, FR-2**: Functional requirements - specific behaviors
- **NFR-1, NFR-2**: Non-functional requirements - performance, security, error handling

## Verification Checklist

Before finalizing:

- [ ] User story captures "who, what, why"
- [ ] All arguments/options documented with defaults
- [ ] Output format specified with example
- [ ] Error handling covers failure modes
- [ ] Edge cases identified
- [ ] Acceptance criteria testable

## Reference Examples

- [feature-requirements-example-search-command.md](references/feature-requirements-example-search-command.md) - CLI search command with API integration
- [feature-requirements-example-episodes-command.md](references/feature-requirements-example-episodes-command.md) - CLI command with date filtering and formatting

## Relationship to Other Skills

| Task Type | Recommended Approach |
|-----------|---------------------|
| New feature with requirements | Use this skill (`documenting-features`) |
| Chore/maintenance task | Use `documenting-chores` skill |
| Bug or defect report | Use `documenting-bugs` skill |

After documenting, run `/reviewing-requirements` to verify against codebase and docs. Then `/creating-implementation-plans`, `/documenting-qa` for the test plan, optionally `/reviewing-requirements` again for test-plan reconciliation. After `/implementing-plan-phases` and PR review, optionally `/reviewing-requirements` for code-review reconciliation, then `/executing-qa` to verify, and `/finalizing-workflow` to merge.
