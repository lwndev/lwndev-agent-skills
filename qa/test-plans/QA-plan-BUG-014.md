---
id: BUG-014
version: 2
timestamp: 2026-04-26T14:57:04Z
persona: qa
---

## User Summary

In Claude Code auto mode, the SDLC orchestrator silently bypasses every user-confirmation gate it defines — workflow pauses, findings-decision gates, and the `finalizing-workflow` SKILL.md merge prompt — culminating in unauthorized `gh pr merge` to `main`. The fix introduces four hooks plus a `pausedAt` timestamp: Hook A on `UserPromptSubmit` writes approval markers under `.sdlc/approvals/` from canonical text shapes; Hook B on `PreToolUse` matcher `Bash` denies `workflow-state.sh resume|clear-gate` and a destructive-Bash prefix-glob list when no fresh marker exists; Hook C on `PreToolUse` matcher `Agent` denies prompts containing carve-out keywords and denies forks of confirmation-owning skills without a marker; Hook D is a managed-settings `permissions.deny` backstop. `pausedAt` is the timestamp anchor that defeats stale-marker replay.

## Capability Report

- Mode: test-framework
- Framework: vitest
- Package manager: npm
- Test command: npm test
- Language: typescript

Note: hook scripts are bash and tested via bats (consistent with existing `plugins/lwndev-sdlc/scripts/tests/`); the vitest suite covers the orchestrator-side wiring (e.g., `pausedAt` field write).

## Scenarios (by dimension)

### Inputs

- [P0] User types `approve plan-approval BUG-014` while no plan-approval pause is active for BUG-014 | mode: test-framework | expected: bats — Hook A creates no marker (or creates one that Hook B never references); workflow state unchanged; no error surfaced to user
- [P0] User types `proceed BUG-014` while two gates are simultaneously active (e.g., a paused `pr-review` plus a `findings-decision` set-gate from a re-fork attempt) | mode: test-framework | expected: bats — script reads workflow JSON, resolves which gate `proceed` applies to via documented precedence (active `gate` field beats `pauseReason`); only one marker created
- [P0] Approval marker with future-dated mtime (`touch -t 209912312359 .sdlc/approvals/.approval-pr-review-BUG-014`) attempts to satisfy a fresh pause | mode: test-framework | expected: bats — Hook B compares marker mtime vs `pausedAt`; future timestamps pass the `>= pausedAt` check, so the test asserts the documented behavior (acceptance: future timestamps pass) and flags this as a known limitation if the team prefers `pausedAt <= marker <= now`
- [P0] User types `merge BUG-014` outside any workflow context (no `.sdlc/workflows/BUG-014.json`) | mode: test-framework | expected: bats — Hook A creates `.approval-merge-approval-BUG-014`; Hook B on a subsequent `gh pr merge` allows it because the marker exists; test asserts whether Hook B requires a workflow JSON to exist or accepts a marker-only authorization (documented design choice)
- [P1] `approve plan-approval` typed without a workflow ID | mode: test-framework | expected: bats — silently no-op (per AC2 "unknown shapes are silently ignored"); regression that the silent-skip path doesn't crash on a partial match
- [P1] `APPROVE PLAN-APPROVAL BUG-014` (uppercase) and `Approve Plan-Approval BUG-014` (mixed) | mode: test-framework | expected: bats — case-sensitivity of the regex set is pinned (acceptance: case-insensitive on the keyword, case-preserving on the ID since IDs are uppercase by convention)
- [P1] Unicode look-alikes in the keyword (`аpprove` Cyrillic а, `аpprovе` mixed) | mode: test-framework | expected: bats — Hook A regex is byte-level ASCII; look-alikes do not match; no marker created
- [P1] User types two approval shapes back-to-back in one prompt: `approve plan-approval BUG-014\napprove pr-review BUG-014` | mode: test-framework | expected: bats — Hook A creates two markers (or the spec pins a single-line policy); test pins the documented behavior
- [P2] Workflow ID with adversarial characters (`BUG-014; rm -rf .sdlc`) | mode: test-framework | expected: bats — Hook A's marker filename construction quotes/escapes the ID; no command injection; test asserts no unexpected file creation
- [P2] Long workflow ID (`BUG-99999999`) and ID with leading zeros (`BUG-00014` vs `BUG-014`) | mode: test-framework | expected: bats — Hook A and Hook B agree on canonical ID form; markers and lookups use the same form
- [P2] Empty `UserPromptSubmit` body (whitespace only) | mode: test-framework | expected: bats — Hook A no-ops cleanly

