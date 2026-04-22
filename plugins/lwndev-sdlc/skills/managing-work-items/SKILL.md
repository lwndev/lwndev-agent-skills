---
name: managing-work-items
description: Centralizes issue tracker operations (GitHub Issues, Jira) into a single delegatable skill. Handles fetch and comment operations with automatic backend detection from issue reference format. Use when the orchestrator needs to fetch issue data, post status comments, generate PR body issue links, or extract issue references from requirement documents.
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
argument-hint: "<operation> <issue-ref> [--type <comment-type>] [--context <json>]"
---

# Managing Work Items

Centralized issue tracker operations for GitHub Issues and Jira, invoked by the orchestrator at workflow integration points.

## When to Use This Skill

- Fetch issue data to pre-fill a requirements document
- Post a status comment (phase-start, phase-completion, work-start, work-complete, bug-start, bug-complete)
- Generate the PR body issue link (`Closes #N` or `PROJ-123`)
- Extract the issue reference from a requirement document's `## GitHub Issue` section

This `SKILL.md` is a **reference document read inline by the orchestrator's main context** — the orchestrator `Read`s it once at workflow start and then executes the documented `gh` / Jira backend commands directly using its existing `Bash`, `Read`, and `Glob` access. It is **not** forked via the Agent tool and **not** invoked via the Skill tool; all invocations are inline per the "How to Invoke `managing-work-items`" subsection in `orchestrating-workflows/SKILL.md`. Operations are **supplementary** and must **never** block workflow progression — graceful degradation (NFR-1) governs every call site, so any backend or tool failure logs and skips rather than halting.

## Arguments

The skill accepts the following invocation syntax:

```
managing-work-items <operation> <issue-ref> [--type <comment-type>] [--context <json>]
```

### Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `<operation>` | Yes | One of: `fetch`, `comment`, `pr-link`, `extract-ref` |
| `<issue-ref>` | Yes (for `fetch`, `comment`, `pr-link`) | Issue reference: `#N` (GitHub) or `PROJ-123` (Jira) |
| `--type` | Yes (for `comment`) | Comment type: `phase-start`, `phase-completion`, `work-start`, `work-complete`, `bug-start`, `bug-complete` |
| `--context` | Yes (for `comment`) | JSON string with template variables |

### Operations

| Operation | Description | Example |
|-----------|-------------|---------|
| `fetch` | Retrieve issue details (title, body, labels, state, assignees) | `managing-work-items fetch #119` |
| `comment` | Post a formatted comment using type-specific templates | `managing-work-items comment #119 --type phase-start --context '{"phase": 1, "name": "GitHub Backend"}'` |
| `pr-link` | Generate the auto-close syntax for a PR body | `managing-work-items pr-link #119` |
| `extract-ref` | Extract issue reference from a requirement document | `managing-work-items extract-ref requirements/features/FEAT-012.md` |

## Output Style

Follow the lite-narration rules below. Load-bearing carve-outs MUST be emitted as specified; they are not narration. This skill is executed inline from the orchestrator's main context (not forked via the Agent tool), so its output flows directly through the main conversation.

### Lite narration rules

- No preamble before tool calls. Do not announce "let me check" or "I'll run" -- issue the tool call.
- No end-of-turn summaries beyond one short sentence. Do not recap what the user can read from tool output (e.g., `gh issue view` JSON, `gh issue comment` confirmation URLs).
- No emoji. ASCII punctuation only.
- No restating what the user just said.
- No status echoes that tools already show (e.g., the contents of a successful `gh auth status`).
- Prefer ASCII arrows (`->`) and punctuation over Unicode alternatives in skill-authored prose. Existing Unicode em dashes in tables and reference docs are retained. **Tool-emitted output is out of scope** — `gh` / `acli` / Rovo MCP stdout and JSON responses use their documented format and must be surfaced verbatim when load-bearing.
- Short sentences over paragraphs. Bullet lists over prose when listing more than two items.

### Load-bearing carve-outs (never strip)

The following MUST always be emitted even when they resemble narration:

