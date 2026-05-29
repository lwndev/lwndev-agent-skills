---
id: BUG-021
version: 2
timestamp: 2026-05-29T11:09:08Z
persona: qa
---

## User Summary

The `managing-source-control` Azure DevOps dispatcher stops passing the unsupported `--project` flag to `az repos pr show` and `az repos pr update`. After the change, `view-pr.sh`, `merge-pr.sh`, and `pr-diff.sh` invoke those subcommands with `--id` plus `--organization` only, so PR reads, diffs, and merges succeed against `dev.azure.com` origins and `finalizing-workflow` can merge an active PR. The `--project` flag stays on `az repos pr list` and `az repos pr create`, which require it. GitHub-origin repos are untouched.

## Capability Report

- Mode: test-framework
- Framework: vitest
- Package manager: npm
- Test command: npm test
- Language: typescript

Note: the changed code is Bash under `plugins/lwndev-sdlc/skills/managing-source-control/scripts/`. The relevant automated harness is Bats (`tests/bats/skills/managing-source-control/`) stubbing `az` on PATH; `test-framework` scenarios below assume a stubbed-`az` Bats fixture that captures the argv passed to `az`.

## Scenarios (by dimension)

### Inputs
- [P0] `view-pr.sh` AzDO path with a resolved numeric PR id emits an `az repos pr show` argv containing `--id` and `--organization` but NO `--project` token | mode: test-framework | expected: Bats stubs `az`, captures argv, asserts `--project` absent from the `show` invocation
- [P0] `merge-pr.sh` AzDO path emits an `az repos pr update` argv with `--id --status completed` and NO `--project` token | mode: test-framework | expected: Bats stub argv-capture asserts `--project` absent from the `update` invocation
- [P0] `pr-diff.sh` AzDO path emits `az repos pr show --query targetRefName` argv with NO `--project` token | mode: test-framework | expected: Bats stub argv-capture asserts `--project` absent
- [P1] PR id arrives as the literal string `null` (jq query miss in resolve) — dispatcher treats it as empty and warns "no open PR", does not call `show` with `--id null` | mode: test-framework | expected: stub returns `null`, assert `[warn] no open PR for current branch` and no `show` call
- [P1] PR id with trailing newline/CR from `-o tsv` is normalized before being passed to `--id` | mode: test-framework | expected: stub emits `123\n`, assert `--id 123` (no embedded whitespace)
- [P1] `project` variable is empty/unset when the new code runs — removing the `${project:+...}` expansion must not leave a dangling empty arg or alter quoting of remaining flags | mode: test-framework | expected: argv-capture shows exactly the expected flag set, no empty positional
- [P2] org/project parsed from an origin URL containing a project name with spaces or URL-encoding — `--project` removal means such values can no longer break `show`/`update` argv | mode: exploratory | expected: manual run against an org/project with a space in the name; `show` succeeds

### State transitions
- [P0] `merge-pr.sh` against a PR that is already `completed` or `abandoned` — surfaces the `az` error verbatim, exits gracefully, does not crash finalize | mode: test-framework | expected: stub returns non-zero with status error, assert `[warn] az repos pr update failed:` and exit 0
- [P1] PR resolved by `pr list` then closed before `pr show` runs — `show` returns non-zero; dispatcher graceful-skips with `[warn]` rather than emitting bad JSON | mode: test-framework | expected: stub: list returns id, show returns error; assert `[warn] az repos pr show failed:` and empty stdout
- [P1] Idempotent re-run of `finalize.sh` after a successful merge — second run finds no active PR and exits cleanly, no `--project` regression on the retry path | mode: exploratory | expected: manual double-run against AzDO; second run reports no open PR
- [P2] Concurrent merge of the same PR from two invocations — second `pr update` fails on server state; error surfaced not swallowed silently | mode: exploratory | expected: manual concurrent run; loser sees az error

### Environment
- [P0] `az` CLI not installed / `az repos pr -h` probe fails — dispatcher detects the missing extension and graceful-skips, independent of the `--project` change | mode: test-framework | expected: stub `az` missing from PATH; assert graceful-skip warn, exit 0
- [P1] `jq` unavailable when `view-pr.sh` transforms the `pr show` JSON to gh shape — warns and skips, does not emit malformed JSON | mode: test-framework | expected: PATH without `jq`; assert `[warn] jq required for AzDO shape transformation`
- [P1] Organization cannot be auto-detected / `az_org_url` empty — `--organization` expansion is conditional; `show`/`update` still run without `--project` | mode: test-framework | expected: org unset; argv-capture shows neither `--organization` nor `--project`
- [P2] `az` network failure / offline (auth refresh or API unreachable) — non-zero exit surfaced as `[warn]`, not interpreted as "no PR" silently beyond the documented graceful-skip | mode: exploratory | expected: manual offline run; warn emitted

### Dependency failure
- [P0] Regression guard: `az` stub that REJECTS `--project` with `unrecognized arguments: --project` must now NEVER be triggered on `show`/`update` (the pre-fix failure mode) | mode: test-framework | expected: stub fails hard if argv contains `--project` on show/update; the fixed scripts must pass
- [P1] `az repos pr show` returns exit 0 but empty/garbage stdout — `view-pr.sh`/`pr-diff.sh` handle empty `base_raw`/JSON without crashing | mode: test-framework | expected: stub returns empty; assert graceful `[warn]` (pr-diff treats empty base as failure)
- [P2] `az` returns a 5xx/timeout/rate-limit on `show`/`update` — error head-line captured into the `[warn]` message | mode: test-framework | expected: stub writes error to stderr, assert first stderr line echoed in `[warn]`

### Cross-cutting (a11y, i18n, concurrency, permissions)
- [P0] Retain-site regression guard: `az repos pr list` (view-pr.sh:136, list-pr.sh:126) and `az repos pr create` (create-pr.sh:282) STILL pass `--project` after the change | mode: test-framework | expected: argv-capture on list/create asserts `--project <name>` present
- [P0] GitHub (`gh`) codepath unchanged — backend detection routes a github.com origin to `gh`, never to the `az` path; no `--project` logic touched | mode: test-framework | expected: stub origin github.com; assert `gh` invoked, `az` not called
- [P1] `SDLC_SCM_BACKEND` env override forcing `azdo` vs auto-detect still selects the corrected `show`/`update` argv | mode: test-framework | expected: set env override; argv-capture confirms no `--project` on show/update
- [P2] Permissions: caller authenticated as a non-reviewer attempts `pr update --status completed` — server rejects; dispatcher surfaces the permission error verbatim | mode: exploratory | expected: manual run with reduced PAT scope; error surfaced

## Non-applicable dimensions

- a11y: the change is a CLI dispatcher with no UI/screen-reader surface; accessibility does not apply.
- i18n: the affected argv construction is ASCII flag names; no user-facing localized strings are added or changed by this fix (project-name encoding is covered under Inputs).
