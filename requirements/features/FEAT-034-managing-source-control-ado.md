# Feature Requirements: managing-source-control ADO PR comment support

## Overview
Extend the `managing-source-control` skill so the Azure DevOps (`azdo`) backend can post, list, and reply to pull-request comments — closing the parity gap with the GitHub (`gh`) backend so consumer skills like `/review` can write PR feedback regardless of SCM provider.

## Feature ID
`FEAT-034`

## GitHub Issue
[#280](https://github.com/lwndev/lwndev-marketplace/issues/280)

## Priority
Medium — Unblocks `/review` and any other consumer skill that posts PR feedback on ADO-hosted repos. Workaround today is manual comment posting via the ADO web UI, which breaks the inline-skill contract.

## User Story
As a developer using `lwndev-sdlc` against an Azure DevOps repository, I want consumer skills (`/review`, future PR-feedback skills) to post comments on my ADO PRs the same way they do on GitHub PRs, so that my workflow does not bifurcate by backend.

## Command Syntax (script entry points)

The skill exposes three new bash entry points under `plugins/lwndev-sdlc/skills/managing-source-control/scripts/`, dispatched by backend exactly like the existing `create-pr.sh` / `view-pr.sh` family.

### `pr-comment.sh`

Post a top-level comment (new thread on ADO) on a pull request.

```bash
pr-comment.sh <pr-number> <body>
pr-comment.sh <pr-number> --body-file <path>
pr-comment.sh <pr-number> --body <body> --reply-to <thread-id>
```

#### Arguments
- `<pr-number>` (required) — Numeric PR identifier (GitHub: PR number; ADO: `pullRequestId`).
- `<body>` (positional, optional) — Markdown comment body. Mutually exclusive with `--body-file` and `--body`.

#### Options
- `--body <markdown>` — Explicit body flag (equivalent to positional).
- `--body-file <path>` — Read body from file. Required when body exceeds ~8KB or contains characters that would mangle through shell quoting.
- `--reply-to <thread-id>` — Reply to existing thread. On ADO this maps to appending a comment with `parentCommentId` to the named `threadId`; on GitHub this is rejected (graceful skip with `[warn]`) — GitHub uses linear PR comments without thread reply semantics in the unified comment API. Value MUST be a non-negative integer; non-numeric values exit non-zero with `[error] --reply-to must be a numeric thread id` (client-side validation, runs before backend dispatch).

Body-source flags are mutually exclusive — passing more than one of `<positional>`, `--body`, `--body-file` exits non-zero with `[error] body source ambiguous: pass exactly one of <positional> / --body / --body-file`.

#### Examples
```bash
# Top-level comment
plugins/lwndev-sdlc/skills/managing-source-control/scripts/pr-comment.sh 127 "LGTM"

# Long body from file
plugins/lwndev-sdlc/skills/managing-source-control/scripts/pr-comment.sh 127 --body-file /tmp/review.md

# Reply to thread (ADO only)
plugins/lwndev-sdlc/skills/managing-source-control/scripts/pr-comment.sh 1761 \
  --body "Addressed in commit abc123" --reply-to 9
```

### `list-pr-comments.sh`

List comments / threads on a pull request as newline-delimited JSON, one record per comment.

```bash
list-pr-comments.sh <pr-number>
list-pr-comments.sh <pr-number> --json
```

#### Arguments
- `<pr-number>` (required) — Numeric PR identifier.

#### Options
- `--json` — Default behavior; emit NDJSON. Reserved for forward compatibility if a tabular default is ever added.

### `pr-comment-thread.sh` (stretch / Phase 2)

Inline file-line comment. Out of scope for v1 but the script name is reserved so the API surface stays stable.

```bash
pr-comment-thread.sh <pr-number> --file <path> --line <line-num> --body <markdown>
```

Implementation deferred to a follow-up (see Future Enhancements).

## Functional Requirements

### FR-1: GitHub backend — post top-level comment
- `pr-comment.sh <pr-number> <body>` on the GitHub backend invokes `gh pr comment <pr-number> --body <body>` (or `--body-file` when the flag was passed).
- On success, the script emits the comment URL to stdout (the same URL `gh pr comment` returns) and exits 0.
- `--reply-to` is rejected on GitHub: log `[warn] --reply-to not supported on GitHub backend; skipping.` and exit 0 (graceful skip — NFR-1).

### FR-2: ADO backend — post top-level comment
- `pr-comment.sh <pr-number> <body>` on the ADO backend posts a new PR thread containing a single text comment via the REST API:
  - Endpoint: `POST {organization}/{project}/_apis/git/repositories/{repositoryId}/pullRequests/{pullRequestId}/threads?api-version=7.1`
  - Payload: `{"comments":[{"parentCommentId":0,"content":"<markdown>","commentType":1}],"status":1}` (`status:1` = active, `commentType:1` = text).
- The script resolves `{repositoryId}` via `az repos show --repository <repo> --project <project> --organization https://dev.azure.com/<org>/ --query id -o tsv` and caches it for the duration of the call.
- On success, the script emits the PR comment URL (`https://dev.azure.com/{org}/{project}/_git/{repo}/pullrequest/{pullRequestId}?discussionId={threadId}`) to stdout and exits 0.

### FR-3: ADO backend — reply to existing thread
- `pr-comment.sh <pr-number> --body <body> --reply-to <thread-id>` posts a follow-up comment to an existing thread:
  - Endpoint: `POST {organization}/{project}/_apis/git/repositories/{repositoryId}/pullRequests/{pullRequestId}/threads/{threadId}/comments?api-version=7.1`
  - Payload: `{"parentCommentId":<previousLeafCommentId or 0>,"content":"<markdown>","commentType":1}`
- The script first lists existing comments on `{threadId}` to determine the most recent `parentCommentId` (so replies thread visually in the ADO UI). On empty thread fall back to `parentCommentId: 0`.
- On success emit the reply URL and exit 0.

### FR-4: Authentication path selection (ADO)
- The script prefers `az devops invoke` when available (consistent with the rest of the skill) and only falls through to raw `curl` when `az devops invoke` fails or when the user has set `SDLC_AZDO_HTTP=curl` to force the HTTP path.
- For the `curl` path, build the auth header as `Authorization: Basic $(printf ':%s' "$AZURE_DEVOPS_PAT" | base64)` and require `AZURE_DEVOPS_PAT` (PAT scope `vso.code_write`). When the env var is unset, log `[warn] AZURE_DEVOPS_PAT not set; cannot post PR comment via raw HTTP. Skipping.` and exit 0 (graceful skip).
- For the `az devops invoke` path, use:
  ```
  az devops invoke \
    --area git --resource PullRequestThreads \
    --route-parameters project=<proj> repositoryId=<repoId> pullRequestId=<num> \
    --http-method POST --in-file <payload.json> \
    --api-version 7.1 --organization https://dev.azure.com/<org>/
  ```
  The exact `--resource` token MUST be probed against the live API at script load (one-shot, cached for the call) — the issue notes that `threads` and `pullRequestThreads` both return errors. The probe attempts `PullRequestThreads`, then `pullrequestthreads`, then `threads` in that order, each with `--http-method GET` against the threads-list route (`{prId}/threads`) — the first one that returns HTTP 200 wins (an empty thread list returns 200 with `{"value":[],"count":0}`; we are not relying on a discovery `OPTIONS` verb because `az devops invoke` does not expose one). Cache the resolved token in `/tmp/sdlc-azdo-pr-thread-resource.<org>.<repo>`. The cache is invalidated by: (a) age > 24h (TTL check at script load), (b) explicit `rm /tmp/sdlc-azdo-pr-thread-resource.*` by the user. There is no `make clean` target in this repo; the npm-based build system has no equivalent and the cache file is intentionally session-tolerant.

### FR-5: List PR threads / comments
- `list-pr-comments.sh <pr-number>` emits NDJSON, one record per comment, in chronological order. Schema:
  ```json
  {"thread_id":<int>,"comment_id":<int>,"parent_comment_id":<int>,"author":"<displayName>","author_unique_name":"<email>","published":"<ISO-8601>","content":"<markdown>","status":"<active|fixed|wontFix|closed|pending|byDesign>","is_deleted":false,"thread_status":"<active|fixed|wontFix|closed|pending|byDesign|unknown>"}
  ```
  Field names are stable across backends; missing-on-GitHub fields use sentinel values (`thread_id: 0`, `thread_status: "unknown"`, `parent_comment_id: 0`).
- GitHub backend invokes `gh api repos/{owner}/{repo}/issues/{pr-number}/comments` and maps fields.
- ADO backend invokes `az devops invoke --area git --resource PullRequestThreads --route-parameters ... --http-method GET --api-version 7.1` (or `curl` fallback per FR-4) and flattens threads → comments preserving thread_id linkage.

### FR-6: Backend dispatch
- All three scripts call `backend-detect.sh` first and dispatch on the returned `backend` field exactly as `create-pr.sh` does today.
- When `backend-detect.sh` emits `null`, log `[info] No recognized SCM backend detected from origin. Skipping PR comment.` and exit 0 (graceful skip).
- The `SDLC_SCM_BACKEND` env override is honored — same semantics as the existing dispatched scripts.

### FR-7: SKILL.md entry-point table update
- The Script Entry Points table in `plugins/lwndev-sdlc/skills/managing-source-control/SKILL.md` gains two rows in v1: `pr-comment.sh` and `list-pr-comments.sh`, each marked `dispatched`. The deferred `pr-comment-thread.sh` is NOT added to the entry-point table in v1 — it ships with its own SKILL.md row in the Phase 2 follow-up to keep consumer skills from probing for an entry point that does not exist yet.
- The SKILL.md graceful-degradation matrix gains a row for `AZURE_DEVOPS_PAT not set on curl fallback path` mapping to `[warn] ... Skip. Exit 0.` per NFR-1.

## Output Format

`pr-comment.sh` stdout (one URL line, both backends):
```
https://github.com/lwndev/lwndev-marketplace/pull/127#issuecomment-1234567890
https://dev.azure.com/contoso/sdlc-tools/_git/plugin-repo/pullrequest/42?discussionId=9
```

`list-pr-comments.sh` stdout (NDJSON, one comment per line; example shows two comments in one ADO thread):
```
{"thread_id":9,"comment_id":17,"parent_comment_id":0,"author":"Alice","author_unique_name":"alice@example.com","published":"2026-05-17T10:14:22Z","content":"Please rename `foo` to `bar`.","status":"active","is_deleted":false,"thread_status":"active"}
{"thread_id":9,"comment_id":18,"parent_comment_id":17,"author":"Bob","author_unique_name":"bob@example.com","published":"2026-05-17T10:21:09Z","content":"Done in abc123.","status":"active","is_deleted":false,"thread_status":"active"}
```

Tagged log lines (stderr) follow the repo convention:
```
[info] No recognized SCM backend detected from origin. Skipping PR comment.
[warn] AZURE_DEVOPS_PAT not set; cannot post PR comment via raw HTTP. Skipping.
[warn] --reply-to not supported on GitHub backend; skipping.
[warn] az devops invoke failed; falling back to raw HTTP via curl.
```

## Non-Functional Requirements

### NFR-1: Graceful degradation
- Every failure mode listed in the SKILL.md graceful-degradation matrix MUST exit 0 and skip the PR-comment step rather than halt the workflow. This includes: missing CLI, missing auth, unrecognized origin, network error, 404 on PR/thread, non-2xx HTTP response, `az devops invoke` resource-name probe failure (after exhausting fallbacks).
- Internal script errors (jq parse failure, missing required positional arg) MUST exit non-zero with stderr surfaced verbatim — same boundary as existing dispatched scripts.

### NFR-2: Performance
- Post-comment latency target: < 3s p50 on both backends over a typical residential network. The `az devops invoke` resource-name probe is a one-shot per script invocation (cached for the duration of the call) and SHOULD be lazily executed only when `pr-comment.sh` is actually called against the ADO backend.
- `list-pr-comments.sh` MUST stream NDJSON as records become available rather than buffering an entire thread tree in memory — relevant for PRs with hundreds of comments. (In practice both backends return all threads in one API call, so this is a future-proofing note rather than a hard streaming requirement in v1.)

### NFR-3: Error handling
- All HTTP / CLI failures emit a single `[warn]` line with the first line of stderr (matches existing dispatched scripts).
- The ADO resource-name probe records its outcome on first run in `/tmp/sdlc-azdo-pr-thread-resource.<org>.<repo>`; on probe exhaustion the cache file records the literal `probe-failed` token and subsequent invocations short-circuit to `[warn] ADO PR-thread resource probe previously failed; skipping. Re-run with SDLC_AZDO_HTTP=curl to force raw-HTTP path.` (so consumers do not pay the probe cost on every PR comment in a session).

### NFR-4: Compatibility with consumer skills
- The `/review` skill and any future consumer skill MUST be able to call `pr-comment.sh <pr-number> --body-file <path>` without backend-specific branching. The dispatched script handles all backend differences internally.

## API Integration

ADO REST API endpoints used (all under `api-version=7.1`):

| Operation | Method | Path |
|-----------|--------|------|
| Create thread (top-level comment) | POST | `{org}/{project}/_apis/git/repositories/{repoId}/pullRequests/{prId}/threads` |
| Reply to thread | POST | `{org}/{project}/_apis/git/repositories/{repoId}/pullRequests/{prId}/threads/{threadId}/comments` |
| List threads / comments | GET | `{org}/{project}/_apis/git/repositories/{repoId}/pullRequests/{prId}/threads` |
| Resolve repo ID | GET | `az repos show --repository <name> --project <proj> --query id` |

GitHub REST API endpoints used (via `gh`):

| Operation | gh command |
|-----------|------------|
| Post issue comment (top-level PR comment) | `gh pr comment <pr-number> --body|--body-file` |
| List PR comments | `gh api repos/{owner}/{repo}/issues/{pr-number}/comments` |

## Dependencies

- `gh` CLI (GitHub backend) — already required by the skill.
- `az` CLI with the `azure-devops` extension (ADO backend) — already required by the skill.
- `curl` (ADO raw-HTTP fallback) — present on every supported platform (Linux, macOS, WSL).
- `jq` (JSON parsing) — already required by the skill.
- `base64` (auth header encoding for curl fallback) — present on every supported platform.

No new runtime dependencies beyond what `managing-source-control` already requires.

## Edge Cases

1. **PR closed/abandoned**: ADO threads are still postable on closed PRs; GitHub `gh pr comment` succeeds on closed PRs. Behavior is unchanged — the script does not pre-check PR state.
2. **Empty body**: Both backends reject empty bodies. Surface the CLI error verbatim and exit non-zero (this is a user error, not a graceful-degradation case).
3. **Body file does not exist**: `--body-file /missing/path` exits non-zero with `[error] body file not found: /missing/path` on stderr.
4. **Resource-name probe exhausts all fallbacks on a fresh org**: Log `[warn] ADO PR-thread resource probe failed across [PullRequestThreads, pullrequestthreads, threads]. Skipping comment.` and exit 0 (graceful skip). The probe-failed sentinel is cached so subsequent calls short-circuit.
5. **Concurrent `pr-comment.sh` invocations**: ADO thread IDs are server-allocated and atomic — no client-side coordination needed. The script does not lock.
6. **`--reply-to <invalid-thread-id>`**: ADO returns 404; the script emits `[warn] ADO thread <id> not found; skipping reply.` and exits 0.
7. **Body containing markdown that ADO renders differently than GitHub** (e.g. `~~strikethrough~~`, GFM tables): the script does NOT transform body content. Consumers handle backend-specific rendering quirks themselves; this skill is a transport.
8. **PR number that does not exist**: Both backends return 404; the script emits `[warn] PR <num> not found on <backend>; skipping comment.` and exits 0.
9. **Multi-line body via positional arg**: shell quoting limits apply — consumers MUST use `--body-file` for bodies that contain backticks, dollar signs, or other shell-meaningful characters. The skill does not attempt to escape.
10. **GitHub PR with no comments**: `list-pr-comments.sh` emits zero NDJSON records and exits 0.
11. **Multiple body sources passed** (e.g. positional + `--body-file`, or `--body` + `--body-file`): exit non-zero with `[error] body source ambiguous: pass exactly one of <positional> / --body / --body-file` on stderr. Treated as a user error, not graceful degradation.
12. **Non-numeric `--reply-to` value**: `--reply-to foo` exits non-zero with `[error] --reply-to must be a numeric thread id` on stderr. Client-side validation runs before any backend dispatch.
13. **List-pr-comments graceful skip stdout**: on any FR-6 graceful-skip path (unrecognized backend, missing CLI, missing auth, `null` from `backend-detect.sh`), `list-pr-comments.sh` emits zero NDJSON records on stdout, the corresponding `[info]` / `[warn]` line on stderr, and exits 0. Consumer skills MUST handle the empty-stream case (zero records is a valid result).
14. **Probe cache poisoning on transient network failure**: if the probe records `probe-failed` because of a transient outage, the 24h TTL (NFR-3) auto-clears the entry; in the meantime, the user can `rm /tmp/sdlc-azdo-pr-thread-resource.<org>.<repo>` to force an immediate re-probe. The `[warn]` message on cache-hit-after-failure includes the explicit re-probe hint so the user is not stuck.

## Testing Requirements

### Unit Tests (Bats)

Located at `tests/bats/skills/managing-source-control/`.

- `pr-comment-github.bats` — `gh` mocked with an inline stub built in `setup()` on a per-test `STUBDIR` (same pattern as `create-pr.bats`, `merge-pr.bats`, `view-pr.bats` already in this directory). Cases: top-level comment, `--body-file`, `--reply-to` skip with `[warn]`, missing PR (404 skip), empty body rejection.
- `pr-comment-azdo.bats` — `az` (and `curl` for the raw-HTTP path) mocked with the same inline-stub pattern. Cases: top-level thread create, reply with `parentCommentId` resolution, missing-PAT skip, resource-name probe success on first/second/third token, probe-failure skip.
- `list-pr-comments.bats` — both backends; assert NDJSON shape and field stability.
- `pr-comment-dispatch.bats` — assert `backend-detect.sh` null → graceful skip, env override behavior matches existing dispatched scripts.

### Unit Tests (Vitest)

None — the scripts are bash; no TS modules are added.

### Integration Tests

- **Round-trip (GitHub)**: against a sacrificial PR on a private test repo (env-gated via `SDLC_INTEGRATION_GITHUB_PR_URL`), post a comment, list comments, assert the posted comment appears with matching body and author. Skip the test when the env var is unset (CI does not have credentials).
- **Round-trip (ADO)**: same pattern, env-gated via `SDLC_INTEGRATION_AZDO_PR_URL` + `AZURE_DEVOPS_PAT`. Skip when either env var is unset.

### Manual Testing

- On a real ADO PR (e.g. ADO PR #1761 — the Azure DevOps PR number that surfaced this issue; not a GitHub issue reference), run `pr-comment.sh <pr> "manual test"` and verify the comment appears in the ADO web UI.
- On a real GitHub PR, run the same command and verify the comment appears.
- Trigger every graceful-degradation path manually (unset `AZURE_DEVOPS_PAT`, point at a closed PR, use a bogus PR number).

## Future Enhancements

- **Inline file-line comments** (stretch goal from issue #280): post a thread anchored to `threadContext.filePath` + `rightFileStart`/`rightFileEnd`. Reserved as `pr-comment-thread.sh` in the entry-point table but not implemented in v1. GitHub backend would use `gh api repos/.../pulls/<num>/comments` with `path`/`line`/`side` fields.
- **Thread status transitions** (`active` → `fixed` / `wontFix` / `byDesign`): currently the skill only creates threads in `active` state. A `pr-comment-status.sh` could let consumer skills mark threads resolved.
- **Suggested-edit comments** (GitHub suggestion blocks; ADO equivalent): out of scope for v1.
- **Bulk-comment ingest from review output**: a higher-level `post-review.sh` that takes a structured `/review` artifact and posts a thread per finding. Belongs in `/review` rather than `managing-source-control`.

## Acceptance Criteria

- [ ] `pr-comment.sh` exists on the ADO backend with signature parity to the GitHub backend (positional body, `--body`, `--body-file`, `--reply-to`).
- [ ] Backend is auto-detected from origin URL or `SDLC_SCM_BACKEND` env override — no explicit `--backend` flag on the new scripts.
- [ ] Round-trip integration test (post comment, list threads, assert presence) passes on both GitHub and ADO test PRs when env-gated credentials are available.
- [ ] `list-pr-comments.sh` emits NDJSON with the schema defined in FR-5, identical field names across backends.
- [ ] `/review` (and any other consumer skill) can post ADO PR comments without backend-specific branching or extra arguments.
- [ ] SKILL.md is updated: Script Entry Points table, graceful-degradation matrix, References section (if new reference docs are added).
- [ ] All graceful-degradation paths exit 0 with a `[warn]` line — no failure mode halts the workflow (NFR-1).
- [ ] The `az devops invoke` resource-name probe is implemented with a deterministic fallback order and one-shot caching (FR-4 NFR-3).
- [ ] All new bash scripts pass `shellcheck` (matches existing scripts in this skill).
- [ ] All new Bats tests pass under `npm run test:bats`.