### State transitions

- [P0] User approves `plan-approval`, orchestrator advances, then immediately re-pauses for `plan-approval` again (e.g., review reset) | mode: test-framework | expected: bats — second `pause` updates `pausedAt`; Hook B sees the prior marker mtime is now older than `pausedAt`; second resume is denied without a fresh approval
- [P0] Orchestrator under auto mode self-issues `workflow-state.sh resume BUG-014` immediately after `pause` (the FEAT-030 reproduction, gate 2) | mode: test-framework | expected: bats — Hook B denies the resume with a clear error (synthetic harness asserts denial reason mentions missing/stale marker)
- [P0] Orchestrator under auto mode self-issues `workflow-state.sh clear-gate BUG-014` after `set-gate findings-decision` (the FEAT-030 reproduction, gate 1) | mode: test-framework | expected: bats — Hook B denies the clear-gate; gate stays set
- [P0] Forked `finalizing-workflow` Agent spawn includes the carve-out string `Skip the SKILL.md prompt entirely` (the FEAT-030 reproduction, gate 4) | mode: test-framework | expected: bats — Hook C denies the spawn; subagent never starts; user message names the carve-out match
- [P1] Two-pause race: orchestrator pauses (`pausedAt = T1`), user types `proceed BUG-014` (marker mtime = T2 > T1), orchestrator advances and re-pauses (`pausedAt = T3 > T2`), then re-issues resume | mode: test-framework | expected: bats — second resume denied because marker mtime T2 < new pausedAt T3
- [P1] Workflow paused, then `pause` invoked again with a different `pauseReason` while still paused | mode: test-framework | expected: bats — `pausedAt` updates; old `pauseReason` marker no longer matches; Hook B requires a marker for the new reason
- [P1] Mid-workflow `pause`/`resume` cycle when the gate is set but `pauseReason` is null | mode: test-framework | expected: bats — Hook B's "which marker do I require?" decision tree handles `pauseReason: null` ∧ `gate: findings-decision`; pins which marker name applies
- [P2] Process killed between `Hook A writes marker` and `Hook B reads it` (atomicity test) | mode: test-framework | expected: bats — Hook A uses atomic write (rename or O_EXCL); Hook B sees either the full marker or no marker
- [P2] User types approval, then in the same turn types `pause BUG-014` (decline) | mode: test-framework | expected: bats — last-write-wins on the marker (most recent shape wins) OR explicit decline overrides prior approval (acceptance pins which)

### Environment

