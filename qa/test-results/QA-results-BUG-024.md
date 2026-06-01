---
id: BUG-024
version: 2
timestamp: 2026-06-01T12:12:27Z
verdict: PASS
persona: qa
---

## Summary

PASS — write-surface guard (relocated to finalize.sh per BUG-024 root cause) blocks every out-of-surface delete/rename/content-edit across committed/staged/working-tree, enumerates blast radius, and allows requirement-doc bookkeeping. 10/10 adversarial + 16/16 regression green.

## Capability Report

```json
{
  "id": "BUG-024",
  "timestamp": "2026-06-01T12:04:04Z",
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
- [P0] Bulk out-of-surface rename (30 qa-* files -> *.qa.* to dodge the prefix glob) | mode: test-framework | guard exits 2 and enumerates every source AND destination path (60 lines); no partial-allow. PASS (`qa-BUG-024-write-surface.bats`)
- [P1] Content edit (M-status) to an unrelated tracked file outside the surface — committed, staged, working-tree variants | mode: test-framework | guard blocks (exit 2) in all three; the dev suite covered only rm/mv, this closes the content-edit gap. PASS
- [P1] Allowed: commit touching ONLY requirement docs (BK-5), incl. across features/chores/bugs types | mode: test-framework | guard exits 0. PASS
- [P2] Awkward out-of-surface filenames — spaces, leading dash, Unicode, deeply nested dir | mode: test-framework | guard detects and blocks each (exit 2); no word-splitting misparse, no silent skip. PASS

### State transitions
- [P0] `preflight-checks.sh` non-zero (qa-* safety-net trips) | mode: test-framework | `finalize.sh` exits 1, propagates stderr verbatim, merge dispatcher AND branch-parse never reached (zero recovery). Covered by committed `finalize.bats` case 14 + `finalize-write-surface.bats` case 1. PASS (regression suite)
- [P1] Idempotent refusal on re-invocation with offending file present | mode: test-framework | `finalize-write-surface.bats` case 1 (capture-if-absent reuse) confirms the re-run blocks against the original clean baseline. PASS (regression suite)
- [P2] Stop-hook re-entry (`stop_hook_active`) | mode: exploratory | NOT APPLICABLE: the fix relocated enforcement out of a Stop hook into `finalize.sh` (a forked subagent raises SubagentStop post-merge; a Stop hook never fires pre-merge). No Stop hook exists to re-enter. See Findings F1 (plan drift).

### Environment
- [P1] Outside a git repo / no commits | mode: test-framework | `arm-baseline.sh` prints empty and writes no marker; `check-write-surface.sh` with an empty baseline exits 0 (cannot verify -> does not block). Covered by `arm-baseline.bats` case 4 + `check-write-surface.bats` case 4. PASS (regression suite)
- [P1] Active-marker-absent no-op | mode: exploratory | NOT APPLICABLE: there is no active-marker gate; `finalize.sh` runs the guard unconditionally on every finalize. Plan drift (F1).
- [P2] `jq` unavailable | mode: exploratory | NOT APPLICABLE: neither `arm-baseline.sh` nor `check-write-surface.sh` parses JSON / uses `jq`; they consume git plumbing output only. Plan drift (F1).

### Dependency failure
- [P1] Diff guard scopes only the run's own changes | mode: test-framework | the baseline anchors `git diff <baseline> HEAD` to the pre-finalize tip; pre-existing history below the baseline is not flagged, and pre-existing working-tree dirt cannot reach the guard because `run_preflight` (clean-tree gate) runs before `check_write_surface`. Verified by `finalize-write-surface.bats` cases 1-2. PASS (regression suite)
- [P2] `managing-source-control` dispatcher unavailable during pre-flight | mode: exploratory | on the block path the merge dispatcher is never reached, so a missing dispatcher cannot trigger destructive recovery; the guard aborts first.

### Cross-cutting
- [P0] Orchestrator finalize fork-prompt negative-constraint paragraph present verbatim at all THREE sites in `step-execution-details.md` (feature 5+N+4, chore 7, bug 7) | mode: test-framework | confirmed at lines 36, 75, 130 (forbids `git rm`/`git mv`/`git restore --staged`/`rm` outside `requirements/<type>/{ID}-*.md`; mandates the `failed | preflight blocked:` return). PASS (grep assertion)
- [P1] `finalizing-workflow/SKILL.md` `## Write Surface` section | mode: test-framework | PRESENT; lists allowed paths + forbidden ops + the relocation rationale. PASS. The plan's companion expectation of a `hooks: Stop` frontmatter entry is OBSOLETE — see Findings F1.
- [P2] Write surface is the single source of truth | mode: exploratory | `check-write-surface.sh` hard-codes the allowed surface; no env-var / out-of-band widening path exists. Widening requires a script edit. PASS (code inspection)

