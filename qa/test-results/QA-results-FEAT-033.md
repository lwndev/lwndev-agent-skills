---
id: FEAT-033
version: 2
timestamp: 2026-05-17T01:10:51Z
verdict: PASS
persona: qa
---

## Summary

Verdict PASS: passed=13, failed=0, errored=0.

## Capability Report

```json
{
  "id": "FEAT-033",
  "timestamp": "2026-05-17T01:03:09Z",
  "mode": "test-framework",
  "framework": "vitest",
  "packageManager": "npm",
  "testCommand": "npx vitest run",
  "language": "typescript",
  "notes": []
}
```

## Execution Results

- Total: 13
- Passed: 13
- Failed: 0
- Errored: 0
- Exit code: 0

## Scenarios Run

- Ran 13 passing tests, 0 failing tests, 0 errored tests.

## Findings

No test failures. All 13 adversarial scenarios passed against the as-built dispatchers. The QA pass surfaced two documented behaviors worth recording as Info-level findings:

- **[I1] `create-pr.sh --closes "   "` (whitespace-only) is accepted, not rejected.** The script checks `[ -z "$closes" ]` which is false for whitespace strings, so the closes line renders as `Closes    ` (trailing spaces, no issue ref). Not a security concern. Consider tightening the check to also reject all-whitespace, or to trim and re-check empty. Test: `create-pr.sh adversarial > --closes "   " (whitespace-only) is accepted (documented gap)`.
- **[I2] `validate-no-inline-scm.ts` flags `gh pr` inside heredoc bodies.** The line-by-line scanner does not track heredoc context, so a line inside `: <<'EOF' ... EOF` that begins with `gh pr` is flagged. No occurrences exist in the current tree (CI passes), but a future maintainer adding such a heredoc would hit a false-positive. Documented in the test plan; deliberate trade-off vs. building a heredoc-aware parser. Test: `validate-no-inline-scm.ts adversarial > FALSE-POSITIVE GAP: flags gh pr inside a heredoc body even though it is data`.

Neither finding affects the FEAT-033 ship decision. Both are surfaced for awareness.

## Reconciliation Delta

### Coverage beyond requirements

