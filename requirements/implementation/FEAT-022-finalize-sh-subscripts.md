# Implementation Plan: `finalize.sh` + Subscripts (finalizing-workflow Full Rewrite)

## Overview

Collapse the `finalizing-workflow` skill from a multi-step prose ceremony (pre-flight + BK-1..BK-5 + execution) into a single confirmation prompt followed by one top-level script invocation. The work ships a top-level orchestrator (`finalize.sh`) plus four new leaf subscripts (`preflight-checks.sh`, `check-idempotent.sh`, `completion-upsert.sh`, `reconcile-affected-files.sh`) under `plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/`, extends the plugin-shared `branch-id-parse.sh` with a fourth `release/` classification, and rewrites `SKILL.md` to confirm → run `finalize.sh` → report.

The plan sequences the refactor as six phases. Phase 1 extends `branch-id-parse.sh` in isolation (no other callers change, lowest blast radius). Phases 2–3 ship the four leaf subscripts in two related pairs — each subscript lands with its bats fixture in the same phase. Phase 4 composes the top-level `finalize.sh` once all its dependencies exist. Phase 5 collapses the `SKILL.md` prose and wires the whole thing into the orchestrator. Phase 6 runs the end-to-end integration suite across all four branch-pattern paths plus the ad-hoc and idempotent-re-run cases.

## Features Summary

