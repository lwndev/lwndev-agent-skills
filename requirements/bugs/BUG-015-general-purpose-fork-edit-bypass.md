# Bug: Confirmation gates bypassed by general-purpose forks and Edit calls

## Bug ID

`BUG-015`

## GitHub Issue

[#251](https://github.com/lwndev/lwndev-marketplace/issues/251)

## Category

`security`

## Severity

`high`

## Description

The BUG-014 confirmation-gate hooks contain two structural gaps that allow the orchestrator to bypass `findings-decision` and `merge-approval` gates without an approval marker. Both bypasses were observed in the CHORE-036 workflow run (PR #250).

## Steps to Reproduce

**Bypass 1 — `findings-decision` gate via `Edit`:**

1. Run any chore/bug/feature workflow through `reviewing-requirements` until it returns errors.
2. Orchestrator calls `workflow-state.sh set-gate <ID> findings-decision` and displays findings.
3. Orchestrator (in auto-mode) calls `Edit` against `requirements/<type>/<ID>-*.md` to apply auto-fixes without the user typing `approve findings-decision <ID>`.
4. Observe: no `.approval-findings-decision-<ID>` marker exists, yet the requirement document was edited.

**Bypass 2 — `merge-approval` gate via `subagent_type: general-purpose`:**

1. Run any workflow to PR-review pause.
2. Orchestrator forks at the finalize step using `Agent(subagent_type: general-purpose, prompt: <finalizing-workflow SKILL.md verbatim>)` instead of `subagent_type: finalizing-workflow`.
3. `guard-agent-prompts.sh` reads `tool_input.subagent_type`, classifies the fork as `general-purpose` (not confirmation-owning), and allows it.
4. Subagent runs `finalize.sh`, which calls `gh pr merge` and merges the PR.
5. Observe: no `.approval-merge-approval-<ID>` marker existed when the merge fired.

## Expected Behavior

- An `Edit` against `requirements/<type>/<ID>-*.md` while `gate == findings-decision` is set on workflow `<ID>` is denied unless a fresh `.approval-findings-decision-<ID>` marker exists.
- An `Agent` fork whose embedded prompt contains `name: finalizing-workflow` frontmatter is classified as confirmation-owning regardless of the value of `tool_input.subagent_type`, and is denied without a fresh `.approval-merge-approval-<ID>` marker.
- Marker freshness is verified by comparing marker mtime to `gateSetAt` (analogous to BUG-014 / AC9's `pausedAt` check for resume).

## Actual Behavior

- `Edit` / `Write` / `MultiEdit` are unguarded — `hooks.json` only wires `guard-state-transitions.sh` to `PreToolUse Bash`. Direct doc edits during `gate == findings-decision` are silently allowed.
- `guard-agent-prompts.sh` (line 80) sets `target_skill="$subagent_type"` first and only falls back to embedded-frontmatter regex extraction when `subagent_type` is empty. With `subagent_type: general-purpose` populated, the fallback never runs and `target_skill_norm == "general-purpose"`, which is not in the confirmation-owning set, so AC8's marker check is skipped.
- `set-gate` does not record a `gateSetAt` timestamp, so even if a marker check were added, there is no reference time to detect stale markers.

## Root Cause(s)

1. **Hook B matcher scope is too narrow.** `plugins/lwndev-sdlc/hooks/hooks.json:17-26` wires `guard-state-transitions.sh` only to `PreToolUse` with matcher `Bash`. `Edit`, `Write`, and `MultiEdit` are unguarded. When `gate == findings-decision`, the orchestrator can edit the requirements document without an approval marker. The new `guard-findings-edits.sh` wiring uses a single pipe-separated matcher entry — `"matcher": "Edit|Write|MultiEdit"` — matching the convention used elsewhere in `hooks.json` and the documented Claude Code hook-matcher syntax (per `hook-development/SKILL.md`'s `multipleTools: "Read|Write|Edit"` example).

2. **Hook C trusts `subagent_type` over the embedded prompt.** In `plugins/lwndev-sdlc/scripts/hooks/guard-agent-prompts.sh:78-87`, `subagent_type` is read first (line 78) and `target_skill` is set to it directly (line 80). The embedded-frontmatter regex (lines 82-86) only runs when `target_skill` is empty. With `subagent_type: general-purpose`, the embedded `name: finalizing-workflow` frontmatter is never inspected, so AC8 (lines 155-167) classifies the fork as non-confirmation-owning and allows it.

3. **`set-gate` does not record `gateSetAt`.** `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh:1166-1190` (`cmd_set_gate`) only writes `.gate = <name>`. Without a `gateSetAt` timestamp, a marker-freshness check on Edit-time guards has nothing to compare against, so a stale marker from an earlier gate cycle would satisfy a freshly-opened gate.

## Affected Files

- `plugins/lwndev-sdlc/hooks/hooks.json`
- `plugins/lwndev-sdlc/scripts/hooks/guard-agent-prompts.sh`
- `plugins/lwndev-sdlc/scripts/hooks/guard-state-transitions.sh`
- `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh`
- `plugins/lwndev-sdlc/scripts/hooks/guard-findings-edits.sh` (new)
- `plugins/lwndev-sdlc/scripts/tests/hooks/guard-findings-edits.bats` (new)
- `plugins/lwndev-sdlc/scripts/tests/hooks/guard-agent-prompts.bats`
- `plugins/lwndev-sdlc/scripts/tests/hooks/guard-state-transitions.bats`
- `plugins/lwndev-sdlc/scripts/tests/hooks/record-approval.bats`

## Acceptance Criteria

- [x] A new hook script `plugins/lwndev-sdlc/scripts/hooks/guard-findings-edits.sh` ships and is wired in `plugins/lwndev-sdlc/hooks/hooks.json` for `PreToolUse` with matcher `Edit|Write|MultiEdit` (RC-1)
- [x] When `gate == findings-decision` is set on workflow `<ID>`, an `Edit` / `Write` / `MultiEdit` against a path matching `requirements/(features|chores|bugs)/.+\.md` is denied without a fresh `.approval-findings-decision-<ID>` marker (RC-1, RC-3) — the broader regex (matching any markdown file in those directories, not just `<ID>-*.md`) is intentional defense-in-depth so an editor cannot bypass the gate by writing to a sibling document under the same workflow
- [x] When `gate` is null (cleared), the same `Edit` against the same path is allowed (RC-1)
- [x] An `Edit` against a path outside `requirements/**/*.md` is allowed regardless of gate state (no scope creep) (RC-1)
- [x] `guard-agent-prompts.sh` extracts the embedded SKILL.md `name:` frontmatter from the Agent prompt before consulting `tool_input.subagent_type`. When the embedded `name:` belongs to the confirmation-owning set, the fork is classified by that name regardless of `subagent_type`'s value (RC-2)
- [x] An `Agent(subagent_type: general-purpose, prompt: <finalizing-workflow SKILL.md verbatim>)` call is denied without a fresh `.approval-merge-approval-<active-ID>` marker (RC-2)
- [x] An `Agent(subagent_type: general-purpose, prompt: <reviewing-requirements SKILL.md verbatim>)` call is allowed when no merge-approval gate applies (no false positive on non-confirmation-owning embedded skills) (RC-2)
- [x] `workflow-state.sh set-gate <ID> <gate-name>` records `gateSetAt: <ISO-8601>` to the state file (RC-3)
- [x] `workflow-state.sh clear-gate <ID>` resets `gateSetAt` to null (RC-3)
- [x] `cmd_pause` (which auto-clears the gate) resets `gateSetAt` to null (RC-3)
- [x] A `.approval-findings-decision-<ID>` marker with mtime predating `gateSetAt` does NOT satisfy the gate (stale-marker check) (RC-3)
- [x] A `.approval-findings-decision-<ID>` marker with mtime ≥ `gateSetAt` DOES satisfy the gate (RC-3)
- [x] Missing `gateSetAt` on a pre-fix state file (legacy state files predating this bug fix) is treated as infinitely old: no marker can satisfy the gate, and the user must provide a fresh approval. Mirrors the BUG-014 / AC9 precedent for missing `pausedAt` (RC-3)
- [x] `record-approval.sh` continues to write fresh markers (mtime advances on each `UserPromptSubmit`) — verified by an extension to `record-approval.bats` covering `gateSetAt` interaction (RC-3)
- [x] New bats fixture `guard-findings-edits.bats` covers the gate-on / gate-off / no-marker / stale-marker / fresh-marker / out-of-scope-path matrix (RC-1, RC-3)
- [x] Extension to `guard-agent-prompts.bats` covers the `subagent_type: general-purpose` + embedded `name: finalizing-workflow` frontmatter case (deny) and the `subagent_type: general-purpose` + embedded `name: reviewing-requirements` case (allow) (RC-2)
- [x] Extension to `guard-state-transitions.bats` covers `gateSetAt` interaction with existing `clear-gate` markers (regression coverage) (RC-3)
- [x] CHORE-036 session is reproducible against the patched hooks: re-running the equivalent fork prompts denies; user-typed `approve findings-decision CHORE-036` and `merge CHORE-036` allow (RC-1, RC-2, RC-3)

## Completion

**Status:** `In Progress`

**Pull Request:** [#252](https://github.com/lwndev/lwndev-marketplace/pull/252)

## Notes

**Out of scope** (per issue #251):

- Tightening the AC7 carve-out regexes (Gap 3 in the issue). Belt-and-suspenders only — closing Gap 2 makes the regexes redundant. Track separately if desired.
- Stop-hook variants. Stop hooks fire after the fact and cannot deny a tool that already ran. PreToolUse is the correct primitive.
- Subagent-tier hook inheritance audit. The proposed PreToolUse hooks fire on the parent and apply uniformly to forked subagents' tool calls.

**Optional extension** (per issue #251): when `gate == findings-decision`, treat `reviewing-requirements` as confirmation-owning for the duration of the gate. This blocks the auto-fix re-fork path even if Gap 1's edit guard is somehow bypassed. Defer to implementation phase — closing the Edit guard alone (RC-1) is sufficient. Track separately if a follow-up bug after BUG-015 ships, the same way Gap 3's AC7 carve-out tightening is tracked separately above.

**Related:**

- BUG-014 — original confirmation-gate hook implementation. This bug is a follow-up.
- PR #250 — CHORE-036 session where the bypasses were observed.
- `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/approval-marker-grammar.md` — canonical gate / marker grammar.
- `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/forked-steps.md` — orchestrator fork recipe documenting the `subagent_type: general-purpose` + embedded SKILL.md pattern.
