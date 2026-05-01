---
id: BUG-015
version: 2
timestamp: 2026-05-01T00:35:00Z
persona: qa
---

## User Summary

The BUG-014 confirmation-gate hooks are wired but two structural gaps allow the orchestrator to bypass the `findings-decision` gate (via direct `Edit` / `Write` / `MultiEdit` of the requirements doc) and the `merge-approval` gate (via an `Agent` fork with `subagent_type: general-purpose` and the confirmation-owning SKILL.md embedded in the prompt). The user-visible expectation is that these bypasses fail-closed — the gate keyword ("approve findings-decision <ID>", "merge <ID>") is what permits the next destructive action, not the orchestrator's word that it has authorization. Any path that lets the orchestrator self-authorize is the bug.

## Capability Report

```json
{
  "id": "BUG-015",
  "mode": "test-framework",
  "framework": "vitest",
  "packageManager": "npm",
  "testCommand": "npm test",
  "language": "typescript"
}
```

- Mode: test-framework
- Framework: vitest (consumer-detected); bats is the actual test framework for the bash hook scripts under change
- Package manager: npm
- Test command: `npm test` for vitest; `bats plugins/lwndev-sdlc/scripts/tests/hooks/*.bats` for hook bats fixtures
- Language: typescript (consumer); bash (hook scripts under test)

Note: capability-discovery.sh detects vitest at the repo root. The affected files in this bug are bash hook scripts; the fix's test coverage lives under `plugins/lwndev-sdlc/scripts/tests/hooks/*.bats`. The QA execution will exercise both: bats fixtures via the hook bats harness, and any vitest probes against TypeScript-side state (`workflow-state.sh` is bash; vitest probes are not applicable here).

## Scenarios (by dimension)

### Inputs

- [P0] Edit tool fired against `requirements/bugs/BUG-015-foo.md` while gate is set, no approval marker exists | mode: test-framework | expected: bats fixture posts hook payload with `tool_name: "Edit"`, `tool_input.file_path` matching the gated path; hook stdout contains `"permissionDecision":"deny"` and exit 0
- [P0] Write tool fired against `requirements/features/FEAT-100-x.md` while gate is set, no approval marker exists | mode: test-framework | expected: same deny envelope as Edit; per-tool parity verified
- [P0] MultiEdit tool fired against `requirements/chores/CHORE-200-y.md` while gate is set, no approval marker exists | mode: test-framework | expected: same deny envelope as Edit; per-tool parity verified
- [P0] Edit fired against gated path with stale marker (mtime < gateSetAt) | mode: test-framework | expected: deny; systemMessage names the stale-marker reason and prompts user to retype `approve findings-decision <ID>`
- [P0] Edit fired against gated path with fresh marker (mtime >= gateSetAt) | mode: test-framework | expected: allow (exit 0, empty stdout)
- [P0] Edit fired against `src/index.ts` while gate is set, no marker | mode: test-framework | expected: allow — out-of-scope path is not gated regardless of gate state
- [P0] Agent fork with `subagent_type: general-purpose` and embedded `name: finalizing-workflow` frontmatter, no merge-approval marker | mode: test-framework | expected: deny; systemMessage prompts `merge <ID>`
- [P0] Agent fork with `subagent_type: general-purpose` and embedded `name: reviewing-requirements` frontmatter, no merge-approval marker | mode: test-framework | expected: allow — non-confirmation-owning embedded skill must not trigger AC8 false positive
- [P1] Edit fired against gated path while gate is null (cleared) | mode: test-framework | expected: allow regardless of marker state
- [P1] tool_input.file_path with `..` traversal segment (e.g., `requirements/bugs/../../etc/passwd`) | mode: test-framework | expected: hook does not match the regex; allow OR deny safely — no path normalization vulnerability
- [P1] tool_input.file_path absolute path that resolves into requirements dir (e.g., `/Users/.../lwndev-marketplace/requirements/bugs/BUG-015-foo.md`) | mode: test-framework | expected: hook decision is consistent with relative-path case (either both deny or both allow; document the choice in bats fixture)
- [P1] tool_input.file_path null / empty / missing | mode: test-framework | expected: allow (no path to gate); no jq parse crash
- [P1] tool_input.file_path symlink pointing into requirements dir | mode: exploratory | expected: hook treats symlink as the literal path string in tool_input (does not resolve); document the choice
- [P2] tool_input.file_path with embedded shell metachars (`$(rm -rf /)`, backticks) | mode: test-framework | expected: bash regex match treats input as literal; no command substitution; allow/deny based on path pattern only

### State transitions

- [P0] set-gate -> Edit deny -> approve findings-decision -> Edit allow -> clear-gate -> Edit allow | mode: test-framework | expected: full gate cycle through bats matrix; gateSetAt advances on set-gate, resets on clear-gate
- [P0] set-gate -> approve findings-decision (writes marker A) -> clear-gate -> set-gate (gateSetAt advances) -> Edit with marker A | mode: test-framework | expected: deny — marker A's mtime is now older than the new gateSetAt; user must reapprove
- [P0] cmd_pause auto-clears gate -> resume sets new gateSetAt -> stale marker A from before pause | mode: test-framework | expected: deny; pause is the documented path that resets gateSetAt to null
- [P1] Two Edit calls fired in quick succession against the same gated path, only the first has a fresh marker | mode: test-framework | expected: first allows; second's marker freshness depends on gateSetAt mtime semantics — document race window
- [P1] User types `approve findings-decision BUG-015` then immediately tries Edit before record-approval.sh's mv completes | mode: exploratory | expected: race documented; mv -f is atomic so either marker is fully there or fully absent — no partial-marker edge case
- [P2] User types two approval lines in one prompt: `approve findings-decision BUG-015\napprove merge-approval BUG-015` | mode: test-framework | expected: both markers written; record-approval.sh handles multi-line prompts (already covered in record-approval.bats; verify gateSetAt does not interact)

