# PR Comments -- GitHub

Reference for `pr-comment.sh` and `list-pr-comments.sh` on the GitHub backend (FEAT-034 / FR-1 / FR-5).

## GitHub PR-Comment API Surface

GitHub PR comments use the Issues comments API (linear -- no thread reply semantics in the unified endpoint).

### `gh pr comment` (post)

```bash
gh pr comment <pr-number> --body "<markdown>"
gh pr comment <pr-number> --body-file <path>
```

Flags used by `pr-comment.sh`:

| Flag | Purpose |
|------|---------|
| `--body <text>` | Inline comment body. |
| `--body-file <path>` | Read body from file. Use for bodies > ~8KB or containing shell-meaningful chars. |

On success, `gh pr comment` emits the comment URL to stdout:

```
https://github.com/<owner>/<repo>/pull/<pr-number>#issuecomment-<id>
```

`pr-comment.sh` passes this URL through to its own stdout unchanged.

### `gh api` (list)

```bash
gh api repos/<owner>/<repo>/issues/<pr-number>/comments
```

Returns a JSON array of comment objects in chronological order. Each object has at minimum:

| Field | Type | Description |
|-------|------|-------------|
| `id` | integer | Comment ID (globally unique within the repo). |
| `user.login` | string | Author's GitHub login. |
| `created_at` | string | ISO-8601 creation timestamp. |
| `body` | string | Markdown comment body. |

GitHub issue comments have no `thread_id`, no `parent_comment_id`, and no thread status -- they are a flat chronological list.

## NDJSON Field Mapping (FR-5)

`list-pr-comments.sh` maps each GitHub comment to the FR-5 NDJSON schema. Thread-aware fields are absent from the GitHub API and use sentinel values.

| FR-5 field | GitHub source | Sentinel / Notes |
|------------|---------------|-----------------|
| `thread_id` | -- | `0` (no thread model) |
| `comment_id` | `.id` | |
| `parent_comment_id` | -- | `0` (no reply chain) |
| `author` | `.user.login` | GitHub login, not display name |
| `author_unique_name` | `.user.login` | Same as `author` on GitHub (no separate unique-name field) |
| `published` | `.created_at` | ISO-8601 |
| `content` | `.body` | Raw markdown |
| `status` | -- | `"active"` (GitHub does not expose per-comment status) |
| `is_deleted` | -- | `false` (deleted comments are not returned by the API) |
| `thread_status` | -- | `"unknown"` (no thread concept) |

Example output (one GitHub comment):

```json
{"thread_id":0,"comment_id":1234567890,"parent_comment_id":0,"author":"alice","author_unique_name":"alice","published":"2026-05-17T10:14:22Z","content":"LGTM","status":"active","is_deleted":false,"thread_status":"unknown"}
```

## `--reply-to` Not Supported on GitHub

GitHub's unified issue comments endpoint (`/issues/{pr}/comments`) does not expose thread reply semantics -- all comments are siblings in a flat list. If `pr-comment.sh` receives `--reply-to` on a GitHub origin, it emits:

```
[warn] --reply-to not supported on GitHub backend; skipping.
```

and exits 0 (graceful skip -- NFR-1). This is by design: the thread reply contract only applies to the ADO backend.

Consumer skills that need cross-backend reply support should pass the body as a top-level comment on GitHub and accept that the thread linkage will be missing.

## Graceful-Degradation Summary

| Condition | Response |
|-----------|----------|
| `gh` not on PATH | `[warn] GitHub CLI (gh) not found on PATH.` Skip. Exit 0. |
| `gh auth status` fails | `[warn] GitHub CLI not authenticated -- run gh auth login.` Skip. Exit 0. |
| `--reply-to` set on GitHub backend | `[warn] --reply-to not supported on GitHub backend; skipping.` Exit 0. |
| `gh pr comment` exits non-zero | `[warn] gh pr comment failed: <first stderr line>.` Exit 0. |
| `gh api` exits non-zero (list) | `[warn] PR <num> not found on github; skipping comment.` Zero NDJSON records. Exit 0. |

## See Also

- `${CLAUDE_PLUGIN_ROOT}/skills/managing-source-control/scripts/pr-comment.sh` -- full dispatcher implementation.
- `${CLAUDE_PLUGIN_ROOT}/skills/managing-source-control/scripts/list-pr-comments.sh` -- comments-to-NDJSON implementation.
- [pr-comments-azdo.md](pr-comments-azdo.md) -- Azure DevOps backend reference (thread API, probe, cache, curl fallback).
