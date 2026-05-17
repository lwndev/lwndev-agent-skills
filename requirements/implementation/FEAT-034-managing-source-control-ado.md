# Implementation Plan: managing-source-control ADO PR comment support

## Overview

This plan extends the existing `managing-source-control` skill so the Azure DevOps (`azdo`) backend reaches parity with the GitHub (`gh`) backend for PR comment operations. Today consumer skills like `/review` can only post PR feedback on GitHub-hosted repos; on ADO they have to fall back to the web UI, which breaks the inline-skill contract. After this work, `pr-comment.sh` and `list-pr-comments.sh` dispatch transparently across both backends with the same graceful-degradation semantics as the existing `create-pr.sh` / `view-pr.sh` family.

The work is structured in five phases: GitHub `pr-comment.sh` first (Phase 1 — simpler path validates the dispatch shape), then the ADO `pr-comment.sh` top-level + reply + probe + caching (Phase 2 — the hard one, gated behind the GitHub baseline), then `list-pr-comments.sh` across both backends with the FR-5 NDJSON schema (Phase 3), then SKILL.md + reference doc updates (Phase 4), and finally env-gated round-trip integration tests (Phase 5).

## Features Summary

| Feature ID | GitHub Issue | Feature Document | Priority | Complexity | Status |
|------------|--------------|------------------|----------|------------|--------|
| FEAT-034 | [#280](https://github.com/lwndev/lwndev-marketplace/issues/280) | [FEAT-034-managing-source-control-ado.md](../features/FEAT-034-managing-source-control-ado.md) | Medium | Medium | Pending |

## Recommended Build Sequence

### Phase 1: GitHub `pr-comment.sh` + Bats coverage
**Feature:** [FEAT-034](../features/FEAT-034-managing-source-control-ado.md) | [#280](https://github.com/lwndev/lwndev-marketplace/issues/280)
**Status:** ✅ Complete
**Depends on:** None

#### Rationale
- Ship the simpler backend first so the dispatch shape, arg-parsing surface (positional / `--body` / `--body-file` / `--reply-to`), and stderr-tag conventions are nailed down before the ADO path consumes them.
- The GitHub path is small (`gh pr comment` wraps everything) which keeps the Phase-1 footprint inside the opus budget.
- Validating arg-parsing + dispatch invariants here means Phase 2 only adds ADO-specific logic without re-litigating contract decisions.

#### Implementation Steps
1. Author `plugins/lwndev-sdlc/skills/managing-source-control/scripts/pr-comment.sh` using the `create-pr.sh` structural template: header comment block, `set -euo pipefail`, positional+flag parser, `backend-detect.sh` dispatch, per-backend case. Implement only the `github` and `null` branches; stub the `azdo` branch with `[info] ADO pr-comment.sh arriving in Phase 2.` exit 0 placeholder so the file is committable end-to-end.
2. Add client-side validation that runs before any backend dispatch: mutual-exclusion check across `<positional>`, `--body`, `--body-file` (FR-1 / Edge 11) → exit non-zero with `[error] body source ambiguous: pass exactly one of <positional> / --body / --body-file`; `--reply-to` numeric check (Edge 12) → exit non-zero with `[error] --reply-to must be a numeric thread id`; `--body-file` existence check (Edge 3) → exit non-zero with `[error] body file not found: <path>`.
3. Implement GitHub branch: graceful skip on `command -v gh` failure and `gh auth status` failure (NFR-1 lines copied verbatim from the SKILL.md matrix); invoke `gh pr comment <pr> --body "$body"` or `gh pr comment <pr> --body-file "$path"`; on `--reply-to` set, emit `[warn] --reply-to not supported on GitHub backend; skipping.` and exit 0 (graceful skip per FR-1); surface non-zero `gh` exit as `[warn]` + first line of stderr, exit 0 (NFR-1).
4. Add Bats fixture `tests/bats/skills/managing-source-control/pr-comment-github.bats` mirroring `create-pr.bats` STUBDIR pattern. Cases: top-level positional body succeeds and prints the stub URL; `--body` flag equivalent; `--body-file` reads from path; missing-body-file exits non-zero; ambiguous body-source exits non-zero; `--reply-to` on github emits `[warn]` and exits 0; `gh` missing emits `[warn]` and exits 0; `gh auth status` failing emits `[warn]` and exits 0; `gh pr comment` non-zero surfaces stderr as `[warn]` and exits 0.

#### Deliverables
- [x] New script at plugins/lwndev-sdlc/skills/managing-source-control/scripts/pr-comment.sh exists, executable, passes shellcheck.
- [x] Arg parser handles positional body, body flag, body-file flag, reply-to flag, mutual-exclusion, numeric-id validation.
- [x] GitHub branch dispatches to the gh CLI comment subcommand and honors graceful-degradation matrix.
- [x] ADO branch is a placeholder stub that exits 0 with an info-tagged line (replaced in Phase 2).
- [x] New Bats fixture at tests/bats/skills/managing-source-control/pr-comment-github.bats covers all FR-1 and Edge 3/11/12 cases.
- [x] Targeted bats invocation against the new fixture passes locally.

#### Success Criteria
- Posting a top-level body on a github.com origin succeeds via the stubbed gh and prints the URL on stdout.
- All Phase-1 Bats cases pass.
- Shellcheck is clean on the new script.

---

### Phase 2: ADO `pr-comment.sh` top-level + reply + resource-name probe
**Feature:** [FEAT-034](../features/FEAT-034-managing-source-control-ado.md) | [#280](https://github.com/lwndev/lwndev-marketplace/issues/280)
**Status:** ✅ Complete
**Depends on:** Phase 1
**ComplexityOverride:** opus

> Justification: This phase carries the entire ADO path — top-level thread create, reply with `parentCommentId` resolution, `az devops invoke` resource-name probe with `PullRequestThreads|pullrequestthreads|threads` fallback order, 24h-TTL filesystem cache with `probe-failed` sentinel, raw-HTTP `curl` fallback path with PAT auth, and the matching Bats coverage. Cannot split without breaking the FR-2/FR-3/FR-4 invariant that the ADO path is functional end-to-end before any consumer skill is rerouted through it. 7 steps with 9 deliverables; the deliverable count is intentionally over the sonnet ceiling because each FR-2/FR-3/FR-4/NFR-3 line maps to its own verifiable artifact.

#### Rationale
- ADO is the harder backend: thread API, `az devops invoke` resource-name ambiguity (`threads` vs `pullRequestThreads` vs `pullrequestthreads`), and a raw-HTTP `curl` fallback path are all required by FR-2 / FR-3 / FR-4.
- Replacing the Phase-1 placeholder atomically keeps the dispatch surface in a working state on `azdo` origins instead of half-broken across two PRs.
- Probe caching (NFR-3) and the `probe-failed` sentinel are part of the same logical unit as the probe itself — splitting them would leave the cache file undefined in v1.

#### Implementation Steps
1. Replace the Phase-1 ADO branch placeholder in `pr-comment.sh` with the full ADO flow: graceful-degradation skips on `az` missing, `az devops` extension missing, `az` not authenticated (verbatim `[warn]` lines from the SKILL.md matrix); resolve `repositoryId` once via `az repos show --repository <repo> --project <project> --organization https://dev.azure.com/<org>/ --query id -o tsv` and cache it in a script-local var.
2. Implement the resource-name probe helper (inline function or sibling script — author's choice). The probe attempts `PullRequestThreads`, then `pullrequestthreads`, then `threads` against the threads-list route (`GET .../pullRequests/<prId>/threads`) using `az devops invoke --http-method GET`; the first call returning HTTP 200 wins (empty thread list is `{"value":[],"count":0}` which counts as 200). Cache the resolved token in `/tmp/sdlc-azdo-pr-thread-resource.<org>.<repo>` with a leading timestamp line for the 24h TTL check. On full exhaustion, write the literal `probe-failed` sentinel into the cache file and emit `[warn] ADO PR-thread resource probe failed across [PullRequestThreads, pullrequestthreads, threads]. Skipping comment.` then exit 0 (Edge 4).
3. Implement the top-level thread create path (FR-2): construct the payload `{"comments":[{"parentCommentId":0,"content":"<body>","commentType":1}],"status":1}` via `jq -n --arg body "$body" ...` (do not paste-concat to avoid quoting bugs); POST via `az devops invoke --area git --resource <probed-token> --route-parameters project=<proj> repositoryId=<repoId> pullRequestId=<num> --http-method POST --in-file <payload.json> --api-version 7.1 --organization https://dev.azure.com/<org>/`; parse the response `id` (thread ID) via `jq -r '.id'` and emit `https://dev.azure.com/<org>/<project>/_git/<repo>/pullrequest/<prId>?discussionId=<threadId>` on stdout.
4. Implement the reply path (FR-3): when `--reply-to <thread-id>` is set, GET the existing thread comments first to find the highest-numbered comment id (set as `parentCommentId`); empty thread → `parentCommentId: 0`; POST the comment to `threads/<threadId>/comments`; on 404 emit `[warn] ADO thread <id> not found; skipping reply.` and exit 0 (Edge 6); emit the same URL shape as Phase 3 but with the resolved `discussionId`.
5. Implement the raw-HTTP `curl` fallback (FR-4 second half): when `SDLC_AZDO_HTTP=curl` is set OR `az devops invoke` returns non-zero on the POST, fall back to `curl -sS -X POST https://dev.azure.com/<org>/<project>/_apis/git/repositories/<repoId>/pullRequests/<prId>/threads?api-version=7.1` with `Authorization: Basic $(printf ':%s' "$AZURE_DEVOPS_PAT" | base64)` and `Content-Type: application/json`. On `AZURE_DEVOPS_PAT` unset emit `[warn] AZURE_DEVOPS_PAT not set; cannot post PR comment via raw HTTP. Skipping.` and exit 0 (FR-4 graceful skip). Surface `[warn] az devops invoke failed; falling back to raw HTTP via curl.` on automatic fall-through.
6. Add Bats fixture `tests/bats/skills/managing-source-control/pr-comment-azdo.bats`: STUBDIR-stubbed `az` + `curl`; cases: top-level thread create returns the formatted URL; reply resolves `parentCommentId` from the listed comments; reply on empty thread uses `parentCommentId: 0`; `--reply-to` on missing thread emits `[warn]` + exits 0; probe hits `PullRequestThreads` on first try, on `pullrequestthreads` on second try, on `threads` on third try; probe-failure exit 0 with sentinel written; cache-hit short-circuits the probe within 24h; cache invalidates past 24h TTL; missing `AZURE_DEVOPS_PAT` on forced-curl path emits `[warn]` and exits 0; `az devops invoke` POST failure triggers curl fallback when PAT is set.
7. Add a Bats fixture `tests/bats/skills/managing-source-control/pr-comment-dispatch.bats` covering the cross-backend dispatch concerns: `backend-detect.sh` returning `null` → `[info] No recognized SCM backend detected from origin. Skipping PR comment.` exit 0 (FR-6); `SDLC_SCM_BACKEND=github` override against a non-github origin honors the override semantics from `backend-detect.sh` (no new behavior — assert pass-through).

#### Deliverables
- [x] ADO branch of `plugins/lwndev-sdlc/skills/managing-source-control/scripts/pr-comment.sh` replaces the Phase-1 stub with the full FR-2 + FR-3 + FR-4 flow.
- [x] Resource-name probe in `pr-comment.sh` ADO branch tries `PullRequestThreads → pullrequestthreads → threads` via `az devops invoke` in order.
- [x] Probe cache at `/tmp/sdlc-azdo-pr-thread-resource.<org>.<repo>` with 24h TTL and `probe-failed` sentinel (NFR-3).
- [x] Reply path resolves `parentCommentId` from the existing thread (FR-3).
- [x] Raw-HTTP `curl` fallback with PAT-based Basic auth and `SDLC_AZDO_HTTP=curl` force-flag (FR-4).
- [x] All ADO graceful-skip paths from the SKILL.md matrix emit `[warn]` and exit 0 (NFR-1).
- [x] `tests/bats/skills/managing-source-control/pr-comment-azdo.bats` covers FR-2 / FR-3 / FR-4 / NFR-3 / Edge 4 / Edge 6.
- [x] `tests/bats/skills/managing-source-control/pr-comment-dispatch.bats` covers FR-6 dispatch invariants.
- [x] All new and modified Bats fixtures pass under `npm run test:bats`.

#### Success Criteria
- `pr-comment.sh <pr> "body"` against an `azdo` origin posts a new thread via the probed resource token and prints the discussion URL.
- `pr-comment.sh <pr> --body "reply" --reply-to <thread>` posts a reply with the correct `parentCommentId`.
- All Phase-2 Bats cases pass; `shellcheck` is clean.
- The probe cache file is created on first successful probe and short-circuits subsequent invocations within 24h.

---

### Phase 3: `list-pr-comments.sh` both backends + NDJSON schema
**Feature:** [FEAT-034](../features/FEAT-034-managing-source-control-ado.md) | [#280](https://github.com/lwndev/lwndev-marketplace/issues/280)
**Status:** ✅ Complete
**Depends on:** Phase 2

#### Rationale
- The probe + cache primitive built in Phase 2 is the foundation for the ADO list path — `list-pr-comments.sh` reuses the resolved resource-name token rather than probing twice.
- Splitting list across two phases (one per backend) would duplicate the NDJSON schema decisions; keeping it in one phase guarantees a single source of truth for the FR-5 field set.
- Round-trip tests in Phase 5 depend on a working list path against both backends; Phase 3 unblocks them.

#### Implementation Steps
1. Author `plugins/lwndev-sdlc/skills/managing-source-control/scripts/list-pr-comments.sh` mirroring the `view-pr.sh` template: header block, `backend-detect.sh` dispatch, per-backend case. Accept positional `<pr-number>` (required) and `--json` (no-op, reserved for forward compat). On `backend-detect.sh` null → `[info] No recognized SCM backend detected from origin. Skipping PR comment.` exit 0 with zero NDJSON records (Edge 13).
2. Implement GitHub branch: graceful skips on missing/unauthenticated `gh`; invoke `gh api repos/<owner>/<repo>/issues/<pr-number>/comments`; map each comment via `jq` to the FR-5 NDJSON schema with sentinel values (`thread_id: 0`, `parent_comment_id: 0`, `thread_status: "unknown"`, `status: "active"`, `is_deleted: false`); stream one JSON object per line on stdout in chronological order; on `gh api` non-zero exit, emit `[warn] PR <num> not found on github; skipping comment.` and exit 0 (Edge 8 + 10).
3. Implement ADO branch: reuse the probe helper from Phase 2 to resolve the resource-name token (cache-hit fast path expected); invoke `az devops invoke --area git --resource <token> --route-parameters project=<proj> repositoryId=<repoId> pullRequestId=<num> --http-method GET --api-version 7.1`; for each thread in `.value[]`, walk `.comments[]` and emit one NDJSON line per comment with `thread_id`, `comment_id`, `parent_comment_id`, `author` (displayName), `author_unique_name` (uniqueName), `published` (publishedDate ISO-8601), `content`, `status` (commentType-derived), `is_deleted` (boolean), `thread_status` (thread.status string); skip deleted comments unless `is_deleted: true` is meaningful (preserve them per FR-5 — `is_deleted` is a field, not a filter).
4. Add Bats fixture `tests/bats/skills/managing-source-control/list-pr-comments.bats`: STUBDIR-stubbed `gh` and `az`; cases: github empty PR emits zero NDJSON lines + exits 0 (Edge 10); github single comment emits one line with correct field shape; github multi-comment emits multiple lines in chronological order; azdo single-thread-multi-comment emits comments with shared `thread_id`; azdo multi-thread interleave preserves thread linkage; azdo deleted-comment row carries `is_deleted: true`; missing backend (null) → zero records + `[info]` + exit 0; `gh` missing → zero records + `[warn]` + exit 0 (Edge 13); `gh api` 404 → zero records + `[warn]` + exit 0 (Edge 8).

#### Deliverables
- [x] `plugins/lwndev-sdlc/skills/managing-source-control/scripts/list-pr-comments.sh` exists, executable, passes `shellcheck`.
- [x] GitHub branch flattens `gh api .../issues/<pr>/comments` into the FR-5 NDJSON schema with sentinel values for ADO-only fields.
- [x] ADO branch reuses the Phase-2 probe cache and flattens threads → comments preserving `thread_id` linkage.
- [x] Both backends emit chronological order, one record per line, no whole-tree buffering (NFR-2).
- [x] Graceful-skip paths emit zero NDJSON records + appropriate `[info]`/`[warn]` (Edge 13).
- [x] `tests/bats/skills/managing-source-control/list-pr-comments.bats` covers both backends + all graceful-skip paths.

#### Success Criteria
- `list-pr-comments.sh <pr>` on github emits NDJSON whose schema matches FR-5 exactly.
- `list-pr-comments.sh <pr>` on azdo emits the same schema with full thread/status fidelity.
- The probe cache from Phase 2 is hit (not regenerated) when `list-pr-comments.sh` runs after `pr-comment.sh`.
- All Phase-3 Bats cases pass.

---

### Phase 4: SKILL.md + reference docs
**Feature:** [FEAT-034](../features/FEAT-034-managing-source-control-ado.md) | [#280](https://github.com/lwndev/lwndev-marketplace/issues/280)
**Status:** 🔄 In Progress
**Depends on:** Phase 3

#### Rationale
- SKILL.md is the consumer-facing contract; updating it last (after the scripts settle) prevents prose drift if Phase-2/3 implementation surfaces an API tweak.
- The graceful-degradation matrix update (FR-7 NFR-1) needs accurate `[warn]` strings from the actual implementation, not pre-impl guesses.
- Reference docs for the ADO PR-thread API are net-new and benefit from the same defer-until-impl-stable cadence.

#### Implementation Steps
1. Update `plugins/lwndev-sdlc/skills/managing-source-control/SKILL.md` Script Entry Points table (FR-7): add two rows — `pr-comment.sh` marked `dispatched` with purpose "Post a top-level PR comment or reply to an existing thread"; `list-pr-comments.sh` marked `dispatched` with purpose "List PR comments as NDJSON, one record per comment". Do NOT add the deferred `pr-comment-thread.sh` row (FR-7 explicitly defers it).
2. Update the SKILL.md Graceful Degradation matrix (FR-7 second clause): add one row for `AZURE_DEVOPS_PAT not set on curl fallback path` with response `[warn] AZURE_DEVOPS_PAT not set; cannot post PR comment via raw HTTP. Skipping. Exit 0.`; add one row for `ADO PR-thread resource probe exhausted` with response `[warn] ADO PR-thread resource probe failed across [PullRequestThreads, pullrequestthreads, threads]. Skipping comment. Exit 0.`
3. Add `plugins/lwndev-sdlc/skills/managing-source-control/references/pr-comments-azdo.md` documenting the ADO PR-thread API surface: endpoint table (create thread, reply, list), payload shapes (`commentType: 1` = text, `status: 1` = active), `parentCommentId` semantics, the resource-name probe rationale (link to https://learn.microsoft.com/en-us/rest/api/azure/devops/git/pull-request-threads), and the cache file location + invalidation rules.
4. Add `plugins/lwndev-sdlc/skills/managing-source-control/references/pr-comments-github.md` documenting the GitHub PR-comment API surface: `gh pr comment` flags, `gh api repos/.../issues/<pr>/comments` shape, the field-mapping table that produces FR-5 NDJSON with sentinel values for thread-aware fields, and the explicit "no thread reply semantics" note that explains why `--reply-to` is graceful-skipped on GitHub.
5. Update the SKILL.md `References` section to link both new reference docs (`pr-comments-github.md`, `pr-comments-azdo.md`) — and remove the stale "arriving in Phase 3" placeholders for PR templates if they still exist after FEAT-033.

#### Deliverables
- [x] SKILL.md Script Entry Points table includes `pr-comment.sh` and `list-pr-comments.sh` rows (FR-7).
- [x] SKILL.md Graceful Degradation matrix has rows for `AZURE_DEVOPS_PAT` unset and probe exhaustion (FR-7 NFR-1).
- [x] `references/pr-comments-azdo.md` documents the ADO API surface, probe rationale, and cache rules.
- [x] `references/pr-comments-github.md` documents the GitHub API surface and the NDJSON sentinel-field mapping.
- [x] SKILL.md `References` section links both new reference docs.
- [x] `npm run validate` passes (skill metadata still valid; new reference docs picked up if validator scans them).

#### Success Criteria
- A consumer skill reading SKILL.md can discover the new entry points and the new graceful-skip paths without reading the requirement doc.
- Both new reference docs render cleanly as markdown and contain the API + cache contract.

---

### Phase 5: Round-trip integration tests (env-gated)
**Feature:** [FEAT-034](../features/FEAT-034-managing-source-control-ado.md) | [#280](https://github.com/lwndev/lwndev-marketplace/issues/280)
**Status:** Pending
**Depends on:** Phase 4

#### Rationale
- End-to-end validation against real PRs catches integration mismatches that Bats stubs cannot (e.g. `az devops invoke` resource-name oddities on a fresh org, `parentCommentId` ordering quirks in the ADO UI).
- Env-gating (skip when credentials are absent) means CI stays green without secrets and contributors with credentials can opt in.
- This is the only phase that needs network access; isolating it keeps Phases 1-4 fully hermetic.

#### Implementation Steps
1. Add `tests/bats/skills/managing-source-control/pr-comment-roundtrip-github.bats`: skip the file when `SDLC_INTEGRATION_GITHUB_PR_URL` is unset (use `[ -z "${SDLC_INTEGRATION_GITHUB_PR_URL:-}" ] && skip "..."` in `setup_file()`); parse PR number from the URL; post a comment with a generated GUID body via `pr-comment.sh`; list comments via `list-pr-comments.sh`; grep the GUID in the NDJSON output to assert presence; tear down by leaving the comment in place (integration scratch repo is sacrificial — note this in the bats file header).
2. Add `tests/bats/skills/managing-source-control/pr-comment-roundtrip-azdo.bats`: skip when `SDLC_INTEGRATION_AZDO_PR_URL` or `AZURE_DEVOPS_PAT` is unset; parse PR number; post a top-level comment with a generated GUID body; post a reply to the just-created thread; list comments; assert both the original GUID and the reply GUID appear, both share the same `thread_id`, and the reply's `parent_comment_id` equals the original's `comment_id`.
3. Document the integration-test env vars in the SKILL.md References section or in a small `tests/bats/skills/managing-source-control/README.md` (if one does not yet exist): `SDLC_INTEGRATION_GITHUB_PR_URL`, `SDLC_INTEGRATION_AZDO_PR_URL`, `AZURE_DEVOPS_PAT` (PAT scope `vso.code_write`). Note that the GitHub round-trip needs `gh auth login` already complete and the ADO round-trip needs the PAT in the env (not stored anywhere else by this skill).

#### Deliverables
- [ ] `tests/bats/skills/managing-source-control/pr-comment-roundtrip-github.bats` exists and skips cleanly when the env gate is unset.
- [ ] `tests/bats/skills/managing-source-control/pr-comment-roundtrip-azdo.bats` exists and skips cleanly when either env gate is unset.
- [ ] Integration env vars are documented in the test suite (README or SKILL.md References note).
- [ ] When env vars are set, both round-trip tests pass against a real sacrificial PR.

#### Success Criteria
- `npm run test:bats` continues to pass with the integration files present (skipped, not failing).
- A maintainer with the env vars set can run both round-trip tests and see them pass end-to-end.
- The acceptance-criteria checkbox "Round-trip integration test ... passes on both GitHub and ADO test PRs when env-gated credentials are available" is satisfied.

## Shared Infrastructure

- `backend-detect.sh` (existing) is reused unchanged — it already emits the JSON shape needed by both new scripts.
- The resource-name probe + cache helper introduced in Phase 2 is shared between `pr-comment.sh` (Phase 2) and `list-pr-comments.sh` (Phase 3). Author's choice whether to extract it into a sibling `azdo-resource-probe.sh` or keep it as a function inside each script — the test contract is identical either way.
- `create-pr.sh` and `view-pr.sh` remain the structural templates for `pr-comment.sh` and `list-pr-comments.sh` respectively. No refactor of the existing scripts is in scope.

## Testing Strategy

- **Bats (per-script)**: each new dispatcher gets a dedicated `*.bats` file under `tests/bats/skills/managing-source-control/` using the inline-stub pattern already established by `create-pr.bats`, `view-pr.bats`, `merge-pr.bats`. Stubs for `gh`, `az`, and `curl` live in a per-test `STUBDIR` and PATH-prepended in `setup()`.
- **Bats (cross-backend dispatch)**: `pr-comment-dispatch.bats` covers the FR-6 dispatch invariants (null backend, env override, missing-CLI graceful skips) that are not specific to either backend.
- **Bats (round-trip integration)**: env-gated files under the same directory, skipped by default to keep CI hermetic.
- **Vitest**: none — the new artifacts are bash scripts only; the existing `tests/unit/managing-source-control.test.ts` already covers the skill-metadata invariants and does not need changes.
- **Manual smoke**: the acceptance-criteria block of the requirement doc enumerates the manual paths (real GitHub PR, real ADO PR, every graceful-degradation path). Documented in the Phase 5 deliverables but not gated by automation.

## Dependencies and Prerequisites

- `gh`, `az` + `azure-devops` extension, `curl`, `jq`, `base64` — all already required by the existing `managing-source-control` scripts. No new runtime deps.
- FEAT-033 (already merged) — provides `backend-detect.sh`, `create-pr.sh`, `view-pr.sh`, the SKILL.md scaffolding, and the Bats fixture pattern this plan builds on top of.
- `AZURE_DEVOPS_PAT` env var (PAT scope `vso.code_write`) — required only for the raw-HTTP `curl` fallback path and for the Phase-5 round-trip integration test; absent-PAT is a graceful skip, not a hard dep.

## Risk Assessment

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| `az devops invoke --resource` token differs across ADO org versions / API versions | High (ADO path silently broken on one org) | Med | Resource-name probe (FR-4) tries three known tokens; full exhaustion is a graceful skip with a clear `[warn]`; probe-failed sentinel is cached so the user is not surprised twice. |
| Raw-HTTP `curl` fallback misbehaves under corporate proxies | Med | Med | Surface the first line of `curl` stderr as `[warn]`; users can set `HTTPS_PROXY`/`https_proxy` exactly as they would for any other HTTP client. No proxy logic in-script. |
| Probe cache poisoned by a transient network outage that records `probe-failed` | Med | Low | 24h TTL auto-clears the entry (NFR-3); the `[warn]` message includes the explicit `rm /tmp/sdlc-azdo-pr-thread-resource.*` hint (Edge 14). |
| ADO PR-comment markdown rendering differs from GitHub (tables, strikethrough) | Low | Med | Out of scope — the skill is a transport, not a transformer (Edge 7). Documented in the reference doc. |
| `jq` parse failure on malformed API response | Low | Low | Surface stderr verbatim and exit non-zero (NFR-1 carve-out for internal script errors). |

## Success Criteria

Per the FEAT-034 acceptance-criteria block:
- `pr-comment.sh` exists on ADO with signature parity to GitHub (Phases 1+2).
- Backend auto-detected via `backend-detect.sh` and `SDLC_SCM_BACKEND` override (Phases 1+2).
- Round-trip integration test passes when env-gated credentials are present (Phase 5).
- `list-pr-comments.sh` emits the FR-5 NDJSON schema identically across backends (Phase 3).
- Consumer skills like `/review` post ADO PR comments without backend-specific branching (Phases 1-3 collectively).
- SKILL.md is updated (entry-point table, graceful-degradation matrix, References) (Phase 4).
- All graceful-degradation paths exit 0 with `[warn]` (Phases 1-3, exercised by Bats).
- `az devops invoke` resource-name probe is implemented with deterministic fallback order and one-shot caching (Phase 2).
- All new bash scripts pass `shellcheck` (Phases 1-3 deliverables).
- All new Bats tests pass under `npm run test:bats` (Phases 1-3, Phase 5 when env-gated).
