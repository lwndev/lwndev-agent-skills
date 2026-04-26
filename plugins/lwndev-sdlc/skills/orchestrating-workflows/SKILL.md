---
name: orchestrating-workflows
description: Orchestrate full SDLC workflow chains (feature, chore, bug) end-to-end by sequencing sub-skill invocations, managing state across pause points, and isolating per-step context via Agent tool forking.
argument-hint: "<title-or-issue> or <ID>"
compatibility: Requires jq and a bash-compatible shell
hooks:
  Stop:
    - hooks:
        - type: command
          command: "${CLAUDE_PLUGIN_ROOT}/skills/orchestrating-workflows/scripts/stop-hook.sh"
---

# Orchestrating Workflows

Drive an SDLC workflow chain through a single skill invocation. The orchestrator sequences sub-skill calls, manages persistent state across pause points, and isolates per-step context by forking sub-skills into subagents.

## When to Use This Skill

- User wants to run a full feature, chore, or bug workflow end-to-end
- User says "orchestrate workflow", "run full workflow", "start workflow chain"
- User provides a workflow ID to resume a paused or failed workflow

## Arguments

- **Argument provided**: If the argument matches a workflow ID pattern (`FEAT-NNN`, `CHORE-NNN`, `BUG-NNN`), check for an existing state file at `.sdlc/workflows/{ID}.json` and resume if found. A `FEAT-NNN` ID resumes a feature chain; `CHORE-NNN` resumes a chore chain; `BUG-NNN` resumes a bug chain. A `#N` GitHub issue reference starts a new feature workflow from that issue. Otherwise treat the argument as a free-text title and start a new workflow (feature by default; ask if ambiguous). **Branch-name fallback for resume**: when the user says "resume" or "continue" without an explicit ID, classify the current branch name with `bash "${CLAUDE_PLUGIN_ROOT}/scripts/branch-id-parse.sh" "$(git rev-parse --abbrev-ref HEAD)"` — the script applies the three regexes (`^feat/(FEAT-[0-9]+)-`, `^chore/(CHORE-[0-9]+)-`, `^fix/(BUG-[0-9]+)-`) and emits JSON `{"id": "...", "type": "...", "dir": "..."}` on stdout. Exit `0` means the branch carries an ID — resume that workflow via the state file. Exit `1` means no match — ask the user for an explicit ID. Exit `2` on missing arg.
- **No argument**: Ask for a title, GitHub issue reference (`#N`), or workflow ID to resume.
- **Chore workflows**: Start when `documenting-chores` (step 1) assigns the `CHORE-NNN` ID. The user may indicate a chore by saying "chore", "maintenance task", or similar.
- **Bug workflows**: Start when `documenting-bugs` (step 1) assigns the `BUG-NNN` ID. The user may indicate a bug by saying "bug", "fix", "defect", "regression", or similar.

### Model-Selection Flags (FEAT-014 FR-8)

Three additive, positional-independent flags tune per-workflow model selection. They may appear before or after the ID / `#N` / title argument and do not change the existing argument shapes.

