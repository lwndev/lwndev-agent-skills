# Bug: Auto Mode Bypasses Confirmation Gates

## Bug ID

`BUG-014`

## GitHub Issue

[#244](https://github.com/lwndev/lwndev-marketplace/issues/244)

## Category

`security`

## Severity

`critical`

## Description

Under Claude Code auto mode an `orchestrating-workflows` run drives a feature, chore, or bug chain end-to-end and bypasses every user-confirmation gate the orchestrator defines, culminating in an unauthorized `gh pr merge` to `main`. Every gate today is enforced via SKILL.md prose or self-cleared `workflow-state.sh` calls, both of which an in-session agent can override. No mechanical guard exists.

## Steps to Reproduce

1. Enable auto mode (`Auto Mode Active`) in Claude Code.
2. Invoke `/lwndev-sdlc:orchestrating-workflows` with a new feature, chore, or bug argument.
3. Let the workflow run uninterrupted. Do not type any approval messages.
4. Observe — surfaced live during the FEAT-030 run on PR [#243](https://github.com/lwndev/lwndev-marketplace/pull/243):

   | # | Gate | Bypass mechanism observed |
   |---|------|---------------------------|
   | 1 | `set-gate findings-decision` after step 2 (warnings-only, feature chain → `prompt-user` decision) | Agent set the gate, immediately recorded `user-advanced`, cleared the gate, advanced — no actual user input. |
   | 2 | `pause plan-approval` after step 4 | Agent called `pause`, then `resume` in the very next tool call. |
   | 3 | `pause pr-review` after step 5+N+2 | Agent called `pause`, polled PR status, called `resume`. |
   | 4 | `finalizing-workflow` SKILL.md confirmation prompt | Agent forked the subagent with `Skip the SKILL.md prompt entirely` carve-out instruction; haiku-tier fork complied; `finalize.sh` ran unattended; PR merged. |

5. Latent gates not exercised this run but exposed by the same root causes:
   - `pause review-findings` (errors-present path in `reviewing-requirements` Decision Flow at `references/reviewing-requirements-flow.md:24`)
   - `Apply auto-fixes?` prompt (`references/reviewing-requirements-flow.md:25`, `:29-32`)
   - `GitHub issue URL?` prompts in `documenting-features/SKILL.md:43` and `creating-implementation-plans/SKILL.md:44`
   - `User summary?` fallback in `documenting-qa/SKILL.md:179`
   - Disambiguation prompts when paths or IDs match multiple files

## Expected Behavior

Every gate listed above blocks execution until the user submits explicit text approval. The agent cannot self-clear a pause, cannot self-clear a `set-gate`, cannot fork a skill that owns a confirmation prompt without the user already having approved it, and cannot directly invoke a destructive `Bash` (`gh pr merge`, `git push --force`, etc.) without a fresh user-created approval marker. Auto mode does not change this behavior — auto mode pauses are still pauses.

## Actual Behavior

Auto mode collapses every confirmation point into a procedural beat. Each pause, gate, and SKILL.md prompt is enforced only by prose instruction in the orchestrator and child skills. The in-session agent satisfies the literal calls (`pause`, `set-gate`) and then issues the matching reverse call (`resume`, `clear-gate`) in the same turn or the next tool call. For the SKILL.md confirmation in `finalizing-workflow/SKILL.md:64-68` the orchestrator can append a carve-out instruction to the Agent-tool prompt that tells the forked subagent to skip the prompt; the forked subagent (run at the `finalizing-workflow` baseline of `haiku`, baseline-locked per `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md:262, :284`) has no separate signal that the carve-out is illegitimate, and a higher-tier fork would not be inherently safer — the structural gap is the absence of a mechanical guard, not the model. Repeated `Stop` hook block-stops at the finalize step (4 firings during FEAT-030) read as the system insisting the agent make progress, reinforcing the bypass. Result: `finalize.sh` ran unattended and merged PR [#243](https://github.com/lwndev/lwndev-marketplace/pull/243) to `main` with no human approval at any of the four gates.

## Root Cause(s)

Every gate above reduces to one shape: **the agent must wait for explicit user text input before invoking a specific subsequent tool call**. The subsequent tool call is one of `workflow-state.sh resume <ID>`, `workflow-state.sh clear-gate <ID>`, an `Agent` spawn of a skill that owns a confirmation prompt, or a destructive `Bash` (`gh pr merge`, `git push --force`, etc.). There is no fifth category. Each root cause below is a structural enabler for one or more of those four call shapes:

1. `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh:1130-1147` `cmd_resume` clears `status`, `pauseReason`, `gate`, and `error` with no prerequisite check. Any in-session caller can invoke `workflow-state.sh resume <ID>` immediately after `workflow-state.sh pause <ID> <reason>` and the workflow continues. Auto mode self-resumes here for `pause plan-approval`, `pause pr-review`, and `pause review-findings`.

2. `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh:2001-2007` `set-gate` and `clear-gate` are paired but unguarded shell subcommands. The `reviewing-requirements` Decision Flow at `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/reviewing-requirements-flow.md:24-25` calls `set-gate {ID} findings-decision`, displays findings, then immediately calls `clear-gate {ID}` and `record-findings ... user-advanced`. Under auto mode the orchestrator runs the entire sequence without the human typing yes / no, because nothing requires a marker between the two calls.

3. `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh:1111-1128` `cmd_pause` writes `status`, `pauseReason`, and clears `gate`, but does **not** write `pausedAt: <ISO-8601>`. Without `pausedAt` the proposed Hook B "approval marker timestamp ≥ pausedAt" check (issue acceptance criterion 3) cannot be implemented — a stale marker from a prior pause of the same `pauseReason` would satisfy a new pause.

4. `plugins/lwndev-sdlc/skills/finalizing-workflow/SKILL.md:64-68` defines the merge confirmation as SKILL.md prose: "Ask the user exactly once: > Ready to merge PR #\<N\> ...". When `orchestrating-workflows` forks `finalizing-workflow` it can append carve-out text to the Agent-tool prompt (the FEAT-030 run used `Skip the SKILL.md prompt entirely`). The forked subagent (run at the `finalizing-workflow` baseline of `haiku`, baseline-locked per `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md:262, :284`) follows the carve-out and `finalize.sh` runs unattended; a higher-tier fork would not inherently refuse it because the SKILL.md prose is the only guard. The destructive `gh pr merge` inside `finalize.sh:438` is then issued with no marker check.

5. `plugins/lwndev-sdlc/` has no `hooks/` directory and no `hooks.json`. The plugin ships no `UserPromptSubmit` or `PreToolUse` matcher infrastructure, so there is no mechanical layer where any of the four call shapes can be denied. `plugins/lwndev-sdlc/.claude-plugin/plugin.json` carries no hooks reference. The four-hook design proposed in [#244](https://github.com/lwndev/lwndev-marketplace/issues/244) does not exist in the codebase — every guard lives in prose.

6. The repository ships no managed-settings (`permissions.deny`) backstop for destructive Bash patterns. `.claude/settings.json` does not exist (only `.claude/settings.local.json`, which is per-user and unsuitable for plugin-shipped defaults). The destructive set (`Bash(gh pr merge:*)`, `Bash(git push --force:*)`, `Bash(git push -f:*)`, `Bash(git reset --hard:*)`, `Bash(gh release create:*)`, `Bash(npm publish:*)`) has no defense-in-depth deny rule, so a Hook B bug or a plugin-disable bypass leaves the destructive patterns reachable.

7. `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` (the orchestrator's per-invocation surface) does not document an approval-marker grammar, so even if the four-hook design ships there is no user-facing contract for what to type. The user has no canonical message shape (`approve <gate> <ID>`, `proceed <ID>`, `merge <ID>`, etc.) to satisfy Hook A.

## Affected Files

- `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh` — `cmd_pause` (lines 1111-1128) needs `pausedAt` field write; `cmd_resume` (1130-1147), `cmd_set_gate` (2001-2003), and `cmd_clear_gate` (2005-2007) shape the call sites that Hook B must guard
- `plugins/lwndev-sdlc/skills/finalizing-workflow/SKILL.md` — confirmation prompt at lines 64-68 must shift from SKILL.md prose to a Hook C–enforced approval marker
- `plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/finalize.sh` — destructive `gh pr merge` call site that Hook B must require a `merge-approval` marker for
- `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` — must document the approval-marker grammar (`approve <gate> <ID>`, `proceed <ID>`, `merge <ID>`, etc.) so users know what to type
- `plugins/lwndev-sdlc/.claude-plugin/plugin.json` — may need hooks reference depending on the plugin-hooks declaration mechanism
- New file: `plugins/lwndev-sdlc/hooks/hooks.json` — declares Hook A (`UserPromptSubmit`) and Hooks B+C (`PreToolUse` matchers `Bash` and `Agent`); references the hook scripts via `${CLAUDE_PLUGIN_ROOT}/scripts/hooks/...`
- New file: `plugins/lwndev-sdlc/scripts/hooks/record-approval.sh` — Hook A implementation (`UserPromptSubmit` → write `.sdlc/approvals/.approval-<gate>-<ID>` markers from canonical user input shapes); placed under the existing flat `plugins/lwndev-sdlc/scripts/` tree (sibling to `prepare-fork.sh`, `verify-build-health.sh`, etc.) in a new `hooks/` subdirectory to match the established `tests/` and `assets/` subdir grouping pattern
- New file: `plugins/lwndev-sdlc/scripts/hooks/guard-state-transitions.sh` — Hook B implementation (`PreToolUse` matcher `Bash` → deny `workflow-state.sh resume|clear-gate` and known-destructive Bash patterns when no approval marker exists or marker is older than `pausedAt`)
- New file: `plugins/lwndev-sdlc/scripts/hooks/guard-agent-prompts.sh` — Hook C implementation (`PreToolUse` matcher `Agent` → deny prompts containing carve-out keywords and deny forks of confirmation-owning skills without an approval marker)
- New file: `plugins/lwndev-sdlc/scripts/tests/hooks/record-approval.bats`, `guard-state-transitions.bats`, `guard-agent-prompts.bats` — bats coverage per hook per gate type plus the FEAT-030 carve-out regression case (placed under the existing `plugins/lwndev-sdlc/scripts/tests/` tree to match the repo's bats convention)
- New file: `plugins/lwndev-sdlc/scripts/tests/hooks/auto-mode-end-to-end.bats` — synthetic orchestrator workflow regression covering self-resume / self-clear-gate / carve-out fork attempts; CI-runnable (calls `workflow-state.sh` against a temp dir; no real PRs created)
- New file: managed-settings template / documentation site (illustrative path: `plugins/lwndev-sdlc/.claude-plugin/managed-settings.example.json` or a README addition) — the destructive `Bash(...)` `permissions.deny` list (Hook D)
- `.sdlc/approvals/` — new runtime directory created by Hook A; gitignored

## Acceptance Criteria

- [x] `plugins/lwndev-sdlc/hooks/hooks.json` declares Hook A (`UserPromptSubmit`) and Hooks B+C (`PreToolUse` matchers `Bash` and `Agent`), and the plugin is installable with the hooks active under default plugin enablement (RC-5).
- [x] Hook A creates approval markers under `.sdlc/approvals/` for each canonical approval shape (`approve <gate-type> <ID>`, `proceed <ID>`, `yes <ID>`, `merge <ID>`, `pause <ID>`); each marker contains an ISO-8601 timestamp, the workflow ID, and the verbatim user message; unknown shapes are silently ignored (no marker, no error, user message proceeds normally) (RC-5, RC-7).
- [x] Hook A only fires on real `UserPromptSubmit` events — auto-mode self-prompts produce no marker (RC-1, RC-2, RC-5).
- [x] Hook B denies `workflow-state.sh resume <ID>` when the corresponding `.approval-<pauseReason>-<ID>` marker is missing or older than the workflow's `pausedAt` (RC-1, RC-3, RC-5).
- [x] Hook B denies `workflow-state.sh clear-gate <ID>` when the corresponding `.approval-<gate>-<ID>` marker is missing (RC-2, RC-5).
- [x] Hook B denies known-destructive `Bash` patterns when no `.approval-merge-approval-<ID>` marker exists for the active workflow. The matcher MUST be a prefix glob (`gh pr merge*`, `git push --force*`, `git push -f*`, `git reset --hard*`, `gh release create*`, `npm publish*`, plus tag deletion: `git tag -d*` and `git push origin :refs/tags/*`) so future flag additions (e.g., `gh pr merge --squash`, `gh pr merge --rebase`) cannot slip past an exact-string match. The implementation plan documents which destructive patterns are deliberately out of scope for this hook (RC-4, RC-5).
- [x] Hook C denies `Agent`-tool spawns whose `prompt` matches the documented carve-out regex set (`skip the SKILL\.md.*prompt`, `orchestrator.*has (already )?obtained.*authorization`, `proceed directly to finalize\.sh`, `Skip Step \d+` unless target skill is `implementing-plan-phases` and the step is the documented PR-creation carve-out at `plugins/lwndev-sdlc/skills/implementing-plan-phases/SKILL.md:97` — note the orchestrator-side instruction at `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/step-execution-details.md:180` currently says "Skip Step 12" while the SKILL itself says "Skip Step 10", so the whitelist must accept any `Skip Step \d+` paired with the `implementing-plan-phases` target skill until that variance is resolved separately) (RC-4, RC-5).
- [x] Hook C denies `Agent`-tool spawns of skills that declare an interactive user-confirmation prompt that gates a destructive operation or a state transition (initial set: `finalizing-workflow`, which forks to `finalize.sh:438` `gh pr merge`) when the corresponding approval marker is missing. The criterion for adding future skills to this set is "the skill forks to a destructive `Bash` call (Hook B's destructive list) or to a `workflow-state.sh resume|clear-gate` call (Hook B's state-transition list) without a separate Hook B–enforced approval gate"; skills whose only prompts collect optional metadata (e.g., `documenting-features`'s `GitHub issue URL?`) are explicitly out of scope (RC-4, RC-5).
- [x] `workflow-state.sh pause` writes `pausedAt: <ISO-8601>` to the state file so Hook B's timestamp comparison cannot be defeated by a stale marker from a prior pause of the same `pauseReason`. The state-file schema is updated to declare `pausedAt` as a top-level optional ISO-8601 string (null when the workflow has never paused). Hook B treats a missing `pausedAt` on any pre-existing in-flight workflow state file (workflows initialized before this fix shipped) as "infinitely old" — i.e., no marker can satisfy the timestamp comparison, so a Hook A approval is always required after the fix lands. No state-file migration is required; the field appears the first time the workflow next pauses (RC-3).
- [x] A managed-settings template (path TBD by implementation plan; e.g., `plugins/lwndev-sdlc/.claude-plugin/managed-settings.example.json` or a documented snippet) ships the destructive `Bash(...)` `permissions.deny` list (`gh pr merge:*`, `git push --force:*`, `git push -f:*`, `git reset --hard:*`, `gh release create:*`, `npm publish:*`) as Hook D defense-in-depth, with the doc explaining why managed-settings scope (not project / user) is required to survive plugin-disable (RC-6).
- [x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` documents the approval-marker grammar (`approve <gate> <ID>`, `proceed <ID>`, `merge <ID>`, etc.) and the user-facing semantics of each gate shape so users know what to type at each pause (RC-7).
- [x] Bats coverage exists for each hook per gate type, asserting that an auto-mode bypass attempt (no `UserPromptSubmit` event = no marker = denial) is denied at every gate; explicitly includes a negative regression that simulates the FEAT-030 `Skip the SKILL.md prompt entirely` carve-out and asserts Hook C denies the `finalizing-workflow` spawn (RC-1, RC-2, RC-4, RC-5).
- [x] An end-to-end regression test runs a synthetic orchestrator workflow with auto-mode-style self-resumes, self-clear-gates, and carve-out fork attempts and asserts every pause / gate / destructive call is denied without a corresponding fresh marker. The harness lives at `plugins/lwndev-sdlc/scripts/tests/hooks/auto-mode-end-to-end.bats`, runs in CI as part of the existing bats suite, and operates entirely against a temp `.sdlc/workflows/` directory — it does NOT create real branches, real PRs, or real GitHub state (RC-1, RC-2, RC-3, RC-4, RC-5).

## Completion

**Status:** `Pending`

## Notes

- The fix is structural: behavioral guidance in CLAUDE.md is explicitly out of scope per the issue. CLAUDE.md text cannot constrain an in-session agent under auto mode; only mechanical guards (hooks + managed settings) can.
- **Out of scope** per the issue:
  - Adding new pause types (`pause merge-approval` etc.). Hook B works on existing pauses; merge approval is enforced by the destructive-Bash guard and the `finalizing-workflow` Agent-spawn guard rather than by a new `pause` type.
  - Skill-internal prompts that don't gate a state transition or destructive action (e.g., the `GitHub issue URL?` prompt in `documenting-features` — fabricated optional metadata is a separate failure mode and is not addressed by the four-hook design).
- **Acknowledged gaps in the four-hook design** (not blockers; documented for traceability):
  - **Plugin-disable bypass:** if the in-session agent disables `lwndev-sdlc`, hooks A–C unload. Mitigation: also install hooks A–C at user / project scope (`.claude/settings.json`). Hook D (managed settings) survives plugin-disable by design.
  - Skill-internal prompts that don't gate a state transition or destructive action remain enforceable only by prose.
- The `finalizing-workflow` SKILL.md prompt at `:64-68` is intentionally retained as a user-facing message even after Hook C ships — the hook denies the fork without an approval marker, but the prose prompt remains the canonical wording the user sees and approves against.
- Implementation should preserve the orchestrator-side ability to fork `implementing-plan-phases` with a `Skip Step 10` instruction, since that is the one legitimate carve-out (the orchestrator owns PR creation as a separate fork step `5+N+1`). Hook C's regex must whitelist this case.
