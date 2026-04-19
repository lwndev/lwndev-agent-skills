---
id: FEAT-019
version: 2
timestamp: 2026-04-19T23:15:00Z
persona: qa
---

## User Summary

`finalizing-workflow` gains an automated pre-merge bookkeeping step that performs four mechanical updates to the requirement document: flip acceptance-criteria checkboxes from `[ ]` to `[x]`, set the `## Completion` section to `Complete` with today's date and PR URL, add the PR link to the requirement doc (subsumed in Completion), and trim/extend the `## Affected Files` list to match the actual PR diff. The bookkeeping runs after the user confirms intent but before `gh pr merge` executes; it produces at most one commit and one push per invocation.

## Capability Report

- Mode: test-framework
- Framework: vitest
- Package manager: npm
- Test command: npm test
- Language: typescript

## Scenarios (by dimension)

### Inputs

- [P0] Branch name parser rejects malformed IDs that superficially match prefix (e.g., `feat/FEAT-foo-bar`, `feat/FEAT-019`, `feat/FEAT-019foo`, `chore/CHORE-0-` — non-numeric or boundary numeric) | mode: test-framework | expected: each pattern returns no-match and triggers the non-matching branch benign skip
- [P0] Requirement doc contains nested `- [ ]` checkboxes inside sub-lists or inside code fences — only the TOP-LEVEL Acceptance Criteria entries must flip to `[x]` | mode: test-framework | expected: test doc with `- [ ]` in code fence AND nested list AND top-level AC; assert only top-level AC flipped, code-fence and nested checkboxes untouched
- [P0] Requirement doc has `## Acceptance Criteria` heading inside a fenced code block — the section-detection must NOT treat this as a real section | mode: test-framework | expected: doc with `\`\`\`\n## Acceptance Criteria\n- [ ] foo\n\`\`\`` assertion: no checkbox flipped
- [P0] Two `## Acceptance Criteria` sections in the same doc (malformed doc) — behavior must be deterministic and documented | mode: test-framework | expected: test asserts either "first-section-only" or "all-sections"; either is acceptable if documented, but silent-differences-across-runs is not
- [P0] Completion section upsert against a doc with no trailing newline at EOF — appending must not concatenate onto the last line | mode: test-framework | expected: input file has no final `\n`, output contains `\n\n## Completion` (blank-line separator) as first chars of appended block
- [P0] Doc with Windows CRLF line endings — regex patterns anchored to `^` must match despite `\r` in content | mode: test-framework | expected: mixed-line-ending doc processes correctly; assertion walks the output verifying flips happened regardless of line-ending style
- [P1] Requirement doc with ACs containing backtick code spans, bold, links — replacement of `[ ]` must preserve all inline markup on the AC line | mode: test-framework | expected: input `- [ ] Run \`npm test\` and verify **all** [tests](#) pass` → output `- [x] Run \`npm test\` and verify **all** [tests](#) pass`
- [P1] Affected Files list with paths containing spaces, unicode, or special chars (e.g., `plugins/lwndev-sdlc/skills/a skill/SKILL.md`, `plugins/… /foo.md`) — parser must not split or lose characters | mode: test-framework | expected: reconciliation compares input doc's paths byte-for-byte to `gh` output
- [P1] Affected Files with paths wrapped in varying backtick styles (some ``- `path` ``, some `- path`, some `- **path**`) — parser must handle all or explicitly declare one format | mode: test-framework | expected: test covers each style and asserts deterministic classification
- [P1] Oversized inputs: Acceptance Criteria with 100+ entries, Affected Files with 200+ entries | mode: test-framework | expected: bookkeeping completes in under 3 seconds; no quadratic blowup
- [P1] `gh pr view --json files` returns an empty file list (draft PR edge case) — every existing Affected Files entry becomes `(planned but not modified)`; no new entries | mode: test-framework | expected: mock `gh` returns `{"files":[]}`; assert annotations applied to every entry
- [P1] Requirement doc with `## Completion` section missing the `## ` close boundary (last section, no trailing heading) — body-replacement must stop at EOF | mode: test-framework | expected: Completion section appears at end of doc; re-write replaces content from heading to EOF without truncating trailing content
- [P2] Requirement doc that is entirely empty or contains only frontmatter (no `## ` headings at all) | mode: test-framework | expected: FR-4 condition 1 satisfied (no AC section, per updated rule); FR-5.1 no-op; FR-5.2 appends Completion; FR-5.3 skipped

### State transitions

- [P0] User interrupts (Ctrl-C / process kill) partway through FR-5 edits — partial write to requirement doc must not corrupt doc, and next run's FR-4 idempotency check correctly detects "not finalized" and re-runs | mode: exploratory | expected: manual: start finalize, kill process after AC edit but before Completion edit; re-run; verify doc is coherent and bookkeeping completes
- [P0] Bookkeeping commit lands, push fails — re-run must NOT produce a duplicate commit. FR-4 idempotency detects the already-applied edits on disk; git detects the already-committed state on the branch | mode: test-framework | expected: simulate push failure; re-run; assert no new commit created, assert `git status --porcelain` clean before retrying push
- [P0] Two concurrent `finalizing-workflow` invocations on the same branch — must not produce two bookkeeping commits or push races | mode: exploratory | expected: documented behavior OR explicit "not supported" note; if supported, test asserts second invocation detects first's work and no-ops
- [P1] User re-runs after a successful `finalizing-workflow` (branch already merged and deleted) — pre-flight check 3 catches the "PR not OPEN" case BEFORE bookkeeping runs | mode: test-framework | expected: mock `gh pr view` returns `"state": "MERGED"`; assert bookkeeping is skipped, skill stops cleanly
- [P1] PR branch force-pushed by another user between pre-flight check and bookkeeping edit — `git push` fails with non-fast-forward; bookkeeping aborts per FR-6 | mode: exploratory | expected: remote state advanced beyond local; `git push` rejected; skill reports error and does not attempt merge
- [P1] Pre-commit hook modifies files during `git commit` — bookkeeping commit includes hook-modified state; no retry loop | mode: test-framework | expected: mock pre-commit hook that reformats the requirement doc; assert single commit produced with hook-applied state
- [P1] FR-4 idempotency check: AC section has zero `- [ ]` entries (all already ticked) AND Completion section exists AND PR link matches — skill silently skips FR-5 | mode: test-framework | expected: pre-populated synthetic doc; assert FR-5 is no-op and no commit produced
- [P1] Partial re-run after NFR-5 `gh` failure mid-FR-5.3 — one file already annotated with `(planned but not modified)`, run repeats — annotation must not double-append per the FR-5.3 idempotency guard | mode: test-framework | expected: input already has one annotated line; re-run does not produce `(planned but not modified) (planned but not modified)`

