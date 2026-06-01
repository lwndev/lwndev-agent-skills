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
2. **No Stop-hook diff guard for `finalizing-workflow`.** `finalize.sh` itself already fails-fast on a preflight non-zero exit (`finalize.sh:120-124` cats stderr and `exit 1`) and the NO-ROLLBACK invariant (`finalize.sh:14-17`, `429-433`) forbids the script doing recovery — so the script is not the actor. But there is no equivalent of executing-qa's FR-10 diff guard (`plugins/lwndev-sdlc/skills/executing-qa/scripts/stop-hook.sh:283-447`, wired via SKILL.md `hooks:` frontmatter) that diffs the *subagent's* changes against an allowlist and blocks Stop until violations are reverted. Mutations the agent makes around `finalize.sh` are unguarded. **Critically, the documented overreach COMMITS (`git rm`/`git mv` -> commit -> push -> merge), so at stop time the index and working tree are clean** — a guard that inspects only `git status` / `git diff --cached` sees nothing. The guard MUST diff committed changes since a finalize-start baseline SHA (`baseline..HEAD`), mirroring `executing-qa/scripts/stop-hook.sh:347` (`git diff --name-status "${baseline_sha}" HEAD`), with an active-marker + baseline-SHA capture at finalize start (analogous to executing-qa's `.executing-active` + `.executing-qa-baseline-<ID>`).
3. **The orchestrator's finalize fork prompt has no explicit negative-constraint paragraph.** The finalize fork prompt template in `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/step-execution-details.md` (feature step 5+N+4; chore/bug step 7) never asserts verbatim that the fork must not `git rm`/`git mv`/`rm` files outside `requirements/<type>/{ID}-*.md`, nor instructs it to return `failed | preflight blocked: <reason>` on a block. The negative scope is implicit in SKILL.md but never reaches the assembled fork prompt.

## Affected Files

- `plugins/lwndev-sdlc/skills/finalizing-workflow/SKILL.md` — add `## Write Surface` section; wire Stop-hook in `hooks:` frontmatter; document the active-marker + baseline-SHA capture at finalize start.
- `plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/stop-hook.sh` — NEW; write-surface diff guard over `baseline..HEAD` (committed changes).
- `plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/finalize.sh` — confirm/lock fail-fast-on-preflight behavior (already compliant — assert, do NOT modify the abort path); add baseline-SHA capture at start if that is the chosen wiring point.
- `plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/preflight-checks.sh` — context (emits the FR-9 block reason consumed by the fork).
- `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/step-execution-details.md` — append verbatim negative-constraint paragraph to the finalize fork prompt.
- `tests/bats/skills/finalizing-workflow/stop-hook.bats` — NEW regression.
- `tests/bats/skills/finalizing-workflow/finalize.bats` — preflight fail-fast assertion.

## Acceptance Criteria

- [x] `finalizing-workflow/SKILL.md` has a `## Write Surface` section listing allowed paths (`requirements/<type>/{ID}-*.md`) and allowed operations (`gh pr merge`/`git merge`, `git checkout main`, `git fetch`, `git pull`, and the `finalize.sh` BK-5 bookkeeping `git add` + commit of the requirement doc), and forbidding any other mutation (`git rm`, `git mv`, `rm`, `git restore --staged`, content edits) outside that surface (RC-1)
- [x] On `preflight-checks.sh` non-zero exit, `finalize.sh` exits non-zero with the verbatim preflight stderr and performs no recovery action — the existing abort path is asserted by test, NOT modified (RC-2)
- [x] A new `plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/stop-hook.sh` blocks Stop (exit 2) when changes COMMITTED on the branch since a finalize-start baseline SHA (diffed `baseline..HEAD`, mirroring executing-qa's diff guard) — OR uncommitted staged/working-tree changes — include ANY mutation (deletion `rm`, rename/move `mv`, add/commit, or content edit) to paths outside the documented write surface; both `git rm` AND `git mv` are caught. A commit that touches ONLY `requirements/<type>/{ID}-*.md` (the BK-5 bookkeeping commit) is allowed and does not block (RC-2)
- [x] The new `stop-hook.sh` is wired into `finalizing-workflow/SKILL.md` `hooks:` frontmatter (Stop matcher) and gated by a finalize active-marker so it no-ops when finalize is not running, analogous to executing-qa's FR-10 hook + `.executing-active` marker (RC-2)
- [x] The orchestrator finalize fork prompt template in `orchestrating-workflows/references/step-execution-details.md` (feature step 5+N+4; chore/bug step 7) appends a verbatim negative-constraint paragraph forbidding `git rm`/`git mv`/`git restore --staged`/`rm` on files outside `requirements/<type>/{ID}-*.md` and instructs the fork to return `failed | preflight blocked: <reason>` on a preflight block (RC-3)
- [x] The forked `finalizing-workflow` subagent, on a preflight block, returns `failed | preflight blocked: <one-line reason>` as its final contract line and makes no further `git`/`gh` mutations (RC-1, RC-3)
- [x] Bats regression (hook-logic layer, not a live agent fork): a fixture commits a `git rm` of an out-of-surface `qa-*` file (and a separate case commits a `git mv` rename) on the branch past the finalize-start baseline, then runs `stop-hook.sh`; asserts exit 2 with every offending path enumerated, and asserts a BK-5-only commit (requirement doc alone) exits 0. A `finalize.bats` case asserts `finalize.sh` aborts (exit 1, verbatim stderr) on a preflight block without reaching the merge dispatcher (RC-1, RC-2, RC-3)

## Completion

**Status:** `Completed`

**Completed:** 2026-06-01

**Pull Request:** [#310](https://github.com/lwndev/lwndev-marketplace/pull/310)

## Notes

- Companion issue BUG-021: Hook C's merge-approval gate failed to fire on the BUG-019 finalize fork. The FEAT-020 occurrence shows a *working* merge-approval gate is NOT sufficient mitigation — write-surface enforcement (RC-1/RC-2) is required independently of the gate.
- The FEAT-020 renames were improvised (flat in-place `git mv qa-<name>.test.ts <name>.qa.test.ts`, intermediate `qa-*.qa.test.ts` names visible in `67ee74d`), NOT a run of `adopt-qa-test.sh` (which resolves each test's SUT, moves it next to the peer test, and exits 2 on multi-SUT tests). So this is overreach, not even mis-scoped adoption.
- Optional follow-up (issue "Consider adding"): a dedicated `preflight-blocked` pauseReason in the orchestrator mirroring `qa-loop-exhausted`, so a correctly-failing fork has a clean documented pause path. Out of scope for the core fix unless reconciliation surfaces it.
- The underlying trigger for an initial-PASS run's *own* `qa-*` files (orphaned-adoption gap) is tracked separately (#303/#304); this bug is strictly about the fork's unauthorized *response* to the block, not the block itself.