### Environment

- [P0] `.sdlc/approvals/` directory missing when Edit fires on gated path | mode: test-framework | expected: deny (no marker present); hook does not crash on missing dir
- [P0] `.sdlc/workflows/.active` missing when Agent fork to finalizing-workflow fires | mode: test-framework | expected: deny (existing AC behavior); embedded-name lookup must produce same result
- [P0] State file corrupt JSON when checking gate field in guard-findings-edits.sh | mode: test-framework | expected: fail-secure deny; systemMessage names the corrupt-state reason
- [P0] `jq` missing on PATH when guard-findings-edits.sh runs | mode: test-framework | expected: fail-secure deny (matches existing Hook B / Hook C convention)
- [P1] BSD `stat -f %m` vs GNU `stat -c %Y` mtime comparison cross-platform | mode: test-framework | expected: existing iso_to_epoch / marker_mtime_epoch helpers handle both (already in guard-state-transitions.sh); reuse pattern verbatim
- [P1] Permissions: `.sdlc/approvals/` exists but is not readable by hook | mode: exploratory | expected: marker_mtime_epoch returns empty; hook treats as missing marker; deny
- [P1] gateSetAt timestamp parses as ISO-8601 with subsecond precision | mode: test-framework | expected: iso_to_epoch truncates to whole seconds consistently between marker mtime and gateSetAt
- [P2] Clock skew: marker filesystem mtime jumps backward after NTP sync | mode: exploratory | expected: stale-marker check still based on linear epoch comparison; document that backward clock jumps are out of scope
- [P2] Daylight-saving / TZ change between gate set and marker write | mode: test-framework | expected: both timestamps stored as UTC; no TZ-dependent drift

### Dependency failure

- [P0] `workflow-state.sh set-gate` fails to write `gateSetAt` due to disk full | mode: exploratory | expected: state file remains valid (tmp+mv atomicity); gate field unchanged on failure
- [P0] `workflow-state.sh clear-gate` partially writes (interrupted) | mode: exploratory | expected: tmp+mv atomicity preserves prior valid state
- [P1] State file missing `gateSetAt` field (legacy state file from before this fix) | mode: test-framework | expected: treated as infinitely old (mirrors BUG-014 / AC9 `pausedAt` semantics); no marker can satisfy; user must reapprove
- [P1] State file with `gateSetAt: null` (cleared via clear-gate) and gate is null | mode: test-framework | expected: hook short-circuits (gate is null) before consulting gateSetAt; allow
- [P1] State file with `gateSetAt: null` but gate is non-null (impossible state from a bug elsewhere) | mode: test-framework | expected: fail-secure deny; document defensive handling
- [P2] `gh` CLI missing when Agent hook tries to resolve confirmation-owning context | mode: test-framework | expected: hook does not depend on `gh`; embedded-name lookup is offline-only

### Cross-cutting

- [P0] Hook execution order: when Edit and Bash hooks both fire (e.g., Bash invokes a script that internally Edits) | mode: exploratory | expected: each tool call gates independently; document that the inner Edit is also gated
- [P0] Forked subagent's tool calls inherit the parent's hook config | mode: test-framework | expected: bats fixture runs the hook against an Agent-spawned tool payload and confirms hook fires per Claude Code hook semantics (PreToolUse fires on the parent for tool calls executed by subagents)
- [P0] Auto-mode (no UserPromptSubmit) cannot self-authorize: orchestrator-issued Edit during auto-mode never has a marker because record-approval.sh fires only on real UserPromptSubmit | mode: test-framework | expected: bats fixture simulates auto-mode (no approval marker present, gate set) and confirms deny — this is the load-bearing security property
- [P1] Concurrency: two orchestrators running in parallel on the same workflow ID | mode: exploratory | expected: out of scope (`.sdlc/workflows/.active` is a single-tenant marker); document
- [P1] Performance: hook adds <50ms per Edit call (matches existing Hook B / Hook C latency budget) | mode: test-framework | expected: bats timing assertion or a separate microbench; exit code timing
- [P2] Logging: hook emits `[warn]`/`[info]` lines on skip paths (jq missing, dir missing) consistent with existing hook tagged-log convention | mode: test-framework | expected: bats fixture captures stderr and asserts the tagged-log format

## Non-applicable dimensions

- a11y: this change has no UI surface; hook scripts run in the CLI tool layer and produce JSON envelopes consumed by Claude Code, not by humans directly.
- i18n: hook systemMessage strings are documented in English only; the user-input grammar (`approve <gate> <ID>`, `merge <ID>`) is also English-only by design and not localized.
- pluralization / RTL / date-format / locale: hook does not render user-facing copy beyond fixed-format JSON; gateSetAt is ISO-8601 UTC.
- screen reader / keyboard navigation / color contrast / focus trapping: no UI rendered.
- queue overflow / dropped messages: hook is synchronous, single-process, no message bus.
- cascade failures from one dep to another: hook depends only on `jq`, the local filesystem, and the existing state file; no cascading external services.
