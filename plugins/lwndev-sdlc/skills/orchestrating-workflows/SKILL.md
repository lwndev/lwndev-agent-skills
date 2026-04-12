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

Drive an entire SDLC workflow chain through a single skill invocation. The orchestrator sequences sub-skill calls, manages persistent state across pause points, and isolates per-step context by forking sub-skills into subagents.

## When to Use This Skill

- User wants to run a full feature, chore, or bug workflow end-to-end
- User says "orchestrate workflow", "run full workflow", "start workflow chain"
- User provides a workflow ID to resume a paused or failed workflow

## Arguments

- **When argument is provided**: If the argument matches an existing workflow ID pattern (`FEAT-NNN`, `CHORE-NNN`, `BUG-NNN`), check for an existing state file at `.sdlc/workflows/{ID}.json` and resume if found. A `FEAT-NNN` ID resumes a feature chain; a `CHORE-NNN` ID resumes a chore chain; a `BUG-NNN` ID resumes a bug chain. If the argument is a `#N` GitHub issue reference, start a new feature workflow from that issue. Otherwise, treat the argument as a free-text title and start a new workflow (feature by default; ask the user if ambiguous).
- **When no argument is provided**: Ask the user for a title, GitHub issue reference (`#N`), or existing workflow ID to resume.
- **Chore workflows**: New chore workflows begin when `documenting-chores` (step 1) assigns the `CHORE-NNN` ID. The user may indicate a chore by saying "chore", "maintenance task", or similar.
- **Bug workflows**: New bug workflows begin when `documenting-bugs` (step 1) assigns the `BUG-NNN` ID. The user may indicate a bug by saying "bug", "fix", "defect", "regression", or similar.

### Model-Selection Flags (FEAT-014 FR-8)

Three additive, positional-independent flags tune per-workflow model selection. They may appear before or after the ID / `#N` / title argument and do not change the existing argument shapes.