- **Error messages from `fail` calls** -- users need the reason the operation halted. Surface `gh` / `acli` / Rovo MCP stderr verbatim.
- **Security-sensitive warnings** -- destructive-operation confirmations, credential prompts, auth-failure notices (`gh auth login`, Rovo OAuth consent, `acli` credentials).
- **Interactive prompts** -- any prompt that blocks workflow progression must be visible. (Typically none for this skill; issue operations are non-interactive.)
- **Findings display from `reviewing-requirements`** -- N/A for this skill (it does not consume reviewing-requirements findings); bullet retained for consistency with the canonical template.
- **FR-14 console echo lines** -- `[model] step {N} ({skill}) → {tier} (...)` audit-trail lines emitted by `prepare-fork.sh`. The Unicode `→` is the documented emitter format; do not rewrite to ASCII. (Typically not emitted here since this skill is inline, not forked, but retained for cross-skill consistency.)
- **Tagged structured logs** -- any line prefixed `[info]`, `[warn]`, or `[model]` is a structured log, not narration. Emit verbatim. Per `orchestrating-workflows/references/issue-tracking.md`, WARNING-level mechanism-failure lines (e.g., `[warn] gh CLI not found on PATH`, `[warn] Rovo MCP authorization failed`) are load-bearing and MUST be emitted verbatim.
- **User-visible state transitions** -- skip notices (graceful-degradation info lines), tier fall-through notices, and operation confirmations (at most one line each).

### Inline execution note

`managing-work-items` is invoked **inline from the orchestrator's main context** (per `orchestrating-workflows/references/issue-tracking.md`), NOT spawned via the Agent tool. The fork-to-orchestrator return contract (`done | artifact=<path> | <note>` / `failed | <reason>`) does **not** apply here — there is no subagent boundary. Tool-call results (`gh issue comment` exit codes, `gh issue view` JSON payloads, `acli` stdout, Rovo MCP responses) are consumed directly by the main context.

**Precedence (in spirit)**: when a `[warn]` mechanism-failure line needs to be emitted (per the issue-tracking.md mechanism-failure table), that line is load-bearing and MUST be emitted verbatim even if it reads like narration. The lite rules do not override WARNING-level structured-log emission.

## Backend Detection (FR-1)

Detect the backend from the issue reference format:

| Format | Pattern | Backend |
|--------|---------|---------|
| `#N` | `#` followed by one or more digits | GitHub Issues (via `gh` CLI) |
| `PROJ-123` | Alphabetic/alphanumeric project key + `-` + digits | Jira (via tiered fallback) |
| Empty/absent | No reference provided | Skip all operations gracefully |

### Detection Logic

1. Parse the reference: `^#(\d+)$` -> GitHub (extract `N`); `^([A-Z][A-Z0-9]*)-(\d+)$` -> Jira (extract key + number); empty/null/absent -> log info ("No issue reference provided, skipping issue operations") and return.
2. Route to the matching backend.

## GitHub Issues Backend (FR-2)

All GitHub operations use the `gh` CLI. Verify availability and auth before any operation.

### Fetch Operation

```bash
gh issue view <N> --json title,body,labels,state,assignees
```

Returns a JSON object with `title`, `body`, `labels`, `state`, `assignees`. Used to pre-fill requirements documents and verify the issue exists.

### Comment Operation

```bash
gh issue comment <N> --body "<formatted-comment>"
```

The body is rendered from the matching template in [references/github-templates.md](references/github-templates.md) (selected by `--type`); `--context` JSON variables are substituted in.

## Comment Type Routing (FR-5)

Map `--type` to the correct template and populate it with context data:

