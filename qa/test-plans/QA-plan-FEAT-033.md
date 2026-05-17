---
id: FEAT-033
version: 2
timestamp: 2026-05-16T20:50:00Z
persona: qa
---

## User Summary

Adds a `managing-source-control` skill that centralizes all git and pull-request operations behind a backend dispatcher so workflow consumers can run the full feature/chore/bug chain against either GitHub (`gh`) or Azure DevOps (`az`). Plugin maintainers get uniform graceful-degradation behavior when CLI tools are absent, unauthenticated, or fail; consumer skills delegate through nine new scripts rather than holding inline `gh`/`az` calls. A build-time validator (`validate-no-inline-scm.ts`) enforces the new contract by failing `npm run validate` if any inline `gh pr`/`gh issue`/`az repos`/`az boards` call escapes the two source-of-truth directories.

## Capability Report

- Mode: test-framework
- Framework: vitest
- Package manager: npm
- Test command: npm test
- Language: typescript

(Bats tests run alongside Vitest for shell-script coverage — capability discovery reports the primary unit-test framework.)

## Scenarios (by dimension)

### Inputs

- [P0] backend-detect parses malformed origin URL (missing `:`, missing path, trailing slash, port specifier) | mode: test-framework | expected: bats case in backend-detect.bats asserts `null` stdout + exit 0
- [P0] backend-detect with `SDLC_SCM_BACKEND=gitlab` (unknown override value) | mode: test-framework | expected: bats asserts behavior — either `[warn]` on stderr + `null` exit 0, or documented error; current spec only documents `github|azdo` — gap to surface
- [P0] backend-detect with `SDLC_SCM_BACKEND=github` but origin is `dev.azure.com` (label/URL mismatch) | mode: test-framework | expected: bats asserts `null` + `[warn] SDLC_SCM_BACKEND=github set but origin does not match github URL pattern.` on stderr, exit 0
- [P0] create-pr.sh PR title with single quotes, backticks, and `$(date)` injection attempt | mode: test-framework | expected: bats stubs `gh` and asserts the argv received by the stub preserves the literal string (no shell expansion)
- [P0] create-pr.sh `--closes` flag receives empty string or whitespace-only issue ref | mode: test-framework | expected: bats asserts the placeholder is rendered as empty or the script rejects; no malformed `Closes ` line emitted
- [P0] backend-detect with `vs-ssh.visualstudio.com` (legacy VSTS SSH form not enumerated in spec) | mode: test-framework | expected: bats asserts `null` (treats as unknown host) and graceful-skip downstream
- [P1] build-branch-name slug with emoji, RTL text, combining-character Unicode, and 200+ char description | mode: test-framework | expected: bats asserts slug strips/normalizes per existing `slugify.sh` contract, branch name length is bounded
- [P1] view-pr.sh / merge-pr.sh / pr-diff.sh `<pr-number>` arg is non-numeric (`abc`, `--`, negative) | mode: test-framework | expected: bats asserts the script does NOT silently pass the bogus arg to `gh`/`az`; either rejects with exit code or surfaces the CLI error
- [P1] list-pr.sh `--head` flag receives glob pattern (`feat/FEAT-033-*`) — does the shell expand it locally? | mode: test-framework | expected: bats asserts the glob is passed literally to `gh pr list --head` (matches reviewing-requirements/scripts/detect-review-mode.sh usage)
- [P1] create-pr.sh PR body template substitution when one or more `${VAR}` placeholders is unset in environment | mode: test-framework | expected: bats asserts empty substitution (not the literal `${VAR}` string)
- [P1] create-pr.sh with PR body > 65 KB (Azure DevOps API description limit ≈ 16 KB; GitHub allows ~64 KB) | mode: exploratory | expected: surfaced as size-limit warning in exploratory report when running against real backends
- [P2] backend-detect handles SSH config aliases (`git@my-azdo:org/project/repo`) that resolve to dev.azure.com via `~/.ssh/config` | mode: exploratory | expected: documented limitation — script parses literal hostname, alias resolution is out of scope

### State transitions