### Environment

- [P1] `gh` CLI is not on `PATH` — FR-5.2's PR link is omitted (Status + date only), FR-5.3 is skipped, bookkeeping commit still produced per NFR-5 row 4 | mode: test-framework | expected: mock missing `gh`; assert completion block written without `**Pull Request:**` line, warning logged, commit still made
- [P1] `gh` is on PATH but returns auth error — both `gh pr view` calls fail; NFR-5 row 3 applies | mode: test-framework | expected: mock `gh` exit 1 with auth-error stderr; assert PR link omitted, FR-5.3 skipped, warnings logged, commit produced
- [P1] `gh pr view --json files` succeeds but `--json number,url` fails — NFR-5 row 1 applies (one call fails, one succeeds) | mode: test-framework | expected: selective mock; assert FR-5.2 omits PR link but FR-5.3 still runs
- [P1] Disk full when `Edit` writes the modified requirement doc — bookkeeping aborts; merge does not run | mode: exploratory | expected: manual: fill disk to test edit-failure path; skill reports error, does not invoke `gh pr merge`
- [P1] Locale set to `C.UTF-8` / `POSIX` — `date -u +%Y-%m-%d` still produces the correct canonical YYYY-MM-DD string | mode: test-framework | expected: run test with `LANG=C` env; assert date format in output
- [P2] Running on Windows (cmd.exe, not bash) — if supported, path separators and `date` availability must not break | mode: exploratory | expected: documented OS-support matrix; currently the skill uses bash-style tool invocations

### Dependency failure

- [P0] `gh pr view` returns stale data — PR number captured in pre-flight disagrees with number returned in FR-5.2 (race between pre-flight and bookkeeping) | mode: test-framework | expected: mock `gh` to return PR=100 on pre-flight then PR=101 on bookkeeping; FR-4 uses pre-flight's captured value per spec; assert no inconsistency in the Completion block
- [P0] `gh pr merge --merge --delete-branch` fails after bookkeeping commit was pushed — commit is now on remote but PR is unmerged; skill reports error | mode: exploratory | expected: manual: trigger a merge-conflict between pre-flight's mergeability check and actual merge; assert bookkeeping commit is visible on remote, PR remains OPEN with extra commit (documented recoverable state)
- [P1] `git push` rejected by branch protection (e.g., required status checks failing) — bookkeeping aborts before merge; commit exists locally but not remotely | mode: exploratory | expected: manual against a protected branch; assert skill stops and does not merge
- [P1] `gh` rate-limit hit — `gh pr view` exits non-zero with rate-limit error | mode: test-framework | expected: mock `gh` returns rate-limit exit code; assert degradation per NFR-5, warning logged
- [P1] `gh pr view --json number,url` returns malformed JSON or missing expected fields — jq extraction fails | mode: test-framework | expected: mock `gh` returns `{}` or invalid JSON; assert FR-5.2 omits PR link gracefully
- [P2] Network partition during `git push` (push hangs) — timeout handling | mode: exploratory | expected: bounded wait or user-visible status; no silent deadlock

### Cross-cutting (a11y, i18n, concurrency, permissions)

- [P1] Requirement doc written in non-ASCII encoding (UTF-8 BOM, Latin-1, UTF-16) — read/edit must handle or reject consistently | mode: test-framework | expected: doc with BOM; assert bookkeeping succeeds (BOM preserved) or fails loudly (not silently corrupts)
- [P1] Requirement doc contains em-dashes, ellipses, curly quotes in section headings — regex `^## ` matching must not stumble | mode: test-framework | expected: doc with `## Acceptance Criteria (notes — caveat)`; assert section detected normally
- [P1] Requirement doc is read-only on the filesystem (permissions 0444) — `Edit` tool fails; bookkeeping aborts before commit | mode: test-framework | expected: chmod doc 0444; assert skill reports error, does not commit, does not merge
- [P1] Concurrent edit to the requirement doc mid-run (user opens editor and saves during FR-5) — `Edit` atomic-write detects the change or produces a non-corrupt merge | mode: exploratory | expected: racy manual test; the `Edit` tool's atomic read-match-write should catch
- [P1] Git author not configured (`user.name` / `user.email` missing) — `git commit` fails; skill reports per FR-6 identity handling | mode: test-framework | expected: unset git config in test env; assert commit fails with actionable error, no partial state

## Non-applicable dimensions

- a11y (within Cross-cutting): `finalizing-workflow` is a CLI / skill invocation with no user interface surface. No visual output, no screen-reader pathway, no keyboard-focus model. Accessibility testing has no target.
