---
id: BUG-020
version: 2
timestamp: 2026-05-19T19:05:00Z
persona: qa
---

## User Summary

The orchestrator's pause-step user-review contract is hardened in two ways. First, the `[info] auto-paused` audit line emitted by `cmd_advance` and the prose in `step-execution-details.md` "Pause Steps" gain explicit halt-and-surface instructions, with a cross-link from the SKILL.md `:89` "Workflow-defined approval gates override 'work without stopping'" carve-out. Second, the `cmd_set_gate` whitelist is extended to accept `merge-approval` so the orchestrator can open a gate before the Finalize merge prompt — closing the documented stop-hook 9-block override path where the merge confirmation is dismissed before the user can type `merge {ID}`. No mechanical guards are changed; the fix is documentation, audit-line strengthening, and an enum extension that flows through the existing Hook B/C check infrastructure unchanged.

## Capability Report

- Mode: test-framework
- Framework: vitest
- Package manager: npm
- Test command: npm test
- Language: typescript

## Scenarios (by dimension)

### Inputs

- [P0] `cmd_set_gate <ID> merge-approval` on an in-progress workflow succeeds, writes `.gate = "merge-approval"` and a fresh ISO-8601 `.gateSetAt` | mode: test-framework | expected: bats asserts state file post-call has both fields populated correctly
- [P0] `cmd_set_gate <ID> findings-decision` on an in-progress workflow continues to succeed (regression check) | mode: test-framework | expected: bats asserts no behavioral change for the pre-existing gate type
- [P0] `cmd_set_gate <ID> <unknown-value>` (e.g. `bogus`, `MERGE-APPROVAL` uppercase, empty string) rejects with exit 1 and an error message naming both valid values | mode: test-framework | expected: bats asserts exit code + stderr substring `Expected one of: findings-decision, merge-approval`
- [P0] The strengthened `[info] auto-paused` line on auto-pause emission contains all four required tokens in a single line on stderr: literal `[info] auto-paused`, literal `pauseReason=<reason>`, literal `HALT` (case-sensitive), literal `surface` (case-sensitive) | mode: test-framework | expected: bats run_advance fixture asserts stderr matches each substring
- [P1] Strengthened audit-line separator between `(pauseReason=<reason>)` and `HALT` is a plain ASCII `- ` hyphen-space, NOT an em-dash (`—`) or en-dash (`–`) — protects against future stylistic edits silently breaking grep-based tests | mode: test-framework | expected: bats asserts `\\- HALT` (regex with escaped hyphen) is present and `—` / `–` Unicode codepoints are absent
- [P1] `set-gate <ID> merge-approval` is idempotent: calling twice in succession leaves the gate set, refreshes `gateSetAt` to the second call's timestamp, and does not error | mode: test-framework | expected: bats asserts two sequential calls succeed and second `gateSetAt` > first
- [P2] `cmd_set_gate <ID> 'merge-approval; rm -rf /tmp/x'` (shell injection attempt in gate-type arg) rejects on the enum check before any shell expansion of the arg | mode: test-framework | expected: bats asserts injection arg rejected by enum check (no exit-code change, no FS side effect)

### State transitions

