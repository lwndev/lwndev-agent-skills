---
name: implementing-plan-phases
description: Required workflow for implementing phases from plans in requirements/implementation/. Enforces status tracking (Pending → 🔄 In Progress → ✅ Complete), branch naming (feat/{ID}-summary), and verification sequence. Use when the user says "run phase workflow", "execute phase workflow", "start phase N workflow", or asks to implement from an implementation plan document.
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
argument-hint: "<plan-file> [phase-number]"
---

# Implementing Plan Phases

Execute implementation plan phases with systematic tracking and verification.

## When to Use

- User says "run phase workflow", "execute phase workflow", or "start phase N workflow"
- User asks to implement from an implementation plan document
- References files in `requirements/implementation/`

## Arguments

- **When argument is provided**: Parse the argument as `<plan-file> [phase-number]`. Match the first part against files in `requirements/implementation/` by ID prefix (e.g., `FEAT-001` matches `FEAT-001-podcast-cli-features.md`). If a phase number is provided (e.g., `FEAT-001 3`), target that specific phase. If the phase number exceeds the plan's phase count, display available phases and ask the user to choose. If no match is found for the plan file, inform the user and fall back to interactive selection.
- **When no argument is provided**: Scan `requirements/implementation/` for plan documents and prompt the user to select one. Then identify the next pending phase automatically.

## Quick Start

1. Locate the implementation plan — when the user supplies a `FEAT-NNN` ID, resolve it via `bash "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-requirement-doc.sh" "<FEAT-NNN>"` (exit `0`/`1`/`2`/`3`) and then Glob `requirements/implementation/{ID}-*.md` for the implementation plan specifically.
2. Identify target phase (user-specified or next pending)
3. Update plan status to "🔄 In Progress"
   ```markdown
   **Status:** 🔄 In Progress
   ```
4. Create the feature branch (if not already on it). Build the name with:

   ```bash
   branch=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/build-branch-name.sh" feat "<FEAT-NNN>" "<2-3 word summary>")
   ```

   (The script internally calls `slugify.sh` — `bash "${CLAUDE_PLUGIN_ROOT}/scripts/slugify.sh" "<summary>"` — so lowercasing, punctuation stripping, stopword removal, and the 4-token cap are all handled. Exit `1` means the summary produced an empty slug; prompt for a more descriptive summary. Exit `2` means invalid type.) Then ensure the branch is current with:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/ensure-branch.sh" "$branch"
   ```

   Exit codes: `0` on success (`on <branch>` / `switched to <branch>` / `created <branch>` on stdout); `2` on missing arg; `3` on dirty working tree — stash or commit first, then retry.
5. Load implementation steps into todos
6. Execute each step, **checking off each deliverable** in the implementation plan as it is completed with:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-acceptance.sh" "<plan-path>" "<deliverable-matcher>"
   ```

   The script finds the first `- [ ] ` line outside a fenced code block containing the literal (non-regex) matcher substring and flips it to `- [x] `. Exit codes: `0` on `checked` or `already checked` (idempotent); `1` on criterion not found; `2` on ambiguous (multiple matches); `3` on missing arg.
7. Verify deliverables (tests pass, build succeeds)
8. **Always** commit and push changes to remote — do not ask the user for confirmation
9. Update plan status to "✅ Complete"
10. **After all phases complete:** Create pull request **(MUST include `Closes #N` if issue exists)** with:

    ```bash
    bash "${CLAUDE_PLUGIN_ROOT}/scripts/create-pr.sh" feat "<FEAT-NNN>" "<summary>" [--closes <issueRef>]
    ```

    The script reads the current branch, runs `git push -u origin <branch>`, assembles the PR title as `feat(<FEAT-NNN>): <summary>`, substitutes into `scripts/assets/pr-body.tmpl`, and runs `gh pr create`. Pass `--closes #N` when a GitHub issue exists — this auto-closes the linked issue on merge. Exit codes: `0` on success (PR URL on stdout); `1` on `git push` or `gh pr create` failure; `2` on missing/invalid required args or malformed `--closes` token.

> **Note:** Issue tracking (start/completion comments) is handled by the orchestrator via `managing-work-items`. This skill focuses on implementation, verification, and status tracking.

## Output Style

Follow the lite-narration rules below. Load-bearing carve-outs MUST be emitted as specified; they are not narration. This skill is forked by `orchestrating-workflows` once per phase (feature chain steps 6…5+N), so its output flows to a parent orchestrator rather than directly to the user.

### Lite narration rules

- No preamble before tool calls. Do not announce "let me check" or "I'll run" -- issue the tool call.
- No end-of-turn summaries beyond one short sentence. Do not recap what the user can read from tool output (e.g., the per-phase commit/push trail or the plan status checkmark edit).
- No emoji. ASCII punctuation only.
- No restating what the user just said.
- No status echoes that tools already show (e.g., successful `Edit` confirmations, `git push` tracking lines).
- Prefer ASCII arrows (`->`) and punctuation over Unicode alternatives in skill-authored prose. Existing Unicode em dashes in tables and reference docs are retained.
- Short sentences over paragraphs. Bullet lists over prose when listing more than two items.

### Load-bearing carve-outs (never strip)

The following MUST always be emitted even when they resemble narration:

