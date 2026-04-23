---
id: FEAT-025
version: 2
timestamp: 2026-04-22T23:22:22Z
persona: qa
---

## User Summary

`managing-work-items` is being collapsed from a reference-document skill that the orchestrator executes inline (roughly 60 lines of shell/gh/acli/Rovo-MCP routing prose per invocation) into six deterministic shell scripts that implement the same contract. Every issue-tracking integration point in every workflow — phase-start comments, phase-end comments, work-start/complete, bug-start/complete, one fetch at workflow start, one extract-ref, and the PR-body auto-close fragment — becomes a single script invocation with stable exit codes, stable stdout shape, and the same `[info]` / `[warn]` graceful-degradation lines emitted verbatim. Callers change only where they pointed: the public contract (GitHub `#N` refs and Jira `PROJ-123` refs, comment types, context JSON) is unchanged. The win is uniform: ~2,200–2,800 tokens and a non-trivial wall-clock saving per workflow run, across feature, chore, and bug chains.

## Capability Report

- Mode: test-framework
- Framework: vitest
- Package manager: npm
- Test command: npm test
- Language: typescript

Notes: the feature ships shell scripts, so the primary test harness is bats (script-scoped, under `plugins/lwndev-sdlc/skills/managing-work-items/scripts/tests/`). The repo's top-level vitest suite is orthogonal — it covers the plugin validation pipeline and typescript helpers, not shell scripts. Vitest still matters for regression testing plugin validation after SKILL.md rewrites; bats covers the script contracts themselves. Several `exploratory` scenarios below are tagged that way because they require external-dependency orchestration (live gh auth states, simulated Rovo MCP disconnection, real 429 rate-limit responses) that bats fixtures can stub but cannot authentically produce.

## Scenarios (by dimension)

### Inputs