- [P0] ensure-branch.sh invoked twice in quick succession with same branch name (idempotency contract) | mode: test-framework | expected: bats asserts second invocation no-ops and exits 0 without git error noise on stderr
- [P0] merge-pr.sh partial failure — PR merged remotely but local branch-delete step fails (e.g., uncommitted changes on the branch) | mode: test-framework | expected: bats asserts the partial-success diagnostic is surfaced to caller; consumer can recover
- [P0] create-pr.sh invoked when a PR already exists for the same head branch | mode: test-framework | expected: bats asserts the script either returns the existing PR URL idempotently or surfaces the `gh pr create` "already exists" error in a structured way callers can detect
- [P1] view-pr.sh called between PR-creation and PR-merge by a separate process; PR state flips mid-poll | mode: exploratory | expected: documented as race; consumer (finalizing-workflow preflight-checks.sh) must re-poll
- [P1] pr-diff.sh on AzDO path: another process pushes commits to `origin/<base>` between the `git fetch` and the `git diff` | mode: exploratory | expected: documented race window; tolerable since diff is informational
- [P1] commit-work.sh interrupted (SIGINT) mid-stage with some files staged and others not | mode: test-framework | expected: bats asserts no partial-commit state; re-invocation completes the work or surfaces a clear "staged but uncommitted" diagnostic
- [P2] ensure-branch.sh asked to switch to a branch that has uncommitted local changes | mode: test-framework | expected: bats asserts the script does NOT clobber local work; surfaces the git error verbatim

### Environment

- [P0] gh / az not on PATH (graceful-skip matrix) for all five PR dispatchers | mode: test-framework | expected: per-dispatcher bats case asserts `[warn] <CLI> not found on PATH.` on stderr + exit 0
- [P0] gh authenticated but token lacks `pull_requests:write` scope → `gh pr create` returns 403 | mode: test-framework | expected: bats asserts script classifies as auth-skip (`[warn] GitHub CLI not authenticated`) OR surfaces the scope error distinctly — verify which path the script takes; misclassification silently swallows real auth failures
- [P0] az authenticated to wrong organization (token scoped to org A, repo is in org B) | mode: exploratory | expected: documented as auth-error class; exploratory verification against a real AzDO repo
- [P0] backend-detect when run inside a worktree (origin inherited from parent, but `git rev-parse --abbrev-ref HEAD` returns `HEAD` for detached worktrees) | mode: test-framework | expected: bats asserts list-pr.sh AzDO path handles `HEAD` source-branch gracefully (does not pass `HEAD` to `az repos pr list --source-branch`)
- [P0] No origin remote configured (e.g., fresh clone with origin removed) | mode: test-framework | expected: bats asserts backend-detect emits `null` and all dispatchers exit 0 with `[info] No recognized SCM backend detected from origin.`
- [P1] `$CLAUDE_PLUGIN_ROOT` unset in calling context | mode: test-framework | expected: bats asserts every dispatcher's path resolution falls back or emits a clear error — the existing pattern uses `${CLAUDE_PLUGIN_ROOT:-/Users/.../}` defaults; verify they survive unset-with-set-u
- [P1] Slow network: `git fetch origin "$base"` in pr-diff.sh AzDO path stalls > 60s | mode: exploratory | expected: documented in exploratory report; pr-diff.sh has no explicit timeout flag
- [P1] DNS failure for github.com — `gh pr view` exits non-zero with network-error-shaped stderr | mode: test-framework | expected: bats asserts the dispatcher classifies network failure as `[warn]` graceful-skip OR surfaces it; verify the classification heuristic does not collide with auth-error pattern
- [P1] Filesystem read-only mid-commit (commit-work.sh) — `git commit` fails to write COMMIT_EDITMSG | mode: exploratory | expected: documented failure mode; caller surfaces the git error
- [P2] Non-UTF-8 locale (`LC_ALL=C`) when piping JSON through jq with non-ASCII PR titles | mode: exploratory | expected: documented as jq utf8 handling case
- [P2] Clock skew sufficient to invalidate `az` JWT mid-flight | mode: exploratory | expected: documented as `az login` re-auth boundary

### Dependency failure

