---
id: FEAT-022
version: 2
timestamp: 2026-04-22T00:26:00Z
persona: qa
---

## User Summary

The `finalizing-workflow` skill is being collapsed from a multi-step prose ceremony (pre-flight checks, five bookkeeping sub-steps, and a four-command execution sequence) into a single user confirmation plus one top-level `finalize.sh` invocation. Five new shell scripts ship under the skill directory — a top-level orchestrator and four leaf subscripts covering pre-flight validation, idempotency checking, Completion-section upsert, and Affected-Files reconciliation. The plugin-shared `branch-id-parse.sh` gains a fourth classification for release branches (`release/<plugin>-vX.Y.Z`) so release PRs finalize without emitting the unrecognized-branch info message. The promised outcome is a skill that runs materially faster end-to-end than the prose path and uses measurably fewer orchestrator-context tokens.

## Capability Report

- Mode: test-framework
- Framework: vitest
- Package manager: npm
- Test command: npm test
- Language: typescript

Note: the artifacts under test are POSIX shell scripts with accompanying `bats` fixtures. Scenarios marked `mode: test-framework` are feasible as vitest tests that shell out to the scripts (or invoke `bats`) and assert stdout/stderr/exit-code contracts. Scenarios requiring real GitHub merge semantics, real remote git state, or real measurement of a full orchestrated chain are `mode: exploratory`.

## Scenarios (by dimension)

### Inputs

- [P0] Empty branch-name arg to the top-level script → documented exit 2 with usage-line on stderr; no git or gh calls attempted | mode: test-framework | expected: vitest spawns the script with an empty string, asserts exit code === 2 and that the stub git/gh tracers received zero invocations
- [P0] Branch name containing shell metacharacters (backticks, `$()`, semicolons, newlines) is passed straight through to every subscript without being evaluated by the shell | mode: test-framework | expected: vitest invokes with `feat/FEAT-001-$(whoami)-x` and asserts neither the resulting branch-id-parse call nor any subscript executed a subshell (no file side-effects from injected command); argv is preserved byte-for-byte
- [P0] Branch name that matches the release regex in its entirety but with unicode lookalikes (e.g., `release/plugin-v1.0.0` where the `-v` contains a Cyrillic `v`) MUST NOT classify as release | mode: test-framework | expected: bats/vitest against branch-id-parse emits exit 1 (no-match), not exit 0
- [P1] `<prNumber>` passed as non-numeric string (`"NaN"`, `"-1"`, `"#142"` with the hash still attached) to `check-idempotent.sh` or `completion-upsert.sh` | mode: test-framework | expected: documented exit 2 with the `[error]` prefix; no file mutations; no partial writes
- [P1] `<doc-path>` that is a symlink, a directory, a named pipe, or a device node (`/dev/null`) rather than a regular file | mode: test-framework | expected: all three bookkeeping subscripts exit 1 or 2 without mutating any target; stderr carries a diagnostic line
- [P1] Requirement doc with mixed line endings (some CRLF, some LF) across sections → subscripts must not normalize silently, must not produce a diff that flips EVERY line | mode: test-framework | expected: round-trip diff shows edits only inside the targeted section, line-ending character-class preserved per line
- [P1] Requirement doc whose `## Affected Files` bullet list contains paths with embedded spaces, unicode, emoji, or quotes → reconciliation must match against the doc verbatim without shell-splitting | mode: test-framework | expected: `reconcile-affected-files.sh` round-trips a file named `plugins/lwndev-sdlc/skills/with space/αβγ.md` without duplicating it as two entries
- [P1] PR with an extremely large `files` list (1000+ paths) → reconciliation script still terminates in bounded time, does not exceed argv-length limits when building comparison lists | mode: test-framework | expected: stub `gh pr view --json files` emits 1000 paths, script completes under 2s and emits expected `<appended> <annotated>` counts
- [P2] Requirement doc with only frontmatter and no body at all → `check-idempotent.sh` treats Acceptance Criteria as absent (condition 1 passes), Completion as absent (condition 2 fails → exit 1 with label `completion-section-missing`) | mode: test-framework | expected: no crash, correct exit-1 label on stderr
- [P2] Fenced code block containing a literal `- [ ]` example, positioned inside the `## Acceptance Criteria` section body → the box MUST NOT be flipped to `- [x]` | mode: test-framework | expected: bats diff shows the fenced example unchanged after `checkbox-flip-all.sh` run
- [P2] Requirement doc with a `## Completion` heading whose body is only whitespace / commented-out HTML → idempotency condition 2 passes (heading present) but condition 3 fails because no `**Pull Request:**` line exists → exit 1 with label `pr-line-mismatch` | mode: test-framework | expected: stub asserts correct label emission

