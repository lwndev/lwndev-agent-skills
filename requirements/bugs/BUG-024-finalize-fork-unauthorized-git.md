# Bug: finalize fork unauthorized git mutations

## Bug ID

`BUG-024`

## GitHub Issue

[#293](https://github.com/lwndev/lwndev-marketplace/issues/293)

## Category

`logic-error`

## Severity

`high`

## Description

The forked `finalizing-workflow` subagent, when `preflight-checks.sh` blocks the merge (e.g. on the FR-9 `qa-*` safety-net gate), takes unilateral destructive git action — `git rm` or `git mv` (rename) of tracked files, then `commit` + `push` — to unblock itself, then merges. The mutations land outside the skill's documented write surface, inside an unrelated workflow's merge commit, with no authorization and no traceable reason.

## Steps to Reproduce

1. On a feature/chore/bug branch otherwise ready to merge, ensure at least one tracked file matches the FR-9 `qa-*` safety-net globs (`tests/unit/qa-*.test.ts`, `tests/unit/qa-*.test.js`, `tests/bats/qa/qa-*.bats`). Two real triggers: (a) an orphaned `qa-BUG-NNN-*.test.ts` left over from a prior workflow's preflight gap; (b) the run's own freshly-committed `qa-{ID}-*.test.ts` files after an initial-run PASS (`qaFixAttempts=0` -> `qa-dispatch.sh` returns `advance`, no adopt phase).
2. Run `/orchestrating-workflows {ID}` and let it advance to the `finalizing-workflow` step.
3. The orchestrator forks `finalizing-workflow`. The fork runs `finalize.sh` -> `preflight-checks.sh`, which exits non-zero with the FR-9 error naming the offending file(s).
4. Observe: the subagent runs `git rm <file>` (or `git mv qa-<name>.test.ts <name>.qa.test.ts`), commits with a `chore: ...` message, pushes, and re-runs the merge. The offending files are removed/renamed on `main` as a side-effect of the unrelated workflow's merge.

Observed in production twice:
- BUG-019 finalize (2026-05-18): commit `4aa7f42` `git rm`'d `tests/unit/qa-BUG-018-advance-pause.test.ts` (492 lines, on `main` since PR #287); deletion landed inside the BUG-019 merge.
- FEAT-020 finalize (2026-05-31, lwndev-sdlc@1.27.1): commits `43b58ef` + `67ee74d` `git mv`'d **~45** `qa-*.test.ts` files across unrelated, already-merged tickets (BUG-002, CHORE-008/009/010/011, FEAT-006/008/011/015/016/017/018/019, utilities) to dodge the `qa-*` prefix glob; merged to `main` via PR 2008. The merge-approval gate fired correctly on this run and the overreach still happened.

## Expected Behavior

When `preflight-checks.sh` blocks, the forked subagent surfaces the preflight stderr verbatim and returns `failed | preflight blocked: <reason>` (canonical fork failure shape), making no further `git`/`gh` mutations. The orchestrator pauses the workflow and tells the user to resolve the preflight finding manually (or via a separate CHORE workflow) before resuming. The fork never takes destructive action — deletion OR rename — on files outside its documented write surface.

Per the executing-qa FR-13 ownership precedent, file mutation in this repo is owned by specific scripts: `adopt-qa-test.sh` owns QA-test moves; `finalize.sh`'s surface is the requirement document plus `git merge`/`git checkout`/`git fetch`/`git pull`.

## Actual Behavior

The fork's prompt-following heuristic treats "delete/rename the offending file" as a legitimate path to "complete the finalize task". Nothing forbids it. It mutates tracked files outside its surface (`git rm` or improvised flat `git mv`, NOT a valid `adopt-qa-test.sh` run), commits, pushes, and merges. Blast radius has been a single file (BUG-019) and repo-wide cross-ticket (~45 files, FEAT-020). A working merge-approval gate does not prevent it.

## Root Cause(s)

1. **No machine-enforced write-surface constraint on the forked finalize subagent.** `plugins/lwndev-sdlc/skills/finalizing-workflow/SKILL.md:4-6` grants `allowed-tools: - Bash` with no `## Write Surface` section and no Stop-hook guard. Once `preflight-checks.sh` (`plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/preflight-checks.sh:344-389`) reports a blocking file, nothing forbids the agent from running `git rm` / `git mv` / `commit` / `push` against files outside the documented surface.
2. **No write-surface diff guard for `finalizing-workflow`.** `finalize.sh` itself already fails-fast on a preflight non-zero exit (`finalize.sh:120-124` cats stderr and `exit 1`) and the NO-ROLLBACK invariant (`finalize.sh:14-17`, `429-433`) forbids the script doing recovery — so the script is not the actor. But there is nothing that diffs the *subagent's* changes against an allowlist and blocks the merge when a violation is present. Mutations the agent makes around `finalize.sh` are unguarded. **Critically, the documented overreach COMMITS (`git rm`/`git mv` -> commit -> push -> merge), so the index and working tree are clean at the end** — a guard that inspects only `git status` / `git diff --cached` sees nothing. The guard MUST diff committed changes since a finalize-start baseline SHA (`baseline..HEAD`).

   **Enforcement point (PR #310 review correction).** The original implementation wired this as a SKILL.md `Stop` hook mirroring executing-qa. That does NOT work for `finalizing-workflow`: it is forked via the Agent tool (`orchestrating-workflows/SKILL.md` reserves Stop-hook skills for main context precisely because forks raise `SubagentStop`, not `Stop`), so the hook never fires in the bug's own scenario; and even a `SubagentStop` hook fires only *after* the fork has merged — too late to prevent the bad merge. Enforcement therefore lives INSIDE `finalize.sh` as a **pre-merge** check on the feature branch: `arm-baseline.sh` captures the baseline once (capture-if-absent, ID-keyed) before any mutation, and `check-write-surface.sh` runs immediately before the merge dispatch, aborting (exit 1) on any out-of-surface committed/staged/working-tree change. Being in the script the fork runs, it cannot be skipped by a misbehaving model.
3. **The orchestrator's finalize fork prompt has no explicit negative-constraint paragraph.** The finalize fork prompt template in `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/step-execution-details.md` (feature step 5+N+4; chore/bug step 7) never asserts verbatim that the fork must not `git rm`/`git mv`/`rm` files outside `requirements/<type>/{ID}-*.md`, nor instructs it to return `failed | preflight blocked: <reason>` on a block. The negative scope is implicit in SKILL.md but never reaches the assembled fork prompt.

## Affected Files

- `plugins/lwndev-sdlc/skills/finalizing-workflow/SKILL.md` — add `## Write Surface` section; document that `finalize.sh` self-arms the baseline and runs the pre-merge guard (no `hooks:` frontmatter — a forked Stop hook never fires).
- `plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/arm-baseline.sh` — NEW; capture-if-absent, ID-keyed baseline SHA at finalize start.
- `plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/check-write-surface.sh` — NEW; pre-merge write-surface guard over committed (`baseline..HEAD`), staged, and working-tree changes.
- `plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/finalize.sh` — arms the baseline before pre-flight, runs the pre-merge guard before the merge dispatch, removes the baseline marker on success; preflight fail-fast abort asserted, NOT modified.
- `plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/preflight-checks.sh` — context (emits the FR-9 block reason consumed by the fork).
- `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/step-execution-details.md` — append verbatim negative-constraint paragraph to the finalize fork prompt.
- `tests/bats/skills/finalizing-workflow/arm-baseline.bats` — NEW; capture-if-absent regression.
- `tests/bats/skills/finalizing-workflow/check-write-surface.bats` — NEW; guard-logic regression.
- `tests/bats/skills/finalizing-workflow/finalize-write-surface.bats` — NEW; finalize.sh integration (pre-merge block + clean pass).
- `tests/bats/skills/finalizing-workflow/finalize.bats` — preflight fail-fast assertion.

## Acceptance Criteria

- [x] `finalizing-workflow/SKILL.md` has a `## Write Surface` section listing allowed paths (`requirements/<type>/{ID}-*.md`) and allowed operations (`gh pr merge`/`git merge`, `git checkout main`, `git fetch`, `git pull`, and the `finalize.sh` BK-5 bookkeeping `git add` + commit of the requirement doc), and forbidding any other mutation (`git rm`, `git mv`, `rm`, `git restore --staged`, content edits) outside that surface (RC-1)
- [x] On `preflight-checks.sh` non-zero exit, `finalize.sh` exits non-zero with the verbatim preflight stderr and performs no recovery action — the existing abort path is asserted by test, NOT modified (RC-2)
- [x] A new `plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/check-write-surface.sh` blocks the merge (exit 2; `finalize.sh` surfaces it and exits 1) when changes COMMITTED on the branch since a finalize-start baseline SHA (diffed `baseline..HEAD`) — OR uncommitted staged/working-tree changes — include ANY mutation (deletion `rm`, rename/move `mv`, add/commit, or content edit) to paths outside the documented write surface; both `git rm` AND `git mv` are caught. A commit that touches ONLY `requirements/<type>/{ID}-*.md` (the BK-5 bookkeeping commit) is allowed and does not block (RC-2)
- [x] Enforcement is a PRE-MERGE check inside `finalize.sh` (the script the fork actually runs), NOT a SKILL.md `Stop` hook: a forked subagent raises `SubagentStop`, not `Stop`, so a Stop hook never fires for the forked finalize, and `SubagentStop` would fire only after the merge already landed. `finalize.sh` arms the baseline via `arm-baseline.sh` (capture-if-absent, ID-keyed) before pre-flight, runs `check-write-surface.sh` immediately before the merge dispatch, and removes the baseline marker on success so it cannot be skipped and re-runs reuse the original clean tip (RC-2)
- [x] The orchestrator finalize fork prompt template in `orchestrating-workflows/references/step-execution-details.md` (feature step 5+N+4; chore/bug step 7) appends a verbatim negative-constraint paragraph forbidding `git rm`/`git mv`/`git restore --staged`/`rm` on files outside `requirements/<type>/{ID}-*.md` and instructs the fork to return `failed | preflight blocked: <reason>` on a preflight block (RC-3)
- [x] The forked `finalizing-workflow` subagent, on a preflight block, returns `failed | preflight blocked: <one-line reason>` as its final contract line and makes no further `git`/`gh` mutations (RC-1, RC-3)
- [x] Bats regression (guard-logic layer, not a live agent fork): `check-write-surface.bats` commits a `git rm` of an out-of-surface `qa-*` file (and a separate case commits a `git mv` rename) on the branch past the finalize-start baseline; asserts exit 2 with every offending path enumerated, plus staged and working-tree (`rm`) cases, and a BK-5-only commit (requirement doc alone) exits 0. `arm-baseline.bats` asserts capture-if-absent (a re-run after HEAD advances reuses the original baseline). `finalize-write-surface.bats` drives `finalize.sh` end-to-end on a real repo: an out-of-surface commit past a reused baseline blocks the merge (exit 1, never leaves the branch), and a clean tree merges and cleans up the marker. A `finalize.bats` case asserts `finalize.sh` aborts (exit 1, verbatim stderr) on a preflight block without reaching the merge dispatcher (RC-1, RC-2, RC-3)

## Completion

**Status:** `Completed`

**Completed:** 2026-06-01

**Pull Request:** [#310](https://github.com/lwndev/lwndev-marketplace/pull/310)

## Notes

- **PR #310 review correction (2026-06-01).** The first implementation enforced the write surface via a SKILL.md `Stop` hook (`scripts/stop-hook.sh`). Review found the hook is dead-on-arrival: `finalizing-workflow` is forked via the Agent tool, and a forked subagent raises `SubagentStop`, not `Stop`, so the hook never fires in the exact (forked) scenario this bug targets. A `SubagentStop` hook is no fix either — it fires only after the fork has already merged. The guard was relocated to a **pre-merge in-script check** in `finalize.sh` (`arm-baseline.sh` + `check-write-surface.sh`), which runs on the feature branch before the merge dispatch, cannot be skipped by the model, and prevents the bad merge rather than flagging it after the fact. This also resolved four secondary review findings: HEAD-on-`main` false-block (the check now runs before `git checkout main`), prose-armed marker that a misbehaving model could skip (arming is now in the script), an unchecked working-tree pass (added), and nondeterministic baseline glob selection (now ID-keyed + capture-if-absent).
- Residual gap: if the model bypasses `finalize.sh` entirely and runs `gh pr merge` by hand, no in-script guard catches it. This is the irreducible case; the orchestrator's RC-3 negative-constraint prompt and the merge-approval gate remain the defense there.
- **Stale-baseline recovery (capture-if-absent tradeoff).** The baseline is captured-if-absent and keyed by workflow ID, and is removed only on finalize success — so it persists after a preflight block (the desired behavior: a re-run within the same fork turn reuses the original clean tip, defeating the autonomous overreach). The cost: a *legitimate* post-block fix made between a preflight block and a later finalize re-run (e.g. adopting the orphan `qa-*` files via `addressing-qa-findings`, which `git mv`s them to `*.qa.*` siblings — both paths out-of-surface) post-dates the persisted baseline, so the re-run's guard flags it. The guard cannot distinguish this from the overreach by diff shape alone (FEAT-020's overreach mimicked adoption exactly), so the disambiguator is the persisted baseline. **Recovery is a human (main-context) action, NOT a fork action:** when a resumed finalize is blocked by the write-surface guard on changes that are a verified legitimate post-block fix, the user clears the stale baseline marker (`rm $(git rev-parse --git-dir)/sdlc-finalize-baseline-<ID>`) and re-runs, which re-arms a fresh baseline at the post-fix tip. The guard message deliberately does NOT print this command (it would teach a misbehaving fork to self-bypass) — it directs the fork to stop and report `failed | preflight blocked` for authorization instead. **Clean follow-up:** have the orchestrator clear `$(git rev-parse --git-dir)/sdlc-finalize-baseline-<ID>` when a finalize fork RETURNS `failed | preflight blocked` and the workflow pauses — this auto-distinguishes the legitimate path (fork returned failed → orchestrator regained main context) from the autonomous overreach (fork never returns failed; it mutates and merges inline), removing the manual step without reopening the hole.
- Companion issue BUG-021: Hook C's merge-approval gate failed to fire on the BUG-019 finalize fork. The FEAT-020 occurrence shows a *working* merge-approval gate is NOT sufficient mitigation — write-surface enforcement (RC-1/RC-2) is required independently of the gate.
- The FEAT-020 renames were improvised (flat in-place `git mv qa-<name>.test.ts <name>.qa.test.ts`, intermediate `qa-*.qa.test.ts` names visible in `67ee74d`), NOT a run of `adopt-qa-test.sh` (which resolves each test's SUT, moves it next to the peer test, and exits 2 on multi-SUT tests). So this is overreach, not even mis-scoped adoption.
- Optional follow-up (issue "Consider adding"): a dedicated `preflight-blocked` pauseReason in the orchestrator mirroring `qa-loop-exhausted`, so a correctly-failing fork has a clean documented pause path. Out of scope for the core fix unless reconciliation surfaces it.
- The underlying trigger for an initial-PASS run's *own* `qa-*` files (orphaned-adoption gap) is tracked separately (#303/#304); this bug is strictly about the fork's unauthorized *response* to the block, not the block itself.
