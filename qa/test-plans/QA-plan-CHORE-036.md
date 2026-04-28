---
id: CHORE-036
version: 2
timestamp: 2026-04-28T14:08:39Z
persona: qa
---

## User Summary

The chore extracts mechanical shell from three documenting skills into shared scripts: `new-requirement.sh` composes ID allocation, slugification, and template rendering to write a requirement document; `validate-categories.sh` enforces the chore (5 values) and bug (6 values) category enums; and `validate-rc-traceability.sh` enforces the bug-document `(RC-N)` ↔ acceptance-criterion round-trip. The three documenting SKILL.md files are updated to call the new scripts in place of the prose they replace, so future chore/feature/bug authoring runs the deterministic scripts instead of the model regenerating the same shell.

## Capability Report

- Mode: test-framework
- Framework: bats (per-script `.bats` fixtures alongside scripts; auto-detected as vitest at the repo root, but vitest does not exercise the bash scripts in scope here — the canonical test surface for this chore is the bats suites under `plugins/lwndev-sdlc/scripts/tests/` and `plugins/lwndev-sdlc/skills/documenting-bugs/scripts/tests/`)
- Package manager: npm
- Test command: `npx bats plugins/lwndev-sdlc/scripts/tests/new-requirement.bats plugins/lwndev-sdlc/scripts/tests/validate-categories.bats plugins/lwndev-sdlc/skills/documenting-bugs/scripts/tests/validate-rc-traceability.bats` (vitest `npm test` still runs unrelated TS suites; both must pass)
- Language: bash (scripts under test); typescript (existing repo tooling)

## Scenarios (by dimension)

### Inputs

- [P0] new-requirement.sh: pass `<TYPE>=FEAT` with `--severity high` -> rejected with exit 2 and `error: --severity only accepted for BUG` on stderr | mode: test-framework | expected: bats fixture asserts exit 2, stderr regex match
- [P0] new-requirement.sh: pass `<TYPE>=FEAT` with `--category refactoring` -> rejected with exit 2 and `error: --category not accepted for FEAT (features have no category enum)` on stderr | mode: test-framework | expected: bats fixture asserts exit 2, stderr regex match
- [P0] new-requirement.sh: pass title that slugifies to empty (e.g., `"the of and"` — all stopwords) -> exits non-zero (slugify.sh exit 1) and surfaces `error: slug is empty after normalization` on stderr | mode: test-framework | expected: bats fixture asserts non-zero exit, stderr contains slug-empty message
- [P0] new-requirement.sh: pass `<TYPE>=BUG` with `--category cleanup` (chore-only category, not in bug enum) -> rejected via validate-categories.sh with exit 2 and stderr listing the six bug values | mode: test-framework | expected: bats fixture asserts exit 2, stderr lists `runtime-error,logic-error,ui-defect,performance,security,regression`
- [P0] new-requirement.sh: pass `<TYPE>=CHORE` with `--category Refactoring` (capitalized) -> rejected (enum is case-sensitive lowercase) | mode: test-framework | expected: bats fixture asserts exit 2; documents the case-sensitivity contract
- [P1] new-requirement.sh: pass title with embedded shell metacharacters (`"fix $(rm -rf /) bug"`) -> slugify.sh strips to safe ASCII; no command substitution executes; written file path is safe | mode: test-framework | expected: bats fixture asserts the temp `requirements/` dir contents are unchanged besides the new file; written filename has no `$` or `()`
- [P1] new-requirement.sh: pass title containing emoji and RTL Unicode (`"بحث 🔥 search"`) -> slugify strips to ASCII tokens, file is created with ASCII-only filename | mode: test-framework | expected: bats fixture inspects the produced filename and asserts ASCII-only
- [P1] new-requirement.sh: pass excessively long title (10KB string of repeated words) -> slugify keeps first 4 stopword-stripped tokens; filename length stays bounded | mode: test-framework | expected: bats fixture asserts filename ≤ ~80 chars
- [P1] new-requirement.sh: pass `--issue 188` (bare number, no `#`) — verify the rendered document GitHub Issue link uses `#188` | mode: test-framework | expected: bats fixture greps the produced file for `[#188](https://github.com/lwndev/lwndev-marketplace/issues/188)`
- [P1] new-requirement.sh: pass `--issue PROJ-123` (Jira-style) — falls back to raw ref without URL because the regex won't match GitHub format | mode: test-framework | expected: bats fixture asserts `PROJ-123` appears with no GitHub URL
- [P1] validate-categories.sh: pass empty category string `""` -> rejected with exit 2 | mode: test-framework | expected: bats fixture asserts exit 2 and stderr `error: invalid <type> category ''`
- [P1] validate-categories.sh: pass category with leading/trailing whitespace `" cleanup "` -> rejected (no implicit trimming) OR accepted after trim — pin the contract in the bats fixture | mode: test-framework | expected: bats fixture documents the trimming behavior either way
- [P1] validate-rc-traceability.sh: bug doc with `RC-1` declared but every AC line tagged only with `(RC-2)` (which is undeclared) -> reports `missingRCs: ["RC-1"]` and exit 1 | mode: test-framework | expected: bats fixture asserts JSON shape and exit code
- [P1] validate-rc-traceability.sh: bug doc with AC line `- [ ] Some criterion text` (no RC tag at all) -> reports that line in `untaggedACs` and exit 1 | mode: test-framework | expected: bats fixture asserts JSON shape
- [P1] validate-rc-traceability.sh: bug doc with `(RC-1)` tag inside an HTML comment block in the AC section -> the commented-out AC line is excluded from `untaggedACs` (only `^- \[[ x]\] ` lines outside comments count) | mode: test-framework | expected: bats fixture asserts the commented line is not in `untaggedACs`
- [P1] validate-rc-traceability.sh: bug doc where the Acceptance Criteria section contains a nested code fence with text matching `- [ ] ...` -> code-fence content is excluded (mirror of fence-aware contract from `checkbox-flip-all.sh`) — pin behavior in the test | mode: test-framework | expected: bats fixture documents fence-awareness OR documents that fences are not handled (acceptable for v1; surface in implementation phase)
- [P2] new-requirement.sh: pass `<TYPE>=BUG` with both `--category security` and `--severity high` -> both accepted, rendered file reflects both | mode: test-framework | expected: bats fixture greps file for both values