### Coverage gaps
- FR-1 "Backend Detection" — no corresponding scenario in plan
- FR-2 "Branch Management (backend-agnostic)" — no corresponding scenario in plan
- FR-3 "Commit Operations (backend-agnostic)" — no corresponding scenario in plan
- FR-4 "Push Operations (backend-agnostic)" — no corresponding scenario in plan
- FR-5 "Pull Request Operations (backend-dispatched)" — no corresponding scenario in plan
- FR-6 "Auto-Close Issue Linkage in PR Body" — no corresponding scenario in plan
- FR-8 ")." — no corresponding scenario in plan
- FR-7 "Repository Sync (backend-agnostic)" — no corresponding scenario in plan
- FR-8 "PR Body Templates Per Backend" — no corresponding scenario in plan
- FR-9 "below)" — no corresponding scenario in plan
- FR-1 ". The workflow continues; only the PR step is skipped." — no corresponding scenario in plan
- FR-10 "Skill File Structure" — no corresponding scenario in plan
- FR-11 "Consumer Refactor — All Skills Delegate" — no corresponding scenario in plan
- FR-5 "enforcing-check gap (the file currently lives in reviewing-requirements/scripts/, outside the allow-list). |" — no corresponding scenario in plan
- FR-4 "fallback chain and the [warn] resolve-pr-number: gh unavailable … contract. |" — no corresponding scenario in plan
- FR-12 "Orchestrator Integration" — no corresponding scenario in plan
- NFR-1 "Graceful Degradation Matrix" — no corresponding scenario in plan
- NFR-2 "Backward Compatibility on GitHub Repos" — no corresponding scenario in plan
- NFR-3 "Output Shape Stability" — no corresponding scenario in plan
- NFR-4 "Test Coverage Parity" — no corresponding scenario in plan
- NFR-1 "matrix." — no corresponding scenario in plan
- NFR-5 "No Inline gh/az Calls Post-Refactor" — no corresponding scenario in plan
- AC-1 "[ ] `managing-source-control` skill exists at `plugins/lwndev-sdlc/skills/managing-source-control/` with `SKILL.md`, `sc" — no corresponding scenario in plan
- AC-2 "[ ] `backend-detect.sh` parses `git remote get-url origin` to `github` / `azdo` / `null` and honors `SDLC_SCM_BACKEND` e" — no corresponding scenario in plan
- AC-3 "[ ] Branch / commit / push scripts (`ensure-branch.sh`, `build-branch-name.sh`, `commit-work.sh`) are backend-agnostic a" — no corresponding scenario in plan
- AC-4 "[ ] PR dispatchers (`create-pr.sh`, `merge-pr.sh`, `view-pr.sh`, `list-pr.sh`, `pr-diff.sh`) dispatch on backend and pro" — no corresponding scenario in plan
- AC-5 "[ ] Auto-close token in PR body adapts per backend: `Closes #N` for GitHub, `AB#<id>` for Azure Boards, Jira key when wo" — no corresponding scenario in plan
- AC-6 "[ ] `finalize.sh` continues to handle git sync (checkout, fetch, pull) backend-agnostically (FR-7)." — no corresponding scenario in plan
- AC-7 "[ ] PR body templates exist per backend at `references/pr-templates-github.md` and `references/pr-templates-azdo.md` wit" — no corresponding scenario in plan
- AC-8 "[ ] All `gh` / `az` failure modes (missing CLI, not authenticated, missing `az devops` extension, network, not-found) sk" — no corresponding scenario in plan
- AC-9 "[ ] `implementing-plan-phases`, `executing-chores`, `executing-bug-fixes`, `finalizing-workflow`, `reviewing-requirement" — no corresponding scenario in plan
- AC-10 "[ ] PR view/list dispatchers emit GitHub-equivalent JSON shape from the `az` path so existing consumer `jq` queries in `" — no corresponding scenario in plan
- AC-11 "[ ] An enforcing check (preferred: `scripts/validate-no-inline-scm.ts` invoked by `npm run validate`; fallback: CI step)" — no corresponding scenario in plan
- AC-12 "[ ] `orchestrating-workflows` `Read`s the new `SKILL.md` at workflow start (inline pattern, not Agent fork) — same invoc" — no corresponding scenario in plan
- AC-13 "[ ] Bats tests under `tests/bats/skills/managing-source-control/` cover backend detection, env-var override, each dispat" — no corresponding scenario in plan
- AC-14 "[ ] Unit test `tests/unit/managing-source-control.test.ts` validates skill frontmatter and structure (NFR-4)." — no corresponding scenario in plan
- AC-15 "[ ] All existing workflow chains continue to function on a GitHub repo (regression — NFR-2)." — no corresponding scenario in plan
- AC-16 "[ ] All existing workflow chains function on an Azure DevOps repo (new green path)." — no corresponding scenario in plan
- AC-17 "[ ] `npm run validate` passes, including any NFR-5 grep check for residual inline `gh` / `az` calls." — no corresponding scenario in plan
- AC-18 "[ ] `npm test` passes (Vitest + Bats)." — no corresponding scenario in plan
- EDGE-1 "**Repo has no `origin` remote** → `backend-detect.sh` emits `null`. Dispatchers log `[info] No recognized SCM backend de" — no corresponding scenario in plan
- EDGE-2 "**`SDLC_SCM_BACKEND` overrides a recognizable remote** → env var wins for the *backend label*; backend-detect still pars" — no corresponding scenario in plan
- EDGE-3 "**Repo origin is GitLab, Bitbucket, or other** → `null` (skipped). Future backends extend the dispatcher." — no corresponding scenario in plan
- EDGE-4 "**`gh` is installed but not authenticated** → `gh pr ...` exits non-zero. Dispatcher catches, logs `[warn]`, exits 0." — no corresponding scenario in plan
- EDGE-5 "**`az` is installed but `azure-devops` extension is missing** → `az repos pr ...` fails with a recognizable message. Dis" — no corresponding scenario in plan
- EDGE-6 "**PR diff requested on Azure DevOps where the base branch tip is stale locally** → `pr-diff.sh` resolves the base by cal" — no corresponding scenario in plan
- EDGE-7 "**Non-fast-forward push** → `push` operation recovers via fetch+rebase. Rebase conflict surfaces stderr verbatim and exi" — no corresponding scenario in plan
- EDGE-8 "**Branch already exists locally** → `ensure-branch.sh` checks it out (idempotent). Branch already exists on remote with " — no corresponding scenario in plan
- EDGE-9 "**Auto-close token mismatch** → If the work-item backend is Jira but the SCM backend is GitHub, the PR body still uses `" — no corresponding scenario in plan
- EDGE-10 "**Issue reference is empty** → PR body omits the auto-close line entirely; no error." — no corresponding scenario in plan
- EDGE-11 "**Refactor regression: a consumer skill still calls `gh` directly** → caught by NFR-5 grep check during `npm run validat" — no corresponding scenario in plan
- EDGE-12 "**Consumer script reads a field that the Azure DevOps shape lacks** → the `az`-path dispatcher synthesizes the value thr" — no corresponding scenario in plan

### Summary
- coverage-surplus: 0
- coverage-gap: 52

