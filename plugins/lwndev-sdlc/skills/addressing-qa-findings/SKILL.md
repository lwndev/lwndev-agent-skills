---
name: addressing-qa-findings
description: Developer-persona skill that consumes QA findings (verdict ISSUES-FOUND), reproduces failing QA tests, writes production fixes, re-validates, and adopts QA tests into *.qa.* siblings next to peer tests once re-QA passes. Use when the orchestrator branches from executing-qa with a non-PASS verdict, or when re-running addressing-qa-findings to drive the QA loop forward.
allowed-tools:
  - Read
  - Edit
  - Bash
  - Glob
  - Grep
argument-hint: <requirement-id>
---

# Addressing QA Findings

Developer-persona skill: consume QA findings, fix production, re-validate, adopt the QA tests as `*.qa.*` siblings next to their peer tests. Sole owner of QA-test deletion per FR-13 (the move via `git mv` IS the deletion).

## When to Use This Skill

- Forked by `orchestrating-workflows` after `executing-qa` returns verdict `ISSUES-FOUND` (FR-7 dispatch).
- Forked again after re-QA returns `PASS` (FR-7 dispatch -> adopt-phase).
- Manually via `/addressing-qa-findings <ID>` against a checked-out feature branch with a recorded QA verdict.

## Arguments

- **When argument is provided**: Match the requirement ID by prefix (`FEAT-`, `CHORE-`, `BUG-`). The skill reads the QA artifact at `qa/test-results/QA-results-{ID}.md` and the workflow state via `workflow-state.sh get-qa-state {ID}`.
- **When no argument is provided**: Ask the user for a requirement ID.

## Phase Auto-Detection (FR-4 triple)

The skill auto-detects which phase to run from the FR-4 state triple `{qaLastVerdict, qaFixAttempts, adoptedTests}`. No phase argument is taken from the orchestrator; no `lastStepKind` is required.

```bash
phase=$(bash "${CLAUDE_PLUGIN_ROOT}/skills/addressing-qa-findings/scripts/detect-phase.sh" "$ID")
```

| Trigger | Phase |
|---------|-------|
| `qaLastVerdict == "ISSUES-FOUND"` AND `adoptedTests == []` | `phase=fix` |
| `qaLastVerdict == "PASS"` AND `qaFixAttempts > 0` AND `adoptedTests == []` | `phase=adopt` |
| anything else | `phase=unknown` — emit `failed | unable to auto-detect phase from state` and exit |

## Quick Start — Fix Phase

Script paths: `${CLAUDE_PLUGIN_ROOT}/skills/addressing-qa-findings/scripts/` is `$SCRIPTS/`. Workflow-state script: `${CLAUDE_PLUGIN_ROOT}/skills/orchestrating-workflows/scripts/workflow-state.sh`.

1. Pre-checks (fail-fast with verbatim FR-4 messages):

   ```bash
   bash "$SCRIPTS/check-fix-prechecks.sh" "$ID"
   ```

   On exit 1, the script prints one of:
   - `failed | working tree dirty; commit or stash before re-running`
   - `failed | no QA artifact at qa/test-results/QA-results-{ID}.md`

   Surface that line as the FINAL line and exit. Exit 2 = missing args (developer error).

2. Process all findings as a single batch (FR-8):
   - Read each embedded QA test source from the `## Reproduction` block in the QA artifact.
   - Locate the committed QA test file on the branch under one of the FR-3 v1 globs (`tests/unit/qa-*.test.ts`, `tests/unit/qa-*.test.js`, `tests/bats/qa/qa-*.bats`).
   - Run each QA test locally and confirm it FAILS at HEAD (sanity check). On failure to reproduce, surface the framework's verbatim output and exit; do not proceed to fix.
   - Write production fix(es) via `Edit`. Do NOT touch the QA test files.
   - Re-execute each QA test and confirm it now PASSES locally.

