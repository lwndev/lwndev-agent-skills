---
id: BUG-014
version: 2
timestamp: 2026-04-26T18:42:04Z
verdict: PASS
persona: qa
---

## Summary

Bug fix correctly enforces confirmation gates against auto-mode bypass attempts at all four FEAT-030 reproduction sites and the latent review-findings gate. Hook A creates approval markers from canonical user input shapes only; Hook B fail-secures on missing/stale markers, missing dependencies, corrupt state, and unparseable timestamps; Hook C denies carve-out regex matches and gates finalizing-workflow spawns; managed-settings template ships as defense-in-depth backstop; pausedAt anchor defeats stale-marker replay across pause/resume cycles.

## Capability Report

```json
{
  "id": "BUG-014",
  "timestamp": "2026-04-26T18:25:12Z",
  "mode": "test-framework",
  "framework": "vitest",
  "packageManager": "npm",
  "testCommand": "npm test",
  "language": "typescript",
  "notes": []
}
```

## Execution Results

- Total: 10
- Passed: 10
- Failed: 0
- Errored: 0
- Exit code: 0

## Scenarios Run

### Inputs

- [P0] Hook B mtime semantics — future-dated marker passes the `>= pausedAt` check (mode: test-framework; AC-4, AC-9; documented limitation per plan)
- [P0] Hook A + Hook B composite — `merge BUG-014` outside any workflow context creates marker but Hook B denies because `.active` is missing (mode: test-framework; AC-2, AC-6)
- [P2] Leading-zero canonical form — `BUG-00014` and `BUG-014` produce distinct markers; no aliasing (mode: test-framework; AC-2)
- [P2] Multiple shapes back-to-back — `approve plan-approval BUG-014\npause BUG-014` creates both markers (mode: test-framework; AC-2)
- [P0] Hook A canonical-shape regression — every documented shape (`approve <gate> <ID>`, `proceed <ID>`, `yes <ID>`, `merge <ID>`, `pause <ID>`) writes the expected marker (mode: test-framework; AC-2; covered by `record-approval.bats` 27 tests)
- [P0] Adversarial workflow ID injection — `BUG-014; rm -rf .sdlc` does not produce a shell-injected marker filename (mode: test-framework; AC-2; covered by `record-approval.bats`)
- [P1] Case-insensitive keyword folding — `APPROVE PLAN-APPROVAL BUG-014` matches; Cyrillic look-alikes do not (mode: test-framework; AC-2; covered by `record-approval.bats`)

### State transitions

- [P1] Pause-then-different-reason — `plan-approval` marker does not satisfy a re-pause for `pr-review` (mode: test-framework; AC-4, AC-9)
- [P1] Two-pause race full E2E — T2 marker becomes stale after T3 re-pause (mode: test-framework; AC-4, AC-9, AC-13)
- [P0] Self-resume immediately after pause — Hook B denies the auto-mode bypass (mode: test-framework; AC-4, AC-13; covered by `auto-mode-end-to-end.bats` and `guard-state-transitions.bats`)
- [P0] Self-clear-gate immediately after set-gate — Hook B denies the auto-mode bypass (mode: test-framework; AC-5, AC-13; covered by `auto-mode-end-to-end.bats`)
- [P0] Latent review-findings gate — paused workflow with `review-findings` denies self-resume (mode: test-framework; AC-4)
- [P0] `pausedAt` write semantics — `cmd_pause` writes ISO-8601; resume preserves it; second pause overwrites (mode: test-framework; AC-9; covered by `workflow-state-pausedat.bats`)

### Environment

