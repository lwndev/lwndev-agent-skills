## Issue Tracking via `managing-work-items`

The orchestrator integrates with issue trackers (GitHub Issues, Jira) through the `managing-work-items` skill. This is additive -- all existing workflow steps remain unchanged; issue tracking invocations are inserted between steps.

### Issue Reference Extraction

At the start of every workflow, after step 1 (documentation) completes and the requirements artifact exists, the orchestrator extracts the issue reference:

1. Invoke `managing-work-items fetch <requirements-artifact-path>` using FR-7 (issue reference extraction from documents) — executed inline per "How to Invoke `managing-work-items`" below
2. The skill parses the `## GitHub Issue` section of the requirements document for `[#N](URL)` or `[PROJ-123](URL)` patterns
3. Store the extracted reference (e.g., `#42` or `PROJ-123`) as `issueRef` for all subsequent invocations
4. If no issue reference is found, set `issueRef` to empty

### Skip Behavior

When no issue reference is found in the requirements document (`issueRef` is empty), **all `managing-work-items` invocations are skipped** with an info-level message: "No issue reference found in requirements document -- skipping issue tracking." The workflow continues normally without any issue tracker operations.

### Invocation Pattern

All `managing-work-items` calls follow the same syntax (see `managing-work-items/SKILL.md` for full operation details):

```
managing-work-items <operation> <issueRef> [--type <comment-type>] [--context <json>]
```

- **fetch**: Retrieve issue data to pre-fill requirements
- **comment**: Post a status update to the linked issue
- **FR-6 (PR link)**: Generate `Closes #N` or `PROJ-123` for PR bodies

### How to Invoke `managing-work-items`

`managing-work-items` is a **cross-cutting reference document**, not a forkable step. The orchestrator **executes it inline from its own main context** using its existing `Bash`, `Read`, and `Glob` tool access. Concretely:

1. **Once per workflow, at workflow start**, the orchestrator `Read`s `${CLAUDE_PLUGIN_ROOT}/skills/managing-work-items/SKILL.md` plus whichever template reference it will need (`references/github-templates.md` for `#N` issues or `references/jira-templates.md` for `PROJ-123` issues). The file is a reference document — the orchestrator consults it the way a function looks up an argument table, not the way it forks a sub-skill.
2. **At every call site below**, the orchestrator runs the documented `gh` / `acli` / Rovo MCP command directly from main context. No Agent tool fork. No Skill tool call. No sub-conversation.
3. **Graceful degradation** (NFR-1) still applies — every external command is wrapped in the try/skip pattern from `managing-work-items/SKILL.md:287-306`. Failures are logged and the workflow continues.

**Note on cross-cutting skills**: `managing-work-items` is deliberately not in any chain step table (Feature, Chore, or Bug). Cross-cutting skills — skills invoked between steps rather than as a step — do **not** follow the Forked Steps recipe in SKILL.md. They follow this "How to Invoke" subsection instead. This distinction matters because the Forked Steps recipe is scoped to "steps marked **fork** in the step sequence", and cross-cutting invocations have no such marker.

#### Rejected alternatives

Two other invocation mechanisms were considered and explicitly rejected:

- **Agent-tool fork (rejected)**: Forking a subagent for every `gh issue comment` adds conversation-spawn overhead, audit-trail noise, and an unnecessary context boundary for what is usually a single CLI command. `managing-work-items` operations are small, stateless, and don't need isolation — they're idiomatic main-context tool use.
- **Skill-tool invocation (rejected)**: `managing-work-items` is framed as a reference document for the orchestrator; it is not a user-facing skill. Invoking it via the Skill tool would require restructuring its contract (name, trigger phrases, arguments) and would still force the orchestrator to hand off control to a sub-conversation for operations it can execute inline in one tool call.

**Inline execution composes cleanly with the existing Forked Steps recipe.** Step-sequence forks (skills that appear in the chain tables — `reviewing-requirements`, `creating-implementation-plans`, `implementing-plan-phases`, `executing-chores`, `executing-bug-fixes`, `finalizing-workflow`, `pr-creation`) continue to use the Forked Steps recipe in SKILL.md. Cross-cutting invocations (`managing-work-items`) are handled inline per this subsection. The two mechanisms do not overlap and do not need to be reconciled.

#### Runnable examples

Each example assumes the orchestrator has already `Read` the `managing-work-items/SKILL.md` reference document once at workflow start and has `issueRef` in scope (either a `#N` GitHub reference or a `PROJ-123` Jira reference).

**Operation 1: `extract-ref` (parse issue reference from requirements document)**

Use `Read` on the requirements document and search for the `## GitHub Issue` section. Pseudocode:

```
content = Read("requirements/features/FEAT-042-my-feature.md")
# Find the "## GitHub Issue" heading and the next non-empty line
# Match patterns: [#N](URL) or [PROJ-123](URL)
# Example content under the heading:
#   ## GitHub Issue
#   [#131](https://github.com/lwndev/lwndev-marketplace/issues/131)
issueRef = "#131"  # extracted; store for the rest of the workflow
```

