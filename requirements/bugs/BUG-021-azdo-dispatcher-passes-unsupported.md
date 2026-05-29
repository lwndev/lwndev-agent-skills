# Bug: AzDO dispatcher passes unsupported --project flag

## Bug ID

`BUG-021`

## GitHub Issue

[#301](https://github.com/lwndev/lwndev-marketplace/issues/301)

## Category

`logic-error`

## Severity

`high`

## Description

The `managing-source-control` Azure DevOps dispatcher passes `--project` to `az repos pr show` and `az repos pr update`. Neither subcommand accepts it, so every AzDO call fails with `unrecognized arguments: --project`, degrading PR reads/merges to graceful-skip and aborting the orchestrated SDLC chain at `finalizing-workflow` even when an open, mergeable PR exists.

## Steps to Reproduce

1. Use a repo whose `origin` points to `https://dev.azure.com/<org>/<project>/_git/<repo>` and that has an open, active PR for the current branch.
2. Invoke the dispatcher: `bash plugins/lwndev-sdlc/skills/managing-source-control/scripts/view-pr.sh`.
3. Observe stderr `[warn] az repos pr show failed: ERROR: unrecognized arguments: --project <name>`, empty stdout, exit 0 (graceful-skip).
4. Run `finalizing-workflow`: `bash plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/finalize.sh <branch>` -> `[error] preflight: no PR found for current branch`.
5. (RC-3) Invoke `bash plugins/lwndev-sdlc/skills/managing-source-control/scripts/pr-diff.sh` against the same AzDO origin -> base-ref resolution emits `[warn] az repos pr show failed: ... unrecognized arguments: --project` and graceful-skips.

Direct repro (failing): `az repos pr show --id <N> --organization https://dev.azure.com/<org>/ --project <project>` -> `ERROR: unrecognized arguments: --project <project>`.

Expected successful form (no `--project`): `az repos pr show --id <N> --organization https://dev.azure.com/<org>/` -> `{"pullRequestId": <N>, "status": "active", ...}`.

## Expected Behavior

`az repos pr show` and `az repos pr update` are invoked with `--id` plus `--organization` only (no `--project`). `view-pr.sh` returns normalized PR JSON, `pr-diff.sh` resolves the base ref, and `merge-pr.sh` completes the PR, restoring the `finalize.sh` -> `view-pr.sh` -> `merge-pr.sh` chain for AzDO origins. `pr list` and `pr create` continue to pass `--project` (they accept it).

## Actual Behavior

All three `pr show` / `pr update` call sites append a `--project` expansion. The Azure DevOps CLI argparse layer rejects the flag (PR `--id` is org-globally unique, so project scoping is unnecessary and unsupported on `show`/`update`). The dispatcher catches the non-zero exit, emits a `[warn]` line, and exits 0 with empty stdout. Downstream readers interpret the empty result as "no PR", aborting the chain.

## Root Cause(s)

1. `view-pr.sh:164` appends `${az_project:+--project "$az_project"}` to the `az repos pr show --id ... --organization ...` invocation (command block at lines 161-165). `az repos pr show` does not accept `--project`, so the call fails and `view-pr.sh` graceful-skips with a `[warn]`.
2. `merge-pr.sh:121` appends `${project:+--project "$project"}` to the `az repos pr update --id ... --status completed ...` invocation (command block at lines 115-122). `az repos pr update` does not accept `--project`, so the merge fails — this is the call that blocks `finalize.sh`.
3. `pr-diff.sh:107` appends `${project:+--project "$project"}` to the `az repos pr show --id ... --query targetRefName ...` invocation (command block at lines 103-108). Same unsupported-flag failure; base-ref resolution graceful-skips.
4. Shared root cause: the dispatcher treats `--project` as uniformly accepted across `az repos pr <subcommand>`. In reality the Azure DevOps CLI extension accepts `--project` (`-p`) only on `pr list` and `pr create` (verified locally — see Notes). The fix must remove `--project` from `show`/`update` (RC-1/2/3) while preserving it on the subcommands that require it: `pr list` (`view-pr.sh:136`, `list-pr.sh:126`) and `pr create` (`create-pr.sh:282`).

## Affected Files

- `plugins/lwndev-sdlc/skills/managing-source-control/scripts/view-pr.sh` (line ~164, `pr show` — fix; line ~136, `pr list` — leave intact)
- `plugins/lwndev-sdlc/skills/managing-source-control/scripts/merge-pr.sh` (line ~121, `pr update` — fix)
- `plugins/lwndev-sdlc/skills/managing-source-control/scripts/pr-diff.sh` (line ~107, `pr show` — fix)
- `tests/bats/skills/managing-source-control/` (add AzDO `pr show` / `pr update` dispatcher cases)

Correct sites to retain `--project` (no change): `view-pr.sh:136` (`pr list`), `list-pr.sh:126` (`pr list`), `create-pr.sh:282` (`pr create`).

## Acceptance Criteria

- [x] `view-pr.sh` does not pass `--project` to `az repos pr show`; the call uses `--id` plus `--organization` only (RC-1)
- [x] `merge-pr.sh` does not pass `--project` to `az repos pr update`; the call uses `--id`, `--status`, branch/squash flags, and `--organization` only (RC-2)
- [x] `pr-diff.sh` does not pass `--project` to `az repos pr show --query targetRefName` (RC-3)
- [x] `pr list` (`view-pr.sh:136`, `list-pr.sh:126`) and `pr create` (`create-pr.sh:282`) still pass `--project` — no regression to the supported sites (RC-4)
- [x] Bats cases stub `az` and assert no `--project` token reaches `pr show` / `pr update` for the AzDO path, and that `view-pr.sh` emits normalized PR JSON instead of `[warn]` on a successful stubbed `show` (RC-1, RC-2, RC-3, RC-4)

## Completion

**Status:** `In Progress`

**Completed:** YYYY-MM-DD

**Pull Request:** [#305](https://github.com/lwndev/lwndev-marketplace/pull/305)

## Notes

- Verified locally against `az` 2.86.0 + `azure-devops` extension 1.0.3 (`az repos pr <sub> -h`), cross-checked with the Microsoft Azure CLI command reference:
  - `az repos pr show` — `--project` NOT listed (only `--id`, `--detect`, `--open`, `--organization`). Confirms RC-1, RC-3.
  - `az repos pr update` — `--project` NOT listed. Confirms RC-2.
  - `az repos pr list` — `--project` (`-p`) listed and supported. Keep (RC-4).
  - `az repos pr create` — `--project` (`-p`) listed and supported. Keep (RC-4).
  - Report environment: plugin `lwndev-sdlc` 1.26.0, `azure-devops` 1.0.2 (local has 1.0.3; same flag surface).
- GitHub-origin repos are unaffected; the `gh` codepath is independent.
- Suggested fix is mechanical: drop the `${az_project:+--project ...}` / `${project:+--project ...}` expansion from the three `show`/`update` call sites. Surfaced during a CHORE-003 run where `finalizing-workflow` could not merge an active, approved PR on `dev.azure.com`.
