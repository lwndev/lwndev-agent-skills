# Feature Requirements: Add managing-source-control skill

## Overview
Add a new `managing-source-control` skill under `plugins/lwndev-sdlc/skills/` that centralizes all git and pull-request operations, dispatching between GitHub (`gh` CLI) and Azure DevOps (`az` CLI) backends. Mirrors the multi-backend pattern of `managing-work-items`, and unblocks Azure DevOps users who today cannot use this plugin at all because every PR call hard-codes `gh`.

## Feature ID
`FEAT-033`

## GitHub Issue
[#120](https://github.com/lwndev/lwndev-marketplace/issues/120)

## Priority
High - Required to support Azure DevOps repositories. The plugin currently cannot be used on Azure DevOps at all because every PR-touching script hard-codes `gh`. Also a structural prerequisite for future SCM backends (GitLab, Bitbucket).

## User Story
As a plugin maintainer working in an Azure DevOps repository, I want every git and PR operation in the SDLC plugin to dispatch through one source-control skill so that I can run the full feature/chore/bug workflow chain against `dev.azure.com` the same way GitHub users run it against `github.com`.

As a workflow consumer (`implementing-plan-phases`, `executing-chores`, `executing-bug-fixes`, `finalizing-workflow`, `reviewing-requirements`), I want a single delegation surface for git and PR work so that no skill contains inline `gh` or `az` calls and graceful-degradation behavior is uniform.

## Skill Capabilities

This is an internal infrastructure feature, not a user-facing CLI. The skill exposes its surface area through scripts under `managing-source-control/scripts/`. Consumer skills invoke those scripts directly (the same inline-invocation pattern as `managing-work-items`).

### Script Entry Points

| Script | Purpose | Dispatch |
|--------|---------|----------|
| `backend-detect.sh` | Parse `git remote get-url origin` and `SDLC_SCM_BACKEND` env var; emit JSON identifying the backend. | n/a (pure parser) |
| `ensure-branch.sh` | Idempotently create or check out a branch with `feat/`/`chore/`/`fix/` prefix. | backend-agnostic |
| `build-branch-name.sh` | Build canonical branch name from `<type>` + `<ID>` + slug. | backend-agnostic |
| `commit-work.sh` | Stage, commit (conventional format), verify success. | backend-agnostic |
| `create-pr.sh` | Open a pull request. | dispatched (`gh pr create` / `az repos pr create`) |
| `merge-pr.sh` | Merge a pull request and delete the source branch. | dispatched (`gh pr merge --merge --delete-branch` / `az repos pr update --status completed --delete-source-branch true`) |
| `view-pr.sh` | Fetch PR state, reviews, file list. | dispatched (`gh pr view --json ...` / `az repos pr show`) |
| `list-pr.sh` | List PRs filtered by head branch. | dispatched (`gh pr list --head ...` / `az repos pr list --source-branch ...`) |
| `pr-diff.sh` | Emit unified diff of the PR against its base. | dispatched (`gh pr diff` / `git diff origin/<base>...HEAD` since Azure DevOps lacks a `gh pr diff` equivalent) |

## Functional Requirements

### FR-1: Backend Detection
- Parse `git remote get-url origin`:
  - `github.com` (HTTPS or SSH) → `github`
  - `dev.azure.com` (HTTPS), `*.visualstudio.com` (HTTPS), or `ssh.dev.azure.com` (SSH `v3/<org>/<project>/<repo>` form) → `azdo`
- Honor `SDLC_SCM_BACKEND=github|azdo` environment override (mirrors/multi-remote support). **Semantics**: the override flips the *backend label* only; URL parse still runs to populate identity fields against the overridden backend's pattern. If the URL does not match that backend's pattern, emit literal `null` and log `[warn] SDLC_SCM_BACKEND=<x> set but origin does not match <x> URL pattern.` The override never invents identity values out of thin air.
- Emit JSON on stdout matching `managing-work-items/scripts/backend-detect.sh` style:
  - GitHub: `{"backend": "github", "owner": "...", "repo": "..."}`
  - Azure DevOps: `{"backend": "azdo", "organization": "...", "project": "...", "repo": "..."}` — `organization` is the bare name (e.g. `contoso`); dispatchers construct the `--organization https://dev.azure.com/<org>/` URL form when invoking `az`.
  - Unrecognized remote / no origin: literal `null` (exit 0; caller decides whether to proceed).
- Exit 0 in all detection cases. Non-zero only on internal errors.

### FR-2: Branch Management (backend-agnostic)
- `ensure-branch.sh` creates branches with conventional prefixes (`feat/`, `chore/`, `fix/`), matching existing `plugins/lwndev-sdlc/scripts/ensure-branch.sh` semantics.
- Verifies clean working tree before branch creation. Refuses dirty trees with a `[warn]` line.
- Idempotent: if the branch already exists, checks it out instead of failing.
- `build-branch-name.sh` continues to produce `<type>/<ID>-<slug>` form unchanged.

### FR-3: Commit Operations (backend-agnostic)
- `commit-work.sh` writes conventional-commit-format messages: `feat(<ID>): …`, `chore(<ID>): …`, `fix(<ID>): …`.
- Stages explicit paths (no `git add -A`), runs `git commit`, verifies non-zero stdout from `git rev-parse HEAD`.
- On pre-commit hook failure, surfaces the hook stderr and exits non-zero (does NOT `--no-verify`).

### FR-4: Push Operations (backend-agnostic)
- Initial push uses `git push -u origin <branch>` to set upstream tracking.
- Subsequent pushes use `git push`.
- Non-fast-forward recovery: `git fetch && git rebase origin/<branch> && git push`. If rebase produces conflicts, surface stderr verbatim and exit non-zero.

### FR-5: Pull Request Operations (backend-dispatched)
All PR dispatchers call `backend-detect.sh`, branch on the `backend` field, and forward to the appropriate CLI:

| Operation | GitHub | Azure DevOps |
|-----------|--------|--------------|
| Create | `gh pr create --title --body --base` | `az repos pr create --source-branch <branch> --target-branch <base> --title --description` — emit URL by extracting `_links.web.href` from the returned JSON (the `az` command outputs the full PR object, not a bare URL). |
| View / state | `gh pr view <N> --json number,title,state,mergeable,url,files` | `az repos pr show --id <N>` (transform fields to GitHub-equivalent JSON shape per the table below). On the no-arg form, dispatcher first resolves `<N>` via `az repos pr list --source-branch <current-branch> --status active`. |
| List by head | `gh pr list --head <branch> --json number,state` | `az repos pr list --source-branch <branch> --status active` (filter/transform). `--source-branch` takes the **bare branch name** — not `refs/heads/<branch>`. |
| Diff | `gh pr diff <N>` | Dispatcher resolves base via `az repos pr show --id <N> --query targetRefName -o tsv`, strips `refs/heads/`, then runs `git fetch origin <base>` followed by `git diff origin/<base>...HEAD`. |
| Merge | `gh pr merge <N> --merge --delete-branch` | `az repos pr update --id <N> --status completed --delete-source-branch true --squash false`. **Semantic asymmetry**: `gh --merge` explicitly creates a merge commit; `az repos pr update` honors the branch policy's default merge strategy unless overridden. Passing `--squash false` opts out of squash but cannot force a merge commit if the policy forbids it. Document this in operator-facing notes. |

Output shape for view/list MUST be normalized to a GitHub-equivalent JSON so existing consumer scripts (`preflight-checks.sh`, `reconcile-affected-files.sh`, `detect-review-mode.sh`) continue to read the same fields.

**AzDO → GitHub shape transform** (used by `view-pr.sh` and `list-pr.sh` on the AzDO path):

| Consumer field (GitHub shape) | AzDO source | Transform |
|---|---|---|
| `number` | `pullRequestId` | direct copy (integer) |
| `title` | `title` | direct copy |
| `state` | `status` | `active`→`OPEN`, `abandoned`→`CLOSED`, `completed`→`MERGED` |
| `mergeable` | `mergeStatus` | `succeeded`→`MERGEABLE`, `conflicts`→`CONFLICTING`, `queued`/`notSet`→`UNKNOWN` |
| `url` | `_links.web.href` | direct copy |
| `files` | *(not in `az repos pr show` output)* | reconstruct via `git diff --name-only origin/<targetRefName-stripped>...HEAD`; emit `[{"path":"..."}, ...]` |

The transform is large enough that the implementation extracts it into a sourced helper (`scripts/az-shape-transform.sh`) rather than inlining `jq` pipelines in each dispatcher.

### FR-6: Auto-Close Issue Linkage in PR Body
- GitHub: `Closes #<N>` (already produced by `managing-work-items pr-link`).
- Azure DevOps: `AB#<workitem-id>` when the work-item backend is Azure Boards; the Jira issue key (e.g. `PROJ-123`) when the work-item backend is Jira (Jira and Azure Boards both auto-close on `az repos pr update --status completed`).
- The dispatcher accepts a `--issue-ref <ref>` flag and emits the correct auto-close token via the chosen PR-body template (FR-8).

### FR-7: Repository Sync (backend-agnostic)
- After merge, checkout default branch, `git fetch`, `git pull --ff-only`, verify clean state.
- Lives in `finalize.sh` (orchestrated by `finalizing-workflow`); `merge-pr.sh` is responsible only for the merge call itself.

### FR-8: PR Body Templates Per Backend
- `references/pr-templates-github.md` — current `pr-body.tmpl` content (Markdown body with `Closes #N`).
- `references/pr-templates-azdo.md` — Azure DevOps flavor (auto-close via `AB#<id>` or Jira key; preserves the Summary / Test Plan / Changes section structure).
- Placeholder substitution behavior matches existing `create-pr.sh` template handling.

### FR-9: Graceful Degradation (mirrors NFR-1 below)
Every backend-specific failure path logs a tagged `[warn]` or `[info]` line on stderr and exits with the documented exit code per the failure-mode matrix in NFR-1. The workflow continues; only the PR step is skipped.

### FR-10: Skill File Structure
The skill is laid out as:

```
plugins/lwndev-sdlc/skills/managing-source-control/
├── SKILL.md
├── scripts/
│   ├── backend-detect.sh
│   ├── ensure-branch.sh           # moved from plugins/lwndev-sdlc/scripts/
│   ├── build-branch-name.sh       # moved
│   ├── commit-work.sh             # moved
│   ├── create-pr.sh               # rewritten as dispatcher
│   ├── merge-pr.sh                # new (replaces inline gh in finalize.sh)
│   ├── view-pr.sh                 # new (replaces inline gh in preflight-checks.sh / reconcile-affected-files.sh)
│   ├── list-pr.sh                 # new (replaces inline gh in detect-review-mode.sh)
│   └── pr-diff.sh                 # new (replaces inline gh in pr-diff-vs-plan.sh)
└── references/
    ├── branch-conventions.md
    ├── commit-conventions.md
    ├── pr-templates-github.md
    └── pr-templates-azdo.md
```

### FR-11: Consumer Refactor — All Skills Delegate
After this change, no skill contains inline `gh` or `az` calls. The following consumers are refactored:

| Consumer | Before | After |
|----------|--------|-------|
| `implementing-plan-phases` | `scripts/commit-and-push-phase.sh` + plugin-level `create-pr.sh` (both `gh`) | Calls `managing-source-control/scripts/commit-work.sh` + `create-pr.sh` (dispatched) |
| `executing-chores` | Plugin-level `build-branch-name.sh`, `ensure-branch.sh`, `commit-work.sh`, `create-pr.sh` (`gh`) | Call sites in scripts update to `managing-source-control/scripts/*` paths and dispatch |
| `executing-bug-fixes` | Same as `executing-chores` | Same outcome |
| `finalizing-workflow` | `scripts/finalize.sh` (`gh pr merge` + git sync), `preflight-checks.sh` (`gh pr view`), `reconcile-affected-files.sh` (`gh pr view --json files`) | Delegate `gh`/`az` calls to `merge-pr.sh` / `view-pr.sh`; git sync stays in `finalize.sh` (backend-agnostic) |
| `reviewing-requirements` | `scripts/pr-diff-vs-plan.sh` (`gh pr diff`), `detect-review-mode.sh` (`gh pr list`), `verify-references.sh` (`gh issue view --json number,state`) | Delegate to `pr-diff.sh` / `list-pr.sh`. `verify-references.sh` is refactored in the same change to delegate its `gh issue view` call to `managing-work-items/scripts/fetch-issue.sh`, parsing the returned JSON (and exit code) to preserve the existing `OK_LINES` / `MISSING_LINES` / `UNAVAILABLE_LINES` classification. Bats coverage for `verify-references.sh` updates to stub `fetch-issue.sh` instead of `gh`. This closes the NFR-5 enforcing-check gap (the file currently lives in `reviewing-requirements/scripts/`, outside the allow-list). |
| `orchestrating-workflows` | `scripts/resolve-pr-number.sh` (`gh pr list --head` lookup at lines 50, 102) | Delegate the `gh pr list` lookup to `list-pr.sh`; preserve the FEAT-028 FR-4 fallback chain and the `[warn] resolve-pr-number: gh unavailable …` contract. |

**Path-update scope (per consumer)**: This refactor moves scripts from `plugins/lwndev-sdlc/scripts/` to `plugins/lwndev-sdlc/skills/managing-source-control/scripts/`. The "Before → After" entries above cover both the script bodies and the inline `${CLAUDE_PLUGIN_ROOT}/scripts/<script>.sh` path references in consumer `SKILL.md` prose (e.g. `executing-chores/SKILL.md`, `executing-bug-fixes/SKILL.md`, `implementing-plan-phases/SKILL.md` all reference `build-branch-name.sh`, `ensure-branch.sh`, `commit-work.sh`, `create-pr.sh` by current paths and MUST be updated to the new `${CLAUDE_PLUGIN_ROOT}/skills/managing-source-control/scripts/` paths in the same change). Failure to update SKILL.md path references will break the consumer skills even when the script bodies are correct.

The plugin-level `plugins/lwndev-sdlc/scripts/` directory shrinks correspondingly (the PR-touching scripts move into the skill). `branch-id-parse.sh` and other purely-local helpers stay where they are.

### FR-12: Orchestrator Integration
- `orchestrating-workflows` `Read`s `managing-source-control/SKILL.md` once at workflow start (same inline pattern as `managing-work-items/SKILL.md` — **not** an Agent fork).
- Calls `managing-source-control/scripts/<dispatcher>.sh` at each workflow integration point: branch creation, commit, push, PR create, PR diff (for `reviewing-requirements`), PR merge (for `finalizing-workflow`).

## Output Format

`backend-detect.sh` JSON (single line, no trailing whitespace):
```
{"backend":"github","owner":"lwndev","repo":"lwndev-marketplace"}
{"backend":"azdo","organization":"contoso","project":"sdlc-tools","repo":"plugin-repo"}
null
```

Tagged log lines (stderr) follow the existing repo convention:
```
[info] No recognized SCM backend detected from origin.
[warn] GitHub CLI (gh) not found on PATH.
[warn] Azure CLI not authenticated -- run az login.
```

PR-create stdout (both backends; consumers parse the URL line). The numeric IDs below are illustrative example values, not links to existing PRs:
```
https://github.com/lwndev/lwndev-marketplace/pull/127   # example
https://dev.azure.com/contoso/sdlc-tools/_git/plugin-repo/pullrequest/42   # example
```

## Non-Functional Requirements

### NFR-1: Graceful Degradation Matrix
| Failure | Backend | Response |
|---------|---------|----------|
| `gh` not on PATH | GitHub | `[warn] GitHub CLI (gh) not found on PATH.` Skip PR step. Exit 0. |
| `gh` not authenticated | GitHub | `[warn] GitHub CLI not authenticated -- run gh auth login.` Skip. Exit 0. |
| `az` not on PATH | Azure DevOps | `[warn] Azure CLI (az) not found on PATH.` Skip PR step. Exit 0. |
| `az` devops extension auto-install failed | Azure DevOps | The `azure-devops` extension auto-installs on first use of `az repos pr` per MS docs. This warning fires only when auto-install fails (no network, no admin permission, locked install dir, etc.): `[warn] az devops extension not available -- run az extension add --name azure-devops.` Skip. Exit 0. |
| `az` not logged in | Azure DevOps | `[warn] Azure CLI not authenticated -- run az login (Azure AD) or az devops login --pat <token> (PAT-based).` Skip. Exit 0. |
| Unrecognized origin remote | Any | `[info] No recognized SCM backend detected from origin.` Skip. Exit 0. |
| Network / not-found / non-zero CLI exit | Any | `[warn]` with the command output; skip; workflow continues. Exit 0. |
| Internal script error (jq parse, missing arg) | Any | Surface stderr verbatim. Exit non-zero. |

The "skip + exit 0" contract matches `managing-work-items` and ensures graceful-degradation never halts the workflow.

### NFR-2: Backward Compatibility on GitHub Repos
All existing workflow chains (feature, chore, bug) MUST continue to function on a GitHub repo without behavior change. Existing tests covering current scripts must remain green after refactor.

### NFR-3: Output Shape Stability
View/list dispatchers MUST emit JSON in the GitHub `gh pr view --json …` / `gh pr list --json …` shape so existing consumer scripts (`preflight-checks.sh`, `reconcile-affected-files.sh`, `detect-review-mode.sh`) do not require restructuring of their `jq` queries. The Azure DevOps dispatchers transform `az` output into the equivalent shape.

### NFR-4: Test Coverage Parity
Bats tests under `tests/bats/skills/managing-source-control/` cover:
- backend detection from URL (SSH form, HTTPS form, `dev.azure.com`, `*.visualstudio.com`, unknown);
- env-var override (`SDLC_SCM_BACKEND=github` and `=azdo`);
- each dispatcher with a `gh` stub on PATH;
- each dispatcher with an `az` stub on PATH;
- each graceful-skip path from the NFR-1 matrix.

Unit test `tests/unit/managing-source-control.test.ts` validates skill frontmatter (`name`, `description`) and directory structure, mirroring `tests/unit/managing-work-items.test.ts`.

### NFR-5: No Inline gh/az Calls Post-Refactor
A repository-wide grep for `gh pr`, `gh issue`, `az repos`, `az boards` across `plugins/lwndev-sdlc/skills/**` and `plugins/lwndev-sdlc/scripts/**` MUST return only references inside `managing-source-control/scripts/` and `managing-work-items/scripts/` (the latter owns issue-tracker calls). The implementation MUST add an enforcing check — either (a) a dedicated `scripts/validate-no-inline-scm.ts` invoked by `npm run validate` (preferred, mirrors `validate-test-layout.ts`), or (b) a CI step in the workflow. Documenting the rule alone is insufficient; the check must fail the build when a regression is introduced.

## Dependencies

- **`managing-work-items` skill** — sibling pattern; this skill mirrors its `backend-detect.sh` shape and graceful-degradation contract.
- **`gh` CLI** (GitHub backend) — optional at runtime; missing/auth failure triggers NFR-1 skip.
- **`az` CLI + `azure-devops` extension** (Azure DevOps backend) — optional at runtime; missing triggers NFR-1 skip.
- **`git`** — required (already required by the plugin).
- **`jq`** — already a hard dependency of `managing-work-items`; reused for JSON shape transformations on the Azure DevOps path.
- **`python3`** — already used by `new-requirement.sh`; not required by this skill.

## Edge Cases
1. **Repo has no `origin` remote** → `backend-detect.sh` emits `null`. Dispatchers log `[info] No recognized SCM backend detected from origin.` and skip. Workflow continues.
2. **`SDLC_SCM_BACKEND` overrides a recognizable remote** → env var wins for the *backend label*; backend-detect still parses the origin URL against the overridden backend's pattern to populate identity fields. If the URL does not match (e.g. `SDLC_SCM_BACKEND=azdo` set on a `github.com` origin), backend-detect emits `null` and logs `[warn] SDLC_SCM_BACKEND=<x> set but origin does not match <x> URL pattern.` Useful for mirrored repos where the origin already points at the desired backend.
3. **Repo origin is GitLab, Bitbucket, or other** → `null` (skipped). Future backends extend the dispatcher.
4. **`gh` is installed but not authenticated** → `gh pr ...` exits non-zero. Dispatcher catches, logs `[warn]`, exits 0.
5. **`az` is installed but `azure-devops` extension is missing** → `az repos pr ...` fails with a recognizable message. Dispatcher detects and emits the documented `[warn]`.
6. **PR diff requested on Azure DevOps where the base branch tip is stale locally** → `pr-diff.sh` resolves the base by calling `az repos pr show --id <N> --query targetRefName -o tsv` (which returns `refs/heads/<base>`), strips the `refs/heads/` prefix, then runs `git fetch origin <base>` before `git diff origin/<base>...HEAD` to avoid stale diffs.
7. **Non-fast-forward push** → `push` operation recovers via fetch+rebase. Rebase conflict surfaces stderr verbatim and exits non-zero (FR-4).
8. **Branch already exists locally** → `ensure-branch.sh` checks it out (idempotent). Branch already exists on remote with different content → push fails non-fast-forward; FR-4 recovery applies.
9. **Auto-close token mismatch** → If the work-item backend is Jira but the SCM backend is GitHub, the PR body still uses `Closes #N` for the GitHub issue *if one exists*, and additionally references the Jira key in the body. Auto-close behavior is best-effort per the table in FR-6.
10. **Issue reference is empty** → PR body omits the auto-close line entirely; no error.
11. **Refactor regression: a consumer skill still calls `gh` directly** → caught by NFR-5 grep check during `npm run validate`.
12. **Consumer script reads a field that the Azure DevOps shape lacks** → the `az`-path dispatcher synthesizes the value through `scripts/az-shape-transform.sh` per the FR-5 shape-transform table (e.g. `mergeable` ← `mergeStatus` with `succeeded`→`MERGEABLE` / `conflicts`→`CONFLICTING` / `queued`/`notSet`→`UNKNOWN`). The `files` field is not in `az repos pr show` output and is reconstructed via `git diff --name-only origin/<targetRefName-stripped>...HEAD`. Consumers tolerating `null` is an additional safety net for any field not in the transform table.

## Testing Requirements

### Unit Tests
- `tests/unit/managing-source-control.test.ts`:
  - SKILL.md frontmatter (name, description) parses cleanly.
  - Directory layout matches FR-10 (scripts present, references present).
  - Mirror coverage of `tests/unit/managing-work-items.test.ts`.

### Integration Tests (Bats)
Under `tests/bats/skills/managing-source-control/`:
- `backend-detect.bats` — SSH origin URL → `github`; HTTPS origin → `github`; `dev.azure.com` → `azdo`; `*.visualstudio.com` → `azdo`; unknown → `null`; env-var override; no remote → `null`.
- `create-pr.bats` — `gh` stub success; `gh` stub absent → `[warn]` skip; `az` stub success; `az` stub absent → `[warn]` skip.
- `merge-pr.bats` — same matrix.
- `view-pr.bats` — same matrix; verify GitHub-equivalent JSON shape from `az` path.
- `list-pr.bats` — same matrix.
- `pr-diff.bats` — `gh` path calls `gh pr diff`; `az` path falls back to `git diff origin/<base>...HEAD`; pre-fetch happens on the `az` path.
- `ensure-branch.bats`, `commit-work.bats`, `build-branch-name.bats` — confirm behavior unchanged after move.

### Regression Tests
- Existing tests for `implementing-plan-phases`, `executing-chores`, `executing-bug-fixes`, `finalizing-workflow`, `reviewing-requirements` continue to pass on a GitHub-style fixture without modification (NFR-2).

### Manual Testing
- Run a full feature chain against a real GitHub repo end-to-end.
- Run a full feature chain against a real Azure DevOps repo end-to-end (requires `az login` and the `azure-devops` extension).
- Force NFR-1 skip paths: uninstall `gh` and confirm workflow continues with `[warn]`; same for `az`.

## Future Enhancements
- Additional backends: GitLab (`glab` CLI), Bitbucket (`bitbucket-cli`), Gitea — all fit the same dispatcher shape.
- Auto-merge / merge-queue support per backend (currently scoped to simple merge + delete-source-branch).
- Draft-PR support uniform across backends.
- PR template auto-detection from `.github/PULL_REQUEST_TEMPLATE.md` / Azure DevOps equivalents.

## Acceptance Criteria
- [ ] `managing-source-control` skill exists at `plugins/lwndev-sdlc/skills/managing-source-control/` with `SKILL.md`, `scripts/`, and `references/` mirroring `managing-work-items`.
- [ ] `backend-detect.sh` parses `git remote get-url origin` to `github` / `azdo` / `null` and honors `SDLC_SCM_BACKEND` env-var override (FR-1).
- [ ] Branch / commit / push scripts (`ensure-branch.sh`, `build-branch-name.sh`, `commit-work.sh`) are backend-agnostic and existing call sites work unchanged (FR-2, FR-3, FR-4).
- [ ] PR dispatchers (`create-pr.sh`, `merge-pr.sh`, `view-pr.sh`, `list-pr.sh`, `pr-diff.sh`) dispatch on backend and produce equivalent behavior across `gh` and `az` (FR-5).
- [ ] Auto-close token in PR body adapts per backend: `Closes #N` for GitHub, `AB#<id>` for Azure Boards, Jira key when work-item backend is Jira (FR-6).
- [ ] `finalize.sh` continues to handle git sync (checkout, fetch, pull) backend-agnostically (FR-7).
- [ ] PR body templates exist per backend at `references/pr-templates-github.md` and `references/pr-templates-azdo.md` with placeholder substitution matching existing `create-pr.sh` template behavior (FR-8).
- [ ] All `gh` / `az` failure modes (missing CLI, not authenticated, missing `az devops` extension, network, not-found) skip gracefully with `[warn]` / `[info]` lines per NFR-1 — workflow continues; only the PR step is skipped.
- [ ] `implementing-plan-phases`, `executing-chores`, `executing-bug-fixes`, `finalizing-workflow`, `reviewing-requirements`, and `orchestrating-workflows` (specifically `resolve-pr-number.sh`) all delegate to the new skill's scripts; no skill contains inline `gh` or `az` calls (FR-11, NFR-5).
- [ ] PR view/list dispatchers emit GitHub-equivalent JSON shape from the `az` path so existing consumer `jq` queries in `preflight-checks.sh`, `reconcile-affected-files.sh`, and `detect-review-mode.sh` work unchanged (NFR-3).
- [ ] An enforcing check (preferred: `scripts/validate-no-inline-scm.ts` invoked by `npm run validate`; fallback: CI step) fails the build when an inline `gh pr`, `gh issue`, `az repos`, or `az boards` call is introduced outside `managing-source-control/scripts/` or `managing-work-items/scripts/` (NFR-5).
- [ ] `orchestrating-workflows` `Read`s the new `SKILL.md` at workflow start (inline pattern, not Agent fork) — same invocation contract as `managing-work-items` (FR-12).
- [ ] Bats tests under `tests/bats/skills/managing-source-control/` cover backend detection, env-var override, each dispatcher with a `gh` stub, each dispatcher with an `az` stub, and each graceful-skip path (NFR-4).
- [ ] Unit test `tests/unit/managing-source-control.test.ts` validates skill frontmatter and structure (NFR-4).
- [ ] All existing workflow chains continue to function on a GitHub repo (regression — NFR-2).
- [ ] All existing workflow chains function on an Azure DevOps repo (new green path).
- [ ] `npm run validate` passes, including any NFR-5 grep check for residual inline `gh` / `az` calls.
- [ ] `npm test` passes (Vitest + Bats).