| Feature ID | GitHub Issue | Feature Document | Priority | Complexity | Status |
|------------|--------------|------------------|----------|------------|--------|
| FEAT-022 | [#182](https://github.com/lwndev/lwndev-marketplace/issues/182) | [FEAT-022-finalize-sh-subscripts-full.md](../features/FEAT-022-finalize-sh-subscripts-full.md) | High | High | Pending |

## Recommended Build Sequence

### Phase 1: `branch-id-parse.sh` Release Classification (FR-3)

**Feature:** [FEAT-022](../features/FEAT-022-finalize-sh-subscripts-full.md) | [#182](https://github.com/lwndev/lwndev-marketplace/issues/182)
**Status:** ✅ Complete

#### Rationale

The plugin-shared `branch-id-parse.sh` gains a fourth classification (`release/<plugin>-vX.Y.Z`). This change is entirely independent of the four new skill-scoped subscripts — no new script depends on this extension landing first, and no existing callers (e.g., `orchestrating-workflows`) care about the new classification (per FR-3 / NFR-6 they must see zero behavior change for the three existing `feat/`/`chore/`/`fix/` patterns). Landing this in isolation keeps the diff small, easy to review, and preserves backward compatibility as a first, provable invariant before any of the new downstream machinery arrives. Test surface is mechanical: extend the existing `branch-id-parse.bats` fixture with release-branch happy paths and malformed-version cases, and update the one existing "release branch: exit 1" case — which currently asserts the old (no-match) behavior — to the new `type == "release"` happy path.

#### Implementation Steps

1. Add a fourth regex branch to `plugins/lwndev-sdlc/scripts/branch-id-parse.sh`: `^release/[a-z0-9-]+-v[0-9]+\.[0-9]+\.[0-9]+$`.
2. On match, set `id=null`, `type=release`, `dir=null` and emit JSON `{"id": null, "type": "release", "dir": null}` with literal JSON `null` (not the string `"null"`) via both the `jq` path and the hand-assembled fallback. The existing three classifications remain unchanged in shape and behavior.
3. Preserve exit codes: `0` on any of the four matches, `1` on no match (nested-path releases like `release/foo/bar-v1.0.0` land here per edge case 10), `2` on missing arg.
4. Update the script's top-of-file comment block to document the fourth pattern and the `null`-valued `id`/`dir` for the release case.
5. Update `plugins/lwndev-sdlc/scripts/tests/branch-id-parse.bats`:
   - Replace the existing `@test "release branch: exit 1"` case with a happy-path assertion: `release/lwndev-sdlc-v1.16.0` → exit `0`, `type":"release"`, `id":null`, `dir":null`.
   - Add release-branch happy paths for `release/foo-bar-v0.1.2` and `release/x-v10.20.30` (multi-digit version segments).
   - Add negative cases: `release/foo` (no version → exit 1), `release/foo-v1.2` (incomplete version → exit 1), `release/foo/bar-v1.0.0` (nested path → exit 1).
   - Re-run all existing `feat/`, `chore/`, `fix/` happy-path and malformed cases unchanged — explicit regression guard for NFR-6.
6. Verify `jq` and hand-assembled fallback paths produce identical JSON shape for the release case (both emit literal `null`, not `"null"`).

#### Deliverables

- [x] `plugins/lwndev-sdlc/scripts/branch-id-parse.sh` — release classification added, three existing classifications unchanged
- [x] `plugins/lwndev-sdlc/scripts/tests/branch-id-parse.bats` — release happy paths and malformed-version cases added, existing "release → exit 1" case flipped to happy-path, existing `feat/`/`chore/`/`fix/` cases preserved verbatim

---

### Phase 2: `preflight-checks.sh` + `check-idempotent.sh` (FR-2, FR-4)

**Feature:** [FEAT-022](../features/FEAT-022-finalize-sh-subscripts-full.md) | [#182](https://github.com/lwndev/lwndev-marketplace/issues/182)
**Status:** ✅ Complete

#### Rationale

These two subscripts form the "inspection" pair: both read state (git status, branch, PR, or requirement doc) and decide whether to abort or continue, without mutating anything. Grouping them in one phase keeps the review tight around "read-only decision logic" and lets them share a common testing pattern (fixture repo + fixture doc + assert exit code and JSON/stderr shape) before the mutating subscripts arrive in Phase 3. Neither depends on the other nor on Phase 3/4 work. `preflight-checks.sh` also introduces the JSON-on-stdout output convention that `finalize.sh` consumes in Phase 4.

#### Implementation Steps

1. Create `plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/` (new directory) and a sibling `scripts/tests/` subdirectory for bats fixtures.
2. Write `plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/preflight-checks.sh`:
   - `set -euo pipefail`; shebang `#!/usr/bin/env bash`.
   - Run the three pre-flight checks from current SKILL.md: `git status --porcelain` empty, `git branch --show-current` neither `main` nor `master`, `gh pr view --json number,title,state,mergeable,url` returns an `OPEN` and `MERGEABLE`-or-`UNKNOWN` PR.
   - Parallelize the three checks where the shell permits (background `&` + `wait`, capturing exit and stdout per child via tempfiles).
   - Implement the `UNKNOWN → retry-once → accept-if-still-unknown` behavior per edge case 5 (brief `sleep 2` between retries; log the retry to stderr).
   - On success emit JSON on stdout: `{"status": "ok", "prNumber": N, "prTitle": "...", "prUrl": "..."}`, exit `0`.
   - On any abort emit JSON: `{"status": "abort", "reason": "<verbatim existing Error Handling row text>"}` on stdout AND the same reason on stderr, exit `1`.
   - Stderr reasons must match the current SKILL.md Error Handling table verbatim (dirty tree, on main, no PR, PR not open, PR not mergeable) so downstream consumers see unchanged text.
   - `chmod +x`.
3. Write `plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/check-idempotent.sh`:
   - Signature: `check-idempotent.sh <doc-path> <prNumber>`.
   - Implement the three BK-3 conditions with the fence-aware and CRLF-agnostic rules inherited from BK-4 (same scan logic used by `checkbox-flip-all.sh` — re-use the helper pattern; do not reimplement fence tracking inline if a shared helper can be extracted, but for this phase keep the helper local to the script and revisit extraction only if Phase 3 duplicates it).
   - Exit `0` when all three conditions hold (no stdout — silent-pass is the happy path).
   - Exit `1` when any condition fails; stderr must contain exactly one line `[info] idempotent check failed: <condition-label>` where `<condition-label>` is `acceptance-criteria-unticked`, `completion-section-missing`, or `pr-line-mismatch`. No stdout on exit `1`.
   - Exit `2` on missing/invalid args; `[error]`-prefixed stderr.
   - `chmod +x`.
4. Write `plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/tests/preflight-checks.bats`:
   - Happy path: clean tree, feature branch, open+mergeable PR → exit `0`, JSON `{"status":"ok", ...}`.
   - Dirty tree → exit `1`, reason `working directory has uncommitted changes`.
   - On `main` → exit `1`, reason `already on main`.
   - No PR → exit `1`, reason `no PR for current branch`.
   - PR closed → exit `1`, reason `PR not open`.
   - PR draft → exit `1`, reason `PR not open` (or the verbatim existing row text).
   - PR `CONFLICTING` → exit `1`, reason `PR not mergeable`.
   - PR `UNKNOWN` resolves to `MERGEABLE` on retry → exit `0`.
   - PR `UNKNOWN` still unknown after retry → exit `0` with stderr note (per edge case 5).
   - Missing arg: N/A (script takes none) — verify extra args exit `2` or are ignored per convention chosen.
   - Fixtures stub `git` and `gh` via PATH shadowing (see existing `resolve-requirement-doc.bats` for the stub pattern).
5. Write `plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/tests/check-idempotent.bats`:
   - All three conditions hold → exit `0`, no stdout.
   - Condition 1 fails (unticked `- [ ]` present) → exit `1`, stderr `[info] idempotent check failed: acceptance-criteria-unticked`.
   - Condition 2 fails (no `## Completion`) → exit `1`, stderr label `completion-section-missing`.
   - Condition 3 fails (`**Pull Request:** [#999]` but passed `--prNumber 142`) → exit `1`, stderr label `pr-line-mismatch`.
   - CRLF-ending doc with all three conditions true → exit `0`.
   - Fenced `## Completion` in example code block (real doc has no real completion) → condition 2 correctly flagged as missing → exit `1` with label `completion-section-missing`.
   - Fenced unticked `- [ ]` (example-only) is NOT counted → exit `0` when the real section has no unticked items.
   - Missing arg → exit `2`.
   - Malformed arg (non-existent doc path) → exit `2`.

#### Deliverables

- [x] `plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/preflight-checks.sh`
- [x] `plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/check-idempotent.sh`
- [x] `plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/tests/preflight-checks.bats`
- [x] `plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/tests/check-idempotent.bats`

---

### Phase 3: `completion-upsert.sh` + `reconcile-affected-files.sh` (FR-5, FR-6)

**Feature:** [FEAT-022](../features/FEAT-022-finalize-sh-subscripts-full.md) | [#182](https://github.com/lwndev/lwndev-marketplace/issues/182)
**Status:** ✅ Complete

#### Rationale

These two are the "mutating" BK-4.2 and BK-4.3 sub-steps — both edit the requirement doc in place, both must preserve CRLF line endings, and both must skip over fenced code blocks. Grouping them in one phase lets them share the same fixture-doc fixtures (CRLF variant, fence-example variant) and the same line-ending-preservation helper pattern. Neither depends on the other; both depend only on `check-idempotent.sh`-style read logic (which is already in place from Phase 2) and can be developed in parallel within the phase. The `stdout` summary tokens (`upserted`/`appended` for `completion-upsert.sh`; `<appended-count> <annotated-count>` for `reconcile-affected-files.sh`) are load-bearing for `finalize.sh`'s final report in Phase 4, so their exact shapes must be locked in at this phase.

#### Implementation Steps

1. Write `plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/completion-upsert.sh`:
   - Signature: `completion-upsert.sh <doc-path> <prNumber> <prUrl>`.
   - Detect line-ending (LF vs CRLF) on read; preserve on write.
   - Fence-aware `## Completion` detection (skip over fenced blocks).
   - If section exists: replace its body in place (heading line preserved; subsequent Status/Completed/Pull-Request lines fully overwritten; stop at the next `## ` heading or EOF).
   - If absent: append the block preceded by a blank line.
   - Block body per FR-5: Status, Completed (date via `date -u +%Y-%m-%d`), Pull Request with passed `<prNumber>` and `<prUrl>`.
   - Exit `0` on success; stdout exactly one token: `upserted` (section existed) or `appended` (section freshly added).
   - Exit `1` on file I/O failure with stderr `[error] completion-upsert: <reason>`. No stdout.
   - Exit `2` on missing args.
   - `chmod +x`.
2. Write `plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/reconcile-affected-files.sh`:
   - Signature: `reconcile-affected-files.sh <doc-path> <prNumber>`.
   - Fetch PR files via `gh pr view <prNumber> --json files --jq '.files[].path' | sort`.
   - If no `## Affected Files` section: exit `0`, stdout `0 0`, no stderr (matches current skill behavior).
   - Fence-aware section-body scan (skip fenced example bullets per edge case — illustrative `- \`path\`` inside fences must not be treated as real bullets).
   - Reconcile: append new PR-only files as `` - `path` `` bullets; annotate doc-only files with ` (planned but not modified)` (idempotent — skip if annotation already present); leave both-sides files untouched.
   - Exit `0` on success; stdout `<appended-count> <annotated-count>` (two space-separated integers, `0 0` for a fully-reconciled or no-section doc).
   - Exit `1` on `gh` failure; stderr `[warn] reconcile-affected-files: gh failure — <gh-stderr-first-line>`. No stdout. `finalize.sh` treats this as non-fatal in Phase 4.
   - Exit `2` on missing args.
   - Preserve line endings (CRLF/LF) as authored.
   - `chmod +x`.
3. Write `plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/tests/completion-upsert.bats`:
   - No existing section → append → exit `0`, stdout `appended`, block appears at end with blank-line separator.
   - Existing section → replace in place → exit `0`, stdout `upserted`, heading preserved, Status/Completed/Pull Request lines rewritten.
   - Existing section with CRLF endings → replace in place, CRLF preserved.
   - Fenced `## Completion` example in doc body → treated as no real section → append (not replace), stdout `appended`, fenced example untouched.
   - Two successive runs on same doc → same content both times (modulo date across midnight UTC) → second run emits `upserted` with no net diff.
   - File I/O failure (read-only doc) → exit `1`, stderr `[error] completion-upsert:`.
   - Missing arg (< 3 args) → exit `2`.
4. Write `plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/tests/reconcile-affected-files.bats`:
   - No `## Affected Files` section → exit `0`, stdout `0 0`, doc unchanged.
   - All files present in both PR and doc → exit `0`, stdout `0 0`, doc unchanged.
   - Files in PR missing from doc (2 new) → exit `0`, stdout `2 0`, bullets appended.
   - Files in doc missing from PR (1 orphan) → exit `0`, stdout `0 1`, annotation appended.
   - Mixed (1 appended, 2 annotated) → exit `0`, stdout `1 2`.
   - Annotation already present → idempotent skip → exit `0`, stdout `0 0`.
   - Fenced example `- \`path\`` bullet inside code fence → left untouched; reconciliation only runs on real bullets.
   - CRLF doc → line endings preserved after edits.
   - `gh` failure (stub returning non-zero) → exit `1`, stderr `[warn] reconcile-affected-files: gh failure — …`, no stdout.
   - Missing args → exit `2`.

#### Deliverables

- [x] `plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/completion-upsert.sh`
- [x] `plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/reconcile-affected-files.sh`
- [x] `plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/tests/completion-upsert.bats`
- [x] `plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/tests/reconcile-affected-files.bats`

---

### Phase 4: `finalize.sh` Top-Level Orchestrator (FR-1, FR-7, FR-8, FR-9)

**Feature:** [FEAT-022](../features/FEAT-022-finalize-sh-subscripts-full.md) | [#182](https://github.com/lwndev/lwndev-marketplace/issues/182)
**Status:** Pending

#### Rationale

`finalize.sh` is the composition layer — it can only be built once all four leaf subscripts (Phases 2–3) and the extended `branch-id-parse.sh` (Phase 1) exist, since its job is to call them in sequence, interpret their exit codes, branch on the classification result (FR-7), wire together the bookkeeping commit-and-push (FR-8), and drive the execution sequence (FR-9). It also owns the final human-readable multi-line report. Landing it in its own phase lets the review focus on composition logic (exit-code translation, branch classification dispatch, no-rollback invariant, end-of-run summary assembly) without being mixed with the leaf-script contracts. SKILL.md remains unchanged at the end of this phase — the old prose still drives the skill — so the new `finalize.sh` is exercisable from the command line (and by the Phase 6 integration tests) but not yet the default path.

#### Implementation Steps

1. Write `plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/finalize.sh`:
   - `set -euo pipefail`; shebang `#!/usr/bin/env bash`.
   - Accept `<branch-name>` as positional arg 1; exit `2` on missing/empty with `[error] usage: finalize.sh <branch-name>`.
   - Compose the finalize sequence per FR-1 step order: (1) `preflight-checks.sh`; (2) `branch-id-parse.sh`; (3) bookkeeping (conditional per FR-7); (4) execution (FR-9).
   - Pre-flight: invoke `preflight-checks.sh`; on exit `1` surface its stderr verbatim and exit `1`; on exit `0` parse the JSON from stdout to capture `prNumber`, `prTitle`, `prUrl`.
   - Branch classification: invoke `${CLAUDE_PLUGIN_ROOT}/scripts/branch-id-parse.sh` "$branch". Exit `0` → parse `type`; exit `1` → emit `[info] Branch <name> does not match workflow ID pattern; skipping bookkeeping.` on stderr and jump to Execution (FR-7 unrecognized path); exit `2` → propagate as fatal.
   - Bookkeeping dispatch per FR-7:
     - `type == "release"` → skip BK-2..BK-5 silently (no `[info]`/`[warn]`), jump to Execution. Record summary line `Bookkeeping: skipped (release branch)`.
     - `type in {feature, chore, bug}` → resolve doc via `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-requirement-doc.sh <ID>`. Map its exit codes to existing behavior (exit 0 → proceed; exit 1 → `[warn] No requirement doc…` and skip bookkeeping; exit 2 → `[warn] workspace inconsistency — investigate` and skip bookkeeping; exit 3 → warning and skip). Then run `check-idempotent.sh <doc> <prNumber>`: exit 0 → skip BK-4/BK-5, record summary `Bookkeeping: skipped (requirement doc already finalized)`; exit 1 → proceed to BK-4.
   - BK-4 sub-sequence (only when `check-idempotent.sh` exit 1):
     - BK-4.1: `${CLAUDE_PLUGIN_ROOT}/scripts/checkbox-flip-all.sh <doc> "Acceptance Criteria"` — always whole-section flip per FR-7. Capture `checked N lines` N for summary. Do NOT call `check-acceptance.sh` — the single-checkbox fallback is intentionally dropped from `finalize.sh`.
     - BK-4.2: `completion-upsert.sh <doc> <prNumber> <prUrl>` — capture `upserted`/`appended` token for summary.
     - BK-4.3: `reconcile-affected-files.sh <doc> <prNumber>` — capture `<appended> <annotated>` counts; exit `1` is a non-fatal warning (surface stderr, continue to BK-5).
   - BK-5 (FR-8): `git status --porcelain`; if doc dirty, `git add <doc>`, `git commit -m "<canonical message>"`, `git push`. Canonical message body per FR-8. On push failure: exit `1` before merge. On unset `user.name`/`user.email`: stop with a clear stop-and-report message (do NOT auto-configure). Capture short SHA for summary.
   - Execution (FR-9): `gh pr merge --merge --delete-branch`; on failure exit `1`. `git checkout main`; on failure exit `1` with stderr note that merge already succeeded. `git fetch origin` + `git pull`; on failure emit warning on stderr and exit `0` (non-fatal per FR-9).
   - Unexpected subscript exit codes per FR-1: any code not documented for that subscript → exit `1` with `[error] unexpected exit <N> from <subscript-name>` on stderr; propagate subscript stderr verbatim.
   - No-rollback invariant (FR-1): if BK-5 push succeeded but a later step (merge/checkout/fetch/pull) fails, do NOT revert the bookkeeping commit. Re-invocation relies on `check-idempotent.sh` to skip bookkeeping next time.
   - Final report on success: multi-line stdout matching FR Output Format exactly (merged PR line, Bookkeeping summary line, Pushed bookkeeping commit line when applicable, final branch state line).
   - `chmod +x`.
2. Write `plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/tests/finalize.bats` (unit-level composition tests; Phase 6 adds the full E2E matrix):
   - Missing arg → exit `2`.
   - Preflight abort (stubbed `preflight-checks.sh` exit 1) → exit `1`, stderr propagated verbatim, no merge attempted.
   - Release branch (stubbed `branch-id-parse.sh` emits `type":"release"`) → no BK step invoked, merge executed, summary contains `Bookkeeping: skipped (release branch)` and no `[info]`/`[warn]` about the branch.
   - Unrecognized branch (stubbed parse exit 1) → stderr contains the canonical `[info] Branch <name> does not match…` message, merge executed, summary contains `Bookkeeping: skipped` reason.
   - Idempotent skip (stubbed `check-idempotent.sh` exit 0) → BK-4/BK-5 not invoked, summary `skipped (requirement doc already finalized)`.
   - Happy path full BK: all stubs pass → summary contains acceptance-criteria count, `upserted`/`appended` token, reconcile counts, pushed-sha line.
   - `reconcile-affected-files.sh` exit 1 → treated as non-fatal warning, BK-5 proceeds.
   - BK-5 push failure → exit `1`, no merge attempted.
   - Merge failure after successful BK push → exit `1`, stderr contains error, NO revert of BK-5 commit (no-rollback invariant asserted by checking that `git reset` / `git revert` are not called in the stub harness).
   - Unexpected subscript exit (stub returns `99`) → exit `1`, stderr `[error] unexpected exit 99 from <name>`.
   - `git fetch`/`git pull` failure post-merge → exit `0` with warning on stderr.

#### Deliverables

- [ ] `plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/finalize.sh`
- [ ] `plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/tests/finalize.bats` (unit-level composition tests)

---

### Phase 5: SKILL.md Prose Collapse (FR-10)

**Feature:** [FEAT-022](../features/FEAT-022-finalize-sh-subscripts-full.md) | [#182](https://github.com/lwndev/lwndev-marketplace/issues/182)
**Status:** Pending

#### Rationale

The SKILL.md rewrite is the user-visible cutover: it switches the skill from driving the prose ceremony to calling `finalize.sh`. It must land after `finalize.sh` is available (Phase 4) but before the end-to-end integration assertions in Phase 6, which will exercise the skill as-used by the orchestrator. Coupling the rewrite and the orchestrator-invocation path in one phase prevents a window where the SKILL.md prose references a script that doesn't yet exist (or vice versa). The rewrite also prunes the now-unused `allowed-tools` entries per FR-10.

#### Implementation Steps

1. Rewrite `plugins/lwndev-sdlc/skills/finalizing-workflow/SKILL.md` to include ONLY:
   - Frontmatter: `name`, `description`, `allowed-tools` — retain `Bash`, prune `Edit` and `Glob` (no longer used after collapse; `Read` retained only if needed for SKILL introspection, otherwise pruned).
   - "When to Use This Skill" — preserved verbatim from current SKILL.md.
   - "Workflow Position" diagram — preserved verbatim.
   - "Usage" — short section: capture `git branch --show-current` → ask single confirmation `Ready to merge PR #<N> ("<title>") and finalize the requirement document. Proceed?` → run `bash "${CLAUDE_PLUGIN_ROOT}/skills/finalizing-workflow/scripts/finalize.sh" "<branch-name>"` → report stdout verbatim to user. On non-zero exit, report stderr verbatim. Document the confirmation-prompt requirement: `finalize.sh` does NOT prompt; the SKILL layer owns the prompt.
   - "Relationship to Other Skills" table — preserved verbatim.
2. Remove the following sections entirely (now executed inside `finalize.sh`):
   - "Pre-Flight Checks" and its three subsections.
   - "Pre-Merge Bookkeeping" with BK-1 through BK-5 subsections.
   - "Execution" and its three steps.
   - "Completion" block (the finalize.sh stdout report replaces it).
   - "Error Handling" table (finalize.sh stderr is now the user-facing error surface — document that in the Usage section instead).
3. Verify via visual diff that the new SKILL.md is materially shorter (target: under ~60 lines, down from ~228) and contains no references to BK-N, individual git/gh commands, or the removed Error Handling scenarios.
4. Run `npm run validate` to confirm the trimmed `allowed-tools` list still validates against the scripted invocation path.
5. Smoke-test: manually invoke the skill against a disposable fixture branch+PR (feature chain) and confirm the skill produces the single confirmation prompt, calls `finalize.sh`, and reports its stdout.

#### Deliverables

- [ ] `plugins/lwndev-sdlc/skills/finalizing-workflow/SKILL.md` (rewritten per FR-10)
- [ ] Passing `npm run validate` for the plugin

---

### Phase 6: End-to-End Integration Testing (FR-11, NFR-5)

**Feature:** [FEAT-022](../features/FEAT-022-finalize-sh-subscripts-full.md) | [#182](https://github.com/lwndev/lwndev-marketplace/issues/182)
**Status:** Pending

#### Rationale

All four branch-pattern paths (feature, chore, bug, release) plus the unrecognized `adhoc/` path and the idempotent re-run case must round-trip correctly against realistic fixture repos before the feature is considered delivered. Unit-level tests in Phases 2–4 exercise each script in isolation with stubs; this phase exercises `finalize.sh` as a single executable against filesystem fixtures that mimic real local-branch+PR state, catching composition bugs that mocking at the unit level cannot surface. This phase also captures the NFR-1 performance measurement (< 5s end-to-end excluding merge latency) and the NFR-5 token/wall-clock deltas required by the acceptance criteria (measurable token reduction vs prose path; measurable wall-clock reduction vs 30–60s prose baseline).

#### Implementation Steps

1. Write `plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/tests/finalize.e2e.bats` (or a vitest-driven harness if the bats pattern doesn't cleanly support the git fixture setup — match the prevailing plugin convention by checking how FEAT-020's integration tests landed):
   - `feat/FEAT-NNN-*` fixture: fixture repo with a feature-requirements doc that has unticked acceptance criteria, a stubbed `gh` returning OPEN+MERGEABLE PR and realistic files. Assert: BK-5 commit SHA produced, PR merged (stub records the call), branch deleted (stub records), on `main` clean tree, summary report matches FR Output Format for "bookkeeping ran".
   - `chore/CHORE-NNN-*` fixture: same assertions, chore-requirements doc.
   - `fix/BUG-NNN-*` fixture: same assertions, bug-requirements doc.
   - `release/lwndev-sdlc-v1.16.0` fixture: NO requirements doc, no BK step invoked, merge + checkout + fetch + pull run. Assert: stderr carries NO `[info]` or `[warn]` messages about the branch; summary contains `Bookkeeping: skipped (release branch)`.
   - `adhoc/cleanup` fixture: stderr contains canonical `[info] Branch adhoc/cleanup does not match workflow ID pattern; skipping bookkeeping.`; merge proceeds; no BK step invoked.
   - Idempotent re-run: run the feature fixture twice — first run produces BK commit; on second run (with stubbed `gh pr view` returning the same PR as still open — simulating a failure before merge and a retry), `check-idempotent.sh` returns exit `0`, BK-4/BK-5 are skipped, summary contains `skipped (requirement doc already finalized)`.
   - Edge case 3 fixture: requirement doc with no `## Affected Files` section → `reconcile-affected-files.sh` exits `0` silently, summary omits the reconcile count or shows `0 0`.
   - Edge case 6 fixture: requirement doc with `## Completion` inside a fenced code block (documentation example) → not mistaken for a real completion; BK-4.2 appends a real `## Completion` block.
   - CRLF round-trip fixture: feature doc with CRLF endings → after BK-4.1/BK-4.2/BK-4.3 edits, `file` reports CRLF still present.
2. Capture wall-clock measurement for `finalize.sh` on a non-trivial fixture (time from invocation to summary print, excluding the stubbed merge wait). Assert < 5s per NFR-1.
3. Manual verification (documented in the PR description, not automated):
   - Create disposable `release/lwndev-sdlc-v9.99.0` branch with a minimal release PR; run `finalize.sh` against it; confirm success with no branch-pattern messages.
   - Run a full `orchestrating-workflows` feature chain end-to-end with the new SKILL.md; confirm behavior is observationally identical to pre-refactor (modulo wall-clock and token reduction).
   - Measure token usage on a representative workflow run (prose path vs new path) and include numbers in the PR description. Per the acceptance criteria, floor is "measurable reduction"; regression (new path uses MORE tokens) fails AC.
4. Update `plugins/lwndev-sdlc/CHANGELOG.md` entry will be handled by the `/releasing-plugins` skill post-merge; no changelog edit in this PR (per the FEAT-020 precedent).

#### Deliverables

- [ ] `plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/tests/finalize.e2e.bats` (or equivalent vitest harness) covering all four branch patterns + adhoc + idempotent-rerun + affected-files-absent + fenced-completion + CRLF
- [ ] Wall-clock measurement documented in PR description: `finalize.sh` < 5s per NFR-1
- [ ] Token-usage measurement documented in PR description: measurable reduction vs prose path
- [ ] Manual E2E on a real disposable release branch documented in PR description

---

## Shared Infrastructure

- **Plugin-shared scripts (`plugins/lwndev-sdlc/scripts/`)** — `finalize.sh` composes the existing `branch-id-parse.sh` (extended by Phase 1), `resolve-requirement-doc.sh`, and `checkbox-flip-all.sh`. These are invoked via `${CLAUDE_PLUGIN_ROOT}/scripts/<name>.sh`. No new shared scripts — new machinery is skill-scoped.
- **Skill-scoped scripts (`plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/`)** — new directory holding the five new scripts (`finalize.sh`, `preflight-checks.sh`, `check-idempotent.sh`, `completion-upsert.sh`, `reconcile-affected-files.sh`). Invoked from SKILL.md via `${CLAUDE_PLUGIN_ROOT}/skills/finalizing-workflow/scripts/<name>.sh`.
- **Bats test harness** — existing pattern under `plugins/lwndev-sdlc/scripts/tests/*.bats`. New fixtures live under `plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/tests/*.bats`, following the same convention.
- **Fence-aware / CRLF-aware scanning helpers** — used by `check-idempotent.sh`, `completion-upsert.sh`, and `reconcile-affected-files.sh`. Start with local helpers in each script; extract to a shared `scripts/lib/` only if Phase 3 shows real duplication (defer-to-YAGNI).
- **JSON on stdout convention** — `preflight-checks.sh` emits JSON on stdout; `finalize.sh` consumes it. Use `jq` when available, hand-assembled JSON fallback (matches `branch-id-parse.sh` precedent).
- **Stub pattern for `git`/`gh`** — bats tests use PATH-shadowing stubs; re-use the pattern from existing `resolve-requirement-doc.bats` and `create-pr.bats`.

## Testing Strategy

- **Unit tests (bats)** — each of the five new scripts + the extended `branch-id-parse.sh` ships a `.bats` fixture covering: happy path, missing-arg exit `2`, malformed-arg exit `2`, the specific edge case the script targets, and an idempotent-re-run assertion where meaningful (per NFR-5).
- **Composition tests (bats)** — `finalize.bats` (Phase 4) stubs the leaf subscripts and asserts `finalize.sh` wires exit codes, branch classifications, summary-line assembly, and the no-rollback invariant correctly.
- **Integration tests (bats or vitest, Phase 6)** — fixture repos covering all four branch patterns, adhoc, idempotent re-run, CRLF, fenced-example edge cases, and `## Affected Files` absent.
- **Line-ending and fence robustness (NFR-4)** — covered in both unit and integration layers via CRLF and fenced-example fixtures.
- **Performance (NFR-1)** — wall-clock measured in Phase 6; target < 5s end-to-end excluding merge latency.
- **Backward compatibility (NFR-6)** — Phase 1 explicitly re-runs all existing `branch-id-parse.bats` cases unchanged; orchestrator resume detection is unaffected.
- **Manual E2E** — Phase 6 includes a real disposable release-branch run and a full `orchestrating-workflows` feature chain end-to-end run.

## Dependencies and Prerequisites

- **Already shipped (plugin-shared scripts library, FEAT-020)**: `branch-id-parse.sh`, `resolve-requirement-doc.sh`, `checkbox-flip-all.sh`. FEAT-022 extends the first and reuses the other two.
- **Already shipped**: `releasing-plugins` skill (from a separate marketplace — NOT in this repo) handles release-branch changelog generation. `finalize.sh` silently skips bookkeeping on release branches because `releasing-plugins` has already done the relevant writes.
- **External**: `gh` CLI authenticated (required by `preflight-checks.sh`, `reconcile-affected-files.sh`, and the merge step). Treated as fatal if missing/unauthenticated (NFR-2).
- **External**: `git` — required for status, add, commit, push, checkout, fetch, pull, and `branch --show-current`.
- **Optional but preferred**: `jq` for structured JSON emit; hand-assembled fallback exists in `branch-id-parse.sh` and must be mirrored in `preflight-checks.sh`.
- **No new Node/TypeScript dependency** — shell-only, consistent with the `plugins/lwndev-sdlc/scripts/` convention.
- **No orchestrator changes** — `orchestrating-workflows` SKILL.md and scripts are unchanged (NFR-6).

## Risk Assessment

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Release-branch regex admits a legitimate-looking non-release (e.g., `release/foo-v1.0.0-rc1`) or rejects a real release | Med | Low | Regex anchored `^…$` and tested against edge cases in Phase 1 bats (nested-path, incomplete-version, multi-digit). Feature doc's edge-case table (items 10, 11) locks down the intended behavior — confirm tests match the table. |
| Fence-aware scanning in `check-idempotent.sh` / `completion-upsert.sh` / `reconcile-affected-files.sh` diverges across the three scripts and treats fenced content inconsistently | High | Med | Start with per-script local helpers following the `checkbox-flip-all.sh` precedent; add a cross-script unit test (Phase 3) that runs all three scripts against the same fenced-example fixture to assert consistent behavior. If real drift appears, extract to a shared helper (not upfront — defer to YAGNI). |
| `preflight-checks.sh` parallelism introduces race conditions in stdout capture or mis-attributes failures across the three sub-checks | Med | Med | Use tempfile-per-child pattern for stdout/stderr capture; `wait` on each PID individually; explicit exit-code merge. Phase 2 bats covers the dirty-tree + on-main + no-PR cases to catch mis-attribution. |
| `finalize.sh` swallows a subscript's stderr instead of propagating verbatim (violates NFR-2) | High | Low | Explicit Phase 4 bats assertion that stderr is propagated byte-for-byte for every non-zero subscript exit. `finalize.sh` uses `>&2 tee` or equivalent — never `2>/dev/null`. |
| No-rollback invariant misapplied: BK-5 pushes, merge fails, someone reverts the commit → next retry finds the doc "un-finalized" again, loops | High | Low | Phase 4 bats explicitly asserts no `git revert`/`git reset` occurs on merge failure after BK-5 push. `check-idempotent.sh` (Phase 2) handles the re-invocation case. Documented in FR-1 and in the rewritten SKILL.md. |
| SKILL.md collapse breaks orchestrator resume detection (which inspects skill outputs) | High | Low | Orchestrator inspects the skill's stdout report, not the prose. `finalize.sh` emits the canonical report per FR Output Format — same structure as the current prose-driven "Completion" section. Phase 6 runs a full `orchestrating-workflows` chain to confirm. |
| `gh pr merge --merge --delete-branch` fails on repos without the merge strategy configured, but old prose path handled it | Med | Low | FR-9 is explicit that the `--merge` flag is required (matches current SKILL.md rationale). No behavior change. Integration fixture covers the happy path. |
| Token/wall-clock measurement is absent at PR time (AC requires it reported) | Low | Med | Phase 6 explicitly allocates steps to capture both. Missing measurement blocks AC sign-off; make it a Phase 6 deliverable checkbox. |
| bats fixture complexity explodes in Phase 6 (six fixture repos × state variations) | Med | Med | Reuse the stub-pattern from FEAT-020 (`create-pr.bats`, `commit-work.bats`). If bats becomes unwieldy for git-fixture setup, switch to vitest harness per the Phase 6 note — don't fight the tooling. |

## Success Criteria

Per-feature (FEAT-022) — all acceptance criteria from the requirements doc:

- `finalize.sh` exists, is executable, runs pre-flight → bookkeeping (when applicable) → execution in a single invocation.
- Four new subscripts exist under `plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/`, executable, with documented args and exit codes.
- `branch-id-parse.sh` returns `{"id": null, "type": "release", "dir": null}` with exit `0` on `release/<plugin>-vX.Y.Z` patterns; preserves all three existing classifications exactly.
- `finalize.sh` on `feat/`, `chore/`, and `fix/` branches performs full BK-1..BK-5 + merge.
- `finalize.sh` on `release/<plugin>-vX.Y.Z` branches merges + resets + emits no unrecognized-pattern message.
- `finalize.sh` on `adhoc/…` branches emits the canonical `[info]` message and still merges.
- `SKILL.md` collapses to confirm → run `finalize.sh` → report; no BK-N prose or Error Handling table remains.
- Every new script ships a bats fixture covering happy path, missing-arg, and the script's specific edge case.
- Full feature/chore/bug workflow chains through `orchestrating-workflows` produce observationally-identical behavior vs pre-refactor.
- Token-usage measurement reported in the PR description shows measurable reduction vs the prose path (regression fails AC).
- Wall-clock measurement reported in the PR description shows measurable reduction; `finalize.sh` itself runs in < 5s excluding merge latency.

Overall project:
- No behavior regression in any existing `branch-id-parse.sh` caller.
- `npm run validate` and `npm test` pass after Phase 5 SKILL.md rewrite.
- Bats suite passes for all new and extended scripts.
- The `/finalizing-workflow` slash command remains invocable end-to-end with the single confirmation prompt documented in FR-10.

## Code Organization

```
plugins/lwndev-sdlc/
├── scripts/
│   ├── branch-id-parse.sh                      # EXTENDED (Phase 1): fourth `release/` classification
│   └── tests/
│       └── branch-id-parse.bats                # EXTENDED (Phase 1): release happy paths + malformed cases
└── skills/
    └── finalizing-workflow/
        ├── SKILL.md                            # REWRITTEN (Phase 5): confirm → run finalize.sh → report
        └── scripts/                            # NEW directory
            ├── finalize.sh                     # NEW (Phase 4): top-level orchestrator
            ├── preflight-checks.sh             # NEW (Phase 2): clean tree + branch + PR state + mergeable
            ├── check-idempotent.sh             # NEW (Phase 2): BK-3 three-condition idempotency check
            ├── completion-upsert.sh            # NEW (Phase 3): BK-4.2 Completion section upsert
            ├── reconcile-affected-files.sh     # NEW (Phase 3): BK-4.3 Affected Files reconciliation
            └── tests/                          # NEW directory
                ├── finalize.bats               # NEW (Phase 4): composition / unit-level tests
                ├── finalize.e2e.bats           # NEW (Phase 6): end-to-end integration tests
                ├── preflight-checks.bats       # NEW (Phase 2)
                ├── check-idempotent.bats       # NEW (Phase 2)
                ├── completion-upsert.bats      # NEW (Phase 3)
                └── reconcile-affected-files.bats # NEW (Phase 3)
```