| Comment Type | Template | Context Variables |
|-------------|----------|-------------------|
| `phase-start` | Phase start template | `phase` (number), `name` (phase name), `steps` (list), `deliverables` (list), `workItemId` (FEAT-XXX) |
| `phase-completion` | Phase completion template | `phase` (number), `name` (phase name), `deliverables` (verified list), `commitSha` (short SHA), `workItemId` (FEAT-XXX) |
| `work-start` | Work start template | `choreId` (CHORE-XXX), `criteria` (acceptance criteria list), `branch` (branch name) |
| `work-complete` | Work complete template | `choreId` (CHORE-XXX), `prNumber` (PR number), `criteria` (verified criteria list) |
| `bug-start` | Bug start template | `bugId` (BUG-XXX), `severity` (level), `rootCauses` (RC-N list), `criteria` (acceptance criteria list), `branch` (branch name) |
| `bug-complete` | Bug complete template | `bugId` (BUG-XXX), `prNumber` (PR number), `rootCauseResolutions` (RC-N resolution table), `verificationResults` (list) |

### Rendering Process

1. Look up the template in [references/github-templates.md](references/github-templates.md) (GitHub) or [references/jira-templates.md](references/jira-templates.md) (Jira/Rovo MCP) by `--type`.
2. Parse `--context` JSON for variables.
3. Substitute:
   - **GitHub**: replace `<PLACEHOLDER>` with values; expand list placeholders into markdown lists.
   - **Jira (Rovo MCP)**: replace `{placeholder}` values in ADF JSON; generate ADF `listItem` nodes for list variables (steps, deliverables, criteria, rootCauses). Output must be valid ADF.
   - **Jira (acli)**: use markdown (same as GitHub). `acli` handles ADF conversion internally.
4. Post the rendered comment via the matching backend.

## PR Body Issue Link Generation (FR-6)

Backend-specific auto-close syntax for PR bodies:

| Backend | Output | Effect |
|---------|--------|--------|
| GitHub | `Closes #N` | Auto-closes the issue when the PR is merged |
| Jira | `PROJ-123` | Jira auto-transition relies on the branch name containing the issue key |
| No reference | Empty string | No issue link in PR body |

The orchestrator calls `pr-link` at PR creation and includes the result in the PR body's "Related" section.

## Issue Reference Extraction from Documents (FR-7)

Extract the issue reference from a requirement document's `## GitHub Issue` section (also accept `## Issue` / `## Issue Tracker`).

### Extraction Logic

1. Read the requirement document.
2. Find the `## GitHub Issue` section (also `## Issue`, `## Issue Tracker`).
3. Parse for `[#N](URL)` -> `#N` (GitHub) or `[PROJ-123](URL)` -> `PROJ-123` (Jira).
4. Return the first match, or `null` if the section is empty or missing.

**Example**:
```markdown
## GitHub Issue
[#119](https://github.com/lwndev/lwndev-marketplace/issues/119)
```

Extracted: `#119`.

## Jira Backend (FR-3) -- Tiered Fallback

Jira uses a tiered fallback. Tiers are tried in order; the first available backend wins:

1. **Tier 1 -- Rovo MCP**: if the `rovo` MCP server is registered, use Rovo MCP tools. Comments must be in Atlassian Document Format (ADF) JSON -- see [references/jira-templates.md](references/jira-templates.md).
2. **Tier 2 -- Atlassian CLI (`acli`)**: if `acli` is on PATH (`which acli`), use `acli jira workitem` subcommands. `acli` accepts markdown and handles ADF conversion internally.
3. **Tier 3 -- Skip**: if neither is available, log "No Jira backend available (Rovo MCP not registered, acli not found). Skipping Jira operations." and return without failing.

### Tier Detection Logic

```
1. Tier 1 (Rovo MCP): if rovo MCP is registered and responsive -> use it.
   Otherwise log "Rovo MCP server not available, trying acli fallback" -> Tier 2.
2. Tier 2 (acli): if `which acli` finds it -> use it.
   Otherwise log "acli CLI not found on PATH" -> Tier 3.
3. Tier 3: log the no-backend warning above and return.
```

### Jira Fetch Operation

Retrieve issue details (title/summary, description, labels, status, assignees).

**Via Rovo MCP (Tier 1):**

```
getJiraIssue(cloudId, issueIdOrKey)
```

- `cloudId`: Atlassian Cloud ID (from MCP server config or env)
- `issueIdOrKey`: e.g., `PROJ-123` or `PROJ2-456`