3. Run the build-health gate as the suite-level guard:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/verify-build-health.sh" --no-interactive
   ```

   On failure, emit `failed | full suite gate failed after fix; reverting commit not implemented in v1, manual intervention required` and exit (Edge Case 13). Do NOT auto-revert.

4. Stage the production fix and commit (do NOT stage QA test edits — there should be none):

   ```bash
   git add <fixed-paths>
   git commit -m "fix(${ID}): <one-line summary of the fix>"
   ```

5. Emit the return contract as the FINAL line:

   ```
   done | phase=fix-committed | awaiting-re-qa
   ```

The orchestrator (Phase 4) re-invokes `executing-qa` after this exit; `executing-qa` auto-detects re-QA mode (FR-3) and re-records the verdict.

## Quick Start — Adopt Phase

Pre-check: verify `qaLastVerdict == "PASS"` (orchestrator already enforces; double-check with `get-qa-state`).

1. Drive the adoption loop:

   ```bash
   bash "$SCRIPTS/run-adopt-loop.sh"
   ```

   The script enumerates committed QA test files matching the FR-3 v1 glob set (`tests/unit/qa-*.test.ts`, `tests/unit/qa-*.test.js`, `tests/bats/qa/qa-*.bats`), calls `adopt-qa-test.sh` once per file, and streams adopted paths to stdout (one per line) for incremental orchestrator consumption.

   Exit codes:
   - `0`: every QA file adopted; stdout has one adopted-path per line.
   - `1`: partial-success — FR-4 verbatim message on stdout (`failed | adoption failed for <path>; <N> adopted, <M> remaining`); the failing `adopt-qa-test.sh` stderr line (`adopt-qa-test: <path>: <reason>`) is bubbled through. Surface both verbatim and exit.
   - `2`: no committed QA files matched the globs (no-op).

2. On full success, stage and commit the adoption (single commit covering all moves):

   ```bash
   git add -A
   git commit -m "qa(adopt): ${ID} promote QA tests into regression suite"
   ```

3. Emit the return contract as the FINAL line (FR-4):

   ```
   done | phase=adopted | artifact=qa/test-results/QA-results-${ID}.md | adopted=<N>
   ```

## Output Style

Follow the lite-narration rules below. Load-bearing carve-outs MUST be emitted as specified; they are not narration. This skill is forked by `orchestrating-workflows` from the QA-step branch (FR-7 dispatch), so its output flows to a parent orchestrator rather than directly to the user.

### Lite narration rules

- No preamble before tool calls. No emoji. ASCII punctuation only.
- No end-of-turn summaries beyond one short sentence.
- No status echoes that tools already show.
- Short sentences over paragraphs. Bullet lists when listing more than two items.

### Load-bearing carve-outs (never strip)

The following MUST always be emitted even when they resemble narration:

- **Pre-check failure messages** — verbatim FR-4 strings (`failed | working tree dirty; commit or stash before re-running`, `failed | no QA artifact at qa/test-results/QA-results-{ID}.md`, `failed | unable to auto-detect phase from state`).
- **Suite-gate failure message** — verbatim Edge Case 13 string (`failed | full suite gate failed after fix; reverting commit not implemented in v1, manual intervention required`).
- **Adoption partial-success message** — verbatim FR-4 string (`failed | adoption failed for <path>; <N> adopted, <M> remaining`).
- **`adopt-qa-test.sh` stderr line** — `adopt-qa-test: <path>: <reason>` is the FR-5 structured failure log; surface verbatim.
- **Adopted-path stdout stream** — one path per line, emitted immediately after each successful `adopt-qa-test.sh` exit (orchestrator consumes incrementally per FR-4 step 2.2).
- **Tagged structured logs** — any line prefixed `[info]`, `[warn]`, `[model]` is structured log; emit verbatim.

### Fork-to-orchestrator return contract

Emit `done | <key=value chain>` as the FINAL line on success and `failed | <one-sentence reason>` on failure. Two success shapes:

- Fix phase: `done | phase=fix-committed | awaiting-re-qa`
- Adopt phase: `done | phase=adopted | artifact=qa/test-results/QA-results-${ID}.md | adopted=<N>`

Failure shapes (verbatim per FR-4 / FR-5 / Edge Case 13):

- `failed | working tree dirty; commit or stash before re-running`
- `failed | no QA artifact at qa/test-results/QA-results-{ID}.md`
- `failed | unable to auto-detect phase from state`
- `failed | full suite gate failed after fix; reverting commit not implemented in v1, manual intervention required`
- `failed | adoption failed for <path>; <N> adopted, <M> remaining`

**Precedence**: the return contract takes precedence over lite rules when the two conflict.

## Deletion Ownership (FR-13)

`adopt-qa-test.sh` is the SOLE owner of QA-test deletion across the entire plugin. The move via `git mv` IS the deletion. No other script under `plugins/lwndev-sdlc/` deletes any `qa-*` file. The FR-13 negative test pins this invariant at test time (`tests/bats/skills/addressing-qa-findings/deletion-ownership.bats`).

## References

- **adopt-qa-test.sh source**: [`scripts/adopt-qa-test.sh`](scripts/adopt-qa-test.sh)
- **FEAT-032 plan**: `requirements/implementation/FEAT-032-executing-qa-ephemeral-tests.md`

## Relationship to Other Skills

| Trigger | Skill |
|---------|-------|
| QA verdict `ISSUES-FOUND` from `executing-qa` | this skill (fix phase) |
| QA verdict `PASS` after a prior fix attempt | this skill (adopt phase) |
| QA verdict `PASS` on first run | advance directly to `finalizing-workflow` |
| QA verdict `ERROR` | orchestrator pauses with `qa-error` |
