# Bug: pause-step documentation hardening

## Bug ID

`BUG-020`

## GitHub Issue

[#295](https://github.com/lwndev/lwndev-marketplace/issues/295)

## Category

`logic-error`

## Severity

`medium`

## Description

Two adjacent user-review gaps in `orchestrating-workflows` under Claude Code auto mode that survive the BUG-014 hook system and the BUG-018 atomic auto-pause in `cmd_advance`:

1. The orchestrator may emit "bypass" narration when reaching workflow pause gates (`plan-approval`, `pr-review`) even when the mechanical guards prevent any actual state advance past the gate. The `[info] auto-paused` audit line emitted by `cmd_advance` is the load-bearing signal that the workflow is paused, but the orchestrator's required reaction protocol (halt all further tool calls, surface the pause artifact, return control to the user) is not documented at the pause-step site and is not encoded in the audit line itself. Result: the user-facing experience reads as a bypass even though the workflow is mechanically paused.

2. At the `Finalize` step (`context: "fork"`), the orchestrator displays the merge-confirmation prompt in main context before forking `finalizing-workflow`, waiting for the user to type the canonical approval phrase (`merge {ID}`) that Hook A converts to a marker. Status remains `in-progress` and `.gate` is unset, so `stop-hook.sh` fires the in-progress nudge. After 9 consecutive Stop-hook blocks Claude Code overrides the hook and ends the turn, dismissing the prompt before the user can type approval. The destructive guards (Hook B on `gh pr merge`, Hook C on the `finalizing-workflow` fork) still prevent actual merge, but the user-visible interaction is lost.

## Steps to Reproduce

1. Start a feature workflow under Claude Code auto mode (active `Auto Mode Active` system reminder reading "work without stopping for clarifying questions...").
2. Let the chain run through step 3 (creating-implementation-plans, context=fork).
3. After the plan fork returns, the orchestrator calls `workflow-state.sh advance {ID}`. `cmd_advance` correctly auto-pauses (BUG-018): stderr emits `[info] auto-paused on step 4 (pauseReason=plan-approval)` and the state file flips to `status: "paused"`, `pauseReason: "plan-approval"`, with `pausedAt` stamped.
4. Observe — the orchestrator's narration may continue past this point (e.g. "User authorized non-stop work; advance through plan-approval pause without halting") even though any subsequent `advance` is rejected by `cmd_advance`'s paused-check (`workflow-state.sh:1119-1122`) and any `resume` is denied by Hook B without a fresh `.approval-plan-approval-{ID}` marker.
5. Observe — `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/step-execution-details.md` "Pause Steps" section (`:93-127`) documents the atomic auto-pause behavior but does NOT instruct the orchestrator how to react to the `[info] auto-paused` audit line. There is no explicit "halt narration, display artifact, stop" sequence and no auto-mode reinforcement.
6. Observe — `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` `Output Style > Load-bearing carve-outs` at `:89` states the rule ("Workflow-defined approval gates override 'work without stopping'") but does not cross-link to the pause-step procedure where the halt-and-surface sequence would live.

### Repro B — Finalize stop-hook 9-block override

1. Run a feature, chore, or bug workflow under Claude Code auto mode to the `Finalize` step (state file: `currentStep` points at the step whose `skill == "finalizing-workflow"`, `status: "in-progress"`, no `.gate` set).
2. Orchestrator displays the merge-confirmation prompt in main context per the `finalizing-workflow` SKILL.md `:64-68` template (e.g. `Ready to merge PR #1800 ... Proceed? Reply yes to merge`) and waits for the user to type the canonical approval phrase (`merge {ID}`) that Hook A converts to `.approval-merge-approval-{ID}`.
3. Observe — `stop-hook.sh` (`:51-58`) checks `.gate` for non-empty value (only handles `findings-decision`). Since the orchestrator never set a gate before displaying the merge prompt, `.gate` is `null`. The hook falls through to the `in-progress|failed` branch and emits `Workflow {ID} is in-progress. Continue to step N: Finalize` with exit `2`, repeatedly.
4. Observe — after 9 consecutive Stop-hook blocks Claude Code overrides the hook with `A hook blocked the turn from ending 9 consecutive times — overriding and ending turn.` and ends the turn (`CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` default).
5. Result — the user never sees the merge-confirmation prompt in a tab where they can respond. The destructive guards (Hook B on `gh pr merge`, Hook C on the `finalizing-workflow` Agent-spawn) still prevent merge, but the user-visible interaction is dismissed.

Evidence: [issue #295 follow-up comment](https://github.com/lwndev/lwndev-marketplace/issues/295#issuecomment-4490899179) captures the exact transcript — 9 consecutive `Stop hook nudging. Step 14 = merge, awaiting your yes confirmation. Holding.` lines followed by the Claude Code 9-block override message.

## Expected Behavior

`references/step-execution-details.md` "Pause Steps" section must explicitly document the orchestrator's reaction protocol on auto-pause:

1. The `[info] auto-paused on step <N> (pauseReason=<reason>)` line is a load-bearing structured log.
2. On emission, the orchestrator MUST halt all further tool calls in the current turn.
3. The orchestrator MUST surface the pause artifact (plan path for `plan-approval`; PR number, URL, and branch for `pr-review`) and the resume command (`/orchestrating-workflows {ID}`).
4. The Claude Code "work without stopping for clarifying questions" / auto-mode system reminder does NOT authorize bypass of this halt — the SKILL.md `:89` carve-out applies verbatim at this site.

The `[info] auto-paused` audit line emitted by `cmd_advance` must include explicit halt-and-surface tokens so an orchestrator scanning the line in isolation has the reaction protocol inline (not buried in cross-referenced docs).

SKILL.md `:89` Load-bearing carve-out must cross-link to the pause-step procedure so a reader of the rule can locate the operational steps that satisfy it.

For the `Finalize` fork step in all three chains, the orchestrator must set the `merge-approval` gate via `workflow-state.sh set-gate {ID} merge-approval` before displaying the merge-confirmation prompt in main context. With `.gate` set, `stop-hook.sh:51-54` exits `0` via the existing `if [[ -n "$GATE" ]]` branch and the 9-block stop-hook override no longer fires. The orchestrator surfaces the canonical approval-marker grammar (`merge {ID}`) so the user knows what to type. After the user types the approval phrase, Hook A creates `.approval-merge-approval-{ID}`; the orchestrator forks `finalizing-workflow` (Hook C allows: marker present); the fork runs `gh pr merge` (Hook B allows: marker present); on `advance` the `.gate` field is cleared inline by `cmd_advance:1209-1210`. No stop-hook code change is required — only an enum extension in `cmd_set_gate` to accept `merge-approval` and a documentation update at the Finalize fork-step site.

## Actual Behavior

- `cmd_advance` (`plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh:1106-1223`) correctly emits `[info] auto-paused on step ${next_step} (pauseReason=${derived_pause_reason})` (`:1198`) and atomically pauses the workflow on `context: "pause"` steps. The mechanical guard works.
- The mechanical guards in v1.27.0 prevent any actual state advance past the pause: subsequent `advance` calls are rejected with `[error] cannot advance: workflow paused (pauseReason=...); resume first` (`:1120-1121`), and Hook B (`plugins/lwndev-sdlc/scripts/hooks/guard-state-transitions.sh`) denies `resume` without a fresh approval marker.
- `references/step-execution-details.md` "Pause Steps" section (`:93-127`) describes the atomic auto-pause behavior but contains no instruction for the orchestrator's reaction protocol — no "halt", no "surface artifact", no "do not call advance again", and no auto-mode reinforcement.
- SKILL.md `:89` states the carve-out rule but does not cross-link to the operational procedure in `references/step-execution-details.md`.
- The `[info] auto-paused` line carries only `step <N> (pauseReason=<reason>)` — it does not include any imperative ("HALT", "surface") and does not hint at the pause artifact location.
- At the `Finalize` step, the orchestrator displays the merge-confirmation prompt in main context but does NOT set any `.gate` value before the prompt. `stop-hook.sh:51-58` checks `.gate` for non-empty but `.gate == null`, so it falls through to the `in-progress|failed` branch and emits `Workflow {ID} is in-progress. Continue to step N: Finalize` with exit `2`. After 9 firings Claude Code overrides the hook and ends the turn, dismissing the merge-confirmation prompt before the user can respond.
- `workflow-state.sh cmd_set_gate` (`:1290`) hardcodes a single accepted gate type (`findings-decision`). There is currently no mechanism for the orchestrator to express "mid-step, awaiting user input" for the `Finalize` step without extending the enum.

## Root Cause(s)

1. **`references/step-execution-details.md` "Pause Steps" section documents only the mechanical auto-pause, not the orchestrator's reaction protocol.** The section (`:93-127`) tells the orchestrator to "Display: 'Implementation plan created at...'" and "Halt execution" but does not name the `[info] auto-paused` audit line as the load-bearing trigger, does not explicitly state that the halt is mandatory regardless of session-level "work without stopping" / no-clarifying-questions / auto-mode authorizations, and does not cross-reference the SKILL.md `:89` carve-out. A reader following the pause-step procedure under auto mode has no contextual signal that the halt is non-negotiable. This affects all three chain types (Feature `:95-111`, Chore `:113-119`, Bug `:121-127`).

2. **The `[info] auto-paused` audit line at `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh:1198` lacks halt-and-surface tokens.** It currently emits `[info] auto-paused on step <N> (pauseReason=<reason>)` — a parseable structured log, but lacks any imperative ("HALT", "surface", "do not advance") and lacks a hint to the pause artifact location. An orchestrator reading just this line has no inline instruction about what to do next; it must cross-reference docs the orchestrator may not consult mid-fork.

3. **The SKILL.md `:89` Load-bearing carve-out does not cross-link to `references/step-execution-details.md` "Pause Steps".** SKILL.md states the rule ("Workflow-defined approval gates override 'work without stopping'") but the operational steps that satisfy the rule live elsewhere. Without a cross-link, a reader applying the rule may not find the procedure that enforces it, and a future editor may modify one side without updating the other.

4. **No regression test asserts the documentation invariants.** The existing bats coverage at `tests/bats/skills/orchestrating-workflows/workflow-state-advance-pause-context.bats:107-115` asserts only that the `[info] auto-paused` prefix and the `pauseReason=plan-approval` token are emitted (`:113-114`) — there is no test that asserts `step-execution-details.md` contains the auto-mode defense paragraph, no test that asserts SKILL.md `:89` cross-links to the procedure, and no test that asserts the strengthened audit-line tokens ("HALT", "surface") are present alongside the existing prefix and `pauseReason=` tokens.

5. **Stop hook does not signal "awaiting user input" when the orchestrator is at the `Finalize` step in main context, displaying the merge-confirmation prompt before forking `finalizing-workflow`.** At the `Finalize` step (chain-relative step 5+N+4 for feature, step 7 for chore and bug; `context: "fork"`), the orchestrator's pattern is to display the merge prompt in main context and wait for the user to type the canonical approval shape (`merge {ID}`) which Hook A converts to `.approval-merge-approval-{ID}`. With `status: "in-progress"` and `.gate == null`, `stop-hook.sh:51-58` falls through to the `in-progress|failed` branch and emits `Workflow {ID} is in-progress. Continue to step N: Finalize` with exit `2`. After 9 consecutive Stop-hook blocks Claude Code overrides the hook (default `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP=9`) and ends the turn, dismissing the prompt before the user can type approval. The mechanical destructive guards (Hook C `Agent`-spawn deny on `finalizing-workflow` without marker; Hook B destructive-Bash deny on `gh pr merge`) still prevent the actual merge, but the user-visible interaction is lost. Fix: extend `cmd_set_gate` whitelist (`workflow-state.sh:1290`) to accept `merge-approval`; instruct the orchestrator to set the gate before the merge prompt so the existing `stop-hook.sh:51-54` `if [[ -n "$GATE" ]]; then exit 0; fi` branch fires — no stop-hook code change required. This addresses the original issue's suggested fix #4 (stop-hook nudge tone) without modifying the stop-hook source.

## Affected Files

- `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/step-execution-details.md` — add auto-mode reaction protocol to "Pause Steps" (Feature `:95-111`, Chore `:113-119`, Bug `:121-127`) and add `set-gate {ID} merge-approval` instruction to the Finalize fork-step block (Feature step 5+N+4 `:23`; Chore step 7 `:49`; Bug step 7 `:91`) (RC-1, RC-5)
- `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh` — strengthen `[info] auto-paused` line at `:1198` to include "HALT" and "surface" imperatives (RC-2); extend `cmd_set_gate` whitelist at `:1290` to accept `merge-approval` in addition to `findings-decision` (RC-5)
- `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` — cross-link from `:89` carve-out to `references/step-execution-details.md#pause-steps` (RC-3)
- `tests/bats/skills/orchestrating-workflows/workflow-state-advance-pause-context.bats` — extend to assert the strengthened `[info] auto-paused` line content (RC-2, RC-4)
- `tests/bats/skills/orchestrating-workflows/workflow-state-set-gate.bats` (new or extended) — assert `cmd_set_gate` accepts `merge-approval` and rejects unknown gate values with the existing error pattern (RC-4, RC-5)
- `tests/bats/shared/hooks/auto-mode-end-to-end.bats` — extend to assert the stop-hook exits `0` when `.gate == "merge-approval"` and `status == "in-progress"`, simulating the Finalize step main-context wait (RC-4, RC-5)
- `tests/unit/orchestrating-workflows-pause-step-docs.test.ts` (new) — grep-based assertions over step-execution-details.md and SKILL.md (RC-1, RC-3, RC-4)
- `package-lock.json`
- `qa/test-plans/QA-plan-BUG-020.md`
- `qa/test-results/QA-results-BUG-020.md`
- `requirements/bugs/BUG-020-pause-step-documentation-hardening.md`
- `tests/bats/skills/orchestrating-workflows/workflow-state-advance-pause-context.qa.bats`
- `tests/bats/skills/orchestrating-workflows/workflow-state-set-gate.qa-bug-020-gate-clearing.bats`
- `tests/bats/skills/orchestrating-workflows/workflow-state-set-gate.qa.bats`
- `tests/unit/orchestrating-workflows-pause-step-docs.qa.test.ts`

## Acceptance Criteria

- [x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/step-execution-details.md` "Pause Steps" gains an explicit reaction-protocol paragraph (either shared at the section header or repeated under each of Feature `:95-111`, Chore `:113-119`, Bug `:121-127`) stating: (a) the `[info] auto-paused` line is a **load-bearing** structured log; (b) on emission, the orchestrator MUST halt all further tool calls in the current turn; (c) the orchestrator MUST **surface the pause artifact** (plan path for `plan-approval`; PR number+URL+branch for `pr-review`) and the resume command; (d) the Claude Code "work without stopping for clarifying questions" / auto-mode system reminder does NOT authorize bypass of this halt — the SKILL.md `:89` carve-out applies verbatim. Mechanically verifiable: `grep` finds all four literal substrings within the "Pause Steps" section: `load-bearing`, `HALT`, `surface the pause artifact`, `work without stopping`. (RC-1)

- [x] The `[info] auto-paused` line emitted by `cmd_advance` (`plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh:1198`) is strengthened to include the load-bearing imperatives "HALT" and "surface" in its tail, separated from the existing `(pauseReason=<reason>)` token by a plain ASCII separator (` - ` hyphen-space, NOT an em-dash) for portability. Recommended shape: `[info] auto-paused on step <N> (pauseReason=<reason>) - HALT all further tool calls and surface the pause artifact to the user`. The four load-bearing tokens that the strengthened line MUST contain on every emission are: `[info] auto-paused`, `pauseReason=<reason>`, `HALT`, `surface`. (RC-2)

- [x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` `:89` Load-bearing carve-out gains an explicit cross-reference to `references/step-execution-details.md` "Pause Steps" (e.g. a Markdown link or a parenthetical "see references/step-execution-details.md#pause-steps for the halt-and-surface procedure"). Mechanically verifiable: `grep` finds the substring `step-execution-details.md` within the carve-out paragraph. (RC-3)

- [x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh` `cmd_set_gate` (`:1290`) is extended to accept `merge-approval` in addition to `findings-decision`. Invalid gate types continue to reject with the existing error pattern `Error: Invalid gate type '<type>'. Expected one of: findings-decision, merge-approval.` `gateSetAt` continues to be stamped on every successful `set-gate` call (no change to `:1303-1305`). (RC-5)

- [x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/step-execution-details.md` Finalize fork-step block (Feature `:23`, Chore `:49`, Bug `:91`) instructs the orchestrator to: (a) call `workflow-state.sh set-gate {ID} merge-approval` BEFORE displaying the merge-confirmation prompt in main context; (b) display the canonical approval-marker grammar (`merge {ID}`) so the user knows the exact phrase that Hook A converts to a marker; (c) wait for the user input — the `merge-approval` gate causes `stop-hook.sh:51-54` to exit `0` so the wait is not interrupted by stop-hook nudges; (d) fork `finalizing-workflow` only after the user has typed the approval phrase (Hook C enforces marker presence); (e) on `advance` the `.gate` field is cleared inline by `cmd_advance` (`:1192-1193`) — explicit `clear-gate` call is NOT required and would itself trigger Hook B's clear-gate marker check redundantly. Mechanically verifiable: `grep` finds the literal substring `set-gate {ID} merge-approval` in the Finalize fork-step block of each chain. (RC-5)

- [x] A new test at `tests/unit/orchestrating-workflows-pause-step-docs.test.ts` asserts: (a) `step-execution-details.md` "Pause Steps" section (lines from the first `### Pause Steps` heading through the next `##` heading) contains all four substrings `load-bearing`, `HALT`, `surface the pause artifact`, `work without stopping` (case-sensitive on `HALT` since it is the load-bearing token; case-sensitive on `load-bearing`); (b) SKILL.md `:89` Load-bearing carve-out line (the bullet starting with `**Workflow-defined approval gates override`) contains the substring `step-execution-details.md`; (c) each of the three Finalize fork-step blocks (Feature, Chore, Bug) in `step-execution-details.md` contains the literal substring `set-gate {ID} merge-approval`. (RC-1, RC-3, RC-5, RC-4)

- [x] `tests/bats/skills/orchestrating-workflows/workflow-state-advance-pause-context.bats:107-115` is extended with assertions that the strengthened `[info] auto-paused` line contains all four required tokens — the existing `[info] auto-paused` prefix (`:113`), the existing `pauseReason=<reason>` token (`:114`), and the two new `HALT` and `surface` tokens. The existing two assertions continue to pass. (RC-2, RC-4)

- [x] `tests/bats/skills/orchestrating-workflows/workflow-state-set-gate.bats` (new or extended) asserts: (a) `cmd_set_gate {ID} merge-approval` succeeds when status is `in-progress` and writes both `.gate = "merge-approval"` and a fresh ISO-8601 `.gateSetAt`; (b) `cmd_set_gate {ID} findings-decision` continues to succeed (no regression); (c) `cmd_set_gate {ID} <invalid>` rejects with exit `1` and the existing error pattern. (RC-4, RC-5)

- [x] `tests/bats/shared/hooks/auto-mode-end-to-end.bats` is extended with a regression case asserting that when `.gate == "merge-approval"` and `status == "in-progress"`, `stop-hook.sh` exits `0` (matching the existing behavior for `.gate == "findings-decision"`). This proves the 9-block override path is closed for the Finalize main-context wait. (RC-4, RC-5)

- [x] No regression in existing BUG-014 hook coverage, BUG-018 atomic auto-pause coverage, BUG-015 gateSetAt coverage, or any other existing test. Specifically: (a) the existing assertions at `workflow-state-advance-pause-context.bats:113-114` continue to pass after the line is strengthened (prefix `[info] auto-paused` and `pauseReason=` token preserved); (b) Hook B's `clear-gate` marker check continues to require `.approval-<gate>-{ID}` for any explicit `clear-gate` call — the new `merge-approval` value flows through the same check; (c) Hook C's `Agent`-spawn deny on `finalizing-workflow` without `.approval-merge-approval-{ID}` continues to fire — no carve-out for the new gate. (RC-2, RC-5)

## Completion

**Status:** `Complete`

**Completed:** 2026-05-23

**Pull Request:** [#297](https://github.com/lwndev/lwndev-marketplace/pull/297)

## Notes

- **Structural prerequisites already satisfied in v1.27.0.** BUG-014 (#244 → PR #248, completed 2026-04-27) shipped the four-hook system: Hook A (UserPromptSubmit marker recording on canonical approval inputs `approve <gate> <ID>`, `proceed <ID>`, `merge <ID>` etc.), Hook B (PreToolUse deny on `workflow-state.sh resume|clear-gate` and destructive Bash without a fresh marker newer than `pausedAt`), Hook C (PreToolUse deny on `Agent` spawns matching carve-out regexes or targeting confirmation-owning skills without a marker), and Hook D (managed-settings `permissions.deny` defense-in-depth for destructive Bash patterns). BUG-018 (#281 → PR #287, completed 2026-05-17) made `cmd_advance` atomically auto-pause on `context: "pause"` steps (`workflow-state.sh:1106-1223`), reject subsequent `advance` calls on paused workflows (`:1119-1122`), and added the SKILL.md `:89` Load-bearing carve-out paragraph naming the five gate identifiers. Hooks fire mode-agnostically and are not subject to Claude Code's auto-mode classifier or context compaction — they are the hard-guarantee mechanism per Anthropic's [permission-modes docs](https://code.claude.com/docs/en/permission-modes#when-auto-mode-falls-back).

- **Why this is documentation/narration scope only.** Claude Code's `permission_mode` is not exposed to hooks per GitHub issue [anthropics/claude-code#6227](https://github.com/anthropics/claude-code/issues/6227) (closed as not planned). Plugins cannot programmatically detect auto mode and conditionally tighten guards. The remaining defense is (a) mechanical guards that fire regardless of mode — already in place via BUG-014 and BUG-018; and (b) explicit instructions to the model at the pause-step site so the narration matches the mechanical state — this bug's scope.

- **Why severity is `medium` (not `critical` like the user-reported issue).** Issue #295 was filed against `lwndev-sdlc/1.26.0` (pre-BUG-018), where the orchestrator could chain two `advance` calls in a single Bash invocation and walk past the pause. Under v1.27.0 the same sequence is structurally blocked — the first `advance` auto-pauses, the second is rejected. The Finalize 9-block override (RC-5, surfaced via the issue follow-up [comment 4490899179](https://github.com/lwndev/lwndev-marketplace/issues/295#issuecomment-4490899179)) dismisses the user-visible prompt but the destructive guards (Hook B on `gh pr merge`, Hook C on the `finalizing-workflow` Agent-spawn) still prevent merge. Both gaps are user-experience / narration hardening on top of an already-mechanically-correct system.

- **Audit-line consumer audit (W3).** `grep -rn "auto-paused" plugins/ tests/` returns exactly two consumers: the emitter at `workflow-state.sh:1198` and the regex assertion at `workflow-state-advance-pause-context.bats:113`. The bats assertion uses prefix-match `\[info\]\ auto-paused`, so appending a `- HALT ...` suffix to the line preserves it. No other code or test parses the line's tail; the strengthened suffix is purely human-facing and breaks no contract. (verified 2026-05-19)

- **Advance call site audit (W4).** `cmd_advance` is invoked only from the orchestrator's main context (the `${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh advance {ID}` lines in `step-execution-details.md` Pause Steps, Phase Loop, PR Creation, and the chore/bug step-4 sequences). No forked sub-skill calls `advance` — the stderr `[info] auto-paused` line therefore always reaches the orchestrator's main-context stderr (not a sub-agent transcript that the orchestrator may or may not see).

- **Out of scope.**
  - A built-in `workflow-state.sh rollback <ID>` command (the issue's recovery complaint) is a separate feature request, not a bug fix.
  - New pause types. BUG-014's design choice to NOT add a `merge-approval` `pauseReason` stands — this fix uses the existing `.gate` field, which is the correct semantic (mid-step waiting for user input, vs. between-step halt).
  - Modifying the stop-hook source. RC-5 closes the gap by setting a gate value that the existing `stop-hook.sh:51-54` `if [[ -n "$GATE" ]]; then exit 0; fi` branch already handles. No stop-hook code change is required.
  - Mechanical enforcement that the orchestrator MUST fork `finalizing-workflow` (i.e. cannot call `advance` to skip the merge). That is a separate structural concern not introduced by RC-5 — `cmd_advance` does not gate fork-context steps today; only `context: "pause"` steps auto-pause (BUG-018). Adding fork-step enforcement would be a separate bug.

- **Cross-references.**
  - BUG-014: `requirements/bugs/BUG-014-auto-mode-bypasses-confirmation-gates.md`
  - BUG-018: `requirements/bugs/BUG-018-advance-bypasses-pause-context.md`
  - Issue: https://github.com/lwndev/lwndev-marketplace/issues/295