- [P0] `.sdlc/approvals/` directory missing when Hook A fires | mode: test-framework | expected: bats — Hook A creates the directory (or fails silently per the AC silent-skip clause); test asserts the documented behavior
- [P0] `.sdlc/approvals/` is read-only (chmod 555 or owned by another user on a shared dev box) | mode: test-framework | expected: bats — Hook A logs a warning and the marker is not created; subsequent Hook B denies the gated tool call (fail-secure)
- [P0] Filesystem with coarse mtime resolution (HFS+ 1-second, FAT32 2-second, NFS lazy mtime) — `pausedAt` recorded as `2026-04-26T14:57:04Z` and marker created in the same wall-clock second | mode: test-framework | expected: bats — Hook B comparison uses `>=` (not `>`); same-second ties pass; if comparison were `>`, a fast user gets locked out
- [P1] Plugin disabled mid-workflow (`plugins/disabledPlugins[]` includes `lwndev-sdlc`) | mode: exploratory — Hook A/B/C unload; verify Hook D managed-settings deny list still denies `gh pr merge` etc.; document the gap that workflow-state-transition gates (B's resume/clear-gate guard) are no longer enforced
- [P1] User installs the same hooks at user scope (`~/.claude/settings.json`) as a defense-against-disable per the issue's Mitigation note | mode: exploratory — install at both scopes; verify hooks fire once (not twice); pin documented "preferred install scope"
- [P1] Hook scripts present but non-executable (chmod 644) or wrong shebang | mode: test-framework | expected: bats — Claude Code's hook runner reports a clear error; not silent
- [P2] Clock jump (NTP correction) between marker write and `pausedAt` read | mode: exploratory — wall-clock skew of -10s mid-flow; document expected behavior (acceptance: marker mtime is authoritative; pausedAt comparison is monotonic on the same host)
- [P2] Workflow state file written by Claude Code on macOS, hook script reads it on Linux (cross-platform mtime / timestamp format) | mode: exploratory — pin ISO-8601 string comparison vs filesystem mtime equivalence

### Dependency failure

- [P0] `jq` missing on PATH when Hook B fires | mode: test-framework | expected: bats — Hook B exits with a clear error and **denies** (fail-secure, not fail-open); regression: a missing dependency must not silently allow the gated tool call
- [P0] `.sdlc/workflows/BUG-014.json` missing or unreadable when Hook B fires | mode: test-framework | expected: bats — fail-secure (deny) and surface error; do not assume "no workflow = no gate to enforce"
- [P0] Workflow state JSON missing the `pausedAt` field (pre-existing in-flight workflow file from before the fix landed, AC9) | mode: test-framework | expected: bats — Hook B treats missing `pausedAt` as infinitely old; no marker can satisfy; user must approve fresh
- [P1] Workflow state JSON corrupt (truncated mid-write, invalid JSON) | mode: test-framework | expected: bats — `jq` parse error; Hook B fail-secure
- [P1] `gh` CLI missing when destructive `gh pr merge` is attempted | mode: test-framework | expected: bats — irrelevant for hook test (the Bash call would fail anyway), but document: Hook B fires before the Bash; hook denial precedes `gh` execution
- [P1] Hook A reads `UserPromptSubmit` payload that exceeds Claude Code's documented size limit | mode: exploratory — verify Hook A handles oversized prompt without OOM or partial-read

### Cross-cutting (a11y, i18n, concurrency, permissions)

- [P0] Plugin-disable bypass (acknowledged gap per the bug Notes) | mode: exploratory — agent issues `/plugin disable lwndev-sdlc` mid-workflow; verify Hook D managed-settings still denies the destructive Bash; document residual gap (state-transition guard offline)
- [P0] Auto-mode end-to-end regression bats harness actually simulates auto mode (no `UserPromptSubmit` event = no marker = denial) | mode: test-framework | expected: bats — synthetic harness asserts every of the four FEAT-030 gates is denied without a marker; pinned at `plugins/lwndev-sdlc/scripts/tests/hooks/auto-mode-end-to-end.bats` per AC13
- [P0] Hook C's `Skip Step \d+` whitelist correctly accepts `implementing-plan-phases` Step 10 (and Step 12 — see AC7 variance note) and rejects every other skill | mode: test-framework | expected: bats — parameterized test across the three carve-out targets and a sample of denied targets
- [P0] Hook denial UX: when Hook B denies a `workflow-state.sh resume`, the orchestrator agent must see a clear, actionable error (not a silent failure that gets retried in a loop) | mode: test-framework | expected: bats — assert the deny message includes "missing approval marker" and the canonical user input shape required
- [P1] Concurrent `UserPromptSubmit` events under rapid typing (two prompts within the same second) | mode: exploratory — race between Hook A invocations; verify last-write-wins on the marker (or whichever atomicity the AC pins)
- [P1] Two orchestrator runs concurrently against the same `.sdlc/` (separate workflow IDs) | mode: test-framework | expected: bats — marker filenames include the ID; cross-workflow contamination impossible
- [P1] Hook A approval shapes documented in `orchestrating-workflows/SKILL.md` (per AC11) match the regex Hook A actually parses | mode: test-framework | expected: bats — golden test that the documented grammar examples each produce the expected marker (regression guard against doc/code drift)
- [P2] i18n: user's `UserPromptSubmit` message in a non-English locale that romanizes "approve" differently | mode: exploratory — Hook A regex is English-only by design; document the constraint
- [P2] Marker filename collision when two workflows have the same numeric suffix across types (e.g., FEAT-014 and BUG-014 both have markers) | mode: test-framework | expected: bats — marker names include the full prefix; no collision
- [P2] Permission to write `.sdlc/approvals/` when `.sdlc/` was created by a different user on a shared workstation | mode: exploratory — fail-secure (deny gated tool call) and surface a one-line warning

## Non-applicable dimensions

All five dimensions apply to this fix. Hooks touch input parsing (UserPromptSubmit text matching), state transitions (pause/resume + set-gate/clear-gate ordering), environment (filesystem, plugin enablement), dependencies (`jq`, workflow state JSON, `gh`), and cross-cutting concerns (plugin-disable, concurrency, permissions, internationalization, denial UX).