- [P0] `stop-hook.sh` exits 0 when `.gate == "merge-approval"` and `status == "in-progress"` (the new gate value flows through the existing `if [[ -n "$GATE" ]]; then exit 0; fi` branch at `:51-54` without code change) | mode: test-framework | expected: bats fixture sets gate, invokes stop-hook, asserts exit 0 and no stderr nudge
- [P0] `stop-hook.sh` exits 0 when `.gate == "findings-decision"` and `status == "in-progress"` (regression check for the pre-existing gate value) | mode: test-framework | expected: bats asserts no regression
- [P0] After `set-gate <ID> merge-approval`, calling `advance <ID>` clears `.gate` to `null` and `.gateSetAt` to `null` as a side-effect of the inline mutation at `cmd_advance:1192-1193`; subsequent stop-hook fires (now with `.gate == null`) revert to the in-progress nudge path | mode: test-framework | expected: bats asserts post-advance state file has gate/gateSetAt = null
- [P1] After `set-gate <ID> merge-approval`, calling `pause <ID> <reason>` clears `.gate` and `.gateSetAt` to `null` (cmd_pause auto-clears gate at `:1250`) | mode: test-framework | expected: bats asserts post-pause state file has gate/gateSetAt = null
- [P1] `set-gate <ID> merge-approval` on a workflow with `status != "in-progress"` (paused, complete, failed) rejects with the existing `Cannot set gate on a <status> workflow` error (no regression in cmd_set_gate `:1284-1288`) | mode: test-framework | expected: bats asserts exit 1 for each non-in-progress status
- [P1] After `cmd_advance` lands on a `context: "pause"` step and auto-pauses, no `.gate` value is set (auto-pause is a status transition, not a gate transition) — confirms BUG-018 atomic auto-pause does not collide with the new `merge-approval` gate semantic | mode: test-framework | expected: bats asserts post-advance state file has gate == null, status == "paused", pauseReason set
- [P2] Rapid `set-gate merge-approval` / `advance` / `set-gate merge-approval` cycles do not corrupt the state file (jq `.tmp && mv` pattern survives the cycle) | mode: test-framework | expected: bats loops 50 cycles and asserts final state file is parseable JSON with expected shape

### Environment

- [P0] Doc invariant: `grep` over `step-execution-details.md` "Pause Steps" section (lines from `### Pause Steps` through the next `##`) finds all four required substrings — `load-bearing`, `HALT`, `surface the pause artifact`, `work without stopping` | mode: test-framework | expected: vitest reads the section and asserts each substring is present (case-sensitive on `HALT` and `load-bearing`)
- [P0] Doc invariant: each of the three Finalize fork-step blocks (Feature `:23`, Chore `:49`, Bug `:91`) in `step-execution-details.md` contains the literal substring `set-gate {ID} merge-approval` | mode: test-framework | expected: vitest asserts the substring appears at least three times in the file with the surrounding context tag the Finalize block
- [P0] Doc invariant: SKILL.md `:89` Load-bearing carve-out paragraph (the bullet starting with `**Workflow-defined approval gates override`) contains the substring `step-execution-details.md` | mode: test-framework | expected: vitest extracts the carve-out line and asserts the cross-link substring
- [P1] Doc invariant: the SKILL.md `:89` carve-out continues to enumerate all five gate identifiers (`plan-approval`, `pr-review`, `findings-decision`, `review-findings`, `merge-approval`) — confirms `merge-approval` is named in the carve-out so the auto-mode override applies to it | mode: test-framework | expected: vitest asserts each of the five identifiers appears in the carve-out paragraph
- [P1] State file written under a read-only mount (or with the parent dir lacking write permission) fails with a clear error from `jq > file.tmp && mv file.tmp file` (no half-written state file) | mode: exploratory | expected: manual reproduction on a tmp dir chmod 555 — confirm error message and absence of corrupted state file
- [P2] LANG / LC_ALL=C runs of the strengthened `[info] auto-paused` emitter produce identical output to en_US.UTF-8 runs (ASCII separator protects against locale-dependent regex differences) | mode: test-framework | expected: bats sets LC_ALL=C and re-runs the audit-line assertion suite

### Dependency failure