### State transitions

- [P0] SIGINT delivered to `finalize.sh` after `git add <doc>` but before `git commit` → working tree retains staged but uncommitted changes; no `git revert` is attempted; next invocation sees a dirty tree and pre-flight aborts with the existing dirty-tree message (no silent corruption) | mode: test-framework | expected: vitest sends SIGINT at a chosen breakpoint via a sentinel stub, asserts subsequent pre-flight exit 1 and reason string
- [P0] `gh pr merge` succeeds but `git checkout main` fails (hypothetical permission drop) → script exits 1, stderr explicitly notes the merge already succeeded, NO attempt to re-merge or revert; re-invocation fails pre-flight because working branch is deleted | mode: test-framework | expected: stub failures produce the exact stderr contract; no `git revert` appears in the command trace
- [P0] No-rollback invariant: BK-5 commit+push succeeds, then `gh pr merge` fails → `git revert` and `git reset --hard` MUST NOT be invoked; the bookkeeping commit stays on the remote branch | mode: test-framework | expected: command tracer asserts absence of `revert`/`reset --hard` in the full invocation log
- [P0] Idempotent re-run: first run partially fails after BK-5 push but before merge; second run must see the finalized doc, `check-idempotent.sh` returns exit 0, BK-4 and BK-5 are skipped, merge is retried | mode: test-framework | expected: two sequential script invocations against the same fixture; second invocation's command tracer records zero calls into `checkbox-flip-all.sh`, `completion-upsert.sh`, `reconcile-affected-files.sh`, one call to `gh pr merge`
- [P1] Two concurrent `finalize.sh` invocations on the same branch (e.g., developer reruns in a second terminal after the first hung) → second invocation must hit `.git/index.lock` on `git add` and exit 1 cleanly; it must not corrupt the bookkeeping commit | mode: test-framework | expected: coordinated vitest spawns with a contrived lock; assert second invocation's exit is 1 and its stderr names the lock contention
- [P1] Double confirmation: SKILL.md prompts once; if the user types `yes` twice (one in the prompt, one accidentally injected into stdin before `finalize.sh` reads), the script must not re-trigger the prompt mid-run | mode: exploratory | expected: manual tester invokes the skill, pastes `yes\nyes\n` into the TTY, confirms single execution path
- [P2] Re-invocation of a fully-finalized workflow (PR merged, branch deleted) → second `finalize.sh` call hits pre-flight exit 1 (either "already on main" or "no PR for branch"), returns quickly without attempting re-merge | mode: test-framework | expected: vitest fixture with merged state asserts exit 1 and reason string

### Environment