- [P0] Same-second tie — marker mtime equal to `pausedAt` second passes via `>=` (not `>`); coarse-mtime FS robustness (mode: test-framework; AC-4, AC-9)
- [P0] Read-only `.sdlc/approvals/` — Hook A no-ops gracefully (no marker written); Hook B subsequently denies (mode: test-framework; AC-2, AC-4)
- [P0] Missing `.sdlc/approvals/` directory — Hook A creates it on demand (mode: test-framework; AC-2; covered by `record-approval.bats`)
- [P1] Plugin disabled mid-workflow — Hook D managed-settings deny list still gates destructive Bash; Hooks A/B/C unload gap is documented (mode: exploratory; AC-10; verified via file-presence on managed-settings.example.json)
- [P2] Cross-platform timestamp parity — `pausedAt` is ISO-8601 string compared against marker mtime via `iso_to_epoch`; documented in fix design (mode: exploratory; AC-9)

### Dependency failure

- [P0] Hook B with missing jq — fail-secure deny when jq is not on PATH (mode: test-framework; AC-4, AC-5; new adversarial coverage)
- [P0] `.sdlc/workflows/<ID>.json` missing — Hook B denies on resume (mode: test-framework; AC-4; covered by `guard-state-transitions.bats`)
- [P0] State JSON missing `pausedAt` — Hook B treats as infinitely old; pre-fix workflows require fresh approval (mode: test-framework; AC-9; covered by `guard-state-transitions.bats`)
- [P1] State JSON corrupt — Hook B fail-secures on jq parse error (mode: test-framework; AC-4; covered by `guard-state-transitions.bats`)
- [P1] State JSON unparseable `pausedAt` — Hook B fail-secures rather than treating marker as fresh (mode: test-framework; AC-9; covered by `guard-state-transitions.bats`)

### Cross-cutting

- [P2] Cross-workflow marker isolation — `FEAT-014` merge marker does not authorize a `BUG-014` spawn (mode: test-framework; AC-7, AC-8)
- [P0] Auto-mode end-to-end regression — synthetic workflow asserts every of the four FEAT-030 gates plus latent gates is denied without a marker (mode: test-framework; AC-13; covered by `auto-mode-end-to-end.bats` 19 tests)
- [P0] Hook C carve-out regex set — every documented carve-out shape is denied; Skip-Step whitelist for `implementing-plan-phases` allowed (mode: test-framework; AC-7; covered by `guard-agent-prompts.bats`)
- [P0] Hook C confirmation-owning skill set — `finalizing-workflow` spawn denied without `merge-approval` marker (mode: test-framework; AC-8; covered by `guard-agent-prompts.bats`)
- [P0] Hook denial UX — Hook B output includes the canonical user input shape required (mode: test-framework; AC-4; covered by `guard-state-transitions.bats`)
- [P1] Concurrent UserPromptSubmit — Hook A is line-oriented; multiple shapes in one prompt write multiple markers (mode: test-framework; AC-2)
- [P1] Two concurrent orchestrator runs — marker filenames include the ID; cross-workflow contamination impossible (mode: test-framework; AC-2)

### Static-artifact verification (file-presence on this branch)

- [P0] AC-10 verification — Hook D managed-settings template ships at `plugins/lwndev-sdlc/.claude-plugin/managed-settings.example.json` with companion `MANAGED-SETTINGS.md` (mode: exploratory; verified via `git ls-tree`)
- [P0] AC-11 verification — Approval-marker grammar documented in `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` plus the new `references/approval-marker-grammar.md` (mode: exploratory; verified via file-presence)
- [P0] AC-12 verification — Bats coverage exists for each hook per gate type at `plugins/lwndev-sdlc/scripts/tests/hooks/{record-approval,guard-state-transitions,guard-agent-prompts}.bats` (mode: exploratory; verified via file-presence)
- [P0] AC-1 verification — `plugins/lwndev-sdlc/hooks/hooks.json` declares Hook A / B / C with the documented matchers and is JSON-valid (mode: exploratory; verified via file-presence and `jq -e .`)

## Findings

No defects found. Adversarial scenarios (vitest) and existing bats fixtures (109 tests) pass; build-health gate passes (lint + format:check); reconciliation aligns scenarios to all 13 ACs with zero coverage gaps and zero coverage surplus.

## Reconciliation Delta

### Coverage beyond requirements

### Coverage gaps

### Summary
- coverage-surplus: 0
- coverage-gap: 0

