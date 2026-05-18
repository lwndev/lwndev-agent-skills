---
id: FEAT-034
version: 2
timestamp: 2026-05-17T13:51:00Z
persona: qa
---

## User Summary

Developers using `lwndev-sdlc` against an Azure DevOps repository need consumer skills (`/review`, future PR-feedback skills) to post comments on ADO PRs the same way they post on GitHub PRs, so their workflow does not bifurcate by SCM backend. The change adds `pr-comment.sh` and `list-pr-comments.sh` script entry points to the `managing-source-control` skill with backend dispatch between `gh` and `az` (or `curl` for the raw-HTTP fallback path) and a probe-and-cache mechanism for the elusive ADO PR-threads REST resource name.

## Capability Report

- Mode: test-framework
- Framework: vitest (+ bats for shell scripts)
- Package manager: npm
- Test command: npm test
- Language: typescript (shell scripts under test via bats)

## Scenarios (by dimension)

### Inputs

- [P0] Positional body containing single quotes, double quotes, backticks, and `$VAR` substitutions — assert body posts verbatim and shell does not expand or strip | mode: test-framework | expected: bats — stub gh/az, capture invocation args, assert exact byte-for-byte body match
- [P0] `--body-file` pointing at a file containing a 10MB markdown body (exceeds typical `argv` limits) — assert script reads file rather than embedding via argv | mode: test-framework | expected: bats — synthesize a large fixture file, assert stub receives `--body-file` not `--body`, no `E2BIG`
- [P0] `--body-file` pointing at a non-existent path — assert non-zero exit and `[error] body file not found: <path>` on stderr | mode: test-framework | expected: bats — pass `/nonexistent`, assert exit ≠ 0 and stderr match
- [P0] Multiple body sources passed simultaneously (positional + `--body`; `--body` + `--body-file`; all three) — assert exit non-zero with `[error] body source ambiguous: pass exactly one of <positional> / --body / --body-file` | mode: test-framework | expected: bats — all three permutations, assert error string
- [P0] Empty body `pr-comment.sh 1 ""` — assert script surfaces backend CLI error (gh rejects empty bodies) and exits non-zero | mode: test-framework | expected: bats — stub gh to exit 1 with realistic stderr, assert orchestrator propagates exit code
- [P1] `--reply-to foo` (non-numeric) — assert exit non-zero with `[error] --reply-to must be a numeric thread id` and that no backend invocation occurs (validate before dispatch) | mode: test-framework | expected: bats — record stub invocations, assert zero gh/az calls
- [P1] `--reply-to -1` and `--reply-to 0` boundary — assert behavior: 0 should mean "no parent" semantically (top-level on ADO is `parentCommentId: 0`); negative integers should be rejected | mode: test-framework | expected: bats — explicit cases for 0 and -1, assert -1 rejected, 0 mapped to top-level
- [P1] `--reply-to <huge>` (e.g. `999999999999`) — passed through to ADO; assert script does not truncate or overflow when shelling out | mode: test-framework | expected: bats — assert stub receives the integer as a string, not a truncated int
- [P1] Body containing literal `\n` (escaped newline) vs actual newline — assert script preserves what was passed; no double-escaping | mode: test-framework | expected: bats — both variants, assert exact byte sequence reaches the stub
- [P1] Body containing RTL Unicode (Hebrew/Arabic), combining characters, ZWJ emoji sequences — assert UTF-8 is preserved verbatim through to the API payload | mode: test-framework | expected: bats — fixture with `שלום`, family-emoji `👨‍👩‍👧‍👦`, assert byte-exact passthrough
- [P1] Body containing a closing markdown fence followed by injection (` ``` ` then `--reply-to=99`) — assert no argument-injection through body content | mode: test-framework | expected: bats — assert body shows up in `--body`/`--body-file` payload, not parsed as flags
- [P1] PR number `0`, negative, non-numeric (`abc`) — assert script validates client-side before backend dispatch; non-numeric exits non-zero before any CLI invocation | mode: test-framework | expected: bats — assert zero stub calls and explicit error message
- [P2] `list-pr-comments.sh` invoked with extra/unknown flags (`--format json`, `--limit 10`) — assert script either ignores or rejects deterministically; do not pass through unknown flags to `gh`/`az` (avoid injection risk) | mode: test-framework | expected: bats — assert unknown-flag rejection or documented passthrough

### State transitions

- [P0] Concurrent `pr-comment.sh` invocations against the same PR — both should succeed independently; ADO server-allocates thread IDs atomically and the script does not lock | mode: test-framework | expected: bats — spawn two background invocations against a stubbed backend, assert both succeed and produce distinct mocked thread IDs
- [P0] Probe-and-cache race: two parallel first-time invocations both write `/tmp/sdlc-azdo-pr-thread-resource.<org>.<repo>` — assert no partial-write corruption (cache file contains a single valid token, not a concatenation) | mode: test-framework | expected: bats — parallel invocations with `flock` or atomic-rename verification; assert final cache content matches one of the three valid tokens
- [P0] `--reply-to` resolves `parentCommentId` by listing thread comments first; assert that a thread mutated between list-and-post still produces a valid reply (race resilience) | mode: exploratory | expected: manual — race condition on real ADO PR, document outcome
- [P0] `parentCommentId` resolution on an empty thread (just-created, no replies yet) — assert fallback to `parentCommentId: 0` per FR-3 | mode: test-framework | expected: bats — stub the comments-list endpoint to return empty array, assert payload uses `parentCommentId: 0`
- [P1] Probe-failed cache token (`probe-failed` sentinel) age > 24h — assert TTL invalidates and re-probe runs on next invocation | mode: test-framework | expected: bats — fixture an old cache file with `touch -t YYYYMMDDHHMM`, assert re-probe happens
- [P1] Probe-failed cache token age < 24h — assert short-circuit with `[warn] ADO PR-thread resource probe previously failed; skipping. ...` and zero backend invocations | mode: test-framework | expected: bats — fresh cache file with `probe-failed`, assert short-circuit and zero `az` invocations
- [P1] Cache file points to a stale (no-longer-working) resource token — first invocation succeeds (cached) but the API now returns 404 — assert graceful skip with `[warn]` (FR-4 NFR-3), not crash; assert cache is NOT auto-invalidated by a single 404 (would thrash on transient errors) | mode: test-framework | expected: bats — stub az to return 404 once, assert `[warn]` and exit 0
- [P1] User runs `pr-comment.sh` against PR #N, then immediately against PR #N+1 in the same shell — assert the cached resource token persists across invocations and is not re-probed (perf) | mode: test-framework | expected: bats — assert single probe across two invocations
- [P2] Script killed mid-write to `/tmp/sdlc-azdo-pr-thread-resource.*` (SIGINT) — assert next invocation sees either the full pre-state or a clearly-invalid cache (NOT a half-written token that would be silently trusted) | mode: exploratory | expected: manual — Ctrl-C mid-probe, inspect cache file
- [P2] `list-pr-comments.sh` on a PR with thread count = 0 vs 1 vs 100+ — assert zero records emits empty stdout cleanly; high-count emits NDJSON streaming-friendly (no buffering past memory limit) | mode: test-framework | expected: bats — stub az with synthesized large thread payload, assert NDJSON record count matches

### Environment

- [P0] `gh` not on PATH (GitHub backend, all three operations) — assert `[warn] GitHub CLI (gh) not found on PATH.` to stderr, exit 0 (graceful skip per NFR-1) | mode: test-framework | expected: bats — empty PATH stub, assert exit 0 and stderr match
- [P0] `gh` on PATH but unauthenticated (`gh auth status` returns non-zero) — assert `[warn] GitHub CLI not authenticated -- run gh auth login.` and exit 0 | mode: test-framework | expected: bats — stub `gh auth status` to fail, assert exit 0
- [P0] `az` not on PATH (ADO backend) — assert `[warn] Azure CLI (az) not found on PATH.` and exit 0 | mode: test-framework | expected: bats — empty PATH for az, assert exit 0
- [P0] `az` on PATH but `azure-devops` extension missing — assert `[warn] az devops extension not available ...` and exit 0 | mode: test-framework | expected: bats — stub `az extension list` empty, assert exit 0
- [P0] `az` logged in but `AZURE_DEVOPS_PAT` unset on the curl-fallback path (forced via `SDLC_AZDO_HTTP=curl`) — assert `[warn] AZURE_DEVOPS_PAT not set; cannot post PR comment via raw HTTP. Skipping.` and exit 0 | mode: test-framework | expected: bats — `SDLC_AZDO_HTTP=curl` + unset PAT, assert exit 0
- [P1] Unrecognized origin remote (e.g. `gitlab.com`) — `backend-detect.sh` emits `null`, assert `[info] No recognized SCM backend detected from origin. Skipping PR comment.` and exit 0 | mode: test-framework | expected: bats — `git remote set-url` to gitlab in test fixture, assert exit 0
- [P1] `SDLC_SCM_BACKEND=azdo` but origin is github.com — assert `[warn] SDLC_SCM_BACKEND=azdo set but origin does not match azdo URL pattern.` and `null` (graceful skip) | mode: test-framework | expected: bats — env override mismatch, assert exit 0
- [P1] `git remote get-url origin` fails (no origin configured) — assert `null` from `backend-detect.sh` propagates as graceful skip | mode: test-framework | expected: bats — fixture repo with `git remote remove origin`, assert exit 0
- [P1] `/tmp` read-only or full — probe cache write fails — assert `[warn] could not write probe cache; falling back to re-probe each invocation` or similar, NOT a hard fail | mode: test-framework | expected: bats — `chmod 555 /tmp`-equivalent in a sandbox, assert exit 0 and re-probe behavior
- [P1] System clock skewed (e.g. file mtime in the future) — assert 24h TTL math handles future mtime gracefully (treat as fresh, not stale-but-negative-age crash) | mode: test-framework | expected: bats — `touch -t 209912312359 /tmp/sdlc-azdo-pr-thread-resource.*`, assert no crash and treat as fresh
- [P2] Slow / flaky network (gh/az hang for 30s+) — script should not hang indefinitely; assert reasonable timeout or that NFR-2 p50 < 3s target is observed under nominal conditions | mode: exploratory | expected: manual — `tc qdisc` or proxy delay, measure latency
- [P2] DNS resolution failure — assert `[warn]` with first line of stderr per the graceful-degradation matrix, exit 0 | mode: exploratory | expected: manual — broken `/etc/hosts` entry for `dev.azure.com`
- [P2] PAT containing `:` (the auth-header builder uses `printf ':%s' "$PAT" | base64`) — assert correct base64 output even when PAT contains colon, equals, or other base64-meaningful chars | mode: test-framework | expected: bats — PAT fixtures with special chars, assert auth header round-trips through `base64 -d`

### Dependency failure

- [P0] `gh pr comment` returns non-zero with structured error (rate-limit 403, PR not found 404, server 5xx) — assert `[warn]` with first line of stderr per the graceful-degradation matrix, exit 0 | mode: test-framework | expected: bats — stub gh to exit non-zero with each error class, assert exit 0
- [P0] `az devops invoke` returns the documented `--resource and --api-version combination is not correct` error on the first probe token — assert script falls through to second, then third token, then `probe-failed` sentinel | mode: test-framework | expected: bats — stub `az devops invoke` to exit 1 for `PullRequestThreads` and `pullrequestthreads`, succeed on `threads`; assert correct fallback chain and cache contents
- [P0] All three probe tokens fail — assert `probe-failed` recorded to cache and `[warn] ADO PR-thread resource probe failed across [PullRequestThreads, pullrequestthreads, threads]. Skipping comment.` emitted, exit 0 | mode: test-framework | expected: bats — stub all three to fail, assert exact warning string and cache state
- [P0] `curl` exit code 6 (could not resolve host) / 7 (could not connect) / 28 (timeout) on the raw-HTTP fallback — assert each is treated as graceful skip with `[warn]` containing first line of curl stderr, exit 0 | mode: test-framework | expected: bats — stub curl to exit with each code, assert exit 0
- [P0] ADO API returns HTTP 401 (auth) / 403 (forbidden) / 404 (PR not found) / 429 (rate limit) — assert each path: 401/403 = `[warn]` graceful skip; 404 = `[warn] PR <num> not found on azdo; skipping comment.`; 429 = `[warn]` graceful skip (no client-side retry in v1) | mode: test-framework | expected: bats — stub curl to return each status, assert exit 0
- [P1] ADO returns HTTP 200 but body is malformed JSON — assert `jq` parse failure surfaces as `[warn]` graceful skip, not unhandled crash | mode: test-framework | expected: bats — stub curl to return `{not json` body, assert `[warn]` and exit 0
- [P1] ADO returns HTTP 200 with empty body — assert script does not crash on empty `jq` input; either emit zero records (list) or `[warn]` (post) | mode: test-framework | expected: bats — stub curl with empty response, assert no jq crash
- [P1] `az repos show --query id -o tsv` (repo-ID resolution) returns empty or errors — assert script bails to graceful skip (cannot post without repo ID) | mode: test-framework | expected: bats — stub az to return empty stdout, assert exit 0
- [P1] `gh api repos/.../issues/<pr>/comments` returns 200 but pagination header indicates additional pages — assert `list-pr-comments.sh` either pages through or documents the limit (v1 may accept first-page-only as a known limitation) | mode: test-framework | expected: bats — stub gh to return `Link: <...>; rel="next"`, assert documented behavior
- [P2] Mid-request connection reset (curl exit 56) — assert graceful skip, no retry | mode: exploratory | expected: manual — kill connection mid-flight

### Cross-cutting (a11y, i18n, concurrency, permissions)

- [P1] PAT scope insufficient (read-only PAT used for write op) — assert `[warn]` per ADO 403 response handling | mode: test-framework | expected: bats — stub curl to return 403 with realistic ADO body, assert exit 0
- [P1] `--reply-to` on GitHub backend — `[warn] --reply-to not supported on GitHub backend; skipping.` per FR-1 — assert body is NOT posted as a top-level comment as fallback (no surprise comments) | mode: test-framework | expected: bats — assert zero gh-comment-create invocations
- [P1] `list-pr-comments.sh` NDJSON schema field stability across backends — assert every record has `thread_id`, `comment_id`, `parent_comment_id`, `author`, `author_unique_name`, `published`, `content`, `status`, `is_deleted`, `thread_status` regardless of backend | mode: test-framework | expected: bats — schema-validate every output record via `jq -e`
- [P1] GitHub sentinel values (`thread_id: 0`, `thread_status: "unknown"`, `parent_comment_id: 0`) are populated correctly on GH backend so consumers can rely on the schema | mode: test-framework | expected: bats — assert all GH records contain the sentinels
- [P1] Two concurrent `pr-comment.sh` invocations in the same shell session both rely on the probe-cache — assert no `flock` deadlock and that one of them silently re-uses the other's probe write | mode: test-framework | expected: bats — parallel invocations against fresh cache, assert at most one probe runs, both succeed
- [P1] User without write permission on `/tmp/sdlc-azdo-pr-thread-resource.*` (e.g. file owned by another user) — assert script does not crash; either skip caching with `[warn]` or fall back to in-memory probe | mode: test-framework | expected: bats — `chown root` on cache file (sudo-fixture), assert no crash
- [P2] Internationalization: PR with comments in non-Latin scripts (CJK, Arabic, Hebrew) — assert `list-pr-comments.sh` NDJSON preserves UTF-8 and `jq` round-trips cleanly | mode: test-framework | expected: bats — stub responses with non-Latin content, assert NDJSON validates and content survives round-trip
- [P2] Timezone-skewed `published` field — both backends return ISO-8601 with timezone offset; assert NDJSON does NOT normalize to UTC silently (or document that it does) | mode: test-framework | expected: bats — assert exact ISO-8601 preservation
- [P2] Accessibility: errors and warnings to stderr (not stdout) so that consumer skills can pipe stdout (URL line / NDJSON) into other tools without contamination | mode: test-framework | expected: bats — for each error path, assert stdout is empty and stderr contains the message
- [P2] `--body-file` symlink pointing outside the repo — assert no security check (we trust the local filesystem) but the file content does post; document this so consumer skills do not pass user-controlled symlink paths | mode: exploratory | expected: manual — symlink test, document behavior

## Non-applicable dimensions

- ui-a11y: this feature has no UI surface — `pr-comment.sh` and `list-pr-comments.sh` are CLI scripts invoked by other skills. The "accessibility" cross-cutting bullet is reinterpreted as "stderr vs stdout separation" so downstream consumers can pipe cleanly. No screen-reader, keyboard, or color-contrast concerns apply.
- i18n-RTL-layout: no rendered UI, so RTL layout is not applicable. RTL text inside comment bodies is covered under Inputs (Unicode passthrough).
- pluralization: no user-facing localized strings emitted by these scripts (all log lines are English fixed strings per repo convention); not applicable.
