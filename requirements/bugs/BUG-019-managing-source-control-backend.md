# Bug: managing-source-control backend-detect rejects AzDO origin URLs with user@host credential prefix

## Bug ID

`BUG-019`

## GitHub Issue

[#289](https://github.com/lwndev/lwndev-marketplace/issues/289)

## Category

`logic-error`

## Severity

`high`

## Description

`plugins/lwndev-sdlc/skills/managing-source-control/scripts/backend-detect.sh` emits `null` (no backend detected) when the git origin URL embeds an HTTP basic-auth user prefix (e.g. `https://<user>@dev.azure.com/<org>/<project>/_git/<repo>`). This causes `plugins/lwndev-sdlc/skills/managing-source-control/scripts/create-pr.sh`, `finalizing-workflow`, and every downstream consumer that dispatches on backend identity to silently fall through to the graceful no-op path even though the remote is plainly Azure DevOps and `az` is installed.

## Steps to Reproduce

1. Clone an Azure DevOps repo over HTTPS and authenticate with a PAT via the macOS credential helper (`osxkeychain` / `manager-core`). Git persists origin in the user-prefixed form after the first auth.
2. Confirm origin shape: `git remote get-url origin` returns `https://<user>@dev.azure.com/<org>/<project>/_git/<repo>`.
3. Run `bash plugins/lwndev-sdlc/skills/managing-source-control/scripts/backend-detect.sh`.
4. Observe stdout `null` and exit code `0`.
5. Setting `SDLC_SCM_BACKEND=azdo` does not help — the script's documented behavior is that the override flips the label only and still requires the origin URL to match the AzDO pattern.

## Expected Behavior

`plugins/lwndev-sdlc/skills/managing-source-control/scripts/backend-detect.sh` emits `{"backend":"azdo","organization":"<org>","project":"<project>","repo":"<repo>"}` for the user-prefixed form, identical to the output for the user-less form. The same applies to the `<org>.visualstudio.com` HTTPS variants. Downstream consumers (`plugins/lwndev-sdlc/skills/managing-source-control/scripts/create-pr.sh`, `finalizing-workflow`) then dispatch through the AzDO branch as expected.

## Actual Behavior

`backend-detect.sh` emits literal `null` on stdout and exits `0`. Consumers log `[info] No recognized SCM backend detected from origin.` and graceful-skip. Observed downstream impact on a 1.26.0 orchestrating-workflows run: the orchestrator's PR-creation fork recorded a successful (haiku, baseline-locked) Agent return but produced no PR, leaving the workflow stuck at `pr-review` pause until state was patched manually via `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh set-pr`. `finalizing-workflow` was similarly a no-op and required `az repos pr update --status completed` by hand to merge.

## Root Cause(s)

1. The AzDO HTTPS branch in `parse_azdo()` at `plugins/lwndev-sdlc/skills/managing-source-control/scripts/backend-detect.sh:72` anchors `dev\.azure\.com/` directly after `https?://`, with no allowance for an optional `<user>@` segment. The legacy `<org>.visualstudio.com` branch at `plugins/lwndev-sdlc/skills/managing-source-control/scripts/backend-detect.sh:76` has the same shape and the same gap. Origin URLs of the form `https://<user>@dev.azure.com/…` or `https://<user>@<org>.visualstudio.com/…` therefore fall through and the function returns 1, which propagates to the top-level `auto-detect` and `SDLC_SCM_BACKEND=azdo` paths and emits `null`.
2. The GitHub HTTPS branch in `parse_github()` at `plugins/lwndev-sdlc/skills/managing-source-control/scripts/backend-detect.sh:48` has the same regex shape (`^https?://github\.com/...`) and would also reject a `<token>@github.com/...` origin. This is rarer in practice but the same class of defect; fix for symmetry so the same git-credential-helper persistence pattern works against GitHub remotes too.

The SSH branches (`git@github.com:`, `git@ssh.dev.azure.com:v3/`) are unaffected — SSH origins do not carry an HTTP basic-auth `user@` prefix.

## Affected Files

- `plugins/lwndev-sdlc/skills/managing-source-control/scripts/backend-detect.sh` — both `parse_azdo()` HTTPS branches and the `parse_github()` HTTPS branch.
- `tests/bats/skills/managing-source-control/backend-detect.bats` — add coverage for user-prefixed variants of every affected HTTPS form.

Out of scope (different script, different responsibility):
- `plugins/lwndev-sdlc/skills/managing-work-items/scripts/backend-detect.sh` (planned but not modified)
- `qa/test-plans/QA-plan-BUG-019.md`
- `qa/test-results/QA-results-BUG-019.md`
- `requirements/bugs/BUG-019-managing-source-control-backend.md`
- `tests/bats/skills/managing-source-control/backend-detect.qa.bats`
- `tests/unit/qa-BUG-018-advance-pause.test.ts`

## Acceptance Criteria

- [x] `bash backend-detect.sh` emits `{"backend":"azdo","organization":"<org>","project":"<project>","repo":"<repo>"}` for `https://<user>@dev.azure.com/<org>/<project>/_git/<repo>` origins (RC-1)
- [x] `bash backend-detect.sh` continues to emit the same `{"backend":"azdo",...}` shape for the existing user-less `https://dev.azure.com/<org>/<project>/_git/<repo>` form (RC-1)
- [x] `bash backend-detect.sh` emits `{"backend":"azdo",...}` for `https://<user>@<org>.visualstudio.com/<project>/_git/<repo>` and the `DefaultCollection/` variant, and continues to handle the user-less forms (RC-1)
- [x] `bash backend-detect.sh` emits `{"backend":"github","owner":"<owner>","repo":"<repo>"}` for `https://<token>@github.com/<owner>/<repo>` origins, and continues to handle the user-less HTTPS and SSH forms (RC-2)
- [x] The captured `organization` / `owner` value never contains the `<user>@` prefix (verified by exact-string Bats assertion on the JSON field) (RC-1, RC-2)
- [x] `SDLC_SCM_BACKEND=azdo` set on a user-prefixed AzDO HTTPS origin succeeds (no `[warn] SDLC_SCM_BACKEND=azdo set but origin does not match azdo URL pattern.` line on stderr) (RC-1)
- [x] Bats coverage added in `tests/bats/skills/managing-source-control/backend-detect.bats` for user-prefixed `dev.azure.com`, user-prefixed `<org>.visualstudio.com`, user-prefixed `<org>.visualstudio.com/DefaultCollection/...`, and user-prefixed `github.com` HTTPS origins (RC-1, RC-2)

## Completion

**Status:** `Complete`

**Completed:** 2026-05-18

**Pull Request:** [#290](https://github.com/lwndev/lwndev-marketplace/pull/290)

## Notes

- The fix is the one proposed in the issue: insert an optional `([^/@]+@)?` segment between `https?://` and the host in both AzDO HTTPS branches and the GitHub HTTPS branch. SSH branches are intentionally left unchanged.
- The `BASH_REMATCH` indices shift by one in each affected branch because the new optional group becomes capture group 1; existing capture references must be renumbered accordingly.
- Common trigger in the wild: macOS Git credential helpers (`osxkeychain`, `git-credential-manager-core`) persist origin in the user-prefixed form after the first PAT auth, so this is the default state for many AzDO users on macOS rather than an exotic edge case.
