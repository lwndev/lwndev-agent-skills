# PR Comments -- Azure DevOps

Reference for `pr-comment.sh` and `list-pr-comments.sh` on the ADO backend (FEAT-034 / FR-2 / FR-3 / FR-4 / FR-5).

## ADO PR-Thread API Surface

All endpoints require `api-version=7.1` and use `{org}` as the bare organization name (e.g. `contoso`). The full organization URL form is `https://dev.azure.com/{org}/`.

| Operation | Method | Path |
|-----------|--------|------|
| Create thread (top-level comment) | POST | `https://dev.azure.com/{org}/{project}/_apis/git/repositories/{repoId}/pullRequests/{prId}/threads` |
| Reply to thread (add comment) | POST | `https://dev.azure.com/{org}/{project}/_apis/git/repositories/{repoId}/pullRequests/{prId}/threads/{threadId}/comments` |
| List threads + comments | GET | `https://dev.azure.com/{org}/{project}/_apis/git/repositories/{repoId}/pullRequests/{prId}/threads` |

`{repoId}` is resolved once per script invocation via:

```bash
az repos show --repository <name> --project <project> --organization https://dev.azure.com/<org>/ --query id -o tsv
```

## Payload Shapes

### Create top-level thread

```json
{
  "comments": [
    {
      "parentCommentId": 0,
      "content": "<markdown body>",
      "commentType": 1
    }
  ],
  "status": 1
}
```

- `commentType: 1` = text (the only type used by these scripts).
- `status: 1` = active thread.
- `parentCommentId: 0` = no parent (first comment in the thread).

Always built with `jq -n --arg body "$body" '...'` -- do not paste-concat to avoid quoting bugs.

### Reply to existing thread

```json
{
  "parentCommentId": <previousLeafCommentId | 0>,
  "content": "<markdown body>",
  "commentType": 1
}
```

The script GETs the existing thread first and sets `parentCommentId` to the maximum `id` among `.comments[]`. Empty thread (no existing comments) uses `parentCommentId: 0`.

## `parentCommentId` Semantics

ADO uses `parentCommentId` to build the visual reply chain in the UI. Rules:

- A top-level comment in a new thread uses `parentCommentId: 0`.
- A reply within a thread uses the `id` of the comment being replied to. Setting this to the highest existing `id` in the thread positions the reply at the leaf, which produces the expected chronological chain.
- `parentCommentId` is unrelated to `threadId` -- the thread groups comments; `parentCommentId` chains them within the thread.

## Resource-Name Probe

`az devops invoke` requires an exact `--resource` token. The token that works varies across ADO tenants and API versions (`PullRequestThreads`, `pullrequestthreads`, and `threads` have all been observed). The scripts probe in order:

1. `PullRequestThreads`
2. `pullrequestthreads`
3. `threads`

Each probe issues a `GET` against the threads-list route for the target PR using `az devops invoke --http-method GET`. The first candidate returning HTTP 200 wins. An empty thread list (`{"value":[],"count":0}`) counts as 200 -- the probe is not looking for data, only for a successful route.

Official API reference: https://learn.microsoft.com/en-us/rest/api/azure/devops/git/pull-request-threads

On full exhaustion (all three candidates fail), the script:
1. Writes the `probe-failed` sentinel to the cache file.
2. Emits `[warn] ADO PR-thread resource probe failed across [PullRequestThreads, pullrequestthreads, threads]. Skipping comment.` on stderr.
3. Exits 0 (graceful skip -- NFR-1).

## Probe Cache

Cache file: `/tmp/sdlc-azdo-pr-thread-resource.<org>.<repo>`

Format (two lines):

```
<unix-timestamp>
<resource-token | probe-failed>
```

Rules:

- Written on first successful probe or on probe exhaustion.
- TTL: 24 hours from the timestamp on line 1. A cache entry older than 86400 seconds is ignored and the probe re-runs.
- Cache-hit fast path: if the cache file exists, is fresh, and line 2 is not `probe-failed`, the stored token is used directly -- no `az devops invoke` probe calls are made.
- Sentinel fast path: if line 2 is `probe-failed` and the cache is still fresh, the script emits the `[warn]` and exits 0 immediately.
- Manual invalidation: `rm /tmp/sdlc-azdo-pr-thread-resource.*` forces a re-probe on the next invocation. The `[warn]` message on a sentinel cache-hit includes this hint so the user is not stuck on a transient network failure that wrote `probe-failed`.
- Scope: per `<org>.<repo>` -- different repos in the same org get separate cache files.

## `az devops invoke` Invocation Shape

```bash
az devops invoke \
  --area git \
  --resource <probed-token> \
  --route-parameters "project=<proj>" "repositoryId=<repoId>" "pullRequestId=<prId>" \
  --http-method POST \
  --in-file <payload.json> \
  --api-version 7.1 \
  --organization "https://dev.azure.com/<org>/"
```

For reply, add `"threadId=<id>"` to `--route-parameters` and use `--http-method POST` against the comments sub-route (the resource token stays the same; `az devops invoke` derives the path from route-parameters).

## `curl` Fallback Path (FR-4)

Triggered when:
- `SDLC_AZDO_HTTP=curl` is set (force flag).
- `az devops invoke` POST returns non-zero (automatic fall-through).

Auth header: `Authorization: Basic $(printf ':%s' "$AZURE_DEVOPS_PAT" | base64)`

PAT scope required: `vso.code_write`.

Create thread URL:

```
https://dev.azure.com/<org>/<project>/_apis/git/repositories/<repoId>/pullRequests/<prId>/threads?api-version=7.1
```

Reply URL:

```
https://dev.azure.com/<org>/<project>/_apis/git/repositories/<repoId>/pullRequests/<prId>/threads/<threadId>/comments?api-version=7.1
```

When `AZURE_DEVOPS_PAT` is unset on the `curl` path, the script emits:

```
[warn] AZURE_DEVOPS_PAT not set; cannot post PR comment via raw HTTP. Skipping.
```

and exits 0. This is a graceful skip, not a hard failure.

## Graceful-Degradation Summary

| Condition | Response |
|-----------|----------|
| `az` not on PATH | `[warn] Azure CLI (az) not found on PATH.` Skip. Exit 0. |
| `az devops` extension missing | `[warn] az devops extension not available -- run az extension add --name azure-devops.` Skip. Exit 0. |
| `az` not logged in | `[warn] Azure CLI not authenticated -- run az login (Azure AD) or az devops login --pat <token>.` Skip. Exit 0. |
| `az repos show` fails | `[warn] az repos show failed: <first stderr line>.` Skip. Exit 0. |
| Probe exhausted | `[warn] ADO PR-thread resource probe failed across [PullRequestThreads, pullrequestthreads, threads]. Skipping comment.` Exit 0. |
| `AZURE_DEVOPS_PAT` unset on curl path | `[warn] AZURE_DEVOPS_PAT not set; cannot post PR comment via raw HTTP. Skipping.` Exit 0. |
| `--reply-to <id>` thread not found (404) | `[warn] ADO thread <id> not found; skipping reply.` Exit 0. |
| `az devops invoke` POST fails, no PAT set | `[warn] az devops invoke (<op>) failed: <first stderr line>.` Exit 0. |

## See Also

- `${CLAUDE_PLUGIN_ROOT}/skills/managing-source-control/scripts/pr-comment.sh` -- full dispatcher implementation.
- `${CLAUDE_PLUGIN_ROOT}/skills/managing-source-control/scripts/list-pr-comments.sh` -- threads-to-NDJSON implementation.
- [pr-comments-github.md](pr-comments-github.md) -- GitHub backend reference.
