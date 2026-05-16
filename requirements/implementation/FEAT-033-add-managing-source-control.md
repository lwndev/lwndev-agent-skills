# Implementation Plan: Add managing-source-control skill

## Overview

This plan adds a `managing-source-control` skill under `plugins/lwndev-sdlc/skills/` that centralizes all git and pull-request operations and dispatches between GitHub (`gh` CLI) and Azure DevOps (`az` CLI) backends. It mirrors the multi-backend pattern of `managing-work-items` and removes the GitHub-only hard-coding that currently blocks Azure DevOps users from running any workflow chain.

The work is structured in six phases: scaffold the skill + backend detection (Phase 1), move the three backend-agnostic branch/commit scripts into the skill (Phase 2), implement PR dispatcher scripts with the GitHub path only (Phase 3), add remaining PR dispatchers and the Azure DevOps path (Phase 4), refactor consumer skills and SKILL.md prose to delegate through the new scripts (Phase 5), and wire in the NFR-5 enforcing validation check (Phase 6).

## Features Summary

| Feature ID | GitHub Issue | Feature Document | Priority | Complexity | Status |
|------------|--------------|------------------|----------|------------|--------|
| FEAT-033 | [#120](https://github.com/lwndev/lwndev-marketplace/issues/120) | [FEAT-033-add-managing-source-control.md](../features/FEAT-033-add-managing-source-control.md) | High | High | Pending |

## Recommended Build Sequence

### Phase 1: Scaffold skill + backend-detect
**Feature:** [FEAT-033](../features/FEAT-033-add-managing-source-control.md) | [#120](https://github.com/lwndev/lwndev-marketplace/issues/120)
**Status:** ✅ Complete
**Depends on:** None
**ComplexityOverride:** opus

> Justification: 8 steps span directory scaffold, new script with dual URL-form parsing + env override, two reference docs, a mirrored unit test, and 8-case Bats suite; cannot split without losing the "backend-detect is available before any dispatcher" invariant.

#### Rationale
- Establishes the skill directory layout (FR-10) and the sole shared primitive (`backend-detect.sh`) that every PR dispatcher in later phases depends on.
- Unblocks Phase 2 and Phase 3 immediately — nothing else can proceed without knowing the SCM backend.
- Frontmatter + unit test confirm the skill is valid before any script logic lands.

#### Implementation Steps
1. Create directory tree: `plugins/lwndev-sdlc/skills/managing-source-control/{SKILL.md,scripts/,references/}`.
2. Write `SKILL.md` — YAML frontmatter (`name: managing-source-control`, `description`, `allowed-tools`, `argument-hint`), Quick Start prose mirroring `managing-work-items/SKILL.md` structure: backend detection section, inline-execution note, lite-narration rules, load-bearing carve-outs, graceful degradation matrix (NFR-1 table from the requirement), output format section.
3. Implement `scripts/backend-detect.sh`:
   - Accept zero args (no issue-ref, reads `git remote get-url origin`).
   - Honor `SDLC_SCM_BACKEND=github|azdo` env override — when set, the override flips the **backend label only**. The script still parses the origin URL against the overridden backend's pattern to populate identity fields. If the URL does not match, emit literal `null` and log `[warn] SDLC_SCM_BACKEND=<x> set but origin does not match <x> URL pattern.` on stderr.
   - Parse origin URL: `github.com` → `{"backend":"github","owner":"...","repo":"..."}`, `dev.azure.com` or `*.visualstudio.com` → `{"backend":"azdo","organization":"...","project":"...","repo":"..."}`.
   - For AzDO, emit `organization` as the bare name (e.g. `contoso`). Dispatchers downstream construct the `--organization https://dev.azure.com/<org>/` URL when invoking `az` (consistent with the `az devops configure -d organization=ORG_URL` form documented in MS docs).
   - No origin / parse fails / unrecognized host → emit literal `null`, exit 0.
   - Exit 0 in all detection cases; exit 2 only on internal parse error (jq failure).
   - Support HTTPS and SSH URL forms for each backend. AzDO SSH form is `git@ssh.dev.azure.com:v3/<org>/<project>/<repo>`.
4. Write `references/branch-conventions.md` — canonical branch prefix table (`feat/`, `chore/`, `fix/`), naming format, slug rules.
5. Write `references/commit-conventions.md` — conventional commit format per type, scope conventions, multi-line body guidance.
6. Write unit test `tests/unit/managing-source-control.test.ts`:
   - Mirror `tests/unit/managing-work-items.test.ts` structure.
   - Verify SKILL.md frontmatter (`name`, `description`, `allowed-tools`, `argument-hint`).
   - Verify directory layout: `scripts/` present, `references/` present, `backend-detect.sh` present.
   - Verify `references/branch-conventions.md` and `references/commit-conventions.md` present.
   - Run `ai-skills-manager validate()` on the skill dir.
7. Write Bats test `tests/bats/skills/managing-source-control/backend-detect.bats`:
   - SSH GitHub origin (`git@github.com:owner/repo.git`) → `{"backend":"github",...}`.
   - HTTPS GitHub origin → same.
   - `dev.azure.com` HTTPS origin → `{"backend":"azdo",...}`.
   - `*.visualstudio.com` HTTPS origin → `{"backend":"azdo",...}`.
   - AzDO SSH origin (`git@ssh.dev.azure.com:v3/org/project/repo`) → `{"backend":"azdo",...}`.
   - Unknown host → `null`.
   - No origin remote → `null`.
   - `SDLC_SCM_BACKEND=github` override on a `github.com` origin → label preserved, identity fields parsed.
   - `SDLC_SCM_BACKEND=azdo` override on a `dev.azure.com` origin → label preserved, identity fields parsed.
   - `SDLC_SCM_BACKEND=azdo` override on a `github.com` origin (mismatch) → `null` + `[warn]` on stderr; exit 0.
   - `SDLC_SCM_BACKEND=github` override on a `dev.azure.com` origin (mismatch) → `null` + `[warn]` on stderr; exit 0.
8. Run `npm test -- --testPathPatterns=managing-source-control` and `npx bats tests/bats/skills/managing-source-control/backend-detect.bats` — must pass.

#### Deliverables
- [x] `plugins/lwndev-sdlc/skills/managing-source-control/SKILL.md` — valid frontmatter + Quick Start + NFR-1 table
- [x] `plugins/lwndev-sdlc/skills/managing-source-control/scripts/backend-detect.sh` — URL parse + env override; exit 0 on all detection cases
- [x] `plugins/lwndev-sdlc/skills/managing-source-control/references/branch-conventions.md`
- [x] `plugins/lwndev-sdlc/skills/managing-source-control/references/commit-conventions.md`
- [x] `tests/unit/managing-source-control.test.ts` — frontmatter + layout + validate() pass
- [x] `tests/bats/skills/managing-source-control/backend-detect.bats` — all 8 cases pass

---

### Phase 2: Move backend-agnostic scripts
**Feature:** [FEAT-033](../features/FEAT-033-add-managing-source-control.md) | [#120](https://github.com/lwndev/lwndev-marketplace/issues/120)
**Status:** ✅ Complete
**Depends on:** Phase 1
**ComplexityOverride:** opus

> Justification: 8 steps cover 3 `git mv` operations, intra-script path fixups, path-reference updates across 3 consumer SKILL.md files + 1 consumer script, Bats fixture path verification, and a full test-suite green-gate; splitting the move from the path-reference updates would create a broken-path window between commits.

#### Rationale
- `ensure-branch.sh`, `build-branch-name.sh`, and `commit-work.sh` are backend-agnostic (pure git) and belong in the skill per FR-10 and FR-11.
- Moving them before the PR dispatcher work (Phase 3) keeps the Phase 3 diff clean — Phase 3 only adds new files, it doesn't shuffle existing ones.
- Consumer SKILL.md path references (`executing-chores`, `executing-bug-fixes`, `implementing-plan-phases`) must be updated in the same commit as the move to avoid a broken-path window.

#### Implementation Steps
1. `git mv plugins/lwndev-sdlc/scripts/ensure-branch.sh plugins/lwndev-sdlc/skills/managing-source-control/scripts/ensure-branch.sh`
2. `git mv plugins/lwndev-sdlc/scripts/build-branch-name.sh plugins/lwndev-sdlc/skills/managing-source-control/scripts/build-branch-name.sh`
3. `git mv plugins/lwndev-sdlc/scripts/commit-work.sh plugins/lwndev-sdlc/skills/managing-source-control/scripts/commit-work.sh`
4. Update any `SCRIPT_DIR`-relative references inside the moved scripts themselves (e.g., `build-branch-name.sh` calls `slugify.sh` — confirm path still resolves from new location, add `${CLAUDE_PLUGIN_ROOT}/scripts/slugify.sh` absolute path if needed).
5. Update path references in consumer SKILL.md files (all `${CLAUDE_PLUGIN_ROOT}/scripts/<moved-script>.sh` → `${CLAUDE_PLUGIN_ROOT}/skills/managing-source-control/scripts/<script>.sh`):
   - `plugins/lwndev-sdlc/skills/executing-chores/SKILL.md` — `build-branch-name.sh`, `ensure-branch.sh`, `commit-work.sh`
   - `plugins/lwndev-sdlc/skills/executing-bug-fixes/SKILL.md` — same three
   - `plugins/lwndev-sdlc/skills/implementing-plan-phases/SKILL.md` — `build-branch-name.sh`, `ensure-branch.sh`
6. Update path references inside `plugins/lwndev-sdlc/skills/implementing-plan-phases/scripts/commit-and-push-phase.sh` if it calls `commit-work.sh` by path.
7. Confirm existing Bats tests that stub these scripts still resolve correctly after the move (update fixture paths in any relevant `tests/bats/skills/` test file).
8. Run `npm test` (full suite) and `npx bats tests/bats/skills/` — all must remain green.

#### Deliverables
- [x] `plugins/lwndev-sdlc/skills/managing-source-control/scripts/ensure-branch.sh` (moved from `plugins/lwndev-sdlc/scripts/`)
- [x] `plugins/lwndev-sdlc/skills/managing-source-control/scripts/build-branch-name.sh` (moved)
- [x] `plugins/lwndev-sdlc/skills/managing-source-control/scripts/commit-work.sh` (moved)
- [x] `executing-chores/SKILL.md`, `executing-bug-fixes/SKILL.md`, `implementing-plan-phases/SKILL.md` — path references updated to new skill location
- [x] Existing tests remain green post-move

---

### Phase 3: PR dispatchers — GitHub path + create-pr/view-pr rewrite
**Feature:** [FEAT-033](../features/FEAT-033-add-managing-source-control.md) | [#120](https://github.com/lwndev/lwndev-marketplace/issues/120)
**Status:** ✅ Complete
**Depends on:** Phase 1
**ComplexityOverride:** opus

> Justification: 8 steps cover 2 new dispatcher scripts with full GitHub path + graceful-skip paths, 2 reference template docs, and 2 Bats suites; the PR body template work is tightly coupled to `create-pr.sh` and cannot land separately.

#### Rationale
- GitHub is the only backend used by every existing consumer; landing the GitHub path first means the full test suite validates the refactor with real fixtures before the Azure DevOps path (Phase 4) adds complexity.
- `create-pr.sh` and `view-pr.sh` are the two dispatchers most heavily exercised in existing tests — getting them green first de-risks the later phases.
- PR body templates belong here because `create-pr.sh` depends on them.

#### Implementation Steps
1. Rewrite `plugins/lwndev-sdlc/scripts/create-pr.sh` as a thin dispatcher that delegates to `plugins/lwndev-sdlc/skills/managing-source-control/scripts/create-pr.sh` (keep old path as a shim for one phase; remove in Phase 5).
2. Create `plugins/lwndev-sdlc/skills/managing-source-control/scripts/create-pr.sh`:
   - Call `backend-detect.sh`; branch on `backend` field.
   - GitHub path: preserve current `create-pr.sh` behavior exactly — `git push -u origin <branch>`, read PR body template, substitute placeholders, call `gh pr create --title ... --body ...`; emit URL on stdout; exit 0. Accept `--closes <issueRef>` and `--issue-ref <ref>` flags (FR-6 auto-close token via `--closes`).
   - NFR-1 skip paths: `gh` not on PATH → `[warn] GitHub CLI (gh) not found on PATH.` exit 0; `gh` not authenticated → `[warn] GitHub CLI not authenticated -- run gh auth login.` exit 0.
   - Azure DevOps path: stub — emit `[warn] Azure DevOps PR creation not yet implemented.` exit 0.
   - Unrecognized backend / `null` → `[info] No recognized SCM backend detected from origin.` exit 0.
3. Create `plugins/lwndev-sdlc/skills/managing-source-control/scripts/view-pr.sh`:
   - Call `backend-detect.sh`; branch on `backend`.
   - Accept `<pr-number>` positional arg (optional for GitHub — `gh pr view` infers from the current branch).
   - GitHub path: `gh pr view [<N>] --json number,title,state,mergeable,url,files` — projection chosen to be the union of all consumer reads (`preflight-checks.sh:152` reads `number,title,state,mergeable,url`; `reconcile-affected-files.sh:65` reads `files`). Emit JSON on stdout; exit 0 on success.
   - NFR-1 skip paths same as `create-pr.sh`.
   - Azure DevOps path: stub — emit `[warn] Azure DevOps PR view not yet implemented.` exit 0.
4. Write `references/pr-templates-github.md`:
   - Carry over current `plugins/lwndev-sdlc/scripts/assets/pr-body.tmpl` content (the `${TYPE}`, `${ID}`, `${SUMMARY}`, `${CLOSES_LINE}`, `${GENERATED_WITH}` template).
   - Document placeholder substitution semantics.
   - Document `Closes #N` auto-close syntax.
5. Write `references/pr-templates-azdo.md`:
   - Azure DevOps flavor: `AB#<id>` or Jira key in PR body.
   - Preserve Summary / Test Plan / Changes section structure.
   - Document `--issue-ref` flag behavior for auto-close token selection.
6. Write `tests/bats/skills/managing-source-control/create-pr.bats`:
   - `gh` stub on PATH, GitHub origin → PR URL on stdout, exit 0.
   - `gh` not on PATH (GitHub origin) → `[warn]` line on stderr, exit 0.
   - `az` stub on PATH, Azure DevOps origin → stub `[warn]` path (not-yet-implemented), exit 0.
   - Unrecognized origin → `[info]` skip, exit 0.
7. Write `tests/bats/skills/managing-source-control/view-pr.bats`:
   - `gh` stub success → GitHub-shape JSON on stdout.
   - `gh` absent (GitHub origin) → `[warn]` skip, exit 0.
   - Azure DevOps stub path → `[warn]` not-yet-implemented, exit 0.
8. Run `npm test` and `npx bats tests/bats/skills/managing-source-control/`.

#### Deliverables
- [x] `plugins/lwndev-sdlc/skills/managing-source-control/scripts/create-pr.sh` — dispatcher; GitHub path fully functional; AzDO path stubbed
- [x] `plugins/lwndev-sdlc/skills/managing-source-control/scripts/view-pr.sh` — dispatcher; GitHub path functional; AzDO path stubbed
- [x] `plugins/lwndev-sdlc/skills/managing-source-control/references/pr-templates-github.md`
- [x] `plugins/lwndev-sdlc/skills/managing-source-control/references/pr-templates-azdo.md`
- [x] `tests/bats/skills/managing-source-control/create-pr.bats` — 4 cases pass
- [x] `tests/bats/skills/managing-source-control/view-pr.bats` — 3 cases pass

---

### Phase 4: Remaining PR dispatchers + Azure DevOps path
**Feature:** [FEAT-033](../features/FEAT-033-add-managing-source-control.md) | [#120](https://github.com/lwndev/lwndev-marketplace/issues/120)
**Status:** Pending
**Depends on:** Phase 3
**ComplexityOverride:** opus

> Justification: 8 steps cover 3 new dispatcher scripts, AzDO implementation of 2 Phase 3 stubs, a shared JSON shape transformer, a full NFR-1 skip matrix for all 5 dispatchers (2 backends × ~5 failure modes each), and 3 new Bats suites plus extensions to 2 existing ones; the AzDO path must land atomically across all dispatchers to keep the shape transformer consistent.

#### Rationale
- `merge-pr.sh`, `list-pr.sh`, and `pr-diff.sh` are structurally identical to `view-pr.sh` but touch different CLI operations — grouping them here keeps Phase 3 focused on the two most complex dispatchers.
- The AzDO path for all five dispatchers lands together so the JSON-shape transformer (`az` output → GitHub-equivalent shape) is written once and tested across all five scripts.
- NFR-1 graceful-skip paths are fully exercised this phase for all dispatchers.

#### Implementation Steps
1. Create `plugins/lwndev-sdlc/skills/managing-source-control/scripts/merge-pr.sh`:
   - GitHub path: `gh pr merge <N> --merge --delete-branch`; exit 0 on success.
   - AzDO path: `az repos pr update --id <N> --status completed --delete-source-branch true --squash false`; transform result; exit 0. `--squash false` opts out of squash to maximize parity with `gh --merge` (which creates a merge commit), but the branch policy's default merge strategy ultimately governs — see Risk Assessment for the asymmetry.
   - Preserve the existing `finalize.sh` stderr-capture pattern so the parent workflow can surface merge failures with the same diagnostic shape it does today.
   - NFR-1 skip paths for both backends (tool absent, not-auth, etc.).
2. Create `plugins/lwndev-sdlc/skills/managing-source-control/scripts/list-pr.sh`:
   - Accept `--head <branch>` flag.
   - GitHub path: `gh pr list --head <branch> --json number,state`; emit JSON array on stdout.
   - AzDO path: `az repos pr list --source-branch <branch> --status active`. The `--source-branch` flag takes the **bare branch name**, NOT `refs/heads/<branch>` (verified against `az repos pr` reference docs). `--status active` matches GitHub's default of listing open PRs only; callers who need closed/merged PRs can be extended later. Normalize to `[{"number":<N>,"state":"OPEN"|"CLOSED"|"MERGED"},...]` via `az-shape-transform.sh` (NFR-3).
   - NFR-1 skips.
3. Create `plugins/lwndev-sdlc/skills/managing-source-control/scripts/pr-diff.sh`:
   - Accept `<pr-number>` positional arg.
   - GitHub path: `gh pr diff <N>`; emit unified diff on stdout.
   - AzDO path: resolve base branch via `base=$(az repos pr show --id <N> --query targetRefName -o tsv)` then strip the `refs/heads/` prefix (`base="${base#refs/heads/}"`). Then `git fetch origin "$base"` (Edge Case 6 — avoid stale diffs) and `git diff "origin/${base}...HEAD"`.
   - NFR-1 skips.
4. Complete the Azure DevOps path for `create-pr.sh` and `view-pr.sh` (replace stubs from Phase 3):
   - `create-pr.sh` AzDO: `az repos pr create --source-branch <branch> --target-branch <base> --title <title> --description <body>`. The command outputs the full PR JSON (not a bare URL); extract the URL via `--query '_links.web.href' -o tsv` (or pipe JSON through `jq -r '._links.web.href'`) and emit a single URL line on stdout for parity with `gh pr create`. Repository, organization, and project resolve from `backend-detect.sh`'s JSON output; project is passed via `--project <name>` and organization via `--organization https://dev.azure.com/<org>/`.
   - `view-pr.sh` AzDO: requires `--id`. When called with no `<pr-number>` arg, dispatcher first resolves the ID for the current branch via `az repos pr list --source-branch "$(git rev-parse --abbrev-ref HEAD)" --status active --top 1 --query '[0].pullRequestId' -o tsv`. If no PR is found, emit a `[warn] no open PR for current branch` and exit 0 (graceful skip). Then `az repos pr show --id <N>`; transform `az` JSON output to GitHub-equivalent shape via `az-shape-transform.sh` (FR-5 transform table — `status`→`state`, `mergeStatus`→`mergeable`, `_links.web.href`→`url`, etc.). The `files` field is reconstructed via `git diff --name-only origin/<targetRefName-stripped>...HEAD` since `az repos pr show` does not include changed files.
   - Implement the JSON shape transformer as a sourced helper `plugins/lwndev-sdlc/skills/managing-source-control/scripts/az-shape-transform.sh`. The transform is too large to inline (six fields, three different normalization rules, plus a `git diff` reconstruction for `files`) — promoting it to a helper makes it testable in isolation and keeps each dispatcher's body small.
5. Add NFR-1 graceful-skip paths for Azure DevOps in all five dispatchers. Each dispatcher checks in order:
   - `az` not on PATH → detect via `command -v az >/dev/null 2>&1 || …`. Emit `[warn] Azure CLI (az) not found on PATH.` exit 0.
   - `azure-devops` extension auto-install failure → the extension auto-installs on first use per MS docs; detect failure by running `az repos pr -h >/dev/null 2>&1` (cheap discovery probe). On non-zero exit, emit `[warn] az devops extension not available -- run az extension add --name azure-devops.` exit 0.
   - `az` not logged in → detect via `az account show >/dev/null 2>&1` (covers `az login`) or fall back to attempting the actual `az repos pr` command and matching the auth-error pattern in stderr. Emit `[warn] Azure CLI not authenticated -- run az login (Azure AD) or az devops login --pat <token>.` exit 0.
   - Network / non-zero CLI exit → `[warn]` with the first line of `az` stderr; exit 0.
6. Write Bats tests for new dispatchers (one file per dispatcher):
   - `tests/bats/skills/managing-source-control/merge-pr.bats` — `gh` stub success; `gh` absent; `az` stub success; `az` absent; `az devops` missing; `az` not logged in.
   - `tests/bats/skills/managing-source-control/list-pr.bats` — same matrix; verify normalized JSON shape from `az` path.
   - `tests/bats/skills/managing-source-control/pr-diff.bats` — `gh` path calls `gh pr diff`; `az` path uses `git diff origin/<base>...HEAD`; pre-fetch on `az` path.
7. Extend `view-pr.bats` and `create-pr.bats` with AzDO-path test cases (now that the stubs are replaced).
8. Run `npm test` and `npx bats tests/bats/skills/managing-source-control/`.

#### Deliverables
- [ ] `plugins/lwndev-sdlc/skills/managing-source-control/scripts/merge-pr.sh` — GitHub + AzDO paths; all NFR-1 skips
- [ ] `plugins/lwndev-sdlc/skills/managing-source-control/scripts/list-pr.sh` — GitHub + AzDO paths; normalized JSON shape
- [ ] `plugins/lwndev-sdlc/skills/managing-source-control/scripts/pr-diff.sh` — GitHub + AzDO paths; pre-fetch on AzDO path
- [ ] `create-pr.sh` and `view-pr.sh` AzDO stubs replaced with real `az` implementations
- [ ] `tests/bats/skills/managing-source-control/merge-pr.bats`, `list-pr.bats`, `pr-diff.bats` — all matrix cases pass
- [ ] Updated `create-pr.bats`, `view-pr.bats` with AzDO cases

---

### Phase 5: Consumer refactor
**Feature:** [FEAT-033](../features/FEAT-033-add-managing-source-control.md) | [#120](https://github.com/lwndev/lwndev-marketplace/issues/120)
**Status:** Pending
**Depends on:** Phase 4
**ComplexityOverride:** opus

> Justification: 12 steps touch 7 files (5 scripts + 2 SKILL.md prose) across 4 different skills; each change must be validated together to maintain the FEAT-028 fallback contract in `resolve-pr-number.sh` and the NFR-2 regression gate requires a clean full-suite run at the end.

#### Rationale
- Phase 5 is the "connect the wires" phase — all dispatchers are proven (Phases 3–4); now every consumer skill's inline `gh` call is replaced with a dispatcher call.
- Doing all consumers in one phase keeps the NFR-5 grep check (Phase 6) clean: after this phase the only `gh pr` / `az repos` references inside `plugins/lwndev-sdlc/skills/**` and `plugins/lwndev-sdlc/scripts/**` are inside `managing-source-control/scripts/` (and `managing-work-items/scripts/` for issue ops).
- SKILL.md prose updates are part of this phase because they are load-bearing consumer contracts (per FR-11 path-update scope note in the requirement).

#### Implementation Steps
1. **`finalizing-workflow/scripts/finalize.sh`**: replace `gh pr merge --merge --delete-branch` call (line ~438) with `bash "${CLAUDE_PLUGIN_ROOT}/skills/managing-source-control/scripts/merge-pr.sh" <pr-number>`. Keep git sync (checkout, fetch, pull) in `finalize.sh` — it is backend-agnostic (FR-7). Remove the old `gh` pre-flight inside `finalize.sh` if it was only guarding the merge step.
2. **`finalizing-workflow/scripts/preflight-checks.sh`**: replace `gh pr view --json number,title,state,mergeable,url` calls with `bash "${CLAUDE_PLUGIN_ROOT}/skills/managing-source-control/scripts/view-pr.sh" <pr-number>`. Update `jq` queries on the result if field names changed (they should not — NFR-3 shape stability).
3. **`finalizing-workflow/scripts/reconcile-affected-files.sh`**: replace `gh pr view <N> --json files --jq '.files[].path'` with `view-pr.sh <N>` then extract `.files[].path` from the normalized JSON.
4. **`finalizing-workflow/SKILL.md`**: remove inline `gh pr view` prose from any Quick Start or reference section; point to `view-pr.sh` invocation instead.
5. **`reviewing-requirements/scripts/pr-diff-vs-plan.sh`**: replace `gh pr diff "$PR_NUM"` with `bash "${CLAUDE_PLUGIN_ROOT}/skills/managing-source-control/scripts/pr-diff.sh" "$PR_NUM"`.
6. **`reviewing-requirements/scripts/detect-review-mode.sh`**: replace `gh pr list --head "${branch_prefix}/${ID}-*" --json number,state --jq ...` with `bash "${CLAUDE_PLUGIN_ROOT}/skills/managing-source-control/scripts/list-pr.sh" --head "${branch_prefix}/${ID}-*"` and parse the normalized JSON array.
7. **`orchestrating-workflows/scripts/resolve-pr-number.sh`**: replace `gh pr list --head "$branch" --state open --json number --limit 2` with `bash "${CLAUDE_PLUGIN_ROOT}/skills/managing-source-control/scripts/list-pr.sh" --head "$branch"`. Preserve FEAT-028 FR-4 fallback chain and the `[warn] resolve-pr-number: gh unavailable …` contract (re-emit via the dispatcher's `[warn]` line).
7a. **`reviewing-requirements/scripts/verify-references.sh`**: replace the inline `gh auth status` + `gh issue view "$num" --json number,state` block (lines 266-300 in the current file) with a delegation to `managing-work-items/scripts/fetch-issue.sh`. The refactor:
   - Calls `bash "${CLAUDE_PLUGIN_ROOT}/skills/managing-work-items/scripts/fetch-issue.sh" "#${num}"` per ghRef (the `#N` prefix triggers GitHub backend in `managing-work-items/scripts/backend-detect.sh`).
   - Maps `fetch-issue.sh` exit codes / stderr `[warn]` markers back to the existing `OK_LINES` / `MISSING_LINES` / `UNAVAILABLE_LINES` classification: stdout JSON with valid `state` → OK; `[warn] ... not found` → MISSING; `[warn] gh ... unavailable / not authenticated` → UNAVAILABLE.
   - Update Bats coverage for `verify-references.sh` to stub `fetch-issue.sh` (in `tests/bats/skills/reviewing-requirements/verify-references.bats`) instead of stubbing `gh` directly.
   - This refactor closes the NFR-5 gap: after this step, the only `gh issue` / `gh pr` / `az repos` references in the tree are inside the two source-of-truth dirs.
8. **`implementing-plan-phases/SKILL.md`**: update `${CLAUDE_PLUGIN_ROOT}/scripts/create-pr.sh` path reference → `${CLAUDE_PLUGIN_ROOT}/skills/managing-source-control/scripts/create-pr.sh`. (Script `build-branch-name.sh` and `ensure-branch.sh` paths were updated in Phase 2.)
9. **`executing-chores/SKILL.md`**: update `create-pr.sh` path reference to new skill location (branch/commit paths already updated in Phase 2).
10. **`executing-bug-fixes/SKILL.md`**: same as executing-chores.
11. Remove the old plugin-level `plugins/lwndev-sdlc/scripts/create-pr.sh` shim (it was a thin dispatcher from Phase 3; now consumers call the skill directly).
12. Run full `npm test` and `npx bats tests/bats/skills/` — all must remain green (NFR-2 regression gate).

#### Deliverables
- [ ] `finalizing-workflow/scripts/finalize.sh` — `merge-pr.sh` delegation; git sync stays
- [ ] `finalizing-workflow/scripts/preflight-checks.sh` — `view-pr.sh` delegation
- [ ] `finalizing-workflow/scripts/reconcile-affected-files.sh` — `view-pr.sh` delegation
- [ ] `finalizing-workflow/SKILL.md` — inline `gh pr view` prose removed
- [ ] `reviewing-requirements/scripts/pr-diff-vs-plan.sh` — `pr-diff.sh` delegation
- [ ] `reviewing-requirements/scripts/detect-review-mode.sh` — `list-pr.sh` delegation
- [ ] `orchestrating-workflows/scripts/resolve-pr-number.sh` — `list-pr.sh` delegation; FEAT-028 fallback contract preserved
- [ ] `reviewing-requirements/scripts/verify-references.sh` — delegates to `managing-work-items/scripts/fetch-issue.sh`; classification semantics preserved; Bats updated to stub `fetch-issue.sh`
- [ ] `implementing-plan-phases/SKILL.md`, `executing-chores/SKILL.md`, `executing-bug-fixes/SKILL.md` — `create-pr.sh` path references updated
- [ ] Plugin-level `scripts/create-pr.sh` shim removed
- [ ] All existing tests pass (NFR-2)

---

### Phase 6: NFR-5 enforcing check + final validation
**Feature:** [FEAT-033](../features/FEAT-033-add-managing-source-control.md) | [#120](https://github.com/lwndev/lwndev-marketplace/issues/120)
**Status:** Pending
**Depends on:** Phase 5
**ComplexityOverride:** opus

> Justification: the deliverables count (6 checked items) is driven by the 3-step validation gauntlet (`validate`, `test`, `lint`) that must all pass on the same codebase state, plus a new TypeScript validate script, its unit test, and the `package.json` wire-up; splitting the validator from its test would leave an untested gate in the build.

#### Rationale
- NFR-5 requires a build-time enforcing check — documenting the rule alone is insufficient. Landing the check as the final phase means it runs against an already-clean codebase and immediately fails if any regression is introduced.
- Mirrors `validate-test-layout.ts` in structure and wire-up pattern (invoked by `npm run validate`).

#### Implementation Steps
1. Create `scripts/validate-no-inline-scm.ts`:
   - Walk `plugins/lwndev-sdlc/skills/**` and `plugins/lwndev-sdlc/scripts/**` for files containing `gh pr`, `gh issue`, `az repos`, or `az boards`.
   - Allow-list: `managing-source-control/scripts/**` and `managing-work-items/scripts/**`.
   - On any match outside the allow-list: print `[error] inline SCM call in <path>: <matched-line>` and exit 1.
   - No matches: exit 0 with `[info] No inline SCM calls found outside source-of-truth directories.`
2. Wire into `package.json` `validate` script: add `&& tsx scripts/validate-no-inline-scm.ts` (or `ts-node`, whichever the project uses for validate scripts — check `package.json` `validate` script syntax).
3. Write unit test `tests/unit/validate-no-inline-scm.test.ts`:
   - Confirm a file with `gh pr create` outside the allow-list triggers exit 1.
   - Confirm a file with `gh pr create` inside `managing-source-control/scripts/` passes (exit 0).
   - Confirm a file with `az repos pr create` outside the allow-list triggers exit 1.
   - Confirm a clean tree exits 0.
4. Run `npm run validate` — must pass end-to-end with the enforcing check enabled.
5. Run `npm test` — full suite must pass including the new unit test.
6. Run `npm run lint` — no lint errors.

#### Deliverables
- [ ] `scripts/validate-no-inline-scm.ts` — exits 1 on inline `gh pr`/`gh issue`/`az repos`/`az boards` outside allow-list
- [ ] `package.json` — `validate` script includes `validate-no-inline-scm.ts`
- [ ] `tests/unit/validate-no-inline-scm.test.ts` — 4 cases pass
- [ ] `npm run validate` passes
- [ ] `npm test` passes
- [ ] `npm run lint` passes


## Shared Infrastructure

- `managing-source-control/scripts/backend-detect.sh` — shared primitive called by all five PR dispatchers. Mirrors `managing-work-items/scripts/backend-detect.sh` JSON-output contract. (Exit semantics differ: this script takes no arg and exits 0 on all detection outcomes, exit 2 only on internal parse error.)
- `managing-source-control/scripts/az-shape-transform.sh` — sourced helper, called by `view-pr.sh` and `list-pr.sh` on the AzDO path. Normalizes `az repos pr show` / `az repos pr list` output to the GitHub `gh pr view --json` / `gh pr list --json` shape per the FR-5 transform table (NFR-3). Field map: `pullRequestId`→`number`, `title`→`title`, `status`→`state` (active→OPEN, abandoned→CLOSED, completed→MERGED), `mergeStatus`→`mergeable` (succeeded→MERGEABLE, conflicts→CONFLICTING, queued/notSet→UNKNOWN), `_links.web.href`→`url`. The `files` field is not in `az repos pr show` output and is reconstructed via `git diff --name-only origin/<targetRefName-stripped>...HEAD`, emitted as `[{"path":"..."}, ...]`. Unit-tested via Bats at `tests/bats/skills/managing-source-control/az-shape-transform.bats`.
- `plugins/lwndev-sdlc/scripts/assets/pr-body.tmpl` — still used by the GitHub path of `create-pr.sh`; now also referenced from `references/pr-templates-github.md`.
- `jq` — already a hard dependency; reused for AzDO JSON transformation.

## Testing Strategy

**Unit tests (Vitest):**
- `tests/unit/managing-source-control.test.ts` — SKILL.md frontmatter, directory layout, `ai-skills-manager validate()`.
- `tests/unit/validate-no-inline-scm.test.ts` — enforcing check behavior.

**Bats tests (per script):**
- `tests/bats/skills/managing-source-control/backend-detect.bats`
- `tests/bats/skills/managing-source-control/create-pr.bats`
- `tests/bats/skills/managing-source-control/view-pr.bats`
- `tests/bats/skills/managing-source-control/merge-pr.bats`
- `tests/bats/skills/managing-source-control/list-pr.bats`
- `tests/bats/skills/managing-source-control/pr-diff.bats`
- `tests/bats/skills/managing-source-control/ensure-branch.bats` (confirm behavior unchanged post-move)
- `tests/bats/skills/managing-source-control/commit-work.bats` (confirm behavior unchanged post-move)
- `tests/bats/skills/managing-source-control/build-branch-name.bats` (confirm behavior unchanged post-move)
- `tests/bats/skills/managing-source-control/az-shape-transform.bats` (FR-5 transform table — verifies each field map produces the GitHub-equivalent shape; covers all enum branches of `status` and `mergeStatus`; covers the `files` reconstruction path)
- `tests/bats/skills/reviewing-requirements/verify-references.bats` (regression coverage for the Phase 5 step 7a refactor — stubs `fetch-issue.sh` instead of `gh` and confirms OK / MISSING / UNAVAILABLE classification preserved)

**Regression gate:** every phase ends with a full `npm test` run. Phase 5 is the critical regression gate for NFR-2 (GitHub workflow chains must remain green after the consumer refactor).

**Manual testing (post Phase 5):**
- Full feature chain on a real GitHub repo.
- Full feature chain on a real Azure DevOps repo (`az login` + `azure-devops` extension required).
- Force NFR-1 skip paths: remove `gh` from PATH, confirm `[warn]` and workflow continues; same for `az`.

## Dependencies and Prerequisites

- `gh` CLI — optional at runtime (GitHub backend); must be on PATH for GitHub integration tests.
- `az` CLI + `azure-devops` extension — optional at runtime (AzDO backend).
- `git` — required (already required by the plugin).
- `jq` — already a hard dep of `managing-work-items`; required for AzDO shape transformation.
- `ai-skills-manager` — `validate()` API used in unit test (already a project dev dep).
- No new npm dependencies are expected.

## Risk Assessment

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Consumer SKILL.md path updates missed — broken path references after script move | High | Medium | FR-11 path-update scope note is explicit; Phase 2 deliverables require green full test run before merging |
| AzDO JSON shape mismatch — `jq` transformer emits fields that break consumer `jq` queries | High | Medium | NFR-3 shape-stability requirement; `view-pr.bats` and `list-pr.bats` verify normalized output shape with `az` stubs |
| Graceful-skip contract broken for a new failure path — workflow halts instead of continuing | High | Low | Every dispatcher's NFR-1 skip paths are Bats-tested; the enforcing check (Phase 6) cannot catch a wrong exit code, but per-dispatcher Bats tests do |
| NFR-5 check allow-list too narrow — flags legitimate `gh`/`az` usage | Medium | Low | Allow-list is two dirs; unit test covers both the positive (blocked) and negative (allowed) cases |
| Phase 5 consumer refactor breaks existing tests (NFR-2 regression) | High | Low | Phase 5 ends with full `npm test`; all consumer skills have existing Bats coverage |
| Merge-strategy asymmetry: `gh pr merge --merge` forces a merge commit; `az repos pr update --status completed` honors branch policy default | Medium | Medium | Pass `--squash false` on the AzDO path for partial parity. Document the asymmetry in operator-facing notes (`references/pr-templates-azdo.md` or a new "Backend Differences" note). Cannot be eliminated without configuring AzDO branch policy, which is out of scope. |

## Success Criteria

- `managing-source-control` skill exists at the FR-10 layout with all 9 scripts and 4 reference docs.
- `backend-detect.sh` correctly identifies GitHub, Azure DevOps (both `dev.azure.com` and `*.visualstudio.com`), and honors `SDLC_SCM_BACKEND` env override.
- All five PR dispatchers function on GitHub repos (regression: existing workflow chains unchanged — NFR-2).
- All five PR dispatchers function on Azure DevOps repos (new capability).
- PR view/list dispatchers emit GitHub-equivalent JSON shape from the `az` path so existing consumer `jq` queries work unchanged (NFR-3).
- No skill contains inline `gh pr`, `gh issue`, `az repos`, or `az boards` calls outside the two source-of-truth dirs; `npm run validate` enforces this (NFR-5).
- `npm test` passes (Vitest + Bats).
- `npm run validate` passes.
- `npm run lint` passes.