- [P0] When Hook A is unavailable (plugin disabled mid-session), user types `merge BUG-020` and NO `.approval-merge-approval-BUG-020` marker is written; the orchestrator's subsequent `Agent` spawn of `finalizing-workflow` is denied by Hook C (BUG-014 AC C unchanged); the orchestrator surfaces the denial to the user | mode: exploratory | expected: integration repro disabling the plugin's record-approval.sh, then attempting fork; confirm Hook C denial fires and user sees the failure
- [P0] When Hook B/C are unloaded entirely (plugin uninstalled), set-gate merge-approval still succeeds, but the destructive Bash `gh pr merge` no longer has marker enforcement — confirms Hook D managed-settings `permissions.deny` defense-in-depth still blocks the merge | mode: exploratory | expected: integration repro removing hooks; confirm `gh pr merge` is denied by managed-settings rule
- [P1] `gh pr view` failing while `documenting-qa` runs in a later orchestrator invocation against BUG-020 does not corrupt the QA test plan (QA plan was written without a PR diff per chore/bug step 3) | mode: test-framework | expected: vitest asserts the plan structural conformance is preserved (re-running stop-hook on QA-plan-BUG-020.md exits 0)
- [P2] `workflow-state.sh status BUG-020` immediately after `set-gate merge-approval` returns the gate value in the JSON output (no race between write and read on local FS) | mode: test-framework | expected: bats asserts gate field is present and equals `merge-approval` in the JSON

### Cross-cutting (a11y, i18n, concurrency, permissions)

- [P0] BUG-014 hook coverage no regression: Hook B `clear-gate <ID>` continues to require a marker; Hook B destructive-Bash `gh pr merge` continues to require `.approval-merge-approval-<ID>`; Hook C `Agent` fork of `finalizing-workflow` continues to require the same marker. The new gate value flows through unchanged — no carve-outs added | mode: test-framework | expected: existing BUG-014 bats suite runs green; new test asserts the same checks fire when `.gate == "merge-approval"` is set
- [P0] BUG-018 atomic auto-pause coverage no regression: `cmd_advance` continues to auto-pause on `context: "pause"` steps, reject subsequent advance on paused workflows, and emit the `[info] auto-paused` prefix (now extended with HALT+surface tail) | mode: test-framework | expected: existing `workflow-state-advance-pause-context.bats` runs green with new assertions added per AC9
- [P0] BUG-015 `gateSetAt` coverage no regression: `set-gate` stamps `gateSetAt` on each call; `clear-gate` and `pause` reset it to null; `cmd_advance` inline gate-clear resets it too | mode: test-framework | expected: existing gateSetAt bats coverage runs green; new test extends to merge-approval value
- [P1] Concurrency: two concurrent `workflow-state.sh set-gate` invocations against the same ID — second writer overwrites first; no half-written state file produced (jq tmp+mv pattern protects intra-process; cross-process is best-effort) | mode: exploratory | expected: manual repro with two shells; confirm final state file parses and contains the second writer's value
- [P1] Permissions: state file written with no umask change; subsequent reads by stop-hook (different effective user, e.g. via sudo) require world-readable mode bits — confirm existing default umask produces 644-equivalent | mode: exploratory | expected: manual `stat` on a freshly-written state file under default umask
- [P2] a11y: no a11y impact — this fix has no UI surface. The strengthened `[info]` line is structured-log stderr text consumed by the orchestrator, not displayed to a human as a UI control | mode: exploratory | expected: justified under Non-applicable dimensions
- [P2] i18n: load-bearing tokens (`HALT`, `surface`) are ASCII-only English and intentionally so for grep-token stability. The Pause Steps prose paragraph is English-only, matching the rest of the orchestrator docs | mode: exploratory | expected: justified under Non-applicable dimensions

## Non-applicable dimensions

- a11y: this fix has no UI surface. The `[info] auto-paused` line is stderr structured-log text emitted by a bash script and consumed by the orchestrator (Claude Code); it is not rendered as a UI control to a human user. The doc edits live in `references/step-execution-details.md` and `SKILL.md`, which are loaded into the orchestrator's context as Markdown content, again not a human UI surface. Probed at P2 in Cross-cutting for completeness.
- i18n (deep): the doc/audit-line content is intentionally ASCII-only English so grep tokens (`HALT`, `surface`, `load-bearing`, `work without stopping`, `set-gate {ID} merge-approval`) are stable across locales. Future translation would require updating the verifier substrings in lockstep; no translation is planned for v1.27. Probed at P2 in Cross-cutting for the LANG=C case.