### State transitions

- [P0] new-requirement.sh: invoke twice with identical args from the same shell -> second invocation produces a file with the next ID and does NOT overwrite the first | mode: test-framework | expected: bats fixture runs the script twice and asserts two distinct files exist
- [P0] new-requirement.sh: pre-existing `requirements/chores/CHORE-099-*.md` file present -> next-id.sh returns 100, script writes `CHORE-100-*.md` (no overwrite of CHORE-099) | mode: test-framework | expected: bats fixture seeds requirements/chores/ and asserts the new file is CHORE-100
- [P1] new-requirement.sh: kill the script mid-write (SIGKILL during template rendering) -> requirements/ may have an incomplete file; subsequent invocation re-runs next-id.sh which sees the partial file as the latest ID and continues from N+1 (graceful) | mode: exploratory | expected: manual reproduction; document the recovery path in the implementation
- [P1] validate-rc-traceability.sh: bug doc edited mid-script-run -> file is read once at start; transient writes during script execution don't affect the JSON result | mode: exploratory | expected: low-likelihood race; manual verification only
- [P2] new-requirement.sh: invoked twice in parallel via `&` from the same shell -> race on next-id.sh; both calls may pick the same ID and one will silently overwrite the other (next-id.sh has no locking) | mode: exploratory | expected: document this as a known limitation; no locking added in this chore

### Environment

- [P0] new-requirement.sh: `requirements/` directory does not exist -> next-id.sh returns 001, script must `mkdir -p requirements/<type>/` before writing | mode: test-framework | expected: bats fixture starts with no requirements/, asserts the directory is created and file is written
- [P0] new-requirement.sh: `requirements/<type>/` exists but is read-only (chmod 555) -> script fails with exit 1 and stderr surfacing the filesystem error | mode: test-framework | expected: bats fixture chmods, asserts exit 1, then chmods back
- [P0] new-requirement.sh: invoked outside a git repository (no `.git/`) AND `--issue` is provided -> fallback to raw `#N` ref without URL (origin remote unparseable) | mode: test-framework | expected: bats fixture runs in `mktemp -d` with no git init, asserts the produced file contains bare `#N`
- [P1] new-requirement.sh: `git remote get-url origin` returns SSH URL `git@github.com:lwndev/lwndev-marketplace.git` -> URL regex parses to `lwndev/lwndev-marketplace` correctly | mode: test-framework | expected: bats fixture sets a controlled origin, asserts the rendered URL
- [P1] new-requirement.sh: `git remote get-url origin` returns HTTPS URL `https://github.com/lwndev/lwndev-marketplace.git` -> same parse result | mode: test-framework | expected: bats fixture sets HTTPS origin, asserts URL
- [P1] new-requirement.sh: `git remote get-url origin` returns a non-GitHub URL (`gitlab.com/foo/bar`) -> falls back to raw `#N` ref | mode: test-framework | expected: bats fixture asserts fallback
- [P1] new-requirement.sh: template file (e.g., `feature-requirements.md`) is missing -> script fails with exit 1 and stderr `error: template not found at <path>` | mode: test-framework | expected: bats fixture renames the template, runs the script, asserts exit 1 and stderr message; restores template
- [P1] validate-rc-traceability.sh: bug doc has `LF` line endings (not `CRLF`) — and inverse: doc has CRLF -> regex matches both line-ending styles | mode: test-framework | expected: bats fixture asserts both line-ending variants produce the same JSON
- [P2] new-requirement.sh: `LANG=C` / `LC_ALL=C` environment -> slugify.sh's `tr` calls already use `LC_ALL=C`; the script behaves identically | mode: test-framework | expected: bats fixture sets LC_ALL=C and re-runs an existing happy-path test