Returns the issue object including `fields.summary`, `fields.description` (ADF), `fields.labels`, `fields.status.name`, `fields.assignee`.

**Via acli (Tier 2):**

```bash
acli jira workitem view --key PROJ-123
```

Returns structured text — parse for title, description, status, assignee, labels.

**On failure**: log full output and skip. Example: `Warning: Jira fetch failed for PROJ-123 via [Rovo MCP|acli]. Output: <error details>. Skipping.`

### Jira Comment Operation

Post a formatted comment using the matching template from [references/jira-templates.md](references/jira-templates.md).

**Via Rovo MCP (Tier 1):**

```
addCommentToJiraIssue(cloudId, issueIdOrKey, commentBody)
```

- `cloudId`: Atlassian Cloud ID
- `issueIdOrKey`: e.g., `PROJ-123`
- `commentBody`: comment in **ADF JSON format** (required by the Jira REST API)

`commentBody` must be valid ADF. Load the template by `--type` from [references/jira-templates.md](references/jira-templates.md), substitute context variables into the ADF JSON, and pass the result as `commentBody`.

**Via acli (Tier 2):**

```bash
acli jira workitem comment-create --key PROJ-123 --body "<markdown-comment>"
```

`acli` takes **markdown** (not ADF) and handles ADF conversion internally. Use the markdown format from [references/github-templates.md](references/github-templates.md) as a reference, adapting GitHub references (issue numbers, PR links) to Jira equivalents (issue keys, PR URLs).

**On failure**: log and skip. If Tier 1 fails, fall through to Tier 2 before skipping entirely.

### Jira PR Body Link Generation (FR-6)

For Jira, the PR body link is the issue key itself:

```
PROJ-123
```

Auto-transition relies on the **branch name** containing the issue key (e.g., `feat/PROJ-123-feature-name`), not a `Closes` keyword. The issue key in the PR body is for traceability only.

### Jira-Specific Error Handling

| Error Type | Tier | Response |
|-----------|------|----------|
| Rovo MCP server not registered | Tier 1 | Log: "Rovo MCP server not available, trying acli fallback." Fall through to Tier 2. |
| Rovo MCP tool call timeout | Tier 1 | Log: "Rovo MCP tool `<toolName>` timed out. Falling through to acli." Fall through to Tier 2. |
| Rovo MCP unexpected response | Tier 1 | Log: "Rovo MCP tool `<toolName>` returned unexpected response: <details>. Falling through to acli." Fall through to Tier 2. |
| Rovo MCP authorization error | Tier 1 | Log: "Rovo MCP authorization failed -- check OAuth consent or API token configuration." Fall through to Tier 2. |
| Rovo MCP server disconnection | Tier 1 | Log: "Rovo MCP server disconnected during `<toolName>`. Falling through to acli." Fall through to Tier 2. |
| `acli` not on PATH | Tier 2 | Log: "acli CLI not found on PATH." Fall through to Tier 3 (skip). |
| `acli` authentication error | Tier 2 | Log: "Atlassian CLI not authenticated -- check `acli` credentials configuration." Skip operation. |
| `acli` command failure | Tier 2 | Log: "acli command failed: <full output>." Skip operation. |
| `acli` network error | Tier 2 | Log: "acli network request failed. Skipping Jira operation." Skip operation. |
| Issue not found (any tier) | Any | Log: "Jira issue PROJ-123 not found. Skipping." Skip operation. |

### Alphanumeric Project Keys

Jira keys may contain digits after the first character (e.g., `PROJ2-123`, `AB1-456`). The detection regex `^([A-Z][A-Z0-9]*)-(\d+)$` covers these. Valid examples: `PROJ-123` (standard), `PROJ2-456` (alphanumeric), `AB1-789` (short alphanumeric), `MYTEAM-1` (longer key, single-digit number).

## Graceful Degradation (NFR-1) and Error Handling (NFR-2)