- [P0] `gh` CLI not found on PATH → `preflight-checks.sh` exits 1 with a clear missing-gh diagnostic BEFORE attempting any git writes; `finalize.sh` does not proceed to bookkeeping or merge | mode: test-framework | expected: vitest removes `gh` stub from PATH, asserts exit-1 + stderr match
- [P0] `gh` authenticated but subsequently rate-limited (429) on `gh pr view --json files` call in `reconcile-affected-files.sh` → that subscript exits 1, emits `[warn]` on stderr, `finalize.sh` treats it as non-fatal and continues to BK-5 | mode: test-framework | expected: stub gh returns 429 on the affected-files fetch; vitest confirms BK-5 still runs with zero reconcile output, final merge succeeds
- [P1] `jq` missing on PATH → hand-assembled JSON fallback in `branch-id-parse.sh` AND `preflight-checks.sh` emits identical-shape JSON (including literal `null` vs string `"null"` for release-branch `id`/`dir`) | mode: test-framework | expected: bats removes jq from PATH; JSON output is byte-identical to the jq path except for whitespace
- [P1] `git config user.name` / `user.email` unset → BK-5 commit stops and reports; script does NOT run `git config` to auto-configure identity | mode: test-framework | expected: vitest asserts stderr contains a user-facing "identity not configured" message and exit 1
- [P1] Filesystem read-only for the requirement doc (simulated via `chmod 0444`) → `completion-upsert.sh` or `reconcile-affected-files.sh` exits 1 with file-I/O diagnostic; `finalize.sh` does not proceed to BK-5 commit (nothing to commit) OR does the BK-5 commit cleanly if the diff didn't materialize | mode: test-framework | expected: vitest asserts subscript exit 1 and that `finalize.sh` does NOT crash on subscript non-zero; message propagates to stderr
- [P1] Non-UTF-8 locale (LANG=C, LC_ALL=C) when the requirement doc contains non-ASCII characters → scripts must not garble unicode in the doc body OR in the completion-section writes | mode: test-framework | expected: vitest runs with `LANG=C`; resulting doc diff preserves every non-ASCII byte sequence
- [P1] `core.autocrlf=true` on a developer machine → requirement doc reads back with CRLF; BK subscripts edit and preserve CRLF | mode: test-framework | expected: vitest fixture with git `core.autocrlf=true` confirms post-edit `file <doc>` still reports CRLF
- [P2] Clock skew (system clock set 30 days forward) → `date -u +%Y-%m-%d` in `completion-upsert.sh` reflects the skewed date without crashing; next run on the same fixture later finds the Completion section with the expected upsert and re-idempotent | mode: exploratory | expected: manual tester spoofs system date, runs the script, confirms output
- [P2] Very low disk space during BK-5 commit → `git commit` fails with out-of-space; `finalize.sh` exits 1 with the git stderr propagated verbatim | mode: exploratory | expected: tester caps tmpfs disk to sub-commit-size and confirms graceful failure
- [P2] Git repo is a shallow clone (created with `--depth=1`) → `branch-id-parse.sh` and `resolve-requirement-doc.sh` still succeed because neither walks history; merge still succeeds because `gh pr merge` operates server-side | mode: test-framework | expected: vitest fixture clones shallowly, full happy-path completes

### Dependency failure

