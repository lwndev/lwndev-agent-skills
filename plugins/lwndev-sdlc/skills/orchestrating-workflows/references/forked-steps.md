# Forked Steps — Full Recipe

**Scope**: This recipe applies **only** to steps marked **fork** in the Feature/Chore/Bug chain step-sequence tables in SKILL.md. Cross-cutting skills — skills that are not listed in any chain step table, such as `managing-work-items` — do **not** follow this recipe. They are executed inline from the orchestrator's main context per the "How to Invoke `managing-work-items`" subsection in [issue-tracking.md](issue-tracking.md). If you find yourself trying to apply the Forked Steps recipe to `managing-work-items`, stop: that skill has a different invocation mechanism and the two do not overlap.

For all steps marked **fork** in the step sequence, use the Agent tool to delegate. Every fork site must execute the FEAT-014 pre-fork ceremony **before** spawning the subagent — the audit trail write must precede fork execution (NFR-3) so a crashed fork still leaves a trace. The four-step ceremony (SKILL.md readability check, tier resolution, audit-trail write, FR-14 echo line) is composed into a single script invocation (FEAT-021 FR-1):

1. **Run the pre-fork ceremony** via `prepare-fork.sh`. The script reads the sub-skill's SKILL.md (verifying it exists and is readable), resolves the FEAT-014 tier via `workflow-state.sh resolve-tier`, writes the `modelSelections` audit-trail entry via `workflow-state.sh record-model-selection` (NFR-3: before the fork executes), and emits the FR-14 console echo line to stderr. It prints the resolved tier on stdout:

   ```bash
   tier=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/prepare-fork.sh" {ID} {stepIndex} {skill-name} \
     ${mode:+--mode $mode} ${phase:+--phase $phase} \
     ${cli_model:+--cli-model $cli_model} \
     ${cli_complexity:+--cli-complexity $cli_complexity} \
     ${cli_model_for:+--cli-model-for $cli_model_for})
   ```

   `{skill-name}` is the canonical step-name from the "Fork Step-Name Map" below. On non-zero exit, propagate the error and abort the fork — do **not** spawn the Agent tool. For the PR-creation fork site, pass `pr-creation` as `{skill-name}` (not the state-file's `"orchestrator"` label — see the FEAT-021 FR-1 PR-creation caveat). Pass `--mode standard` for `reviewing-requirements` forks and `--phase {N}` for `implementing-plan-phases` forks; these flags are rejected by the script on mismatched skill-names. The Edge Case 11 hard-override-below-baseline warning (if applicable) is emitted by the script itself — no additional echo is required here.

2. Spawn a general-purpose subagent via the Agent tool. The prompt must include:
   - The full SKILL.md content (read it separately; `prepare-fork.sh` only verifies readability, it does not print the file)
   - The work item ID as argument (e.g., `FEAT-003` or `CHORE-001`)
   - Any step-specific instructions (see below)

   **Pass the resolved `${tier}` captured from step 1's stdout as the `model` parameter to the Agent tool on every fork** (FEAT-014 FR-9). No fork inherits the parent conversation's model by default.

3. Wait for the subagent to return a summary.

4. **NFR-6 Agent-tool-rejection fallback (per call site)**. If the Agent tool call in step 3 errors with an "unknown parameter" error on `model` (Claude Code older than 2.1.72), the orchestrator must **retry the same fork exactly once without the `model` parameter** and emit the documented warning line to the console: `[model] Agent tool rejected model parameter — falling back to parent-model inheritance for this fork. Upgrade to Claude Code 2.1.72+ for adaptive selection.` The retry uses the same prompt and the same subagent identity; it does not append a new `modelSelections` entry (the initial audit-trail write inside `prepare-fork.sh` already captured the intended tier). This wrapper is **per call site** so it composes cleanly with the FR-11 retry classifier below — both can fire for the same fork, but the NFR-6 fallback triggers on tool-parameter errors whereas FR-11 triggers on classifier-flagged output failures.

5. **FR-11 retry-with-tier-upgrade (per call site)**. After the subagent returns, classify its output:
   - **Classifier-flagged failure**: the subagent returned an empty artifact, or its run hit the tool-use loop limit. These are the only two failure modes that count as "possibly under-provisioned".
   - **NOT a failure**: a `reviewing-requirements` fork that returns structured findings (the `Found **N errors**, **N warnings**, **N info**` summary line, or the `No issues found` sentinel). Those are legitimate results and must flow through the Reviewing-Requirements Findings Handling path — do **not** retry with an upgraded tier.
   - **NOT a failure**: any subagent error that originated from user-authored content (bad input, missing doc, malformed plan). Those surface through the normal `fail` path.

   When a classifier-flagged failure occurs, retry the fork **once** at the next tier up using the pure helper `${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh next-tier-up <current-tier>`. Tier escalation is `haiku → sonnet → opus → fail`; each fork's retry budget is `1` (independent per-fork — one failing step does not reduce the budget for subsequent steps). The retry **must**:
   1. Compute the escalated tier via `next-tier-up`. If the current tier is already `opus`, call `fail {ID} "retry exhausted at opus for step N"` and halt. Do not emit a second retry.
   2. Write a new `modelSelections` audit-trail entry for the retry via `${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh record-model-selection` before re-invoking the Agent tool — the original entry is preserved so the audit trail shows both attempts. (The retry path calls `record-model-selection` directly rather than re-running `prepare-fork.sh`, because the SKILL.md readability check and original tier resolution are already complete.)
   3. Emit a fresh FR-14 console echo line for the retry attempt, tagged with the new tier.
   4. Re-invoke the Agent tool with the escalated `model` parameter. If that attempt also classifies as a failure, call `fail {ID} "retry exhausted at <escalated-tier> for step N"` (unless the escalated tier itself was already `opus`, in which case retry is exhausted after this second attempt) and halt.

   The NFR-6 wrapper from step 4 still applies to the retry call — if the escalated-tier fork is rejected by an older Claude Code, the parent-model fallback kicks in on that retry too.

6. Validate the expected artifact exists (use Glob to check). If the artifact is missing after both the NFR-6 fallback and FR-11 retry paths have had their chance, record failure:
   ```bash
   ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh fail {ID} "Step N: expected artifact not found"
   ```

7. On success, advance state:
   ```bash
   ${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh advance {ID} "{artifact-path}"
   ```

## Fork Step-Name Map

The `resolve-tier` and `record-model-selection` subcommands key off canonical step-names (not the human-readable table names). Use these exact strings:

| Fork site | Step-name | Baseline | Baseline-locked? |
|-----------|-----------|----------|------------------|
| Review requirements (standard) | `reviewing-requirements` | sonnet | no |
| Create implementation plan | `creating-implementation-plans` | sonnet | no |
| Implement phases (per-phase) | `implementing-plan-phases` | sonnet | no |
| Execute chore | `executing-chores` | sonnet | no |
| Execute bug fix | `executing-bug-fixes` | sonnet | no |
| Finalize workflow | `finalizing-workflow` | haiku | **yes** |
| PR creation (inline fork) | `pr-creation` | haiku | **yes** |

For `reviewing-requirements` call sites, pass the mode (`standard`) as the `mode` argument of `record-model-selection`. For `implementing-plan-phases`, pass the phase number as the `phase` argument. All other sites pass `null` for both.