- `--model <tier>` — **hard blanket** override. Replaces every non-locked fork's tier with `<tier>` (`haiku`, `sonnet`, or `opus`). May downgrade below baseline; the orchestrator emits a one-line baseline-bypass warning when it does (Edge Case 11). Baseline-locked forks are still pushed by a hard override.
- `--complexity <tier>` — **soft blanket** override. Treated as a `low|medium|high` (or equivalent tier string) floor for work-item complexity. Upgrade-only; respects baseline locks.
- `--model-for <step>:<tier>` — **hard per-step** override. Replaces the tier for a single named step (e.g. `--model-for reviewing-requirements:opus`). Per-step hard beats blanket hard (FR-5 #1 > #2). May be repeated.

Parsing: run `bash "${CLAUDE_PLUGIN_ROOT}/skills/orchestrating-workflows/scripts/parse-model-flags.sh" "$@"` — emits `{cliModel, cliComplexity, cliModelFor, positional}` on stdout; exit `2` on unknown flag, malformed tier, or `=`-form. Pass `cliModel` and `cliComplexity` as scalar tier strings into every `${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh resolve-tier` call. `cliModelFor` is a JSON map (`{"<step>":"<tier>", ...}` or `null`) — convert it to repeated `--cli-model-for <step>:<tier>` flag-value pairs before forwarding to `prepare-fork.sh`; see [step-execution-details.md](references/step-execution-details.md) "Preparing fork flags" for the conversion pattern.

## Issue Tracking via `managing-work-items`

The orchestrator integrates with issue trackers (GitHub Issues, Jira) through the `managing-work-items` skill. Issue tracking is additive and executed inline from main context — existing workflow steps remain unchanged. When no issue reference is found, tracking is skipped with an info-level message; mechanism failures emit a warning-level message.

For the full issue tracking protocol — extraction, invocation pattern, runnable examples, rejected alternatives, and mechanism-failure logging — see [references/issue-tracking.md](references/issue-tracking.md).

## Approval-Marker Grammar (BUG-014)

Every confirmation gate is enforced by a Claude Code hook that requires a fresh `.sdlc/approvals/.approval-<gate>-<ID>` marker. Markers are written by Hook A (`record-approval.sh`) only on real `UserPromptSubmit` events — auto-mode self-prompts produce no marker. To approve a gate, type one of the canonical shapes below verbatim. Case-insensitive on the keyword; the workflow ID is uppercase by convention.

| Shape | Marker written | Use at |
|-------|----------------|--------|
| `approve plan-approval <ID>` | `.approval-plan-approval-<ID>` | feature-chain plan-approval pause (step 4) |
| `approve pr-review <ID>` | `.approval-pr-review-<ID>` | PR-review pause (any chain) |
| `approve findings-decision <ID>` | `.approval-findings-decision-<ID>` | reviewing-requirements findings-decision gate |
| `approve review-findings <ID>` | `.approval-review-findings-<ID>` | reviewing-requirements errors-present pause |
| `proceed <ID>` / `yes <ID>` | resolved against active gate, then pauseReason | shorthand at any pause / gate |
| `merge <ID>` | `.approval-merge-approval-<ID>` | required for `gh pr merge` and the `finalizing-workflow` fork |
| `pause <ID>` | `.approval-pause-<ID>` | explicit decline (future use) |

Examples — copy-paste verbatim:

```
approve plan-approval BUG-014
approve pr-review FEAT-099
approve findings-decision CHORE-042
proceed BUG-014
merge BUG-014
```

Unknown shapes are silently ignored. If a hook denies a tool call, the deny message names the exact shape required (e.g. `User must type: approve plan-approval BUG-014`).

## Quick Start

1. Parse argument — determine new workflow vs resume, and chain type (feature, chore, or bug)
2. **Check Claude Code version (FEAT-014 NFR-6)**: run `${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh check-claude-version 2.1.72` once at the entry point. The subcommand exits `0` silently when current ≥ required (or when the version cannot be determined), and exits `1` with a one-line warning on stderr when the installed Claude Code is older than the minimum. Treat the warning as advisory — continue the workflow; the per-fork NFR-6 fallback wrapper (see "Forked Steps") will catch any Agent-tool `model`-parameter rejection and retry without the parameter.
3. **New feature workflow**: run step 1 (`documenting-features`) in main context; then `bash "${CLAUDE_PLUGIN_ROOT}/skills/orchestrating-workflows/scripts/init-workflow.sh" feature <artifact-path>` (emits `{id, type, complexity, issueRef}`).
4. **New chore workflow**: run step 1 (`documenting-chores`); then `init-workflow.sh chore <artifact-path>` (same JSON shape).
5. **New bug workflow**: run step 1 (`documenting-bugs`); then `init-workflow.sh bug <artifact-path>` (same JSON shape).
6. **Resume**: Load state, handle pause/failure logic, continue from current step
7. Execute steps sequentially using the step execution procedures below
8. **Feature chain**: Pause at plan approval (step 4) and PR review (step 5+N+2)
9. **Chore chain**: Pause at PR review only (step 5) — no plan-approval pause
10. **Bug chain**: Pause at PR review only (step 5) — no plan-approval pause, same as chore chain
11. On completion, mark workflow complete

## Output Style

The orchestrator and its forked subagents must follow the lite-narration rules below. These rules minimize output tokens without discarding load-bearing signals. Load-bearing carve-outs (listed below) MUST be emitted as specified; they are not narration.

### Lite narration rules

- No preamble before tool calls. Do not announce "let me check" or "I'll run" — issue the tool call.
- No end-of-turn summaries beyond one short sentence. Do not recap what the user can read from tool output.
- No emoji. ASCII punctuation only.
- No restating what the user just said.
- No status echoes that tools already show (e.g., the contents of a successful `git status`).
- Prefer ASCII arrows (`->`) and punctuation over Unicode alternatives in orchestrator-authored prose. Existing Unicode em dashes in tables and reference docs are retained. **Script-emitted structured logs are out of scope for this rule** — FR-14 echoes, `[model]` complexity-upgrade notices, and other `prepare-fork.sh` / `workflow-state.sh` output use Unicode `→` as their documented format (see carve-out below); do not normalize them.
- Short sentences over paragraphs. Bullet lists over prose when listing more than two items.

### Load-bearing carve-outs (never strip)

The following MUST always be emitted even when they resemble narration:

- **Error messages from `fail` calls** — users need the reason the workflow halted.
- **Security-sensitive warnings** — destructive-operation confirmations, credential prompts, baseline-bypass warnings.
- **Interactive prompts** — plan-approval pause prompts, findings-decision prompts, review-findings prompts. These block the workflow and must be visible.
- **Findings display from `reviewing-requirements`** — the full findings list must be shown to the user before any findings-decision prompt. Do not truncate.
- **FR-14 console echo lines** — `[model] step {N} ({skill}) → {tier} (...)` audit-trail lines emitted by `prepare-fork.sh`. The Unicode `→` is the documented emitter format (matches `prepare-fork.bats` assertions and `references/step-execution-details.md`); do not rewrite to ASCII.
- **Tagged structured logs** — any line prefixed `[info]`, `[warn]`, or `[model]` is a structured log, not narration. Emit verbatim.
- **User-visible state transitions** — pause, advance, and resume announcements (at most one line each) so the user understands where the workflow is.

### Fork-to-orchestrator return contract

Subagents forked from this orchestrator MUST return a contract line as the **final line** of their response. The orchestrator parses the last matching line. Three canonical shapes are defined:

- `done | artifact=<path> | <note-of-at-most-10-words>` — success. `<path>` is the artifact the fork produced; the note is optional context.
- `failed | <one-sentence reason>` — failure. The orchestrator's FR-11 classifier treats an empty artifact or tool-loop exhaustion as failure; `failed |` is the explicit token a subagent emits to declare failure itself.
- `Found **N errors**, **N warnings**, **N info**` — retained shape for `reviewing-requirements` forks **only**. This is the pre-existing findings shape; the orchestrator's Decision Flow (see Reviewing-Requirements Findings Handling) parses error/warning/info counts from it. `reviewing-requirements` does not emit the `done | ...` shape.

**Precedence**: the return contract takes precedence over the lite rules when the two conflict. Subagents MUST emit the contract shape even if it reads like narration. For `reviewing-requirements`, the full findings block (which the orchestrator displays to the user) still precedes the `Found **N errors** ...` summary line.

## Feature Chain Step Sequence

## Chore Chain Step Sequence

## Bug Chain Step Sequence

All three chains share a common shape, parameterized by chain type. The table below consolidates the Feature, Chore, and Bug step sequences; per-chain deltas follow. The Feature, Chore, and Bug section headings above all index into this one table.

| # | Applies to | Step | Skill | Context |
|---|------------|------|-------|---------|
| 1 | feature / chore / bug | Document requirements / chore / bug | `documenting-features` / `documenting-chores` / `documenting-bugs` | **main** |
| 2 | feature / chore / bug | Review requirements (standard) | `reviewing-requirements` | fork (chore / bug: skip if `complexity == low`) |
| 3 | feature only | Create implementation plan | `creating-implementation-plans` | fork |
| 4 | feature only | **PAUSE: Plan approval** | — | pause |
| 5 | feature | Document QA test plan | `documenting-qa` | **main** |
| 3 | chore / bug | Document QA test plan | `documenting-qa` | **main** |
| 6…5+N | feature only | Implement phases 1…N | `implementing-plan-phases` | fork |
| 4 | chore | Execute chore | `executing-chores` | fork |
| 4 | bug | Execute bug fix | `executing-bug-fixes` | fork |
| 5+N+1 | feature only | Create PR | orchestrator | fork |
| 5+N+2 | feature | **PAUSE: PR review** | — | pause |
| 5 | chore / bug | **PAUSE: PR review** | — | pause |
| 5+N+3 | feature | Execute QA | `executing-qa` | **main** |
| 6 | chore / bug | Execute QA | `executing-qa` | **main** |
| 5+N+4 | feature | Finalize | `finalizing-workflow` | fork |
| 7 | chore / bug | Finalize | `finalizing-workflow` | fork |

**Per-chain deltas** (every difference the three original tables conveyed):

- **Feature chain** has `5 + N + 4` steps (N = phase count). Steps 3–4 (plan + plan-approval pause) and the step 6…5+N phase loop are **feature-only**. PR creation is a separate fork step (5+N+1) before the PR-review pause. Post-plan re-classification runs immediately after step 3.
- **Chore chain** has a fixed `7` steps — no implementation plan, no plan-approval pause, no phase loop. PR creation is handled inside the step 4 `executing-chores` fork (not a separate orchestrator fork).
- **Bug chain** has a fixed `7` steps mirroring the chore chain with bug-specific skills. PR creation is handled inside the step 4 `executing-bug-fixes` fork.
- **`complexity == low` skip**: chore and bug step 2 (`reviewing-requirements`) is skipped when persisted complexity is `low` — call `advance` with no fork (see [references/step-execution-details.md](references/step-execution-details.md)). Feature chains always run step 2.
- **Pause points**: feature chain pauses at step 4 (plan approval) and step 5+N+2 (PR review); chore and bug chains pause at step 5 (PR review) only.

## Chain Workflow Procedures

Step-by-step procedures for starting new feature, chore, and bug workflows (active-marker creation, step 1 execution, ID allocation, issue-reference extraction, state initialization, complexity classification) and the resume procedure for paused or failed workflows live in the chain-procedures reference.

See [references/chain-procedures.md](references/chain-procedures.md) for the full New Feature, New Chore, New Bug, and Resume procedures.

## Step Execution

For each step, determine the context from the Chain Step Sequence table above and execute accordingly. The forked-step and main-context-step patterns are shared across all chains.

### Main-Context Steps

These steps run directly in the orchestrator's conversation because they rely on Stop hooks or interactive prompts that don't work when forked.

#### Feature Chain Main-Context Steps (Steps 1, 5, 5+N+3)

**Step 1 — `documenting-features`**: See New Feature Workflow Procedure in [references/chain-procedures.md](references/chain-procedures.md).

**Step 5 — `documenting-qa`**: Read the SKILL.md content from `${CLAUDE_PLUGIN_ROOT}/skills/documenting-qa/SKILL.md`. Follow its instructions directly in this conversation, passing the workflow ID as argument. Expected artifact: `qa/test-plans/QA-plan-{ID}.md`. On completion:

```bash
${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh advance {ID} "qa/test-plans/QA-plan-{ID}.md"
```

**Step 5+N+3 — `executing-qa`**: Read the SKILL.md content from `${CLAUDE_PLUGIN_ROOT}/skills/executing-qa/SKILL.md`. Follow its instructions directly in this conversation, passing the workflow ID as argument. Expected artifact: `qa/test-results/QA-results-{ID}.md`.

Immediately after the skill returns and before calling `advance`, parse the return contract line and persist findings:

```bash
qa_parsed=$(echo "$qa_response" | bash "${CLAUDE_SKILL_DIR}/scripts/parse-qa-return.sh" --stdin --artifact "qa/test-results/QA-results-{ID}.md")
```

On parse success, persist via:

```bash
${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh record-findings --type qa {ID} {stepIndex} \
  "$(echo "$qa_parsed" | jq -r .verdict)" \
  "$(echo "$qa_parsed" | jq -r .passed)" \
  "$(echo "$qa_parsed" | jq -r .failed)" \
  "$(echo "$qa_parsed" | jq -r .errored)" \
  "$(echo "$qa_parsed" | jq -r .summary)"
```

Then advance:

```bash
${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh advance {ID} "qa/test-results/QA-results-{ID}.md"
```

On parse mismatch (non-zero exit from `parse-qa-return.sh`), halt the workflow:

```bash
${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh fail {ID} "<contract-mismatch error from parse-qa-return.sh stderr>"
```

Surface the contract-mismatch error verbatim — this is a load-bearing carve-out, not narration.

**Note**: the orchestrator does NOT change advance behavior based on verdict. Verdict-based gating is out of scope; FR-12 is persistence-only.

#### Chore Chain Main-Context Steps (Steps 1, 3, 6)

**Step 1 — `documenting-chores`**: See New Chore Workflow Procedure in [references/chain-procedures.md](references/chain-procedures.md).

**Step 3 — `documenting-qa`**: Same pattern as feature chain step 5. Read `${CLAUDE_PLUGIN_ROOT}/skills/documenting-qa/SKILL.md`, follow its instructions in this conversation, passing the workflow ID as argument. Expected artifact: `qa/test-plans/QA-plan-{ID}.md`. On completion:

```bash
${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh advance {ID} "qa/test-plans/QA-plan-{ID}.md"
```

**Step 6 — `executing-qa`**: Same pattern as feature chain step 5+N+3. Read `${CLAUDE_PLUGIN_ROOT}/skills/executing-qa/SKILL.md`, follow its instructions in this conversation, passing the workflow ID as argument. Expected artifact: `qa/test-results/QA-results-{ID}.md`.

Immediately after the skill returns and before calling `advance`, parse the return contract line and persist findings:

```bash
qa_parsed=$(echo "$qa_response" | bash "${CLAUDE_SKILL_DIR}/scripts/parse-qa-return.sh" --stdin --artifact "qa/test-results/QA-results-{ID}.md")
```

On parse success, persist via:

```bash
${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh record-findings --type qa {ID} {stepIndex} \
  "$(echo "$qa_parsed" | jq -r .verdict)" \
  "$(echo "$qa_parsed" | jq -r .passed)" \
  "$(echo "$qa_parsed" | jq -r .failed)" \
  "$(echo "$qa_parsed" | jq -r .errored)" \
  "$(echo "$qa_parsed" | jq -r .summary)"
```

Then advance:

```bash
${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh advance {ID} "qa/test-results/QA-results-{ID}.md"
```

On parse mismatch, halt with `fail` and surface the contract-mismatch error verbatim (load-bearing carve-out). The orchestrator does NOT gate advance on verdict — verdict-based gating is out of scope.

### Forked Steps

Forked steps use the Agent tool with the FEAT-014 pre-fork ceremony composed into `prepare-fork.sh` (FEAT-021 FR-1). Cross-cutting skills like `managing-work-items` are executed inline from main context (see Issue Tracking) — they do **not** follow the forked-step recipe.

See [references/forked-steps.md](references/forked-steps.md) for the full seven-step fork recipe (pre-fork ceremony, Agent-tool spawn with `model` parameter, NFR-6 fallback, FR-11 retry classifier, artifact validation, advance) and the Fork Step-Name Map.

### Reviewing-Requirements Findings Handling

After each `reviewing-requirements` fork (feature step 2; chore/bug step 2) the orchestrator parses the subagent's return text for the `Found **N errors**, **N warnings**, **N info**` summary line, runs the Decision Flow (zero-findings auto-advance; warnings-only gate by chain type and complexity; errors block and prompt for apply-fixes vs pause), applies any auto-fixes in main context, persists findings via `record-findings` before every `advance` or `pause`, and re-runs the fork at most once.

See [references/reviewing-requirements-flow.md](references/reviewing-requirements-flow.md) for the full parsing rules, Decision Flow, Applying Auto-Fixes sequence, Decision-to-Call mapping table, and individual-findings parsing procedure for `auto-advanced` decisions.

### Chain-Specific Step Details

Chain-specific fork instructions for feature, chore, and bug chains (skip conditions, issue-tracking invocations, post-step-3 re-classification), pause step procedures, the phase loop for feature chains, and PR creation are documented in the step execution details reference.

See [references/step-execution-details.md](references/step-execution-details.md) for the full chain-specific fork instructions, pause steps, phase loop, and PR creation.

## Model Selection

This section summarizes the FEAT-014 adaptive model selection policy that every fork in this skill obeys. For the full algorithm pseudocode, tuning guidance, audit-trail field reference, known limitations, and migration guidance, read `references/model-selection.md` — that file is the canonical reference and this section is a concise summary.

Per-fork model selection is a two-axis lookup combined with an override chain. The orchestrator runs the `resolve-tier` subcommand of `${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh` before every fork; the return value is passed verbatim as the Agent tool's `model` parameter.

```text
final_tier = walk_override_chain(
    base = max(step_baseline, work_item_complexity),
    overrides = [cli_model_for, cli_model, cli_complexity, state_model_override]
)
```

Tiers are ordered `haiku < sonnet < opus`. Complexity labels map to tiers via `low → haiku`, `medium → sonnet`, `high → opus`.

### Axis 1 — Step baseline matrix

Each forked step has a baseline tier floor (most are `sonnet`; `finalizing-workflow` and PR creation are `haiku` and baseline-locked). See [references/model-selection.md](references/model-selection.md) for the full step baseline table and rationale.

### Axis 2 — Work-item complexity signal matrix

Complexity is computed at workflow init from requirement-document signals (acceptance criteria count, severity, FR count, etc.) and persisted to state; features may upgrade post-plan via phase count. See [references/model-selection.md](references/model-selection.md) for the full signal matrix and fallback rules.

### Axis 3 — Override precedence (hard vs soft)

Walked in strict precedence order; the first non-null entry wins. Hard overrides replace the tier entirely; soft overrides are upgrade-only and respect baseline locks.

| Order | Override | Kind | Behavior |
|-------|----------|------|----------|
| 1 | CLI `--model-for <step>:<tier>` | hard | Replaces tier for the matching step. Bypasses baseline lock for that step. |
| 2 | CLI `--model <tier>` | hard | Replaces tier for every fork, including baseline-locked steps. Can downgrade below baseline. |
| 3 | CLI `--complexity <tier>` | soft | `max(current, override)` applied via the work-item complexity axis. Respects baseline lock and baseline floor. |
| 4 | State file `modelOverride: <tier>` | soft | Upgrade-only. Respects baseline lock. Editable between pause and resume via `${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh set-complexity`. |
| 5 | Computed tier | — | Lowest precedence. Derived from step baseline and work-item complexity. |

**Hard vs soft in one line**: hard overrides answer "I know exactly what I want; do it"; soft overrides answer "I think this work is at least this complex".

### Baseline-locked step exceptions

`finalizing-workflow` and the inline PR-creation fork are **baseline-locked**:

- The work-item complexity axis is **skipped** for these steps (FR-3 step 2 is a no-op).
- Soft overrides (`--complexity`, state `modelOverride`) are **ignored** — they cannot push baseline-locked steps off their baseline.
- Hard overrides (`--model`, `--model-for`) **bypass** the lock and apply normally — `--model opus` on a feature chain forces `finalizing-workflow` and PR creation to `opus`.

Rationale: these are mechanical `gh` / `git` operations with no reasoning component, regardless of how complex the overall feature is. Upgrading them to a higher tier costs tokens with zero quality benefit. A hard override is the explicit escape hatch for users who want to force them anyway.

## Error Handling

- **Step failure**: Call `${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh fail {ID} "{error message}"`. Display the error clearly. Halt execution. The user can re-invoke to retry.
- **Phase failure**: Halt the phase loop. Do not proceed to subsequent phases or PR creation. Call `fail` with the phase error.
- **QA failure**: `executing-qa` handles retries internally via its own loop. If ultimately unfixable, the orchestrator records the failure.
- **Sub-skill SKILL.md not found**: Display "Error: Skill '{skill-name}' not found at `${CLAUDE_PLUGIN_ROOT}/skills/{skill-name}/SKILL.md`. Check that the lwndev-sdlc plugin is installed." Call `fail`.
- **State file not found on resume**: Display "Error: No workflow state found for {ID}. Start a new workflow with `/orchestrating-workflows "feature title"`."

## Verification Checklist and Skill Relationships

Verification checklists for all chain types (common, feature, chore, bug), managing-work-items checks, issue-tracking verification (Cases A/B/C), and the full relationship-to-other-skills diagram with per-chain skill tables are documented in the verification reference.

See [references/verification-and-relationships.md](references/verification-and-relationships.md) for the full verification checklists and skill relationship tables.
