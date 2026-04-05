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

- Orchestrator needs to fetch issue data to pre-fill a requirements document
- Orchestrator needs to post a status comment (phase start, phase completion, work start, work complete, bug start, bug complete) on an issue
- Orchestrator needs to generate the PR body issue link (`Closes #N` or `PROJ-123`)
- Orchestrator needs to extract the issue reference from a requirement document's `## GitHub Issue` section

This skill is invoked by the orchestrator -- not directly by users. All operations are supplementary to the workflow and must never block workflow progression on failure.

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

## Backend Detection (FR-1)

Automatically detect the issue tracker backend from the issue reference format:

| Format | Pattern | Backend |
|--------|---------|---------|
| `#N` | `#` followed by one or more digits | GitHub Issues (via `gh` CLI) |
| `PROJ-123` | Alphabetic/alphanumeric project key + `-` + digits | Jira (via tiered fallback) |
| Empty/absent | No reference provided | Skip all operations gracefully |

### Detection Logic

1. **Parse the issue reference**:
   - If it matches `^#(\d+)$` -- GitHub Issues. Extract the number `N`.
   - If it matches `^([A-Z][A-Z0-9]*)-(\d+)$` -- Jira. Extract the project key and issue number.
   - If the reference is empty, null, or absent -- log an info message ("No issue reference provided, skipping issue operations") and return immediately.
2. **Route to the appropriate backend** based on the detected format.

## GitHub Issues Backend (FR-2)

All GitHub operations use the `gh` CLI. Before executing any operation, verify the CLI is available and authenticated.

### Fetch Operation

Retrieve issue details and return structured data:

```bash
gh issue view <N> --json title,body,labels,state,assignees
```

**Returns**: JSON object with `title`, `body`, `labels`, `state`, `assignees` fields.

**Usage**: Pre-fill requirements documents, verify issue exists before starting a workflow.

### Comment Operation

Post a formatted comment to the issue:

```bash
gh issue comment <N> --body "<formatted-comment>"
```

The comment body is formatted using the appropriate template from [references/github-templates.md](references/github-templates.md) based on the `--type` argument. Template variables from the `--context` JSON are substituted into the template.

## Comment Type Routing (FR-5)

Map the `--type` argument to the correct template and populate it with context data:

| Comment Type | Template | Context Variables |
|-------------|----------|-------------------|
| `phase-start` | Phase start template | `phase` (number), `name` (phase name), `steps` (list), `deliverables` (list), `workItemId` (FEAT-XXX) |
| `phase-completion` | Phase completion template | `phase` (number), `name` (phase name), `deliverables` (verified list), `commitSha` (short SHA), `workItemId` (FEAT-XXX) |
| `work-start` | Work start template | `choreId` (CHORE-XXX), `criteria` (acceptance criteria list), `branch` (branch name) |
| `work-complete` | Work complete template | `choreId` (CHORE-XXX), `prNumber` (PR number), `criteria` (verified criteria list) |
| `bug-start` | Bug start template | `bugId` (BUG-XXX), `severity` (level), `rootCauses` (RC-N list), `criteria` (acceptance criteria list), `branch` (branch name) |
| `bug-complete` | Bug complete template | `bugId` (BUG-XXX), `prNumber` (PR number), `rootCauseResolutions` (RC-N resolution table), `verificationResults` (list) |

### Rendering Process

1. Look up the template in [references/github-templates.md](references/github-templates.md) (for GitHub) or [references/jira-templates.md](references/jira-templates.md) (for Jira/Rovo MCP) based on the `--type` value.
2. Parse the `--context` JSON to extract template variables.
3. Substitute variables into the template:
   - **GitHub**: Replace `<PLACEHOLDER>` with actual values, expand list placeholders into formatted markdown lists.
   - **Jira (Rovo MCP)**: Replace `{placeholder}` values in the ADF JSON structure. For list context variables (steps, deliverables, criteria, rootCauses), generate the appropriate ADF `listItem` nodes dynamically. The resulting JSON must be valid ADF.
   - **Jira (acli)**: Use markdown format (same approach as GitHub). `acli` handles ADF conversion internally.
4. Post the rendered comment via the appropriate backend.

## PR Body Issue Link Generation (FR-6)

Generate the appropriate auto-close syntax for PR bodies based on the detected backend:

| Backend | Output | Effect |
|---------|--------|--------|
| GitHub | `Closes #N` | Auto-closes the issue when the PR is merged |
| Jira | `PROJ-123` | Jira auto-transition relies on the branch name containing the issue key |
| No reference | Empty string | No issue link in PR body |

**Usage**: The orchestrator calls `pr-link` at PR creation to get the correct syntax, then includes it in the PR body's "Related" section.

## Issue Reference Extraction from Documents (FR-7)