- [P0] gh returns 5xx for `gh pr view` (transient GitHub outage) | mode: test-framework | expected: bats stubs gh to exit 1 with "HTTP 503" stderr; asserts the dispatcher classification is correct — surfacing as auth-skip would silently hide a real outage
- [P0] gh returns 429 rate-limit on `gh pr list` | mode: test-framework | expected: bats asserts the rate-limit path is distinguishable from auth-error; consumer can decide to retry vs. fail-open
- [P0] az repos pr show returns partial JSON (network truncation) — jq parse failure | mode: test-framework | expected: bats stubs az to emit truncated JSON; asserts the dispatcher exits non-zero with a clear "shape transform failed" diagnostic rather than emitting silently malformed output to consumers
- [P0] az-shape-transform.sh encounters an unknown `mergeStatus` value (e.g., `rejected`, `queued`, future enum addition) | mode: test-framework | expected: bats asserts the transformer maps unknown values to `UNKNOWN` (not error, not silent drop) — verify each enum branch is exhaustive
- [P0] gh pr merge returns 409 (PR not mergeable — conflicts, failing required checks, branch protection) | mode: test-framework | expected: bats asserts merge-pr.sh exits non-zero with the gh stderr surfaced; finalize.sh diagnostic shape must be preserved (existing finalize.sh stderr-capture pattern)
- [P0] Branch protection on AzDO blocks merge → `az repos pr update --status completed` returns success but PR remains active (policy override required) | mode: exploratory | expected: documented in references/pr-templates-azdo.md as merge-strategy asymmetry; exploratory verification
- [P1] az `azure-devops` extension auto-install fails (network or proxy issue during first-run install) | mode: test-framework | expected: bats asserts the discovery probe `az repos pr -h` non-zero is classified as `[warn] az devops extension not available -- run az extension add --name azure-devops.` (per Phase 4 step 5)
- [P1] gh pr create when branch has not been pushed → `git push -u origin <branch>` inside create-pr.sh fails (e.g., diverged remote) | mode: test-framework | expected: bats asserts create-pr.sh exits with a clear push-failed diagnostic; consumer state unambiguous (no PR created remotely, branch still local-only)
- [P1] gh path's create-pr.sh PR body template file (`pr-body.tmpl`) missing on disk | mode: test-framework | expected: bats asserts a clear error rather than silently creating a PR with empty body
- [P1] view-pr.sh AzDO PR-ID resolution: `az repos pr list --source-branch <branch> --status active --top 1` returns empty when PR exists but is `abandoned` | mode: test-framework | expected: bats asserts `--status active` filter behavior is documented; warning emitted when callers expect an open PR
- [P2] list-pr.sh AzDO path: organization URL constructed from `backend-detect.sh` JSON contains a trailing slash → `az` may reject `https://dev.azure.com/contoso//` | mode: test-framework | expected: bats asserts URL normalization

### Cross-cutting (a11y, i18n, concurrency, permissions)

- [P0] validate-no-inline-scm.ts false-positive — a Bats fixture file under `tests/bats/fixtures/` containing the literal string `gh pr` for stubbing purposes triggers the gate | mode: test-framework | expected: vitest case in validate-no-inline-scm.test.ts asserts fixtures are excluded from the scan OR the allow-list extends to `tests/bats/fixtures/**`
- [P0] validate-no-inline-scm.ts false-negative — `gh pr` inside a multi-line bash comment (`: <<'EOF' ... gh pr ... EOF`) escapes the regex | mode: test-framework | expected: vitest asserts the regex catches commented strings (false-positive on comments is acceptable; false-negative on real calls is not)
- [P0] validate-no-inline-scm.ts allow-list scope drift — a new script `managing-source-control/scripts/<new>.sh` is added but not picked up by the allow-list glob | mode: test-framework | expected: vitest asserts the allow-list uses a `**/scripts/**` wildcard rather than a static file list
- [P0] Concurrency: two SDLC workflows for different IDs running on the same repo invoke ensure-branch.sh simultaneously for branches with similar prefixes | mode: exploratory | expected: documented as user-must-serialize; ensure-branch.sh's git operations are not transactional across processes
- [P1] Permissions: GitHub fine-grained token with read-only `pull_requests` scope → `gh pr view` succeeds but `gh pr merge` fails | mode: exploratory | expected: documented as separate-scope path; verify graceful-skip vs. surface decision matches consumer expectations
- [P1] i18n: PR title/body containing CJK characters, RTL Arabic, and emoji modifiers | mode: exploratory | expected: documented; gh and az must render parity-equivalent
- [P1] Stop hook race: another workflow running `documenting-qa` simultaneously — `.documenting-active` marker contention | mode: exploratory | expected: documented as user-must-serialize; the marker is a single-writer signal
- [P2] Consumer-call surface: existing `jq` queries in `finalizing-workflow/scripts/preflight-checks.sh` and `reconcile-affected-files.sh` rely on field names — JSON-shape stability across both backends must be byte-equivalent for the projection | mode: test-framework | expected: bats compares az-path output through `jq '.number, .title, .state, .mergeable, .url, .files[].path'` against gh-path output; asserts identical field set

## Non-applicable dimensions

- accessibility: this feature is internal plugin infrastructure (shell scripts and TypeScript build-time validator) with no user-facing UI surface — no keyboard navigation, screen reader, color contrast, or focus management is in scope. The five adversarial scenarios that touched a11y in the cross-cutting dimension are replaced by validator-correctness and permissions scenarios that better match the change shape.