- `--model <tier>` — **hard blanket** override. Replaces every non-locked fork's tier with `<tier>` (`haiku`, `sonnet`, or `opus`). May downgrade below baseline; the orchestrator emits a one-line baseline-bypass warning when it does (Edge Case 11). Baseline-locked forks are still pushed by a hard override.
- `--complexity <tier>` — **soft blanket** override. Treated as a `low|medium|high` (or equivalent tier string) floor for work-item complexity. Upgrade-only; respects baseline locks.
- `--model-for <step>:<tier>` — **hard per-step** override. Replaces the tier for a single named step (e.g. `--model-for reviewing-requirements:opus`). Per-step hard beats blanket hard (FR-5 #1 > #2). May be repeated for multiple steps.

Parsing rules: strip each recognised flag and its argument from the argv list before interpreting the remaining positional token as the ID / `#N` / title. Unknown flags are a usage error. Pass the surviving flag values into every `${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh resolve-tier` call so the FR-3 chain sees them.

## Issue Tracking via `managing-work-items`

The orchestrator integrates with issue trackers (GitHub Issues, Jira) through the `managing-work-items` skill. Issue tracking is additive and executed inline from main context — all existing workflow steps remain unchanged. When no issue reference is found, tracking is skipped with an info-level message; mechanism failures emit a warning-level message.

For the full issue tracking protocol — extraction, invocation pattern, runnable examples, rejected alternatives, and mechanism-failure logging — see [references/issue-tracking.md](references/issue-tracking.md).

## Quick Start

1. Parse argument — determine new workflow vs resume, and chain type (feature, chore, or bug)
2. **Check Claude Code version (FEAT-014 NFR-6)**: run `${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh check-claude-version 2.1.72` once at the entry point. The subcommand exits `0` silently when current ≥ required (or when the version cannot be determined), and exits `1` with a one-line warning on stderr when the installed Claude Code is older than the minimum. Treat the warning as advisory — continue the workflow; the per-fork NFR-6 fallback wrapper (see "Forked Steps") will catch any Agent-tool `model`-parameter rejection and retry without the parameter.
3. **New feature workflow**: Run step 1 (`documenting-features`) in main context, read allocated ID, initialize state with `init {ID} feature`
4. **New chore workflow**: Run step 1 (`documenting-chores`) in main context, read allocated ID, initialize state with `init {ID} chore`
5. **New bug workflow**: Run step 1 (`documenting-bugs`) in main context, read allocated ID, initialize state with `init {ID} bug`
6. **Resume**: Load state, handle pause/failure logic, continue from current step
7. Execute steps sequentially using the step execution procedures below
8. **Feature chain**: Pause at plan approval (step 4) and PR review (step 6+N+2)
9. **Chore chain**: Pause at PR review only (step 6) — no plan-approval pause
10. **Bug chain**: Pause at PR review only (step 6) — no plan-approval pause, same as chore chain
11. On completion, mark workflow complete

## Feature Chain Step Sequence

The feature chain has 6 + N + 5 steps where N = number of implementation phases:

| # | Step | Skill | Context |
|---|------|-------|---------|
| 1 | Document requirements | `documenting-features` | **main** |
| 2 | Review requirements (standard) | `reviewing-requirements` | fork |
| 3 | Create implementation plan | `creating-implementation-plans` | fork |
| 4 | **PAUSE: Plan approval** | — | pause |
| 5 | Document QA test plan | `documenting-qa` | **main** |
| 6 | Reconcile test plan | `reviewing-requirements` | fork |
| 7…6+N | Implement phases 1…N | `implementing-plan-phases` | fork |
| 6+N+1 | Create PR | orchestrator | fork |
| 6+N+2 | **PAUSE: PR review** | — | pause |
| 6+N+3 | Reconcile post-review | `reviewing-requirements` | fork |
| 6+N+4 | Execute QA | `executing-qa` | **main** |
| 6+N+5 | Finalize | `finalizing-workflow` | fork |

## Chore Chain Step Sequence

The chore chain has a fixed 9 steps with no phase loop and no plan-approval pause:

| # | Step | Skill | Context |
|---|------|-------|---------|
| 1 | Document chore | `documenting-chores` | **main** |
| 2 | Review requirements (standard) | `reviewing-requirements` | fork (skip if `complexity == low`) |
| 3 | Document QA test plan | `documenting-qa` | **main** |
| 4 | Reconcile test plan | `reviewing-requirements` | fork (skip if `complexity == low`) |
| 5 | Execute chore | `executing-chores` | fork |
| 6 | **PAUSE: PR review** | — | pause |
| 7 | Reconcile post-review | `reviewing-requirements` | fork |
| 8 | Execute QA | `executing-qa` | **main** |
| 9 | Finalize | `finalizing-workflow` | fork |

## Bug Chain Step Sequence

The bug chain has a fixed 9 steps with no phase loop and no plan-approval pause, mirroring the chore chain structure with bug-specific skills:

| # | Step | Skill | Context |
|---|------|-------|---------|
| 1 | Document bug | `documenting-bugs` | **main** |
| 2 | Review requirements (standard) | `reviewing-requirements` | fork (skip if `complexity == low`) |
| 3 | Document QA test plan | `documenting-qa` | **main** |
| 4 | Reconcile test plan | `reviewing-requirements` | fork (skip if `complexity == low`) |
| 5 | Execute bug fix | `executing-bug-fixes` | fork |
| 6 | **PAUSE: PR review** | — | pause |
| 7 | Reconcile post-review | `reviewing-requirements` | fork |
| 8 | Execute QA | `executing-qa` | **main** |
| 9 | Finalize | `finalizing-workflow` | fork |

## Chain Workflow Procedures

Detailed step-by-step procedures for starting new feature, chore, and bug workflows, plus the resume procedure for continuing paused or failed workflows. Each procedure covers active-marker creation, step 1 execution in main context, ID allocation, issue-reference extraction, state initialization, and complexity classification.

For the full procedures — New Feature, New Chore, New Bug, and Resume — see [references/chain-procedures.md](references/chain-procedures.md).

## Step Execution

For each step, determine the context from the appropriate step sequence table (Feature Chain, Chore Chain, or Bug Chain) and execute accordingly. The forked step and main-context step patterns are shared across all chains.

### Main-Context Steps

These steps run directly in the orchestrator's conversation because they rely on Stop hooks or interactive prompts that don't work when forked.

#### Feature Chain Main-Context Steps (Steps 1, 5, 6+N+4)

**Step 1 — `documenting-features`**: See New Feature Workflow Procedure above.

**Step 5 — `documenting-qa`**: Read the SKILL.md content from `${CLAUDE_PLUGIN_ROOT}/skills/documenting-qa/SKILL.md`. Follow its instructions directly in this conversation, passing the workflow ID as argument. Expected artifact: `qa/test-plans/QA-plan-{ID}.md`. On completion:

```bash
${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh advance {ID} "qa/test-plans/QA-plan-{ID}.md"
```

**Step 6+N+4 — `executing-qa`**: Read the SKILL.md content from `${CLAUDE_PLUGIN_ROOT}/skills/executing-qa/SKILL.md`. Follow its instructions directly in this conversation, passing the workflow ID as argument. Expected artifact: `qa/test-results/QA-results-{ID}.md`. On completion:

```bash
${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh advance {ID} "qa/test-results/QA-results-{ID}.md"
```

#### Chore Chain Main-Context Steps (Steps 1, 3, 8)

**Step 1 — `documenting-chores`**: See New Chore Workflow Procedure above.

**Step 3 — `documenting-qa`**: Same pattern as feature chain step 5. Read `${CLAUDE_PLUGIN_ROOT}/skills/documenting-qa/SKILL.md`, follow its instructions in this conversation, passing the workflow ID as argument. Expected artifact: `qa/test-plans/QA-plan-{ID}.md`. On completion:

```bash
${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh advance {ID} "qa/test-plans/QA-plan-{ID}.md"
```

**Step 8 — `executing-qa`**: Same pattern as feature chain step 6+N+4. Read `${CLAUDE_PLUGIN_ROOT}/skills/executing-qa/SKILL.md`, follow its instructions in this conversation, passing the workflow ID as argument. Expected artifact: `qa/test-results/QA-results-{ID}.md`. On completion:

```bash
${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh advance {ID} "qa/test-results/QA-results-{ID}.md"
```

### Forked Steps

**Scope**: This recipe applies **only** to steps marked **fork** in the Feature/Chore/Bug chain step-sequence tables above. Cross-cutting skills — skills that are not listed in any chain step table, such as `managing-work-items` — do **not** follow this recipe. They are executed inline from the orchestrator's main context per the "How to Invoke `managing-work-items`" subsection in the Issue Tracking section. If you find yourself trying to apply the Forked Steps recipe to `managing-work-items`, stop: that skill has a different invocation mechanism and the two do not overlap.

For all steps marked **fork** in the step sequence, use the Agent tool to delegate. Every fork site must execute the FEAT-014 pre-fork sequence **before** spawning the subagent — the audit trail write must precede fork execution (NFR-3) so a crashed fork still leaves a trace:

1. Read the sub-skill's SKILL.md content:
   ```
   ${CLAUDE_PLUGIN_ROOT}/skills/{skill-name}/SKILL.md
   ```

2. **Resolve the tier (FEAT-014 FR-3)**. Call `resolve-tier` with the canonical step-name (see "Fork Step-Name Map" below) and forward any CLI model-selection flags received from the orchestrator invocation:

   ```bash
   tier=$("${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh" resolve-tier {ID} {step-name} \
     ${cli_model:+--cli-model $cli_model} \
     ${cli_complexity:+--cli-complexity $cli_complexity} \
     ${cli_model_for:+--cli-model-for $cli_model_for})
   ```

3. **Write the audit trail entry (FEAT-014 FR-7, NFR-3)**. The write happens BEFORE the fork so a crashed subagent still leaves a trace:

   ```bash
   stage=$(jq -r '.complexityStage // "init"' ".sdlc/workflows/{ID}.json")
   "${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh" record-model-selection \
     {ID} {stepIndex} {skill-name} {mode-or-null} {phase-or-null} "${tier}" "${stage}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
   ```

4. **Emit the FR-14 console echo line** in the documented format. Non-locked forks use `wi-complexity=`; baseline-locked forks (`finalizing-workflow`, `pr-creation`) use the literal `baseline-locked` tag instead:

   ```
   [model] step {N} ({skill}, {mode-or-phase}) → {tier} (baseline={baseline}, wi-complexity={complexity}, override={override-or-none})
   ```

   Baseline-locked example:
   ```
   [model] step 11 (finalizing-workflow) → haiku (baseline=haiku, baseline-locked)
   ```

   If the resolved tier is a hard-override-below-baseline downgrade (Edge Case 11), also emit the warning line: `[model] Hard override --model {tier} bypassed baseline {baseline} for {skill}. Proceeding at user request.`

5. Spawn a general-purpose subagent via the Agent tool. The prompt must include:
   - The full SKILL.md content
   - The work item ID as argument (e.g., `FEAT-003` or `CHORE-001`)
   - Any step-specific instructions (see below)

   **Pass the resolved `${tier}` as the `model` parameter to the Agent tool on every fork** (FEAT-014 FR-9). No fork inherits the parent conversation's model by default.

6. Wait for the subagent to return a summary.

7. **NFR-6 Agent-tool-rejection fallback (per call site)**. If the Agent tool call in step 6 errors with an "unknown parameter" error on `model` (Claude Code older than 2.1.72), the orchestrator must **retry the same fork exactly once without the `model` parameter** and emit the documented warning line to the console: `[model] Agent tool rejected model parameter — falling back to parent-model inheritance for this fork. Upgrade to Claude Code 2.1.72+ for adaptive selection.` The retry uses the same prompt and the same subagent identity; it does not append a new `modelSelections` entry (the initial audit-trail write from step 3 already captured the intended tier). This wrapper is **per call site** so it composes cleanly with the FR-11 retry classifier below — both can fire for the same fork, but the NFR-6 fallback triggers on tool-parameter errors whereas FR-11 triggers on classifier-flagged output failures.

8. **FR-11 retry-with-tier-upgrade (per call site)**. After the subagent returns, classify its output:
   - **Classifier-flagged failure**: the subagent returned an empty artifact, or its run hit the tool-use loop limit. These are the only two failure modes that count as "possibly under-provisioned".
   - **NOT a failure**: a `reviewing-requirements` fork that returns structured findings (the `Found **N errors**, **N warnings**, **N info**` summary line, or the `No issues found` sentinel). Those are legitimate results and must flow through the Reviewing-Requirements Findings Handling path — do **not** retry with an upgraded tier.
   - **NOT a failure**: any subagent error that originated from user-authored content (bad input, missing doc, malformed plan). Those surface through the normal `fail` path.

   When a classifier-flagged failure occurs, retry the fork **once** at the next tier up using the pure helper `${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh next-tier-up <current-tier>`. Tier escalation is `haiku → sonnet → opus → fail`; each fork's retry budget is `1` (independent per-fork — one failing step does not reduce the budget for subsequent steps). The retry **must**:
   1. Compute the escalated tier via `next-tier-up`. If the current tier is already `opus`, call `fail {ID} "retry exhausted at opus for step N"` and halt. Do not emit a second retry.
   2. Write a new `modelSelections` audit-trail entry for the retry via `${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh record-model-selection` before re-invoking the Agent tool — the original entry is preserved so the audit trail shows both attempts.
   3. Emit a fresh FR-14 console echo line for the retry attempt, tagged with the new tier.
   4. Re-invoke the Agent tool with the escalated `model` parameter. If that attempt also classifies as a failure, call `fail {ID} "retry exhausted at <escalated-tier> for step N"` (unless the escalated tier itself was already `opus`, in which case retry is exhausted after this second attempt) and halt.

   The NFR-6 wrapper from step 7 still applies to the retry call — if the escalated-tier fork is rejected by an older Claude Code, the parent-model fallback kicks in on that retry too.

9. Validate the expected artifact exists (use Glob to check). If the artifact is missing after both the NFR-6 fallback and FR-11 retry paths have had their chance, record failure:
   ```bash
   ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh fail {ID} "Step N: expected artifact not found"
   ```

10. On success, advance state:
    ```bash
    ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh advance {ID} "{artifact-path}"
    ```

#### Fork Step-Name Map

The `resolve-tier` and `record-model-selection` subcommands key off canonical step-names (not the human-readable table names). Use these exact strings:

| Fork site | Step-name | Baseline | Baseline-locked? |
|-----------|-----------|----------|------------------|
| Review requirements (standard / test-plan / code-review) | `reviewing-requirements` | sonnet | no |
| Create implementation plan | `creating-implementation-plans` | sonnet | no |
| Implement phases (per-phase) | `implementing-plan-phases` | sonnet | no |
| Execute chore | `executing-chores` | sonnet | no |
| Execute bug fix | `executing-bug-fixes` | sonnet | no |
| Finalize workflow | `finalizing-workflow` | haiku | **yes** |
| PR creation (inline fork) | `pr-creation` | haiku | **yes** |

For `reviewing-requirements` call sites, pass the mode (`standard`, `test-plan`, `code-review`) as the `mode` argument of `record-model-selection`. For `implementing-plan-phases`, pass the phase number as the `phase` argument. All other sites pass `null` for both.

### Reviewing-Requirements Findings Handling

All `reviewing-requirements` fork steps (feature steps 2, 6, 6+N+3; chore steps 2, 4, 7; bug steps 2, 4, 7) require findings handling after the subagent returns. The orchestrator parses the subagent's return text and acts on the findings before advancing.

#### Parsing Findings

After the `reviewing-requirements` subagent returns its summary, parse the summary line for severity counts:

```
Found **N errors**, **N warnings**, **N info**
```

Extract the error, warning, and info counts from this line. If the summary line is not found (e.g., the subagent returned "No issues found"), treat as zero errors, zero warnings, zero info.

#### Decision Flow

Based on the parsed counts, follow this flow:

1. **Zero findings** (zero errors, zero warnings, zero info) → Advance state automatically. No user interaction needed.

2. **Warnings/info only (zero errors)** → Read chain type and complexity from the state file:
   ```bash
   type=$(jq -r '.type' ".sdlc/workflows/{ID}.json")
   complexity=$(jq -r '.complexity // "medium"' ".sdlc/workflows/{ID}.json")
   ```
   Apply the gate:
   - **Bug or chore chain with `complexity == low` or `complexity == medium`** → Log the findings and auto-advance:
     ```
     [info] {N} warnings, {N} info from reviewing-requirements ({mode}) — auto-advancing (chain={type}, complexity={complexity})
     ```
     Display the full findings to the user (for visibility), emit the `[info]` line above, then advance state. Do not prompt.
   - **Bug or chore chain with `complexity == high`**, or **any feature chain** → Display the full findings to the user. Prompt: "{N} warnings and {N} info found by reviewing-requirements. Review findings above and continue? (yes / no)". If the user confirms, advance state. If the user declines, pause the workflow:
     ```bash
     ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh pause {ID} review-findings
     ```
     Halt execution. The user re-invokes with `/orchestrating-workflows {ID}` after addressing findings manually.

3. **Errors present** → Display the full findings to the user. List the auto-fixable items from the "Fix Summary" / "Update Summary" section of the findings. Errors always block progression — present two options:
   - **Apply fixes** → The orchestrator applies the auto-fixable corrections in main context using the Edit tool. Then spawn a **new** `reviewing-requirements` subagent fork to re-verify (this is the re-run, max 1). Parse the re-run findings per the rules in "Applying Auto-Fixes" below.
   - **Pause for manual resolution** → Pause immediately:
     ```bash
     ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh pause {ID} review-findings
     ```
     Halt execution.

#### Applying Auto-Fixes

When the user opts to apply fixes, the orchestrator (not a subagent) applies them:

1. Read the auto-fixable items from the findings (listed under "Auto-fixable" or "Applicable updates" in the subagent's return text)
2. For each fix, use the Edit tool to apply the correction to the target file
3. After all fixes are applied, spawn a new `reviewing-requirements` subagent fork with the same arguments as the original step to re-verify
4. This re-run is the single allowed retry. After the re-run completes, **do not apply any further edits regardless of what the re-run findings contain**:
   - If the re-run returns zero errors → advance state.
   - If the re-run returns warnings/info only (zero errors) → advance state unconditionally. Zero errors after a fix pass means the fixes succeeded; residual warnings are accepted.
   - If the re-run returns errors → display the remaining findings and pause with `review-findings`. Do not attempt to fix the errors.
     ```bash
     ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh pause {ID} review-findings
     ```
     Halt execution.

### Chain-Specific Step Details

Chain-specific fork instructions for feature, chore, and bug chains (including skip conditions, issue-tracking invocations, and post-step-3 re-classification), pause step procedures, the phase loop for feature chains, and PR creation are documented in the step execution details reference.

For the full chain-specific fork instructions, pause steps, phase loop, and PR creation — see [references/step-execution-details.md](references/step-execution-details.md).

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

For the full verification checklists and skill relationship tables — see [references/verification-and-relationships.md](references/verification-and-relationships.md).