- [P0] backend-detect: whitespace-only issue-ref (`" "`, `"\t"`, `"\n"`) | mode: test-framework | expected: bats asserts exit 2 (post-trim empty is an arg-shape failure, not a match)
- [P0] backend-detect: issue-ref with leading/trailing whitespace around valid `#N` (`" #183 "`) | mode: test-framework | expected: bats asserts trim-then-match yields `{"backend":"github","issueNumber":183}` exit 0
- [P0] backend-detect: `#N` with leading zeros (`#007`) | mode: test-framework | expected: bats asserts exit 0 and `"issueNumber":7` (numeric, not `"007"` string — catches implicit string-to-int failures)
- [P0] backend-detect: negative-number ref (`#-5`) | mode: test-framework | expected: bats asserts exit 0 emitting `null` (the `^#([0-9]+)$` regex rejects the minus sign)
- [P0] backend-detect: Jira key with alphanumeric project (`PROJ2-456`, `AB1-789`) | mode: test-framework | expected: bats asserts `{"backend":"jira","projectKey":"PROJ2","issueNumber":456}` exit 0
- [P0] backend-detect: lowercase ref (`proj-123`) | mode: test-framework | expected: bats asserts `null` exit 0 (regex is anchored uppercase-first)
- [P0] backend-detect: ref with underscore separator (`PROJ_123`) | mode: test-framework | expected: bats asserts `null` exit 0
- [P1] backend-detect: very long numeric ref (`#` + 20 digits) | mode: test-framework | expected: bats asserts exit 0; if the implementation overflows `int` the emitted `issueNumber` must still round-trip through the caller without silent truncation (document the behavior either way)
- [P1] backend-detect: unicode homoglyph ref (full-width `＃183`, Cyrillic `А` in project key) | mode: test-framework | expected: bats asserts `null` exit 0 — Unicode fallthrough does not accidentally match
- [P1] extract-issue-ref: requirement doc with `## GitHub Issue` section but empty body | mode: test-framework | expected: bats asserts empty stdout exit 0
- [P1] extract-issue-ref: doc with multiple `[#N](URL)` links in the GitHub Issue section | mode: test-framework | expected: bats asserts first-match-only selection; the second and third matches MUST NOT be emitted
- [P1] extract-issue-ref: doc where `## Issue` heading is inside a fenced code block (`` ```markdown `` preview) | mode: test-framework | expected: bats asserts the fenced heading is NOT matched (prevent false positives from embedded template examples)
- [P1] extract-issue-ref: link target URL is wrong domain (`[#42](https://example.com/...)`) | mode: test-framework | expected: bats asserts the ref is still emitted (the URL is not the validator — the bracketed text is)
- [P1] extract-issue-ref: `## GitHub Issue` section with plain `#42` text (no markdown link brackets) | mode: test-framework | expected: bats asserts empty stdout (contract says `[#N](URL)` shape is required; plain text must NOT match)
- [P0] pr-link: empty arg | mode: test-framework | expected: bats asserts exit 2
- [P0] pr-link: `null` ref (unrecognized format) | mode: test-framework | expected: bats asserts empty stdout (zero bytes, no trailing newline) exit 0
- [P1] pr-link: GitHub ref output is exactly `Closes #N\n` (single newline, no extras) | mode: test-framework | expected: bats asserts stdout matches `^Closes #[0-9]+\n$` — a missing newline or double newline breaks downstream PR-body concatenation
- [P0] render-issue-comment: invalid backend (`slack`, `github_issues`, empty string) | mode: test-framework | expected: bats asserts exit 2 with parser error on stderr
- [P0] render-issue-comment: invalid comment type (`phase_start`, `phase-started`, `completion`) | mode: test-framework | expected: bats asserts exit 2 on each variant
- [P0] render-issue-comment: malformed context JSON (trailing comma, unquoted key, truncated) | mode: test-framework | expected: bats asserts exit 2 with jq/parser error on stderr
- [P0] render-issue-comment: context JSON missing a template-referenced variable | mode: test-framework | expected: bats asserts exit 1 (unsubstituted placeholder left in output is a render failure — the script MUST NOT emit a half-rendered body)
- [P1] render-issue-comment: context JSON contains extra variable the template does not reference | mode: test-framework | expected: bats asserts exit 0 and a `[warn]` on stderr naming the unused key — rendering succeeds, unused key is observability
- [P0] render-issue-comment: ADF path — user-supplied list item contains a literal double-quote | mode: test-framework | expected: bats asserts the emitted ADF is valid JSON (jq `.` round-trips); improper escaping must exit 1, not produce malformed JSON
- [P0] render-issue-comment: ADF path — user-supplied value contains backslash-n (`"foo\\n bar"`) | mode: test-framework | expected: bats asserts the backslash-n is preserved as two ASCII chars in the ADF text node, NOT collapsed into an ADF hardBreak
- [P1] render-issue-comment: context list expansion — empty list | mode: test-framework | expected: bats asserts the `<DELIVERABLES>` placeholder renders as an empty block (not a literal `<DELIVERABLES>`), and the surrounding section heading is preserved
- [P1] render-issue-comment: context list expansion — list with 500 items | mode: test-framework | expected: bats asserts exit 0 within a 5s budget (no O(n^2) substitution)
- [P1] render-issue-comment: markdown path — user-supplied deliverable contains a pipe character (`|`) | mode: test-framework | expected: bats asserts the pipe is preserved; must NOT accidentally get interpreted as a markdown table delimiter in downstream rendering
- [P0] render-issue-comment: markdown path — user-supplied `name` contains backticks and triple-backticks | mode: test-framework | expected: bats asserts the rendered body is still parseable by `gh issue comment --body` (no accidental code-fence injection that breaks the outer body)
- [P0] post-issue-comment: injection attempt in context JSON (`name` = `"; rm -rf / #"`) | mode: test-framework | expected: bats asserts the shell expansion does not execute — the value is passed through jq variable binding, never string-interpolated into a shell command
- [P1] post-issue-comment: context JSON that is exactly 10MB | mode: test-framework | expected: bats asserts exit 0 (ARG_MAX matters — document if we need stdin piping)
- [P1] extract-issue-ref: requirement doc is a symlink pointing outside the repo | mode: test-framework | expected: bats asserts the script reads the symlink target as configured (test that it does NOT silently ignore the file on security grounds; confirm documented behavior)
- [P1] fetch-issue: `gh issue view` returns a body with embedded null bytes | mode: test-framework | expected: bats asserts stdout is valid JSON; null bytes must be escaped per JSON spec, not truncated

### State transitions

- [P0] post-issue-comment called twice in rapid succession for the same `(issue, type, context)` | mode: test-framework | expected: bats asserts both invocations exit 0; duplicate comment is the documented acceptable outcome (NFR-3 idempotency)
- [P1] post-issue-comment interrupted with SIGTERM mid-`gh` call | mode: exploratory | expected: manual reproduction — confirm no partial state written to the filesystem (the script holds no state); confirm the parent workflow can retry cleanly
- [P1] post-issue-comment interrupted with SIGHUP between render and post | mode: exploratory | expected: manual reproduction — the rendered body lives in memory only; SIGHUP drops it cleanly, no tempfile cleanup required
- [P0] post-issue-comment — gh CLI returns exit 0 but prints stderr warning ("Resource not accessible by integration") | mode: test-framework | expected: bats asserts the script treats gh's non-zero-then-success scenario as success; a soft-failure warning on stderr does NOT cause a spurious `[warn]` skip
- [P1] fetch-issue called on an issue that transitions from OPEN → CLOSED between two invocations | mode: test-framework | expected: bats asserts both calls succeed with the current `state` field; there is no caching between calls
- [P1] post-issue-comment: issue renamed on the remote between `extract-issue-ref` and `post` | mode: exploratory | expected: manual reproduction — `#N` is immutable on GitHub (rename does not change number), so the comment lands on the correct issue. For Jira, key changes are rare; document the limitation
- [P2] post-issue-comment: comment body that exactly matches a previously-posted body (e.g., two phase-1-started comments after a failed first-run) | mode: exploratory | expected: manual reproduction — GitHub allows duplicate comments; verify no 409 or dedup rejection

### Environment

- [P0] All scripts: `CLAUDE_PLUGIN_ROOT` env var unset or pointing at a non-existent directory | mode: test-framework | expected: bats asserts exit 2 with stderr explaining the missing env var — the scripts must not silently read from `$HOME` or CWD
- [P0] post-issue-comment: `gh` CLI not installed (PATH stripped) | mode: test-framework | expected: bats asserts exit 0 (graceful-degradation skip) and stderr contains `[warn] GitHub CLI (\`gh\`) not found on PATH. Skipping GitHub issue operations.` verbatim (NFR-1 zero-divergence)
- [P0] post-issue-comment: `gh` installed but `gh auth status` fails | mode: test-framework | expected: bats asserts exit 0 and stderr contains `[warn] GitHub CLI not authenticated -- run \`gh auth login\` to enable issue tracking.` verbatim (note the ASCII double-hyphen — this is NFR-1's zero-divergence requirement under test)
- [P0] post-issue-comment: Jira ref, neither Rovo MCP registered nor `acli` installed | mode: test-framework | expected: bats asserts exit 0 with the documented Tier-3 skip warning emitted once (not duplicated across tier fall-through attempts)
- [P1] post-issue-comment: Jira ref, Rovo MCP registered but times out; `acli` fails auth | mode: test-framework | expected: bats asserts exit 0, stderr contains the Rovo-timeout fall-through warning AND the acli-auth skip warning (both tier-failure lines surface)
- [P1] All scripts: offline — no network access | mode: exploratory | expected: manual reproduction — `backend-detect`, `extract-issue-ref`, `pr-link`, `render-issue-comment` succeed (no network); `post-issue-comment` and `fetch-issue` fail gracefully with network-error `[warn]`
- [P1] render-issue-comment: template reference file (`github-templates.md`) is deleted | mode: test-framework | expected: bats asserts exit 1 with `Failed to render` on stderr; FR-5 catches this and emits its own graceful-degradation skip instead of propagating exit 1
- [P1] render-issue-comment: template reference file is present but has been corrupted (binary data) | mode: test-framework | expected: bats asserts exit 1 with a recognizable parse error, not a segfault or hang
- [P1] All scripts: read-only filesystem (unable to write /tmp) | mode: exploratory | expected: manual reproduction — `jq` may refuse to operate if it cannot write a tempfile. Document the dependency if adopted
- [P1] All scripts: UTF-8 locale missing (`LANG=C`) | mode: test-framework | expected: bats asserts emoji/Unicode in comment bodies are preserved correctly by `gh issue comment` (a locale regression in the wrapping shell is the real risk, not the scripts themselves)
- [P2] Clock skew — script run on a host whose clock is 5 minutes ahead | mode: exploratory | expected: no impact — the scripts do not timestamp anything; GitHub/Jira timestamps come from the API
- [P2] gh CLI installed but not on PATH (in an unusual location like `/opt/homebrew/bin`) | mode: test-framework | expected: bats asserts `command -v gh` check is authoritative; scripts do NOT try unusual discovery paths

### Dependency failure

- [P0] post-issue-comment: `gh issue comment` returns HTTP 404 (issue does not exist / was deleted) | mode: test-framework | expected: bats asserts exit 0, stderr contains the documented "not found" warning; the workflow continues
- [P0] post-issue-comment: `gh issue comment` returns HTTP 403 (token scopes insufficient for commenting) | mode: test-framework | expected: bats asserts exit 0, stderr surfaces the gh error verbatim in the `[warn]` line; the scripts must NOT swallow the 403
- [P0] post-issue-comment: `gh issue comment` returns HTTP 429 (rate limited) | mode: test-framework | expected: bats asserts exit 0, no retry is attempted (per managing-work-items SKILL.md Graceful Degradation table — "Do not retry"); warning is emitted once
- [P0] post-issue-comment: `gh issue comment` returns HTTP 500 / 502 / 503 | mode: test-framework | expected: bats asserts exit 0 on each code; a server 5xx is treated as a skip-able failure exactly like a 4xx
- [P0] post-issue-comment: `gh` subprocess hangs indefinitely | mode: exploratory | expected: manual reproduction — confirm the caller has a wrapping timeout (or that we add one); the script itself has no built-in timeout per the current contract
- [P1] fetch-issue: `gh issue view` returns JSON with unexpected fields (schema drift) | mode: test-framework | expected: bats asserts the normalized JSON shape is produced by projecting ONLY the documented fields; extra fields are dropped, missing expected fields produce explicit nulls (not crashes)
- [P1] post-issue-comment (Jira, Tier 1): Rovo MCP tool returns the wrong type (string instead of ADF object) | mode: test-framework | expected: bats asserts the script validates response shape and falls through to Tier 2, not silently posts malformed data
- [P1] post-issue-comment (Jira, Tier 1): Rovo MCP session disconnects mid-call | mode: exploratory | expected: manual reproduction — confirm graceful fall-through to `acli` Tier 2
- [P1] post-issue-comment (Jira, Tier 2): `acli` succeeds but returns empty stdout (no confirmation) | mode: test-framework | expected: bats asserts exit 0; no confirmation is acceptable as long as exit is 0, but a `[warn]` at INFO level for observability is acceptable
- [P1] post-issue-comment (Jira, Tier 2): `acli jira workitem comment-create` exits 0 but the issue key is invalid server-side (acli does not validate, server silently ignores) | mode: exploratory | expected: acli's default behavior is to echo the `Created issue comment` line even on server failure. Document known limitation; no script-side fix possible
- [P1] fetch-issue: GitHub API returns a 200 with an empty body `{}` (unusual but possible on proxied edges) | mode: test-framework | expected: bats asserts the normalized JSON contains null/empty fields, not a crash
- [P2] render-issue-comment: Rovo MCP ADF schema changes (new required field) | mode: exploratory | expected: long-horizon concern — schema evolution breaks the template; test by hand-crafting an invalid ADF and feeding it through; fallback is to regenerate templates

### Cross-cutting (a11y, i18n, concurrency, permissions)

- [P1] i18n: issue body contains mixed LTR/RTL text and emoji in a list-item context | mode: test-framework | expected: bats asserts the rendered markdown/ADF preserves grapheme clusters; `gh issue comment --body` round-trips the UTF-8 bytes
- [P1] i18n: Jira project key with diacritics (hypothetical — real Jira disallows them) | mode: test-framework | expected: bats asserts the regex rejects the ref (emits `null`), confirming the ASCII-only contract
- [P1] Concurrency: two feature workflows running in parallel (`FEAT-A` and `FEAT-B`) both post phase-start comments to the same issue `#100` within 1 second | mode: exploratory | expected: manual reproduction with two parallel `/orchestrating-workflows` invocations — confirm GitHub accepts both comments distinctly; scripts have no shared state to race on
- [P1] Concurrency: `post-issue-comment.sh` invoked from two independent hosts simultaneously | mode: exploratory | expected: manual reproduction — no shared-state risk; GitHub server-side serializes
- [P0] Permissions: gh token has `repo` scope but not `issues:write` | mode: test-framework | expected: bats asserts the 403 path produces the documented skip warning; the token-scope error surfaces on stderr verbatim
- [P1] Permissions: gh token has `public_repo` only; issue is in a private repo | mode: exploratory | expected: manual reproduction — 404 (not 403) is the expected response from GitHub; script handles as issue-not-found
- [P2] Permissions: running in a CI with no gh token at all | mode: test-framework | expected: bats asserts the auth-failure warning fires; this is the dominant CI behavior and must not break the workflow

## Non-applicable dimensions

- a11y: the feature ships six shell scripts with no UI surface, no stdout formatting intended for screen readers, and no color-coded output. Accessibility is not applicable.
- Internationalization (partial): dates, time zones, currency formatting, and pluralization rules do not apply — the scripts emit only ASCII `[info]` / `[warn]` lines and plain rendered markdown / ADF. The i18n dimension still applies to the user-supplied *content* that flows through the scripts (RTL, emoji, diacritics), which is covered above under Cross-cutting.
- Queue overflow / dropped messages: the scripts are synchronous and make at most one HTTP call per invocation. There is no internal queue to overflow.
- Database disconnects: no database is involved at any point in these six scripts.