- [P0] `gh pr merge` returns 5xx mid-flight → script exits 1; stderr contains gh's error verbatim; BK-5 commit (already pushed) is NOT reverted | mode: test-framework | expected: stub gh returns 500; command tracer asserts no `git revert`/`reset --hard` after the failure
- [P0] `git push` rejected as non-fast-forward (remote branch advanced since local checkout) → BK-5 exits 1, merge never attempted; stderr contains push rejection | mode: test-framework | expected: vitest fixture simulates remote-advance via a staged `git push --force-with-lease` conflict pattern; script exit 1
- [P1] `gh pr view` returns malformed JSON (missing `mergeable` field, new required field shape, or a `null` where an object was expected) → `preflight-checks.sh` handles gracefully: either aborts with a clear parse error or treats as UNKNOWN and retries once | mode: test-framework | expected: stub gh returns `{"number":142}` only; preflight exit 1 with a "malformed PR JSON" diagnostic, NOT a raw jq parse error leak
- [P1] `gh pr merge --delete-branch` succeeds on remote but the local-branch delete sub-step fails (stale working tree) → script still exits 0 because merge succeeded; stderr notes the local-delete residue | mode: exploratory | expected: tester observes the residual local branch and the documented stderr note
- [P1] Network partition between `git fetch` and `git pull` at the end of execution → fetch succeeds, pull fails with upstream-lost error → script exits 0 per the documented "fetch/pull post-merge failure is non-fatal" contract; stderr emits the warning | mode: test-framework | expected: vitest stub drops network between commands, asserts exit 0 with warning
- [P2] `gh pr view --json files` returns partial data (network drop mid-response) → `reconcile-affected-files.sh` exits 1 (non-fatal), stderr warns, BK-5 still runs | mode: test-framework | expected: stub gh truncates output; script exits 1, `finalize.sh` continues
- [P2] `gh` CLI version mismatch (older `gh` that doesn't support `--json files` or `--merge` flag) → subscript exits 1 with an explanatory stderr; `finalize.sh` propagates verbatim | mode: exploratory | expected: tester downgrades `gh` to a very old release, confirms diagnostic

### Cross-cutting (a11y, i18n, concurrency, permissions)

- [P0] Concurrency / FR-14 audit-trail integrity: two orchestrator runs invoking this skill against the same workflow state file in quick succession → the state file's `modelSelections` entries remain well-formed JSON; neither run corrupts the other's audit-trail write | mode: exploratory | expected: operator launches two orchestrator instances against the same ID, inspects `.sdlc/workflows/FEAT-022.json` for JSON validity and well-ordered entries
- [P1] Permissions: invoker lacks write permission to the remote branch (e.g., branch-protection enforces required reviewers) → `git push` in BK-5 exits non-zero; `finalize.sh` stops before merge with the push error surfaced | mode: exploratory | expected: tester configures a protected-branch test repo, confirms clean failure mode
- [P1] Shell-metacharacter injection via `<prUrl>` in the `completion-upsert.sh` block body — if the PR URL happens to contain backticks or `$()` from a malicious or malformed upstream response, those bytes appear as literal text in the doc, never evaluated | mode: test-framework | expected: vitest passes `https://github.com/x/y/pull/1?evil=\`whoami\`` as prUrl; doc diff contains the literal backticks, no command was executed, no file appeared as a side effect
- [P1] Concurrency: `finalize.sh` invoked while the orchestrator has an active `.sdlc/qa/.documenting-active` marker from an unrelated in-progress `documenting-qa` run → this skill MUST NOT touch that marker, and MUST NOT crash if the marker is present | mode: test-framework | expected: vitest pre-creates the documenting-active marker, runs `finalize.sh`, asserts marker still exists post-run
- [P2] Internationalization: requirement doc written with RTL text in description bullets and emoji in acceptance-criteria content → subscripts preserve byte sequences verbatim; no mojibake in the committed doc diff | mode: test-framework | expected: vitest fixture includes Arabic and emoji content; post-run `git diff` shows bytes intact
- [P2] Permissions / authz: `gh` token scoped to read-only (no `repo` write scope) → `gh pr merge` returns 403 → `finalize.sh` exits 1 with clear stderr, no retry loop | mode: exploratory | expected: tester revokes merge scope on a test token, confirms single-attempt failure with readable diagnostic

## Non-applicable dimensions

- Accessibility (screen reader, keyboard navigation, color contrast, focus trapping): this skill is a CLI flow with no graphical surface. No rendered components exist to navigate, no text styling to contrast-check, no focus order to trap. The prompt emitted by SKILL.md is a single plaintext line; stdout and stderr are plaintext streams consumed by the orchestrator or terminal.
- Internationalization of script output (pluralization, RTL layouts of the log messages themselves, locale-specific number/date formatting in emitted tokens): the `[info]`, `[warn]`, `[error]`, and summary-line outputs are defined as ASCII fixed strings whose contents are contract with the orchestrator's parser — they intentionally do not vary by locale. Locale-specific pluralization of messages is not a feature. (Scenarios under Inputs, Environment, and Cross-cutting above cover unicode and non-UTF-8-locale handling of file *content*, which is the real correctness concern here.)