Extract the issue reference from a requirement document by reading the `## GitHub Issue` section (or `## Issue` / `## Issue Tracker` for future compatibility):

### Extraction Logic

1. Read the requirement document.
2. Find the `## GitHub Issue` section (also check `## Issue` and `## Issue Tracker`).
3. Parse the section content for issue reference patterns:
   - `[#N](URL)` -- extract `#N` (GitHub)
   - `[PROJ-123](URL)` -- extract `PROJ-123` (Jira)
4. Return the first match found, or `null` if the section is empty or missing.

**Example document section**:
```markdown
## GitHub Issue
[#119](https://github.com/lwndev/lwndev-marketplace/issues/119)
```

**Extracted reference**: `#119`

## Jira Backend (FR-3) -- Tiered Fallback

Jira support uses a tiered fallback approach. The tiers are checked in order; the first available backend is used:

1. **Tier 1 -- Rovo MCP**: Check if the `rovo` MCP server is available. If present, use Rovo MCP tools for issue operations. Comments must be in Atlassian Document Format (ADF) JSON -- see [references/jira-templates.md](references/jira-templates.md).
2. **Tier 2 -- Atlassian CLI (`acli`)**: Check if `acli` is on PATH (`which acli`). If present, use `acli jira workitem` subcommands. `acli` accepts markdown and handles ADF conversion internally.
3. **Tier 3 -- Skip**: If neither backend is available, log a warning ("No Jira backend available (Rovo MCP not registered, acli not found). Skipping Jira operations.") and skip without failing.

### Tier Detection Logic

```
1. Check Tier 1 (Rovo MCP):
   - Verify the `rovo` MCP server is registered and responsive
   - If available → use Rovo MCP tools for all Jira operations
   - If unavailable or registration check fails → log "Rovo MCP server not available, trying acli fallback" → proceed to Tier 2

2. Check Tier 2 (acli CLI):
   - Run: which acli
   - If found on PATH → use acli for all Jira operations
   - If not found → log "acli CLI not found on PATH" → proceed to Tier 3

3. Tier 3 (Skip):
   - Log warning: "No Jira backend available (Rovo MCP not registered, acli not found). Skipping Jira operations."
   - Return without failing — workflow continues normally
```

### Jira Fetch Operation

Retrieve Jira issue details (title/summary, description, labels/tags, status, assignees).

**Via Rovo MCP (Tier 1):**

Use the `getJiraIssue` MCP tool:

```
getJiraIssue(cloudId, issueIdOrKey)
```

- `cloudId`: The Atlassian Cloud ID for the Jira instance (obtained from MCP server configuration or environment)
- `issueIdOrKey`: The issue key, e.g., `PROJ-123` or `PROJ2-456`

The tool returns the issue object including `fields.summary`, `fields.description` (in ADF format), `fields.labels`, `fields.status.name`, and `fields.assignee`.

**Via acli (Tier 2):**

```bash
acli jira workitem view --key PROJ-123
```

Returns issue details in a structured text format. Parse the output to extract title, description, status, assignee, and labels.

**On failure**: Log the error with full output and skip. Example:

```
Warning: Jira fetch failed for PROJ-123 via [Rovo MCP|acli]. Output: <error details>. Skipping.
```

### Jira Comment Operation

Post a formatted comment to a Jira issue using the appropriate template from [references/jira-templates.md](references/jira-templates.md).

**Via Rovo MCP (Tier 1):**

Use the `addCommentToJiraIssue` MCP tool:

```
addCommentToJiraIssue(cloudId, issueIdOrKey, commentBody)
```

- `cloudId`: The Atlassian Cloud ID
- `issueIdOrKey`: The issue key, e.g., `PROJ-123`
- `commentBody`: The comment in **ADF JSON format** (required by the Jira REST API)

The `commentBody` must be a valid ADF document. Load the appropriate template from [references/jira-templates.md](references/jira-templates.md) based on the `--type` argument, substitute context variables into the ADF JSON structure, and pass the resulting ADF JSON as `commentBody`.

**Via acli (Tier 2):**

```bash
acli jira workitem comment-create --key PROJ-123 --body "<markdown-comment>"
```

When using `acli`, format the comment as **markdown** (not ADF). The `acli` tool handles ADF conversion internally. Use the equivalent markdown format from [references/github-templates.md](references/github-templates.md) as a reference for the markdown content structure, adapting the GitHub-specific references (issue numbers, PR links) to Jira equivalents (issue keys, PR URLs).

**On failure**: Log the error and skip. If Tier 1 (Rovo MCP) fails, fall through to Tier 2 (acli) before skipping entirely.

### Jira PR Body Link Generation (FR-6)

For Jira issues, the PR body link is the issue key itself:

```
PROJ-123
```

