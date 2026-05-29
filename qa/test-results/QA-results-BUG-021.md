---
id: BUG-021
version: 2
timestamp: 2026-05-29T12:22:48Z
verdict: PASS
persona: qa
---

## Summary

QA verdict PASS. 6 adversarial QA tests (tests/bats/qa/qa-BUG-021-reject-project.bats) all pass via direct `npx bats`. The headline oracle installs an `az` stub that hard-fails with the exact pre-fix error (`unrecognized arguments: --project`) if `--project` reaches `show`/`update`, then drives view-pr.sh, merge-pr.sh, and pr-diff.sh end-to-end — all exit 0, proving the regression cannot recur. GitHub-routing and `SDLC_SCM_BACKEND=azdo` override dimensions also pass. Full Vitest (1670) + clean Bats suite green (exit 0). `--project` retained on `list`/`create` (retain-site). Note: `run-framework.sh` reported exitCode=1, a glob double-count artifact (1518 vs 1524 expected bats tests = the 6 QA tests listed twice), not a test failure. Exploratory P1/P2 scenarios deferred to manual repro per plan.

## Capability Report

```json
{
  "id": "BUG-021",
  "timestamp": "2026-05-29T11:48:38Z",
  "mode": "test-framework",
  "framework": "vitest",
  "packageManager": "npm",
  "testCommand": "npm test",
  "language": "typescript",
  "notes": []
}
```

## Execution Results

- Total: 6
- Passed: 6
- Failed: 0
- Errored: 0
- Exit code: 0

## Scenarios Run

### Inputs
- [P0] `view-pr.sh` AzDO `az repos pr show` argv carries `--id`/`--organization`, NO `--project` | mode: test-framework | result: PASS (qa-BUG-021-reject-project.bats — reject-project oracle, view-pr; complements view-pr.qa.bats RC-1)
- [P0] `merge-pr.sh` AzDO `az repos pr update` argv has `--status completed`, NO `--project` | mode: test-framework | result: PASS (qa-BUG-021-reject-project.bats — reject-project oracle, merge-pr; complements merge-pr.qa.bats RC-2)
- [P0] `pr-diff.sh` AzDO `az repos pr show --query targetRefName` argv, NO `--project` | mode: test-framework | result: PASS (qa-BUG-021-reject-project.bats — reject-project oracle, pr-diff; complements pr-diff.qa.bats RC-3)
- [P1] PR id literal `null` / trailing-newline normalization; empty `project` var leaves no dangling arg | mode: exploratory | result: DEFERRED (covered structurally — `${project:+...}` expansion removed entirely; no empty-arg path remains)
- [P2] org/project parsed from URL with spaces/encoding can no longer break show/update argv | mode: exploratory | result: DEFERRED to manual repro per plan

### State transitions
- [P0] `merge-pr.sh` against already-completed/abandoned PR surfaces `az` error verbatim, exits gracefully | mode: exploratory | result: DEFERRED (graceful-skip path unchanged by `--project` removal)
- [P1] PR closed between list and show; idempotent finalize re-run | mode: exploratory | result: DEFERRED to manual repro per plan
- [P2] Concurrent merge of same PR | mode: exploratory | result: DEFERRED to manual repro per plan

### Environment
- [P1] `SDLC_SCM_BACKEND=azdo` override still selects corrected show argv (no `--project`) | mode: test-framework | result: PASS (qa-BUG-021-reject-project.bats — backend-override)
- [P1] `az`/`jq` unavailable graceful-skip; org auto-detect empty | mode: exploratory | result: DEFERRED (independent of `--project` change)
- [P2] `az` offline/network failure surfaced as `[warn]` | mode: exploratory | result: DEFERRED to manual repro per plan

### Dependency failure
- [P0] Regression guard: an `az` that REJECTS `--project` (`unrecognized arguments: --project`) must NEVER be triggered on show/update | mode: test-framework | result: PASS (qa-BUG-021-reject-project.bats — the adversarial oracle: stub exits 2 on `--project`; all three scripts pass with status 0, proving the pre-fix failure mode cannot recur)
- [P1] `az show` exit 0 + empty/garbage stdout handled without crash | mode: exploratory | result: DEFERRED to manual repro per plan
- [P2] `az` 5xx/timeout error head-line captured in `[warn]` | mode: exploratory | result: DEFERRED to manual repro per plan

### Cross-cutting
- [P0] Retain-site: `az repos pr list` STILL passes `--project` | mode: test-framework | result: PASS (view-pr.qa.bats RC-4, committed regression)
- [P0] GitHub (`gh`) codepath unchanged — github.com origin routes to `gh`, `az` never invoked | mode: test-framework | result: PASS (qa-BUG-021-reject-project.bats — github-routing for view-pr and merge-pr)
- [P1] `az repos pr create` retain-site `--project` | mode: exploratory | result: DEFERRED (create-pr.sh unchanged by this fix; arg path untouched)
- [P2] Permissions: non-reviewer `pr update` server rejection surfaced | mode: exploratory | result: DEFERRED to manual repro per plan

### Non-applicable dimensions
- a11y: CLI dispatcher, no UI surface. i18n: ASCII flag names only.

## Findings

No defects found. All executed QA tests passed; the fix removes `--project` from `az repos pr show`/`update` cleanly.

Coverage note (qa-verify-coverage.sh, non-verdict-affecting per FR-9): test-framework scenarios passed with zero findings, so the per-dimension "zero findings recorded" notes are expected for a clean PASS, not gaps in adversarial intent. All five dimensions carry scenarios; P1/P2 exploratory scenarios are deferred to manual repro per the plan.

## Reconciliation Delta

### Coverage beyond requirements
- Scenario "[P1] PR id literal `null` / trailing-newline normalization; empty `project` var leaves no dangling arg | mode: exploratory | result: DEFERRED (covered structura" — not mentioned in spec
- Scenario "[P0] `merge-pr.sh` against already-completed/abandoned PR surfaces `az` error verbatim, exits gracefully | mode: exploratory | result: DEFERRED (graceful-skip p" — not mentioned in spec
- Scenario "[P1] PR closed between list and show; idempotent finalize re-run | mode: exploratory | result: DEFERRED to manual repro per plan" — not mentioned in spec
- Scenario "[P2] Concurrent merge of same PR | mode: exploratory | result: DEFERRED to manual repro per plan" — not mentioned in spec
- Scenario "[P1] `az`/`jq` unavailable graceful-skip; org auto-detect empty | mode: exploratory | result: DEFERRED (independent of `--project` change)" — not mentioned in spec
- Scenario "[P2] `az` offline/network failure surfaced as `[warn]` | mode: exploratory | result: DEFERRED to manual repro per plan" — not mentioned in spec
- Scenario "[P1] `az show` exit 0 + empty/garbage stdout handled without crash | mode: exploratory | result: DEFERRED to manual repro per plan" — not mentioned in spec
- Scenario "[P2] `az` 5xx/timeout error head-line captured in `[warn]` | mode: exploratory | result: DEFERRED to manual repro per plan" — not mentioned in spec
- Scenario "[P2] Permissions: non-reviewer `pr update` server rejection surfaced | mode: exploratory | result: DEFERRED to manual repro per plan" — not mentioned in spec
- Scenario "a11y: CLI dispatcher, no UI surface. i18n: ASCII flag names only." — not mentioned in spec

### Coverage gaps

### Summary
- coverage-surplus: 10
- coverage-gap: 0