- **Error messages from `fail` calls** -- users need the reason the skill halted. Surface script and tool stderr verbatim (e.g., `resolve-requirement-doc.sh`, `build-branch-name.sh`, `ensure-branch.sh`, `check-acceptance.sh`, `create-pr.sh` failures; `npm test` / `npm run build` failing output).
- **Security-sensitive warnings** -- destructive-operation confirmations, credential prompts.
- **Interactive prompts** -- any prompt that blocks the workflow and requires user input (e.g., disambiguation when multiple plan files match the provided ID, phase-selection prompt when the supplied phase number exceeds the plan's phase count, summary re-prompt when `build-branch-name.sh` exits `1` on an empty slug).
- **Findings display from `reviewing-requirements`** -- N/A for this skill (it does not consume reviewing-requirements findings); bullet retained for consistency with the canonical template.
- **FR-14 console echo lines** -- `[model] step {N} ({skill}) -> {tier} (...)` audit-trail lines emitted by `prepare-fork.sh`. The Unicode `->` is the documented emitter format; do not rewrite to ASCII.
- **Tagged structured logs** -- any line prefixed `[info]`, `[warn]`, or `[model]` is a structured log, not narration. Emit verbatim.
- **User-visible state transitions** -- pause, advance, and resume announcements (at most one line each).

### Fork-to-orchestrator return contract

This skill is forked by `orchestrating-workflows` once per phase (feature chain steps 6…5+N; one invocation per `### Phase N` block in the plan). Emit `done | artifact=<path> | <note-of-at-most-10-words>` as the **final line** on success, and `failed | <one-sentence reason>` on failure. The `Found **N errors**, **N warnings**, **N info**` shape is reserved for `reviewing-requirements` only and MUST NOT be emitted here.

`artifact=` points to the file(s) the phase actually produced. Because a phase typically commits to multiple files (source + tests + plan-document checkmark edits), use the most-representative single path: the main source/skill file modified by the phase when the phase delivers a focused change, or the implementation plan path (`requirements/implementation/<ID>-*.md`) when deliverables genuinely span many files and no single one dominates. Example: `done | artifact=plugins/lwndev-sdlc/skills/<edited-skill>/SKILL.md | phase N complete, <note>`.

**Orchestrator-side contract**: when this skill is invoked by `orchestrating-workflows`, the parent appends an instruction to the fork prompt saying "Do NOT create a pull request at the end -- the orchestrator handles PR creation separately. Skip Step 10 (Create Pull Request) entirely." The subagent MUST honor that carve-out. This SKILL.md still documents Step 10 in full for standalone (non-orchestrated) invocations, where the user runs the skill directly and the PR must be created by the skill itself.

**Precedence**: the return contract takes precedence over the lite rules when the two conflict. The subagent MUST emit the contract shape as the final line of the response even if it reads like narration.

## Workflow

Copy this checklist and track progress:

```
Phase Implementation:
- [ ] Locate implementation plan
- [ ] Identify target phase
- [ ] Update plan status to "🔄 In Progress"
- [ ] Create/switch to feature branch
- [ ] Load steps into todos
- [ ] Execute implementation steps, checking off deliverables (- [ ] → - [x]) as completed
- [ ] Verify deliverables
- [ ] Always commit and push changes to remote (do not prompt — this is mandatory)
- [ ] Update plan status to "✅ Complete"
- [ ] Create pull request after all phases complete (include "Closes #N" in body if issue exists)
```

**Important:** Including `Closes #N` in the PR body auto-closes the linked GitHub issue when merged. Without it, the issue must be closed manually.

See [step-details.md](references/step-details.md) for detailed guidance on each step.

## Phase Structure

Implementation plans follow this format:

```markdown
### Phase N: [Phase Name]
**Feature:** [FEAT-XXX](../features/...) | [#IssueNum](https://github.com/...)
**Status:** Pending | 🔄 In Progress | ✅ Complete

#### Rationale
Why this phase comes at this point in the sequence.

#### Implementation Steps
1. Specific action to take
2. Another specific action
3. Write tests for new functionality

#### Deliverables
- [ ] `path/to/file.ts` - Description
- [ ] `tests/path/to/file.test.ts` - Tests
```

The GitHub issue number `[#N]` is used for the `Closes #N` PR reference when creating the pull request after all phases complete.

## Branch Naming

Format: `feat/{Feature ID}-{2-3-word-summary}`. Assemble via `bash "${CLAUDE_PLUGIN_ROOT}/scripts/build-branch-name.sh" feat "<FEAT-NNN>" "<summary>"` (see Step 4 above) rather than hand-kebabing.

Examples:
- `feat/FEAT-001-scaffold-skill-command`
- `feat/FEAT-002-validate-skill-command`
- `feat/FEAT-007-chore-task-skill`

## Verification

Before marking a phase complete, verify:

- All deliverables created/modified
- Tests pass: `npm test`
- Build succeeds: `npm run build`
- Coverage meets threshold (if specified)
- Changes committed and pushed to remote (blocking — do not update plan status until push succeeds)
- Plan status updated with checkmarks
- After all phases: create PR per Step 10

## References

- **Complete workflow example**: [workflow-example.md](references/workflow-example.md) - Full Phase 2 implementation walkthrough
- **Detailed step guidance**: [step-details.md](references/step-details.md) - In-depth explanation of each workflow step
- **PR template**: [assets/pr-template.md](assets/pr-template.md) - Pull request format for feature implementations