### Dependency failure

- [P0] new-requirement.sh: `next-id.sh` exits 2 (e.g., script invokes with bad type) -> caller surfaces the error and does not write a file | mode: test-framework | expected: bats fixture mocks next-id.sh by inserting a dummy in PATH OR uses a known-bad type to force the failure
- [P0] new-requirement.sh: `slugify.sh` exits 1 (empty slug) -> caller surfaces the error and does not write a file | mode: test-framework | expected: bats fixture passes a stopwords-only title and asserts no file is written
- [P0] new-requirement.sh: `validate-categories.sh` exits 2 (invalid category) when `--category` provided -> caller surfaces the error and does not write a file | mode: test-framework | expected: bats fixture asserts no file is written and exit code propagates
- [P1] validate-categories.sh: shell PATH manipulation removes `tr` / `grep` -> script fails loudly | mode: exploratory | expected: manual edge case; the project assumes a working POSIX environment
- [P2] validate-rc-traceability.sh: `jq` not installed (if the script depends on it for JSON emission) -> document the dependency in the script header per Cross-cutting AC; bats fixture skips with `bats_require_minimum_version` and a `command -v jq` check OR the script uses pure-bash JSON emission and `jq` is not required | mode: exploratory | expected: pin in the implementation phase; `jq` is already used elsewhere in the plugin so its absence is a broader CI failure

### Cross-cutting (a11y, i18n, concurrency, permissions)

- [P1] new-requirement.sh: concurrency — two parallel invocations on different types (FEAT and CHORE) — should be safe (different ID namespaces, different directories) | mode: exploratory | expected: manual smoke test; same-type concurrency is documented as a limitation
- [P1] Permissions: `requirements/<type>/` writable by user but `next-id.sh` cannot read it (chmod 333) -> next-id.sh fails with `nullglob` returning empty, returns 001, then write fails because the directory isn't readable for the existence check. Document the failure mode | mode: exploratory | expected: manual reproduction; not a primary concern since the user invokes via their own shell with normal perms
- [P1] i18n: titles in non-Latin scripts (Cyrillic, CJK, Arabic) are stripped to ASCII by slugify -> if the title contains zero ASCII alphanumerics, slugify exits 1 and `new-requirement.sh` surfaces the error rather than silently writing a malformed filename | mode: test-framework | expected: bats fixture passes `"привет мир"` and asserts exit 1 with slug-empty message
- [P2] i18n: titles with mixed scripts (`"привет hello world"`) -> slugify strips Cyrillic, keeps `hello-world`, file is written with `hello-world` slug | mode: test-framework | expected: bats fixture asserts the produced filename
- [P2] Permissions: SKILL.md files updated to invoke `${CLAUDE_PLUGIN_ROOT}/scripts/new-requirement.sh` — when a downstream user does not have execute permission on the script (e.g., the plugin was installed with broken modes), the SKILL.md instruction fails. The chore's Cross-cutting AC `chmod +x` covers this on creation; verify the executable bit survives `npm publish` / git checkouts | mode: exploratory | expected: visual inspection of `git ls-files --stage plugins/lwndev-sdlc/scripts/*.sh` for the `100755` mode bits after the implementation lands

## Non-applicable dimensions

- a11y: the work product is shell scripts invoked from SKILL.md procedures and from the orchestrator. There is no UI surface, no screen-reader interaction, no keyboard-navigation path. Accessibility does not apply to the change at hand.
- networking: the three new scripts are local-only — no HTTP, no database, no third-party API. The only external interaction is `git remote get-url origin` (a local command) inside `new-requirement.sh`. Network-loss scenarios do not apply.
