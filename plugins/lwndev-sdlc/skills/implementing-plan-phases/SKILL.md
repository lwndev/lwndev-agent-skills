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

- **When argument is provided**: Parse as `<plan-file> [phase-number]`. Match the first part against files in `requirements/implementation/` by ID prefix (e.g., `FEAT-001` matches `FEAT-001-podcast-cli-features.md`). If a phase number is provided (e.g., `FEAT-001 3`), target that phase; if it exceeds the plan's phase count, display available phases and ask the user to choose. If no plan file matches, fall back to interactive selection.
- **When no argument is provided**: Scan `requirements/implementation/` and prompt the user to pick a plan. Identify the next pending phase automatically.

## Quick Start

Script paths below are relative to `${CLAUDE_PLUGIN_ROOT}/skills/implementing-plan-phases/scripts/` (abbreviated `$SCRIPTS/` in the snippets).

1. Locate the plan. Resolve a `FEAT-NNN` ID via `bash "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-requirement-doc.sh" "<FEAT-NNN>"` (exit `0`/`1`/`2`/`3`), then Glob `requirements/implementation/{ID}-*.md`.
2. Identify target phase. If the user named one, use it; otherwise run `bash "$SCRIPTS/next-pending-phase.sh" "<plan-path>"` and dispatch on JSON stdout: `{"phase":<N>,"name":"..."}` → implement; `...,"reason":"resume-in-progress"}` → resume; `{"phase":null,"reason":"all-complete"}` → jump to Step 10; `{"phase":null,"reason":"blocked","blockedOn":[...]}` → halt, surface the blocker.
3. Transition status to "🔄 In Progress": `bash "$SCRIPTS/plan-status-marker.sh" "<plan-path>" <phase-N> in-progress`. Stdout: `transitioned` or `already set` (idempotent). Exit `1` on missing phase block.
4. Create the feature branch (if not already on it):

   ```bash
   branch=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/build-branch-name.sh" feat "<FEAT-NNN>" "<2-3 word summary>")
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/ensure-branch.sh" "$branch"
   ```

   `build-branch-name.sh`: exit `1` = empty slug (re-prompt for a more descriptive summary); `2` = invalid type. `ensure-branch.sh`: `0` on success (`on <branch>` / `switched to <branch>` / `created <branch>`); `2` missing arg; `3` dirty tree (stash or commit first, then retry).
5. Load implementation steps into todos.
6. Execute each step and check off each deliverable as it completes: `bash "$SCRIPTS/check-deliverable.sh" "<plan-path>" <phase-N> "<idx-or-text>"`. Third arg dispatches: digits → 1-based deliverable index; any non-digit → literal substring. Exit `0` `checked` / `already checked` (idempotent); `1` not-found or out-of-range; `2` ambiguous (multi-match on `- [ ]` lines); `3` missing arg. Phase-scoped, fence-aware.
7. Verify deliverables: `bash "$SCRIPTS/verify-phase-deliverables.sh" "<plan-path>" <phase-N>`. Extracts backticked paths from the phase's `#### Deliverables`, checks existence, then runs `npm run lint`, `npm run format:check`, `npm test`, `npm run build`, and (when the plan mentions `coverage` or a `[0-9]+%` threshold) `npm run test:coverage` — each only when defined in `package.json`. Fail-fast: a failing stage leaves downstream stages reported `skipped` (e.g. `lint:"fail"` → `format:"skipped"`, `test:"skipped"`, …). JSON stdout: `{"files":{"ok":[...],"missing":[...]},"lint":"pass|fail|skipped","format":"...","test":"...","build":"...","coverage":"...","output":{...}}`. Exit `0` only when `files.missing` is empty AND every check is `pass` or `skipped`; else `1`. Gracefully degrades when `npm` is absent (`[warn]` to stderr; all five reported `skipped`).
8. Commit and push — always, no confirmation prompt: `bash "$SCRIPTS/commit-and-push-phase.sh" "<FEAT-NNN>" <phase-N> "<phase-name>"`. Produces canonical commit `<type>(<ID>): complete phase <N> - <name>` (`FEAT-`→`feat`, `CHORE-`→`chore`, `BUG-`→`fix`). Runs `git add -A` + commit, detects upstream, pushes (`-u origin <branch>` on first push; bare `git push` after). Stdout `pushed <branch>`. Exit `1` on `no changes to commit`, `git add` failure (stderr `[error] git add failed`), hook rejection, or push failure (git stderr verbatim + `[error] push failed; see Push Failure Recovery in SKILL.md`). Exit `2` on malformed args.