Issue tracker operations are supplementary -- they must **never** block workflow progression. All failure modes degrade gracefully (NFR-1); NFR-2 reuses the same skip/fall-through responses with no separate behavior.

| Failure | Backend | Response |
|---------|---------|----------|
| `gh` CLI not installed or not on PATH | GitHub | Log warning: "GitHub CLI (`gh`) not found on PATH. Skipping GitHub issue operations." Skip operation. |
| `gh` not authenticated | GitHub | Log: "GitHub CLI not authenticated -- run `gh auth login` to enable issue tracking." Skip operation. |
| Network unavailable | GitHub | Log: "Network request failed. Skipping issue operation." Skip operation. |
| Rate limited | GitHub | Log: "GitHub API rate limit reached. Skipping issue operation." Skip operation. Do not retry. |
| Issue does not exist | GitHub | Log: "`gh issue view` returned not found for #N. Skipping." Skip operation. |
| Command failure (non-zero exit) | Any | Log error with full command output. Skip operation. Continue workflow. |
| Timeout | Any | Log warning with timeout duration. Skip. |
| Jira backend unavailable | Jira | Fall through tiered selection (Rovo MCP -> acli -> skip). Log which tier was attempted. |
| MCP tool invocation failure | Jira | Log error with tool name and response. Fall through to `acli` tier. |
| Rovo MCP authorization error | Jira | Log "Rovo MCP authorization failed -- check OAuth consent or API token configuration." Fall through to `acli`. |
| MCP server disconnection | Jira | Log error with tool name. Fall through to `acli`. |
| `acli` not authenticated | Jira | Log: "Atlassian CLI not authenticated -- check `acli` credentials configuration." Skip. |

(See "Jira-Specific Error Handling" above for the per-tier Jira matrix that this table summarizes.)

### Implementation Pattern

Wrap every external command in an exit-code check (try/catch equivalent):

```bash
# Example: GitHub comment with graceful degradation
if ! command -v gh &>/dev/null; then
  echo "Warning: gh CLI not found. Skipping issue comment."
  return
fi

if ! gh auth status &>/dev/null 2>&1; then
  echo "Warning: gh CLI not authenticated. Run 'gh auth login'. Skipping issue comment."
  return
fi

if ! gh issue comment <N> --body "<comment>" 2>&1; then
  echo "Warning: Failed to post issue comment. Continuing workflow."
fi
```

## Idempotency (NFR-3)

- **Comments are safe to retry.** A duplicate comment is acceptable -- better than a missing one.
- **Fetch is inherently idempotent** -- read-only, no side effects.
- **PR link generation is pure** -- same input always yields the same result.
- **Workflow re-runs/resumes** can re-execute issue operations freely; the orchestrator does not need to track prior calls.

## Workflow

```
1. Receive: <operation> <issue-ref> [--type <type>] [--context <json>]
2. Detect backend (FR-1): #N -> GitHub; PROJ-123 (incl. PROJ2-123) -> Jira; empty -> skip.
3. If no reference -> log info, return.
4. If GitHub (#N): verify gh available + authenticated; run operation (fetch/comment) via gh; on failure log warning + skip.
5. If Jira (PROJ-123):
   a. Tier 1 (Rovo MCP): if available, run via getJiraIssue / addCommentToJiraIssue; for comments, load ADF template, substitute, pass as commentBody. On MCP failure (timeout, auth, unexpected, disconnect) -> log + fall through to Tier 2.
   b. Tier 2 (acli): if available, run via `acli jira workitem view` / `comment-create`; comments use markdown (acli converts to ADF). On failure -> fall through to Tier 3.
   c. Tier 3: log "No Jira backend available. Skipping Jira operations." Return without failing.
6. Return result (fetch data, confirmation, or skip notice).
```

## References

- **GitHub comment templates**: [github-templates.md](references/github-templates.md) - markdown templates for all six comment types, plus commit messages, PR body, issue creation
- **Jira comment templates**: [jira-templates.md](references/jira-templates.md) - ADF JSON templates for all six comment types (Rovo MCP path; `acli` path uses markdown)
