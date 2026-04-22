# Feature Requirements: `finalize.sh` + Subscripts (finalizing-workflow Full Rewrite)

## Overview
Collapse the `finalizing-workflow` skill to a single confirmation prompt + one top-level `finalize.sh` call by extracting all mechanical pre-flight, bookkeeping, and execution steps into shell subscripts. Ships `finalize.sh` (top-level orchestration) and four subscripts (`preflight-checks.sh`, `check-idempotent.sh`, `completion-upsert.sh`, `reconcile-affected-files.sh`) and extends the existing plugin-shared `branch-id-parse.sh` with a release-branch classification.

## Feature ID
`FEAT-022`

## GitHub Issue
[#182](https://github.com/lwndev/lwndev-marketplace/issues/182)

## Priority
High — Second-largest mechanical-to-script win in the #179 backlog (estimate: ~1,500–2,500 tokens and 30–60 seconds saved **per workflow run**, across all three chain types — feature, chore, bug). Terminal step in every chain, so every workflow benefits. The token/time figures are carried forward from the #179 audit and are estimates, not measurements — see NFR-5 and the Acceptance Criteria for the measurement contract.

## User Story
As an orchestrator (or user invoking `finalizing-workflow` directly), I want to replace the multi-step prose ceremony (pre-flight checks, BK-1..BK-5 bookkeeping, and merge/checkout/fetch/pull execution) with a single script invocation so that the skill collapses to one confirmation dialog plus one command, eliminating per-workflow token overhead and shaving 30–60 seconds off each finalize.

## Command Syntax

### Top-level

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/finalizing-workflow/scripts/finalize.sh" <branch-name>
```

Arguments:
- `<branch-name>` (required) — The current branch name (the caller captures this from `git branch --show-current` before invoking).

Exit codes:
- `0` — Merge + checkout + fetch + pull all succeeded. Bookkeeping either ran, was skipped silently (idempotent), or skipped with the documented info/warn message.
- `1` — Any pre-flight check failed, bookkeeping commit/push failed, merge failed, checkout failed, or a non-recoverable error in a subscript. Stdout/stderr carry the reason.
- `2` — Missing or invalid `<branch-name>` arg.

Stdout on success: a short multi-line report listing merged PR number/title, the bookkeeping actions taken (or "skipped — already finalized" / "skipped — not a workflow branch"), and final branch state. Stderr is reserved for warnings and errors.

### Subscripts

Each subscript is independently callable and returns structured JSON or human-readable output. The caller (`finalize.sh`) handles composition.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/finalizing-workflow/scripts/preflight-checks.sh"
bash "${CLAUDE_PLUGIN_ROOT}/skills/finalizing-workflow/scripts/check-idempotent.sh" <doc-path> <prNumber>
bash "${CLAUDE_PLUGIN_ROOT}/skills/finalizing-workflow/scripts/completion-upsert.sh" <doc-path> <prNumber> <prUrl>
bash "${CLAUDE_PLUGIN_ROOT}/skills/finalizing-workflow/scripts/reconcile-affected-files.sh" <doc-path> <prNumber>
```

### Examples

```bash
# Typical feature workflow finalize
bash "${CLAUDE_PLUGIN_ROOT}/skills/finalizing-workflow/scripts/finalize.sh" "feat/FEAT-022-finalize-sh-subscripts"

# Release branch (bookkeeping skipped silently — new behavior)
bash "${CLAUDE_PLUGIN_ROOT}/skills/finalizing-workflow/scripts/finalize.sh" "release/lwndev-sdlc-v1.16.0"

# Unrecognized branch (existing behavior preserved — info message, proceed to merge)
bash "${CLAUDE_PLUGIN_ROOT}/skills/finalizing-workflow/scripts/finalize.sh" "adhoc/cleanup-branch"
```

## Functional Requirements

### FR-1: `finalize.sh` — Top-Level Orchestration
- Accept `<branch-name>` as a positional argument. Exit `2` on missing or empty arg.
- Compose the full finalize sequence in this order:
  1. `preflight-checks.sh` (FR-2). Abort with exit `1` on any failure reason surfaced by the subscript.
  2. Branch classification via `branch-id-parse.sh` (extended per FR-3).
  3. Bookkeeping — skipped when classification yields `type == "release"`, when the parse exits `1` (unrecognized), or when the idempotency check (FR-4) passes. When it runs, it is the BK-2..BK-5 subsequence from the current SKILL.md (BK-1 is the branch-id-parse step itself, already completed in step 2 above).
  4. Execution — `gh pr merge --merge --delete-branch`, `git checkout main`, `git fetch origin`, `git pull`.
- Do **not** emit the user-confirmation prompt — that remains in SKILL.md prose (FR-10). `finalize.sh` runs unattended after confirmation.
- **Unexpected subscript exit codes**: every subscript documents the exit codes it emits (`0`, `1`, `2`, and for some, `3`). If a subscript exits with a code `finalize.sh` does not recognize for that subscript, treat it as a fatal error — propagate with `finalize.sh` exit `1` and write the subscript's stderr to `finalize.sh`'s stderr with the prefix `[error] unexpected exit <N> from <subscript-name>`. Do not attempt to continue past an unknown exit.
- **No rollback invariant**: if bookkeeping (BK-5) commits and pushes successfully but a later step fails (merge, checkout, fetch, pull), `finalize.sh` does **not** attempt to revert the bookkeeping commit. The bookkeeping push is durable; re-invocation after the user resolves the downstream issue relies on the idempotency check (FR-4) to skip bookkeeping and re-attempt only the remaining execution steps.
- `git fetch`/`git pull` failures after a successful merge + checkout are reported as warnings, not errors (the merge already succeeded and the user is already on `main`).

### FR-2: `preflight-checks.sh` — Pre-Flight (Clean Tree + Branch + PR State + Mergeable)
- Execute Pre-flight checks 1–3 from the current SKILL.md in parallel where possible:
  1. `git status --porcelain` empty.
  2. `git branch --show-current` is neither `main` nor `master`.
  3. `gh pr view --json number,title,state,mergeable` returns a PR in `OPEN` state that is `MERGEABLE` (or `UNKNOWN` — GitHub occasionally reports `UNKNOWN` for fresh PRs; treat as retry-once-then-accept).
- Emit JSON on stdout: `{"status": "ok" | "abort", "reason"?: "...", "prNumber"?: N, "prTitle"?: "...", "prUrl"?: "..."}`.
- Exit `0` on ok; exit `1` on abort. Stderr carries the same reason string for human readers.
- Abort reasons follow the existing Error Handling table verbatim (dirty working directory, already on main, no PR, PR not open, PR not mergeable) so downstream error messages are unchanged.

### FR-3: `branch-id-parse.sh` — Fourth Classification (Release Branches)
- **Extend** the existing plugin-shared `branch-id-parse.sh` (item 10.3, already merged) with a fourth classification:
  - Regex: `^release/[a-z0-9-]+-v[0-9]+\.[0-9]+\.[0-9]+$`
  - Emit `{"id": null, "type": "release", "dir": null}` on stdout; exit `0`.
- Preserve all three existing classifications (`feat/`, `chore/`, `fix/`) and their emitted JSON shapes unchanged.
- Exit `0` on any of the four matches; exit `1` on no match (truly unrecognized — preserves existing caller contract); exit `2` on missing arg.
- The distinction between exit `0` with `type == "release"` and exit `1` is load-bearing: callers must silently skip bookkeeping on `release` but emit the `[info]` message on exit `1`.

### FR-4: `check-idempotent.sh` — BK-3 Three-Condition Check
- Signature: `check-idempotent.sh <doc-path> <prNumber>`.
- Implement all three conditions from SKILL.md BK-3 with the existing robustness rules (line-ending agnostic, fenced-code-block aware):
  1. `## Acceptance Criteria` section absent, or present with zero unticked `- [ ]` lines outside fenced blocks.
  2. `## Completion` section exists containing `` **Status:** `Complete` `` or `` **Status:** `Completed` ``.
  3. `**Pull Request:**` line within `## Completion` contains `[#N]` or `/pull/N` matching the passed `<prNumber>`.
- Exit `0` when all three conditions hold (idempotent — skip BK-4 and BK-5 silently).
- Exit `1` when any condition fails (proceed to BK-4).
- Exit `2` on missing/invalid args.
- **Stdout contract**: none on exit `0` (silent-pass is the expected happy path).
- **Stderr contract**: on exit `1`, emit exactly one line identifying the failing condition in the form `[info] idempotent check failed: <condition-label>` where `<condition-label>` is one of `acceptance-criteria-unticked`, `completion-section-missing`, or `pr-line-mismatch`. `finalize.sh` does not display this to the user but uses the label to shape its end-of-run "Bookkeeping: ..." summary line.

### FR-5: `completion-upsert.sh` — BK-4.2 (Completion Section Upsert)
- Signature: `completion-upsert.sh <doc-path> <prNumber> <prUrl>`.
- If `## Completion` section exists: replace its body in place (heading preserved; Status, Completed, and Pull Request lines fully replaced).
- If absent: append the block at end of doc, preceded by a blank line.
- Block content:
  ```
  ## Completion

  **Status:** `Complete`

  **Completed:** YYYY-MM-DD

  **Pull Request:** [#N](<prUrl>)
  ```
- Date source: `date -u +%Y-%m-%d`.
- Fence-aware: a literal `## Completion` inside a fenced code block is NOT treated as a section marker.
- Line-ending agnostic: preserve CRLF/LF as authored.
- Exit `0` on success; exit `1` on file I/O failure; exit `2` on missing args.
- **Stdout contract**: on exit `0`, emit a single-word token on stdout — either `upserted` (existing section replaced) or `appended` (section freshly added). `finalize.sh` consumes this token for its summary line. No stdout on non-zero exit.
- **Stderr contract**: non-zero exit emits a one-line `[error] completion-upsert: <reason>` diagnostic.

### FR-6: `reconcile-affected-files.sh` — BK-4.3 (Affected Files Reconciliation)
- Signature: `reconcile-affected-files.sh <doc-path> <prNumber>`.
- Fetch PR files via `gh pr view <prNumber> --json files --jq '.[].path'` (sorted).
- If the doc has no `## Affected Files` section: skip silently, exit `0`. This matches current skill behavior.
- If present:
  - Files in PR but not in doc → append as `` - `path` `` bullets within the section.
  - Files in doc not in PR → append ` (planned but not modified)` to the bullet (idempotent — skip if already annotated).
  - Files in both → leave unchanged.
- Fence-aware: bullets inside fenced blocks (illustrative examples) are not modified.
- Exit `0` on success (including the "no section" skip); exit `1` on `gh` failure (log warning on stderr, skip the sub-step — `finalize.sh` treats exit `1` here as a non-fatal warning and proceeds to BK-5).
- Exit `2` on missing args.
- **Stdout contract**: on exit `0`, emit a single line `<appended-count> <annotated-count>` (two integers, space-separated). Counts are `0 0` on "no section" skip and for fully-reconciled docs; non-zero values drive the `finalize.sh` summary line. No stdout on non-zero exit.
- **Stderr contract**: exit `1` emits `[warn] reconcile-affected-files: gh failure — <gh-stderr-first-line>` and no other output.

### FR-7: Bookkeeping Skip Behavior
- When `branch-id-parse.sh` exits `0` with `type == "release"`: skip the remaining BK-2..BK-5 sequence silently. No `[info]` or `[warn]` message. Proceed directly to Execution. Rationale: release branches have no requirement doc and the `releasing-plugins` skill (installed from a separate marketplace — it does **not** live in this repo) already writes its own changelog as part of the release flow.
- When `branch-id-parse.sh` exits `1` (unrecognized): emit the existing info-level message `[info] Branch <name> does not match workflow ID pattern; skipping bookkeeping.` on stderr and proceed to Execution. Preserves current behavior for ad-hoc branches.
- When exit `0` with `type` in `{"feature", "chore", "bug"}`: resolve the requirement doc via `resolve-requirement-doc.sh` and run the full BK-2..BK-5 sequence (BK-1 is the branch-id-parse step itself, already completed).
- **BK-4.1 checkbox strategy**: the new `finalize.sh` always uses `checkbox-flip-all.sh` against `## Acceptance Criteria`. The pre-existing single-checkbox fallback documented in the current SKILL.md (the `check-acceptance.sh <doc> <matcher>` form, used when only one criterion needs flipping) is intentionally **dropped** from the `finalize.sh` flow — the whole-section flip is idempotent and covers both the single-criterion and all-criteria cases. `check-acceptance.sh` remains shipped for other callers (`executing-chores`, `executing-bug-fixes`, `implementing-plan-phases`) but is not invoked by `finalize.sh`.

### FR-8: BK-5 Commit and Push (Unchanged Behavior, Moved into `finalize.sh`)
- When bookkeeping produced changes (BK-4.1 checkoff, BK-4.2 completion upsert, and/or BK-4.3 affected-files reconcile):
  - Stage only the requirement doc: `git add <resolved-doc-path>`.
  - Commit with the canonical message:
    ```
    chore(<ID>): finalize requirement document

    - Tick completed acceptance criteria
    - Set completion status with PR link
    - Reconcile affected files against PR diff
    ```
  - `git push` (no amend, no force).
- If `git status --porcelain` reports no changes after bookkeeping: skip commit and push; proceed to Execution.
- Push failure: stop with exit `1` before attempting merge. Matches existing Error Handling row.
- Preserve the existing "stop and report — do not auto-configure" behavior when `git config user.name`/`user.email` is unset.

### FR-9: Execution Sequence (Unchanged, Moved into `finalize.sh`)
- After bookkeeping (or skip), run:
  1. `gh pr merge --merge --delete-branch` — no force, no bypass of required checks.
  2. `git checkout main`.
  3. `git fetch origin`.
  4. `git pull`.
- Merge failure: exit `1` with the error on stderr. Do not retry.
- Checkout failure after successful merge: exit `1` but note in stderr that the merge already succeeded.
- Fetch or pull failure after successful merge + checkout: exit `0` with a warning on stderr (non-fatal — user is already back on `main`).

### FR-10: SKILL.md Prose Collapse
- Rewrite `plugins/lwndev-sdlc/skills/finalizing-workflow/SKILL.md` to contain only:
  - Frontmatter (name, description, allowed-tools — add `Bash` retained, prune unused `Edit`/`Glob` if truly unused after collapse).
  - "When to use" section (preserved from current SKILL.md).
  - "Workflow Position" diagram (preserved).
  - A short Usage section: capture branch name → ask single confirmation → run `finalize.sh` → report stdout verbatim to user.
  - Relationship to other skills table (preserved).
- Remove: the Pre-Flight Checks subsections, Pre-Merge Bookkeeping (BK-1..BK-5) subsections, Execution subsections, and the per-step Error Handling table (the script's stderr output is now the user-facing error surface).

### FR-11: Release Branch Support End-to-End
- `finalize.sh` on a `release/<plugin-name>-vX.Y.Z` branch must: complete successfully, skip bookkeeping silently, merge the PR, delete the branch, return to a clean `main`, and emit **no** unrecognized-pattern message.
- All four branch classifications must round-trip correctly with JSON values `{"type": "feature"}`, `{"type": "chore"}`, `{"type": "bug"}`, and `{"type": "release"}` for branch-prefix patterns `feat/FEAT-NNN-*`, `chore/CHORE-NNN-*`, `fix/BUG-NNN-*`, and `release/<plugin>-vX.Y.Z` respectively. Quoted string values are the canonical representation emitted by `branch-id-parse.sh`; any place this doc compares against them (FR-1 step 3, FR-3, FR-7, edge cases) uses the double-quoted form.
- A fifth, non-matching branch (e.g., `adhoc/cleanup`) must still emit the existing `[info]` message and proceed to merge.

## Output Format

### `finalize.sh` success (bookkeeping ran)
```
Merged PR #142 — feat(FEAT-022): finalize.sh + subscripts
Bookkeeping: ticked 3 acceptance criteria, wrote Completion section, reconciled 2 affected files
Pushed bookkeeping commit as <sha-short>
On main, up to date
```

### `finalize.sh` success (release branch, bookkeeping skipped)
```
Merged PR #143 — release(lwndev-sdlc): v1.16.0
Bookkeeping: skipped (release branch)
On main, up to date
```

### `finalize.sh` success (idempotent skip)
```
Merged PR #144 — chore(CHORE-040): flake cleanup
Bookkeeping: skipped (requirement doc already finalized)
On main, up to date
```

### `finalize.sh` failure (pre-flight abort)
Stderr:
```
[error] Pre-flight failed: working directory has uncommitted changes. Commit or stash before finalizing.
```
Exit `1`.

## Non-Functional Requirements

### NFR-1: Performance
- `finalize.sh` end-to-end (excluding the merge wait itself) must complete in under 5 seconds on a typical workflow branch. Current prose path runs in ~30–60 seconds of LLM-driven tool calls.
- Parallelize the three independent pre-flight checks inside `preflight-checks.sh` (clean tree + branch + PR view) where the shell permits.

### NFR-2: Error Handling
- Every subscript must emit a single-line, actionable stderr message on failure naming the failed step and reason.
- `finalize.sh` must surface subscript stderr verbatim — no swallowing.
- Graceful degradation for `gh` failures inside `reconcile-affected-files.sh` (FR-6) — warn and skip the sub-step rather than abort the whole finalize.
- `gh` unavailable or unauthenticated before the merge step is a fatal error (exit `1`) — the merge cannot happen without it, so surface clearly rather than skip.

### NFR-3: Idempotency
- Re-running `finalize.sh` on the same branch after a successful first run must: detect the merge-completed state (branch already deleted, or PR state `MERGED`) and exit with a clear message rather than error out on `gh pr merge`.
- `check-idempotent.sh` must return exit `0` (skip bookkeeping) when the three conditions hold, regardless of whether it was the first or Nth invocation.
- `completion-upsert.sh` must replace an existing `## Completion` block in place — two successive runs produce the same content (modulo date if run across midnight UTC).

### NFR-4: Line-Ending and Fence-Block Robustness
- Inherit the robustness rules documented in the current SKILL.md BK-4 section: CRLF-agnostic section detection, fence-aware scanning in `check-idempotent.sh`, `completion-upsert.sh`, and `reconcile-affected-files.sh`. Any example markdown (triple-backtick fenced) must not be mistaken for real section headings or bullets.

### NFR-5: Test Coverage
- Each new script ships a bats (or equivalent) fixture covering: happy path, missing-arg exit, malformed-arg exit, idempotent re-run, and the specific edge case the script exists to handle (release branch for `branch-id-parse.sh`, `## Affected Files` absent for `reconcile-affected-files.sh`, etc.).
- `finalize.sh` integration test must exercise all four branch-pattern paths on fixture repos.

### NFR-6: Backward Compatibility
- The new scripts must be drop-in for existing orchestrator call sites — no orchestrator changes required beyond the SKILL.md collapse documented in FR-10.
- `branch-id-parse.sh` callers other than `finalize.sh` (e.g., orchestrator resume detection in `orchestrating-workflows`) must observe zero behavior change for the three existing classifications.

## Dependencies

- Plugin-shared scripts library:
  - `branch-id-parse.sh` (extended by this feature — FR-3)
  - `checkbox-flip-all.sh` (already shipped; invoked by `finalize.sh` for BK-4.1)
  - `resolve-requirement-doc.sh` (already shipped; invoked by `finalize.sh` for BK-2)
- `gh` CLI (available and authenticated) — required for `preflight-checks.sh`, `reconcile-affected-files.sh`, and the merge step in `finalize.sh`.
- `git` — required for status/checkout/fetch/pull and the BK-5 commit+push path.
- No Node or TypeScript dependency — shell-only, consistent with the `plugins/lwndev-sdlc/scripts/` convention.

## Edge Cases

1. **Release branch (`release/lwndev-sdlc-v1.15.3`)**: classified as `type == "release"` with exit `0`; bookkeeping skipped silently; merge + checkout + fetch + pull run normally.
2. **Ad-hoc branch (`adhoc/cleanup`)**: `branch-id-parse.sh` exits `1`; `finalize.sh` emits the existing `[info]` message and proceeds to merge. No bookkeeping attempted.
3. **`## Affected Files` section missing**: `reconcile-affected-files.sh` exits `0` silently; `finalize.sh` proceeds to BK-5 without that sub-step's output.
4. **Multiple requirement docs matching the ID (`resolve-requirement-doc.sh` exit `2`)**: BK-1 aborts with the existing error-level "workspace inconsistency" warning; `finalize.sh` skips remaining bookkeeping and proceeds to Execution — matches current behavior.
5. **PR in `UNKNOWN` mergeable state**: `preflight-checks.sh` retries once after a brief pause (GitHub often resolves within 1–2 seconds on fresh PRs). If still `UNKNOWN` after the retry, treat as mergeable (current behavior matches real user expectation) but log a stderr note.
6. **Fenced code block containing literal `## Completion`**: `check-idempotent.sh` and `completion-upsert.sh` must skip over fenced content — a doc that documents the Completion format in an example code block must not be mistaken for a completed doc.
7. **CRLF line endings**: All three BK-processing subscripts (`check-idempotent.sh`, `completion-upsert.sh`, `reconcile-affected-files.sh`) detect and preserve line endings. Round-trip a CRLF doc without converting to LF.
8. **`git push` rejected (remote has new commits on branch)**: BK-5 exits `1`; `finalize.sh` does not proceed to merge. User must pull/rebase and re-invoke. Matches current behavior.
9. **`gh pr merge` fails after successful bookkeeping push**: `finalize.sh` exits `1`. The bookkeeping commit is already pushed — this is acceptable; re-invoking after fixing the merge issue will skip bookkeeping via the idempotency check.
10. **Branch name matches the release regex but with extra path segments (`release/foo/bar-v1.0.0`)**: The `^release/[a-z0-9-]+-v\d+\.\d+\.\d+$` regex explicitly disallows nested slashes in the name segment — such a branch exits `1` as unrecognized, falling into the ad-hoc branch path. Intentional.
11. **Idempotent second run after full success**: the first run deletes the remote branch via `--delete-branch`; the second run on the same now-nonexistent branch fails pre-flight check 2 (or `gh pr view` returns no PR). Clear error message, exit `1`.

## Testing Requirements

### Unit Tests
- **`preflight-checks.sh`** — fixtures for: clean tree + open PR + mergeable (happy path), dirty tree, on main, no PR, PR closed, PR draft, PR `UNKNOWN` then `MERGEABLE`, PR `CONFLICTING`. Assert JSON shape and exit codes.
- **`branch-id-parse.sh` release classification** — fixtures for: `release/lwndev-sdlc-v1.16.0`, `release/foo-bar-v0.1.2`, `release/x-v10.20.30` (happy path); `release/foo` (no version → exit 1); `release/foo-v1.2` (incomplete version → exit 1); `release/foo/bar-v1.0.0` (nested → exit 1); existing `feat/FEAT-001-x`, `chore/CHORE-001-x`, `fix/BUG-001-x` must still exit `0` with the correct `type`. Preserve existing test cases unchanged.
- **`check-idempotent.sh`** — fixtures for: all three conditions hold (exit 0), acceptance criteria has un-ticked boxes (exit 1 naming condition 1), completion section missing (exit 1 naming condition 2), completion section present but PR number mismatch (exit 1 naming condition 3), CRLF doc, fenced `## Completion` in example code block.
- **`completion-upsert.sh`** — fixtures for: no existing section (append), existing section (replace in place), existing section with CRLF, fenced `## Completion` example (leave untouched).
- **`reconcile-affected-files.sh`** — fixtures for: no `## Affected Files` section (skip), all files present (no-op), files in PR missing from doc (append), files in doc not in PR (annotate `(planned but not modified)`), annotation already present (idempotent skip), fenced example `- \`path\`` bullet (leave untouched), `gh` failure (exit 1 with warning).

### Integration Tests
- **`finalize.sh` on `feat/FEAT-NNN-*`** — full BK-1..BK-5 path on a realistic fixture with a matching requirement doc, passing PR, and unticked acceptance criteria. Assert: bookkeeping commit pushed, PR merged, branch deleted, on `main` with clean tree.
- **`finalize.sh` on `chore/CHORE-NNN-*`** — same as above with a chore fixture.
- **`finalize.sh` on `fix/BUG-NNN-*`** — same as above with a bug fixture.
- **`finalize.sh` on `release/<plugin>-vX.Y.Z`** — no bookkeeping, merge + reset only. Assert: stderr carries no `[info]` or `[warn]` messages about branch pattern.
- **`finalize.sh` on `adhoc/cleanup`** — `[info]` message emitted, merge proceeds, no bookkeeping.
- **`finalize.sh` idempotency** — two successive runs on the same fixture: first produces the full bookkeeping commit; second (after the first fails mid-execution before merge) skips bookkeeping silently via the idempotency check.

### Manual Testing
- Run `finalize.sh` end-to-end against a real local branch with a real PR (use a disposable test PR).
- Verify the SKILL.md collapse does not regress orchestrator behavior — run a full `orchestrating-workflows` feature chain to completion with the new SKILL.md in place.
- Verify release-branch support by creating a `release/lwndev-sdlc-v9.99.0` (or similar unused-but-valid-version) branch with a minimal release PR and running `finalize.sh` against it. The branch name must match the FR-3 regex `^release/[a-z0-9-]+-v[0-9]+\.[0-9]+\.[0-9]+$` exactly — a `-test` or other suffix would make it fall through to the ad-hoc-branch `[info]` path, which is the opposite of what we want to verify.

## Acceptance Criteria

- [x] `finalize.sh` exists at `plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/finalize.sh`, is executable, and runs the full pre-flight → bookkeeping (when applicable) → execution sequence in a single invocation.
- [x] `preflight-checks.sh`, `check-idempotent.sh`, `completion-upsert.sh`, `reconcile-affected-files.sh` all exist under `plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/`, are executable, accept the arguments documented in FR-2/FR-4/FR-5/FR-6, and exit with the documented codes.
- [x] `branch-id-parse.sh` at `plugins/lwndev-sdlc/scripts/branch-id-parse.sh` gains the fourth classification (FR-3) and returns `{"id": null, "type": "release", "dir": null}` exit `0` on `release/<plugin>-vX.Y.Z` patterns.
- [x] `branch-id-parse.sh` preserves identical behavior for `feat/`, `chore/`, `fix/`, and truly unrecognized branches — no regression in existing callers.
- [x] `finalize.sh` on `feat/FEAT-123-foo`, `chore/CHORE-456-bar`, `fix/BUG-789-baz` performs full BK-1..BK-5 bookkeeping and merges.
- [x] `finalize.sh` on `release/lwndev-sdlc-v1.16.0` merges, resets to clean `main`, and emits **no** unrecognized-pattern message (`[info]`, `[warn]`, or otherwise) about the branch.
- [x] `finalize.sh` on a branch matching none of the four patterns emits the existing `[info] Branch <name> does not match workflow ID pattern; skipping bookkeeping.` message and proceeds to merge.
- [x] SKILL.md at `plugins/lwndev-sdlc/skills/finalizing-workflow/SKILL.md` is rewritten to: confirm with user → run `finalize.sh` → report. Pre-flight, BK-1..BK-5, and Execution prose sections are removed.
- [x] Every new script ships with a bats (or equivalent) test fixture covering happy path, missing-arg exit, and the specific edge case it targets.
- [x] Running a full feature, chore, and bug workflow through `orchestrating-workflows` end-to-end produces the same observable behavior as before the refactor (apart from wall-clock and token savings).
- [x] Token savings measured on a fresh workflow run are captured and reported in the PR description. The #179 audit estimate is 1,500–2,500 tokens; the acceptance bar for this feature is "measurable reduction in orchestrator-context tokens vs the prose path" — a floor is not required to pass, but a regression (i.e., the new path uses *more* tokens than the old) fails the AC.
- [x] Wall-clock for the finalize step on a typical workflow drops measurably vs the current prose path. The #179 audit estimate is 30–60 seconds saved; the acceptance bar is "measurable reduction", not a fixed floor. Target: under 5 seconds end-to-end (excluding GitHub's own merge latency).

## Completion

**Status:** `Complete`

**Completed:** 2026-04-21

**Pull Request:** [#207](https://github.com/lwndev/lwndev-marketplace/pull/207)

## Future Enhancements

- **`finalize.sh --dry-run`** — print the bookkeeping diff and merge command without executing. Not in scope; file as follow-up if real demand surfaces.
- **Pre-merge slash-command shortcut** — extend `releasing-plugins` to call `finalize.sh` directly at release time. Out of scope per #182; tracked separately.
- **Script consolidation with `executing-qa`'s commit helpers** — potential future convergence on a single `commit-and-push-with-message.sh` across skills. Not in scope.