9. Transition status to "✅ Complete": `bash "$SCRIPTS/plan-status-marker.sh" "<plan-path>" <phase-N> complete`.
10. **After all phases complete:** Create pull request — gate on `verify-all-phases-complete.sh`, then invoke `create-pr.sh` (MUST include `Closes #N` if issue exists):

    ```bash
    bash "$SCRIPTS/verify-all-phases-complete.sh" "<plan-path>"
    bash "${CLAUDE_PLUGIN_ROOT}/scripts/create-pr.sh" feat "<FEAT-NNN>" "<summary>" [--closes <issueRef>]
    ```

    `verify-all-phases-complete.sh`: exit `0` with `all phases complete` only when every phase is `✅ Complete`; otherwise `1` with JSON `{"incomplete":[{"phase":<N>,...}...]}` — or stderr `[error] no phase blocks found in plan` when the plan has no `### Phase` blocks. Treat any non-zero as "do not create PR". `create-pr.sh`: reads current branch, runs `git push -u origin <branch>`, assembles title `feat(<FEAT-NNN>): <summary>`, substitutes `scripts/assets/pr-body.tmpl`, runs `gh pr create`. Pass `--closes #N` when a GitHub issue exists. Exit `0` PR URL on stdout; `1` on git/gh failure; `2` on malformed args.

> **Note:** Issue tracking (start/completion comments) is handled by the orchestrator via `managing-work-items`. This skill focuses on implementation, verification, and status tracking.

## Push Failure Recovery

On push rejection, resolve with `git fetch origin && git rebase origin/<branch> && git push` — do not re-run `commit-and-push-phase.sh` after rebasing. On auth failure, re-authenticate (e.g. `gh auth login`) and retry `git push`. See the Push Failure Recovery section in [step-details.md](references/step-details.md) for rationale.

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

- **Error messages from `fail` calls** -- users need the reason the skill halted. Surface script and tool stderr verbatim (e.g., `resolve-requirement-doc.sh`, `next-pending-phase.sh`, `plan-status-marker.sh`, `build-branch-name.sh`, `ensure-branch.sh`, `check-deliverable.sh`, `verify-phase-deliverables.sh`, `commit-and-push-phase.sh`, `verify-all-phases-complete.sh`, `create-pr.sh` failures).
- **Security-sensitive warnings** -- destructive-operation confirmations, credential prompts.
- **Interactive prompts** -- any prompt that blocks the workflow and requires user input (e.g., disambiguation when multiple plan files match the provided ID, phase-selection prompt when the supplied phase number exceeds the plan's phase count, summary re-prompt when `build-branch-name.sh` exits `1` on an empty slug).
- **Findings display from `reviewing-requirements`** -- N/A for this skill (it does not consume reviewing-requirements findings); bullet retained for consistency with the canonical template.
- **FR-14 console echo lines** -- `[model] step {N} ({skill}) → {tier} (...)` audit-trail lines emitted by `prepare-fork.sh`. The Unicode `→` is the documented emitter format; do not rewrite to ASCII.
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
- [ ] Execute implementation steps, checking off deliverables (- [ ] -> - [x]) as completed
- [ ] Verify deliverables
- [ ] Always commit and push changes to remote (do not prompt — this is mandatory)
- [ ] Update plan status to "✅ Complete"
- [ ] Create pull request after all phases complete (include "Closes #N" in body if issue exists)
```

**Important:** Including `Closes #N` in the PR body auto-closes the linked GitHub issue when merged. Without it, the issue must be closed manually.

See [step-details.md](references/step-details.md) for detailed guidance on each step.

## Phase Structure

Plans use `### Phase N: <name>` headings with a `**Status:**` line (`Pending` / `🔄 In Progress` / `✅ Complete`), a `**Feature:**` reference line including the `[#N]` GitHub issue (supplies `Closes #N`), and `#### Rationale`, `#### Implementation Steps`, `#### Deliverables` subsections. Deliverables are `- [ ]` lines — typically a leading backticked path (e.g. `` - [x] `path/to/file.ts` - description ``) for file deliverables.

## Branch Naming

Format: `feat/{Feature ID}-{2-3-word-summary}`. Assemble via `bash "${CLAUDE_PLUGIN_ROOT}/scripts/build-branch-name.sh" feat "<FEAT-NNN>" "<summary>"` (see Step 4) rather than hand-kebabing. Examples: `feat/FEAT-001-scaffold-skill-command`, `feat/FEAT-002-validate-skill-command`, `feat/FEAT-007-chore-task-skill`.

## Verification

Before marking a phase complete, `verify-phase-deliverables.sh` (Step 7) must exit `0` — files present, `lint` / `format` / `test` / `build` / `coverage` all `pass` or `skipped`. `commit-and-push-phase.sh` (Step 8) must report `pushed <branch>` before the `✅ Complete` transition (blocking). After all phases: `verify-all-phases-complete.sh` must exit `0` before `create-pr.sh` is called.

## References

- **Complete workflow example**: [workflow-example.md](references/workflow-example.md) - Full Phase 2 implementation walkthrough
- **Detailed step guidance**: [step-details.md](references/step-details.md) - In-depth explanation of each workflow step
- **PR template**: [assets/pr-template.md](assets/pr-template.md) - Pull request format for feature implementations