Concretely, `Grep` the file for `^\[#[0-9]+\]` or `^\[[A-Z][A-Z0-9]*-[0-9]+\]` within the `## GitHub Issue` section, or (equivalently) `Read` the file and string-search in the orchestrator's head. If the section is missing or empty, set `issueRef` to empty and log the info-level skip message; do **not** warn.

**Operation 2: `fetch` (retrieve issue data via `gh issue view`)**

For a GitHub `#N` reference:

```bash
gh issue view 131 --json title,body,labels,state,assignees
```

The orchestrator runs this via its `Bash` tool and parses the returned JSON. For a Jira `PROJ-123` reference, the orchestrator follows the tiered fallback documented in `managing-work-items/SKILL.md` — first try Rovo MCP (`getJiraIssue(cloudId, "PROJ-123")`), then `acli jira workitem view --key PROJ-123`, then skip with a warning if both are unavailable. The orchestrator executes whichever tier succeeds directly; no subagent fork.

**Operation 3: `comment` (post a lifecycle comment via `gh issue comment`)**

For a phase-start comment on a GitHub issue:

1. `Read` the appropriate template from `${CLAUDE_PLUGIN_ROOT}/skills/managing-work-items/references/github-templates.md` — select the `phase-start` section.
2. Substitute context variables (`phase`, `totalPhases`, `workItemId`, phase name, steps, deliverables) into the template to produce the rendered markdown body.
3. Run the following command. Use the plain multi-line double-quoted string form (matching the canonical templates in `github-templates.md`); do **not** wrap the body in a `$(cat <<'EOF' ... EOF)"` heredoc — the closing `EOF` delimiter must be at column 0, which conflicts with markdown list-continuation indentation and breaks copy-paste from raw source:

   ```bash
   gh issue comment 131 --body "## Phase 1 Started: GitHub Backend

   **FEAT-014** — Phase 1 of 4

   ### Steps
   - Implement classifier script
   - Wire up state-file fields
   ..."
   ```

   If the rendered body contains literal `$`, backticks, or backslashes that you do not want bash to interpret, use single quotes instead: `gh issue comment 131 --body '...'`. For dynamic substitution, build the body in a shell variable first (`body="..."; gh issue comment 131 --body "$body"`).

4. On failure (non-zero exit), emit a warning-level skip message (see "Mechanism-Failure Logging" below) and continue the workflow.

For a Jira `PROJ-123` reference, the orchestrator instead reads `jira-templates.md`, renders the ADF JSON (for Rovo MCP) or markdown (for `acli`), and invokes the matching backend tier. The template and backend selection are the only differences — the inline-execution pattern is the same.

**Operation 4: `pr-link` (generate PR body issue link)**

For GitHub, hand-write the syntax when constructing the PR body:

```
Closes #131
```

For Jira, write the issue key:

```
PROJ-123
```

This is pure string generation — the orchestrator does not need to shell out for it. It builds the PR body in main context and passes it to `gh pr create --body` alongside all other PR metadata.

#### Mechanism-Failure Logging (WARNING level)

Graceful degradation (NFR-1) tells the orchestrator to skip issue operations on failure rather than block the workflow. That's still correct — but a **mechanism-missing** failure must be distinguishable from a legitimate empty-`issueRef` skip. The orchestrator emits a WARNING-level log line (visibly distinct from the INFO-level skip) in the following cases:

| Failure mode | Warning message format |
|--------------|------------------------|
| `managing-work-items/SKILL.md` cannot be read at workflow start | `[warn] managing-work-items reference document unreadable at ${CLAUDE_PLUGIN_ROOT}/skills/managing-work-items/SKILL.md — issue tracking disabled for this workflow.` |
| `gh` CLI missing when `issueRef` is a `#N` reference | `[warn] gh CLI not found on PATH — cannot invoke managing-work-items for GitHub issue ${issueRef}. Skipping issue tracking.` |
| `gh` CLI not authenticated when `issueRef` is `#N` | `[warn] gh CLI not authenticated (run \`gh auth login\`) — cannot invoke managing-work-items for GitHub issue ${issueRef}. Skipping issue tracking.` |
| Jira tiered fallback exhausts all three tiers | `[warn] No Jira backend available (Rovo MCP not registered, acli not found) — cannot invoke managing-work-items for Jira issue ${issueRef}. Skipping issue tracking.` |
| GitHub template file unreadable | `[warn] managing-work-items GitHub template file unreadable at references/github-templates.md — cannot render ${commentType} comment. Skipping.` |
| Jira template file unreadable | `[warn] managing-work-items Jira template file unreadable at references/jira-templates.md — cannot render ${commentType} comment. Skipping.` |

Contrast with the INFO-level skip (legitimate empty-`issueRef`):

```
[info] No issue reference found in requirements document -- skipping issue tracking.
```

The key distinction: INFO means "nothing to do", WARNING means "we have work to do but can't do it — silent-skip regression risk". The `[warn]` prefix is mandatory so a future `grep -n '\[warn\]' conversation.log` catches mechanism regressions.