### Non-applicable dimensions
- a11y / i18n / injection: SDLC tooling (Bash + Markdown), no rendered UI, no localized strings, no SQL/XSS/network surface. The only "input" is git index/work-tree state, covered under Inputs.

## Findings

No blocking findings. Verdict PASS: 10/10 adversarial scenarios passed; the committed guard regression suite (16 cases) is green.

### F1 — Plan drift (informational, NOT a defect): enforcement relocated from a Stop hook to an in-script pre-merge guard

The v2 QA plan (and several requirement-doc ACs) were authored against an earlier design in which a `finalizing-workflow` **Stop hook** (`stop-hook.sh`) enforced the write surface (commits a40e5ed, a8dad3d). Commit 4e10f01 correctly **relocated** enforcement into `finalize.sh` (`arm-baseline.sh` + `check-write-surface.sh`), because a forked subagent raises **SubagentStop** — which fires only AFTER the fork has already merged — so a Stop hook can never block a pre-merge mutation. This is the bug's own root cause; the relocation makes the implementation MORE correct than the plan, not less. AC-4 in the requirement doc explicitly ratifies this ("Enforcement is a PRE-MERGE check inside `finalize.sh` ... NOT a SKILL.md `Stop` hook").

Consequently the following plan scenarios are obsolete and were re-scoped, not failed:
- Inputs/State "Stop hook exits 2 ..." -> re-scoped to "`check-write-surface.sh`/`finalize.sh` exit 2/1".
- State P2 "Stop-hook re-entry (`stop_hook_active`)" -> N/A (no Stop hook).
- Environment P1 "active-marker absent no-op" -> N/A (guard runs unconditionally).
- Environment P2 "`jq` unavailable" -> N/A (guard uses git plumbing only, no `jq`).
- Cross-cutting P1 "`hooks: Stop` frontmatter" -> obsolete; the `## Write Surface` section is the surviving, correct half.

### F2 — Reconciliation delta gaps are reconciler-naive (informational)

`qa-reconcile-delta.sh` reports 7 "coverage gaps" by string-matching requirement ACs against the artifact's flat scenario list. The ACs are structural assertions (SKILL.md section present, `finalize.sh` check present, doc paragraph present) verified directly in this run (Cross-cutting dimension) and by the committed regression suite; they are not behavioral scenarios the matcher can pair. No real coverage gap — see the dimension-organized `## Scenarios Run`.

## Reconciliation Delta

### Coverage beyond requirements
- Scenario "[P1] Allowed: commit touching ONLY requirement docs (BK-5), incl. across features/chores/bugs types: guard exits 0. PASS" — not mentioned in spec
- Scenario "[P1] Diff guard scopes only the run's own changes: the baseline anchors `git diff <baseline> HEAD` to the pre-finalize tip; pre-existing committed history below" — not mentioned in spec
- Scenario "[P2] `managing-source-control` dispatcher unavailable during pre-flight — exploratory: on the block path the merge dispatcher is never reached, so a missing dis" — not mentioned in spec
- Finding "State P2 "Stop-hook re-entry (`stop_hook_active`)" -> N/A (no Stop hook)." — not mentioned in spec
- Finding "Environment P1 "active-marker absent no-op" -> N/A (guard runs unconditionally)." — not mentioned in spec
- Finding "Environment P2 "`jq` unavailable" -> N/A (guard uses git plumbing only, no `jq`)." — not mentioned in spec

### Coverage gaps

### Summary
- coverage-surplus: 6
- coverage-gap: 0