Jira auto-transition relies on the **branch name** containing the issue key (e.g., `feat/PROJ-123-feature-name`), not on a `Closes` keyword. Including the issue key in the PR body provides traceability but does not trigger auto-transition directly.

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

Jira project keys can contain numbers after the first character (e.g., `PROJ2-123`, `AB1-456`). The backend detection regex `^([A-Z][A-Z0-9]*)-(\d+)$` correctly handles these patterns. Examples of valid Jira references:

- `PROJ-123` -- standard alphabetic key
- `PROJ2-456` -- alphanumeric key (numbers allowed after first letter)
- `AB1-789` -- short alphanumeric key
- `MYTEAM-1` -- longer key with single digit issue number

## Graceful Degradation (NFR-1)

Issue tracker operations are supplementary -- they must **never** block workflow progression. All failure modes degrade gracefully:

| Failure | Behavior |
|---------|----------|
| `gh` CLI not installed or not on PATH | Log warning: "GitHub CLI (`gh`) not found on PATH. Skipping GitHub issue operations." Skip operation. |
| `gh` not authenticated | Log warning: "GitHub CLI not authenticated. Run `gh auth login` to enable issue tracking." Skip operation. |
| Network unavailable | Log warning: "Network request failed. Skipping issue operation." Skip operation. |
| Rate limited | Log warning: "GitHub API rate limit reached. Skipping issue operation." Skip operation. Do not retry. |
| Issue does not exist | Log warning: "`gh issue view` returned not found for #N. Skipping." Skip operation. |
| Jira backend unavailable | Fall through tiered selection (Rovo MCP -> acli -> skip). Log which tier was attempted. |
| MCP tool invocation failure | Log error with tool name and response. Fall through to `acli` tier. |
| Rovo MCP authorization error | Log "Rovo MCP authorization failed -- check OAuth consent or API token configuration." Fall through to `acli`. |

### Implementation Pattern

Wrap every external command in a try/catch (or check exit code) pattern:

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

## Error Handling (NFR-2)

| Error Type | Response |
|-----------|----------|
| Command failure (non-zero exit) | Log error with full command output. Skip operation. Continue workflow. |
| Authentication error (GitHub) | Log: "GitHub CLI not authenticated -- run `gh auth login`". Skip. |
| Authentication error (Jira/Rovo MCP) | Log: "Rovo MCP authorization failed -- check OAuth consent or API token configuration". Fall through to `acli`. |
| Authentication error (Jira/acli) | Log: "Atlassian CLI not authenticated -- check `acli` credentials configuration". Skip. |
| Rate limiting | Log warning. Skip. Do not retry. |
| Timeout | Log warning with timeout duration. Skip. |
| MCP server disconnection | Log error with tool name. Fall through to `acli`. |

## Idempotency (NFR-3)

- **Comment operations are safe to retry.** Posting the same comment twice results in a duplicate comment, which is acceptable -- better than a missing comment.
- **Fetch operations are inherently idempotent** -- reading issue data has no side effects.
- **PR link generation is pure computation** -- no side effects, always returns the same result for the same input.
- **If a workflow is re-run or resumed**, issue operations can be re-executed without concern. The orchestrator does not need to track which operations have already been performed.

## Workflow

```
1. Receive invocation: <operation> <issue-ref> [--type <type>] [--context <json>]
2. Detect backend from issue reference format (FR-1)
   - #N → GitHub Issues
   - PROJ-123 (including PROJ2-123 alphanumeric keys) → Jira
   - Empty/absent → skip all operations
3. If no reference provided → log info, return
4. If GitHub (#N):
   a. Verify gh CLI available and authenticated
   b. Execute operation (fetch/comment) via gh CLI
   c. On failure → log warning, skip, return
5. If Jira (PROJ-123):
   a. Check Tier 1 (Rovo MCP):
      - If available → execute operation via MCP tools (getJiraIssue / addCommentToJiraIssue)
      - For comment operations → load ADF template from jira-templates.md, substitute context variables, pass ADF JSON as commentBody
      - On MCP failure (timeout, auth error, unexpected response, disconnection) → log error, fall through to Tier 2
   b. Check Tier 2 (acli):
      - If available → execute operation via acli CLI (acli jira workitem view / comment-create)
      - For comment operations → use markdown format (acli converts to ADF internally)
      - On acli failure → log error, fall through to Tier 3
   c. Tier 3 (Skip):
      - Log warning: "No Jira backend available. Skipping Jira operations."
      - Return without failing
6. Return result (fetch data, confirmation, or skip notice)
```

## References

- **GitHub comment templates**: [github-templates.md](references/github-templates.md) - Consolidated templates for all six comment types (markdown format), plus commit messages, PR body, and issue creation
- **Jira comment templates**: [jira-templates.md](references/jira-templates.md) - Jira templates in ADF JSON format for all six comment types (used by Rovo MCP path; `acli` path uses markdown)
