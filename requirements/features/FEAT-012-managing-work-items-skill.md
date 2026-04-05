# Feature Requirements: Managing Work Items Skill

## Overview

Create a new `managing-work-items` skill that centralizes all issue tracker operations (GitHub Issues and Jira) into a single, delegatable skill. Refactor existing skills to remove inline issue tracker interactions and have the orchestrator invoke `managing-work-items` at the appropriate workflow points.

## Feature ID
`FEAT-012`

## GitHub Issue
[#119](https://github.com/lwndev/lwndev-marketplace/issues/119)

## Priority
High - Prerequisite for Jira support (#118) and eliminates duplicated issue tracker logic across 6 skills

## User Story

As a developer using the lwndev-sdlc plugin, I want issue tracker operations centralized in a single skill so that adding support for new trackers (Jira, Linear, Azure DevOps) requires changes in one place instead of across every execution and documentation skill.

## Skill Structure

```
plugins/lwndev-sdlc/skills/
└── managing-work-items/
    ├── SKILL.md                    # Skill instructions with backend selection, operations
    └── references/
        ├── github-templates.md     # Consolidated from executing skills (markdown format)
        └── jira-templates.md       # New Jira comment templates (ADF JSON format per FR-8)
```

## Invocation Syntax

The skill is invoked by the orchestrator (not directly by users) with an operation and arguments:

```
managing-work-items fetch <issue-ref>
managing-work-items comment <issue-ref> --type <comment-type> --context <json-context>
```

### Arguments
- `<issue-ref>` (required) - Issue reference in either `#N` format (GitHub) or `PROJ-123` format (Jira)
- `--type <comment-type>` - Comment type: `phase-start`, `phase-completion`, `work-start`, `work-complete`, `bug-start`, `bug-complete`
- `--context <json-context>` - JSON string with template variables (e.g., work item ID, PR number, root causes, deliverables)

## Functional Requirements

### FR-1: Backend Detection and Selection
Automatically detect the issue tracker backend from the issue reference format:

| Format | Backend | Detection |
|--------|---------|-----------|
| `#N` | GitHub Issues | Numeric-only reference prefixed with `#` |
| `PROJ-123` | Jira | Alphabetic project key followed by `-` and number |

When no issue reference is provided (the GitHub Issue field in the requirement doc is empty or absent), skip all issue operations gracefully with an info-level message.

### FR-2: GitHub Issues Backend
Execute operations via the `gh` CLI:

| Operation | Command |
|-----------|---------|
| Fetch | `gh issue view <N> --json title,body,labels,state,assignees` |
| Comment | `gh issue comment <N> --body "<formatted-comment>"` |

### FR-3: Jira Backend with Tiered Fallback
Select the Jira backend using a tiered approach:

1. **Rovo MCP** (primary) - Check if the `rovo` MCP server is available. If present, use Rovo MCP tools for issue operations.
2. **Atlassian CLI (`acli`)** (fallback) - Check if `acli` is on PATH. If present, use `acli jira` subcommands.
3. **Skip** (graceful degradation) - If neither backend is available, log a warning and skip the operation without failing the workflow.

| Operation | Rovo MCP | acli |
|-----------|----------|------|
| Fetch | `getJiraIssue(cloudId, issueIdOrKey)` | `acli jira workitem view --key PROJ-123` |
| Comment | `addCommentToJiraIssue(cloudId, issueIdOrKey, commentBody)` | `acli jira workitem comment-create --key PROJ-123 --body "..."` |

> **Note:** Rovo MCP tool names are sourced from the [Atlassian MCP server repo](https://github.com/atlassian/atlassian-mcp-server) skills (April 2026). ACLI subcommands are from the [Atlassian CLI reference](https://developer.atlassian.com/cloud/acli/reference/commands/jira/). Both should be re-verified at implementation time as these APIs are actively evolving.

### FR-4: Fetch Operation
Retrieve issue details and return structured data:

**Input**: Issue reference (`#N` or `PROJ-123`)
**Output**: Issue title, body/description, labels/tags, state/status, assignees

Used by:
- `documenting-features` (step 1) to pre-fill requirements from a `#N` argument
- Orchestrator to verify issue exists before starting a workflow

### FR-5: Comment Operations
Post formatted comments to the issue using type-specific templates:

| Comment Type | Used By | Template Data |
|-------------|---------|---------------|
| `phase-start` | `implementing-plan-phases` | Phase name, steps, deliverables |
| `phase-completion` | `implementing-plan-phases` | Phase name, verified deliverables, commit SHA |
| `work-start` | `executing-chores` | CHORE-XXX ID, acceptance criteria |
| `work-complete` | `executing-chores` | PR number, verified acceptance criteria |
| `bug-start` | `executing-bug-fixes` | BUG-XXX ID, severity, root causes (RC-N), acceptance criteria |
| `bug-complete` | `executing-bug-fixes` | PR number, root cause resolution table, verification results |

Each comment type has both a GitHub template (markdown) and a Jira template (ADF) in the references directory. See FR-8 for ADF format requirements.

### FR-6: PR Body Issue Link Generation
Generate the appropriate auto-close syntax for PR bodies:

| Backend | Syntax |
|---------|--------|
| GitHub | `Closes #N` |
| Jira | `PROJ-123` (with branch name containing the key for Jira auto-transition) |

Used by the orchestrator at PR creation steps and by execution skills that create PRs.

### FR-7: Issue Reference Extraction from Documents
Extract the issue reference from requirement documents by reading the `## GitHub Issue` section:

- Parse `[#N](URL)` → extract `#N`
- Parse `[PROJ-123](URL)` → extract `PROJ-123`
- If section is empty or missing → return null (no issue linked)
- Search for the section under both `## GitHub Issue` (current convention) and `## Issue` or `## Issue Tracker` (future-compatible). The documenting skills currently use `## GitHub Issue` as the section name; when Jira support is fully integrated (#118), the section name in document templates should be generalized to `## Issue` to be tracker-agnostic.

This replaces the inline extraction logic currently duplicated in execution skills.

### FR-8: Atlassian Document Format (ADF) for Jira Comments
Jira's REST API and Rovo MCP tools require comments in [Atlassian Document Format (ADF)](https://developer.atlassian.com/cloud/jira/platform/apis/document/structure/) — a JSON-based rich text format — not markdown. The skill must produce comments in the correct format per backend:

| Backend | Comment Format |
|---------|---------------|
| GitHub | Markdown string (passed to `gh issue comment --body`) |
| Jira (Rovo MCP) | ADF JSON (passed as `commentBody` to `addCommentToJiraIssue`) |
| Jira (acli) | Markdown string (`acli` handles conversion internally) |

**ADF structure**: Every ADF document is a JSON object with `version: 1`, `type: "doc"`, and a `content` array of block nodes (`paragraph`, `heading`, `bulletList`, `orderedList`, `codeBlock`, `table`, `panel`, `rule`). Text nodes carry formatting via a `marks` array (`strong`, `em`, `code`, `link`).

**Template approach**: Jira templates in `references/jira-templates.md` should define the ADF JSON structure for each comment type. The skill renders templates by substituting context variables into the ADF structure. Templates must use ADF-native constructs:
- `heading` nodes (not markdown `##`)
- `marks: [{"type": "strong"}]` for bold (not `**bold**`)
- `bulletList` / `listItem` for lists (not `- item`)
- `codeBlock` with `attrs: {"language": "..."}` for code snippets
- `panel` nodes with `attrs: {"panelType": "info|note|warning|success|error"}` for status callouts (maps to Jira's colored panels)
- `link` marks with `attrs: {"href": "URL"}` for hyperlinks

**Example — phase start comment in ADF**:
```json
{
  "version": 1,
  "type": "doc",
  "content": [
    {
      "type": "heading",
      "attrs": {"level": 3},
      "content": [{"type": "text", "text": "🔄 Starting Phase {N}: {Phase Name}"}]
    },
    {
      "type": "paragraph",
      "content": [
        {"type": "text", "text": "Work item: "},
        {"type": "text", "text": "{FEAT-XXX}", "marks": [{"type": "strong"}]}
      ]
    }
  ]
}
```

## Non-Functional Requirements

### NFR-1: Graceful Degradation
- If the `gh` CLI is not authenticated or network is unavailable, log a warning and skip the operation without failing the workflow
- If a Jira backend is unavailable, fall through the tiered selection (Rovo MCP → acli → skip)
- Never block workflow progression due to issue tracker failures — issue operations are supplementary

### NFR-2: Error Handling
- Command failures (non-zero exit, timeout): Log error with the full command output, skip the operation, continue workflow
- Authentication errors: Log a clear message ("GitHub CLI not authenticated — run `gh auth login`" or "Jira credentials not configured") and skip
- Rate limiting: Log warning and skip; do not retry
- MCP tool invocation failures: If the Rovo MCP server is registered but a tool call fails (timeout, unexpected response schema, MCP server disconnection mid-operation), log the error with the tool name and response, fall through to the `acli` fallback. If the MCP server is registered but returns an authorization error, log "Rovo MCP authorization failed — check OAuth consent or API token configuration" and fall through to `acli`

### NFR-3: Idempotency
- Comment operations should be safe to retry (duplicate comments are acceptable; better than missing comments)

### NFR-4: Template Consistency
- All comment templates must include the work item ID (FEAT-XXX, CHORE-XXX, BUG-XXX) for traceability
- Bug-related templates must preserve RC-N (root cause) tagging
- Templates should produce equivalent information across GitHub (markdown) and Jira (ADF JSON) formats
- Jira ADF templates must be valid ADF per the [ADF specification](https://developer.atlassian.com/cloud/jira/platform/apis/document/structure/) — invalid ADF will cause API rejections
- The `acli` CLI accepts markdown and handles conversion internally; ADF templates are only required for the Rovo MCP path

## Refactoring Requirements

### Skills to Modify

| Skill | Operations to Remove | Location | Replacement |
|-------|---------------------|----------|-------------|
| `implementing-plan-phases` | `gh issue comment` (phase start/completion), `gh issue close` (final phase) | SKILL.md workflow steps + `references/github-templates.md` + `references/step-details.md` | Orchestrator invokes `managing-work-items` before/after each phase |
| `executing-chores` | `gh issue comment` (start/completion), `Closes #N` in PR body | SKILL.md workflow steps + `references/github-templates.md` + `references/workflow-details.md` | Orchestrator invokes `managing-work-items`; PR body link via FR-7 |
| `executing-bug-fixes` | `gh issue comment` (start/completion), `Closes #N` in PR body | SKILL.md workflow steps + `references/github-templates.md` + `references/workflow-details.md` | Orchestrator invokes `managing-work-items`; PR body link via FR-7 |
| `documenting-features` | Issue fetch from `#N` argument (described in SKILL.md Arguments section; skill lacks Bash in allowed-tools so cannot execute `gh` directly) | SKILL.md arguments section | Orchestrator invokes `managing-work-items fetch` before step 1 (or skill delegates to orchestrator) |
| `documenting-chores` | Issue link storage pattern | `assets/chore-document.md` template (`## GitHub Issue` section) | No change to storage — extraction centralized in FR-7 |
| `documenting-bugs` | Issue link storage pattern | `assets/bug-document.md` template (`## GitHub Issue` section) | No change to storage — extraction centralized in FR-7 |

### Template Migration

Consolidate three `references/github-templates.md` files into one:
- `implementing-plan-phases/references/github-templates.md` → `managing-work-items/references/github-templates.md`
- `executing-chores/references/github-templates.md` → merged into consolidated file
- `executing-bug-fixes/references/github-templates.md` → merged into consolidated file

After migration, remove the `github-templates.md` files from the source skills and remove the `gh issue` instructions from those skills' SKILL.md files.

### Orchestrator Changes

The `orchestrating-workflows` skill needs new invocation points for `managing-work-items`:

| Workflow Point | Operation | Context |
|---------------|-----------|---------|
| After step 1 (documenting) | `fetch` | Pre-fill requirement doc from issue (feature chain only when `#N` arg) |
| Before execution step start | `comment` with `work-start` / `bug-start` / `phase-start` | Post "starting work" comment |
| After execution step completion | `comment` with `work-complete` / `bug-complete` / `phase-completion` | Post "work complete" comment |
| At PR creation | Generate issue link via FR-6 | Include in PR body |

## Dependencies

- `gh` CLI (for GitHub Issues backend)
- Rovo MCP server (optional, for Jira primary backend)
- `acli` CLI (optional, for Jira fallback backend)
- Existing `orchestrating-workflows` skill (for invocation integration)
- Existing execution skills (for refactoring)

## Edge Cases

1. **No issue linked**: Requirement document has empty or missing `## GitHub Issue` section — all issue operations skip gracefully
2. **Multiple issue references**: Document contains both `#N` and `PROJ-123` — use the first reference found
3. **Invalid issue reference**: `#N` where N doesn't exist — log warning from `gh issue view` failure, skip
4. **Jira project key with numbers**: `PROJ2-123` — regex must handle alphanumeric project keys
5. **Network unavailable mid-workflow**: Issue operation fails after earlier operations succeeded — skip and continue; comments may be partially posted
6. **Permission denied**: User lacks permission to comment — log error, skip operation
7. **Long comment bodies**: Template expansion produces very large comments — no truncation (GitHub/Jira handle their own limits)

## Testing Requirements

### Unit Tests
- Backend detection from issue reference formats (`#N` → GitHub, `PROJ-123` → Jira)
- Issue reference extraction from requirement document markdown
- Template rendering for each comment type with sample context data
- Tiered Jira backend selection logic

### Integration Tests
- GitHub fetch/comment operations via `gh` CLI
- Graceful degradation when `gh` is not available
- Jira fallback chain (Rovo MCP → acli → skip)

### Manual Testing
- Run a complete feature chain and verify issue comments appear at each stage
- Run a chore chain with a linked GitHub issue and verify start/completion comments
- Run a bug chain and verify RC-N traceability in issue comments
- Test with no issue linked — verify no errors and clean workflow progression
- Test with Jira reference (if Jira environment available)

## Future Enhancements

- **Issue close/transition operation** ([#121](https://github.com/lwndev/lwndev-marketplace/issues/121)): Deferred due to Jira workflow complexity — transition IDs are dynamic (regenerated on workflow save), status names vary per project, and custom workflows can have arbitrarily complex state machines. GitHub `Closes #N` in PR bodies and Jira branch-name-based auto-transition (FR-6) handle the common case. A dedicated close/transition operation would require: querying available transitions per-issue, matching by status name, handling "no valid transition" errors, and potentially project-specific configuration.
- Linear backend support (linear.app API)
- Azure DevOps work item support
- Bidirectional sync (update requirement docs from issue tracker changes)
- Issue creation operation (for workflows that start without an existing issue)
- Label/tag management operations

## Acceptance Criteria

- [ ] `managing-work-items` skill exists at `plugins/lwndev-sdlc/skills/managing-work-items/` with SKILL.md
- [ ] Skill handles fetch and comment operations for GitHub Issues via `gh` CLI
- [ ] Skill includes backend detection logic (GitHub `#N` vs Jira `PROJ-123`)
- [ ] Jira operations supported via Rovo MCP (primary) and `acli` (fallback)
- [ ] Graceful degradation when no Jira backend is available (skip without error)
- [ ] Graceful degradation when `gh` CLI fails (skip without blocking workflow)
- [ ] `references/github-templates.md` consolidated from three skills into `managing-work-items`
- [ ] `references/jira-templates.md` created with equivalent templates for Jira
- [ ] `implementing-plan-phases` SKILL.md no longer contains inline `gh issue` operations
- [ ] `executing-chores` SKILL.md no longer contains inline `gh issue` operations
- [ ] `executing-bug-fixes` SKILL.md no longer contains inline `gh issue` operations
- [ ] `documenting-features` delegates issue fetch to `managing-work-items` (or orchestrator)
- [ ] Orchestrator SKILL.md updated with `managing-work-items` invocation points
- [ ] All existing GitHub Issues workflows continue to function (regression)
- [ ] All skills pass `npm run validate`
- [ ] Issue reference extraction from documents works for both formats
