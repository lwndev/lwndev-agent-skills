# Feature Requirements: Plugin-Shared Scripts Library Foundation

## Overview

Establish `plugins/lwndev-sdlc/scripts/` as a new plugin-shared script layer holding ten cross-cutting shell scripts that every SDLC skill already reproduces as prose. This is the foundation lift for the wider #179 prose-to-script backlog: many per-skill conversions cited there depend on these ten scripts existing first. Each script is a small, single-purpose shell utility with a defined exit-code and stdout contract and a bats fixture; the callers that adopt them replace their matching prose in the **same** PR so no unused scripts are left dangling.

## Feature ID

`FEAT-020`

## GitHub Issue

[#180](https://github.com/lwndev/lwndev-marketplace/issues/180)

## Priority

High — Must land first. #180 is explicitly gated by its "Must land first" header: `resolve-requirement-doc.sh` alone has seven consumers (`reviewing-requirements` ×3 modes, `creating-implementation-plans`, `implementing-plan-phases`, `executing-chores`, `executing-bug-fixes`, `executing-qa`, `finalizing-workflow`); `check-acceptance.sh` / `checkbox-flip-all.sh` hit four callers; `build-branch-name.sh`, `ensure-branch.sh`, `commit-work.sh`, and `create-pr.sh` hit three each. Blocking this foundation means every per-skill PR in #179 stalls.

## User Story

As a skill author working in `lwndev-sdlc`, I want deterministic shell scripts for the mechanical operations every skill already performs (ID allocation, slugging, requirement-doc resolution, branch surgery, checkbox flipping, commit/PR emission, branch-name classification) so that per-skill prose stops duplicating the same 80–400-token recipes and new skills compose these operations as one-line `bash ${CLAUDE_PLUGIN_ROOT}/scripts/<name>.sh` calls instead.

## Motivation

The #177 audit (delivered as #179) enumerated ~30 prose-to-script conversions across the 13 skills and 2 agents in `lwndev-sdlc`. Ten of those scripts are **cross-cutting**: they are called by two or more skills with identical semantics. The audit in #179 records the cross-cutting table at the bottom:

| Script | Consumers |
|--------|-----------|
| `next-id.sh` | `documenting-features`, `documenting-chores`, `documenting-bugs` |
| `slugify.sh` | all `documenting-*`, all `executing-*`, `implementing-plan-phases` |
| `resolve-requirement-doc.sh` | `reviewing-requirements` (×3 modes), `creating-implementation-plans`, `implementing-plan-phases`, `executing-chores`, `executing-bug-fixes`, `executing-qa`, `finalizing-workflow` |
| `build-branch-name.sh` | `implementing-plan-phases`, `executing-chores`, `executing-bug-fixes` |
| `ensure-branch.sh` | `implementing-plan-phases`, `executing-chores`, `executing-bug-fixes` |
| `check-acceptance.sh` / `checkbox-flip-all.sh` | `executing-chores`, `executing-bug-fixes`, `implementing-plan-phases`, `finalizing-workflow` |
| `commit-work.sh` | `executing-chores`, `executing-bug-fixes` |
| `create-pr.sh` | `executing-chores`, `executing-bug-fixes`, `implementing-plan-phases` |
| `branch-id-parse.sh` | `finalizing-workflow`, `orchestrating-workflows` (resume detection) |

Housing each of these ten scripts in its primary skill directory would force one of the following: (a) duplicating the logic across every consumer, or (b) designating one skill as "owner" and having other skills call across skill boundaries. Neither is consistent with the existing precedent — `workflow-state.sh`, `capability-discovery.sh`, `persona-loader.sh`, and `stop-hook.sh` already live under `plugins/lwndev-sdlc/skills/<owner>/scripts/` because each has a single owner. Scripts with multiple consumers need a neutral plugin-shared home.

This feature creates that home (`plugins/lwndev-sdlc/scripts/`), lands all ten scripts with full bats coverage, and ships the matching prose replacements in each consumer skill in the same PR so no dangling scripts are left without callers.

Per-workflow savings (from #179's Tier-1 estimate) attributable to these ten scripts alone: ~3,000–5,000 tokens per feature workflow, before any per-skill scripts ship.

## Current State

The `plugins/lwndev-sdlc/` root currently has three directories:

- `agents/` — two subagent definitions (`qa-verifier.md`, `qa-reconciliation-agent.md`)
- `skills/` — thirteen skill directories
- `.claude-plugin/plugin.json` — manifest

There is no `scripts/` directory at the plugin root. Three skills do own skill-scoped `scripts/` subdirectories — `orchestrating-workflows/scripts/` (`workflow-state.sh`, `stop-hook.sh`), `documenting-qa/scripts/` (`capability-discovery.sh`, `persona-loader.sh`, `stop-hook.sh`), and `executing-qa/scripts/` (same capability infrastructure as `documenting-qa`) — but nothing is plugin-shared today.

The ten scripts' logic lives as prose inside the consuming skills. Representative examples:

- `documenting-features`, `documenting-chores`, `documenting-bugs` each re-describe "scan `requirements/<type>/`, find the max `{PREFIX}-NNN` suffix, return +1, pad to 3 digits" in their "Quick Start" sections.
- `reviewing-requirements`'s Step 1 in all three modes (standard, test-plan, code-review) re-describes the ID→file resolution as "Glob `requirements/<type>/{ID}-*.md`, error if not found or multiple match".
- `executing-chores` and `executing-bug-fixes` both re-describe branch-name construction, branch creation/switch, commit-message prefixing, and PR creation as step-by-step instructions, with trivial wording differences.
- `implementing-plan-phases`'s Step 4 re-describes branch naming and ensure-branch surgery identically to the executing skills.
- `finalizing-workflow`'s FR-2 (from FEAT-019) re-describes the three-regex branch classifier that `orchestrating-workflows`'s resume procedure also needs.
- Checkbox-flipping prose is duplicated across four consumer skills with minor wording variations — and because it is prose, each skill must re-describe the "fence-aware" rule (do not flip `- [ ]` that appear inside fenced code blocks) from scratch.

None of this prose is wrong — it is just duplicated, subtly different at every call site, and slow to execute because the model has to re-interpret identical logic each time.

## Scripts in Scope

Ten scripts land under `plugins/lwndev-sdlc/scripts/`. Each has a defined CLI contract (positional args, exit codes, stdout shape) and an adjacent bats test fixture.

### FR-1: `next-id.sh <FEAT|CHORE|BUG>`

**Purpose**: Allocate the next sequential requirement-doc ID.

**Inputs**: Exactly one positional argument: the uppercase type tag `FEAT`, `CHORE`, or `BUG`.

**Behavior**:
1. Map type → directory: `FEAT` → `requirements/features/`, `CHORE` → `requirements/chores/`, `BUG` → `requirements/bugs/`.
2. List files matching `{TYPE}-[0-9]+-*.md` in that directory.
3. Parse the numeric suffix from each filename, take the max, add 1, zero-pad to 3 digits.
4. If the directory is empty or does not exist, return `001`.
5. Print the resulting zero-padded ID (e.g., `020`) to stdout. No `{PREFIX}-` prefix — callers prepend as needed.

**Exit codes**: `0` on success. `2` on usage error (missing/invalid type arg). `1` on filesystem error.

**No side effects**. Idempotent: calling it twice without writing a new file returns the same value.

### FR-2: `slugify.sh <title>`

**Purpose**: Produce a filename/branch-safe kebab-case slug from a freeform title.

**Inputs**: One positional argument: the title string.

**Behavior**:
1. Lowercase the input.
2. Strip non-ASCII characters (or transliterate to ASCII where trivial — space-separated stopwords stay intact).
3. Replace runs of non-alphanumeric characters with a single `-`.
4. Trim leading/trailing `-`.
5. Drop common stopwords (`a`, `an`, `the`, `of`, `for`, `to`, `and`, `or`) when they appear as tokens.
6. Take the first four remaining tokens.
7. Join with `-`.
8. Print the slug to stdout (no trailing newline).

**Exit codes**: `0` on success. `2` on usage error (missing arg). `1` if the slugification result is empty (e.g., title was all stopwords / punctuation).

**Deterministic**: identical input → identical output.

### FR-3: `resolve-requirement-doc.sh <ID>`

**Purpose**: Map a requirement ID to its single document path.

**Inputs**: One positional argument: an ID of the form `FEAT-NNN`, `CHORE-NNN`, or `BUG-NNN` (case-sensitive).

**Behavior**:
1. Parse the prefix → directory (same map as FR-1).
2. Glob `requirements/<dir>/{ID}-*.md`.
3. If exactly one match: print its path to stdout, exit 0.
4. If zero matches: print a one-line error to stderr (`error: no file matches {ID}`), exit 1.
5. If multiple matches: print a one-line error to stderr (`error: ambiguous — multiple files match {ID}:`) followed by each candidate on its own line, exit 2.

**Exit codes**: `0` single match, `1` not found, `2` ambiguous, `3` usage error (malformed ID).

Callers distinguish "not found" from "ambiguous" to apply different recovery flows (ambiguity → prompt or `git log`; not-found → abort).

### FR-4: `build-branch-name.sh <type> <ID> <summary>`

**Purpose**: Assemble the canonical branch name for a work item.

**Inputs**:
- `<type>` — one of `feat`, `chore`, `fix`.
- `<ID>` — the full work-item ID including prefix (`FEAT-001`, `CHORE-023`, `BUG-004`).
- `<summary>` — freeform summary text; will be slugified internally.

**Behavior**:
1. Invoke `slugify.sh` on the summary.
2. Emit `<type>/<ID>-<slug>` to stdout.

**Exit codes**: `0` on success. `2` on usage error (missing args or invalid type). `1` if slugify fails.

Example: `build-branch-name.sh feat FEAT-001 "scaffold skill"` → `feat/FEAT-001-scaffold-skill`.

### FR-5: `ensure-branch.sh <branch-name>`

**Purpose**: Idempotently place the working tree on the named branch.

**Inputs**: One positional argument: the full branch name (e.g., `feat/FEAT-001-scaffold-skill`).

**Behavior**:
1. Read `git rev-parse --abbrev-ref HEAD`.
2. If the current branch equals the target: no-op, print `on <branch>` to stdout, exit 0.
3. Else, check `git show-ref --verify --quiet refs/heads/<branch>`:
   - If it exists: `git checkout <branch>`, print `switched to <branch>`, exit 0.
   - If it does not exist: `git checkout -b <branch>`, print `created <branch>`, exit 0.
4. If the working tree is dirty (uncommitted changes preventing switch): exit 3 with message `error: uncommitted changes prevent branch switch`.

**Exit codes**: `0` success. `2` usage error. `3` dirty working tree. `1` on git command failure.

### FR-6: `check-acceptance.sh <doc-path> <criterion-id-or-substring>`

**Purpose**: Flip a specific acceptance-criteria checkbox from `- [ ]` to `- [x]` in a requirement doc, idempotently and fence-aware.

**Inputs**:
- `<doc-path>` — path to a requirement-doc markdown file.
- `<criterion-id-or-substring>` — either a criterion ID (`AC-1`, `AC-2.3`) or a unique substring from the criterion text.

**Behavior**:
1. Read the file.
2. Walk line-by-line, tracking fenced-code-block state (toggle on ` ``` ` or ` ~~~ ` openings; nested fences tracked correctly).
3. Find the first `- [ ] ` line **outside** a fenced block that contains the matcher.
4. If none found and no `- [x] ` line matches either: exit 1 with `error: criterion not found`.
5. If a matching `- [x] ` line is found (already ticked): exit 0 with `already checked`.
6. If a matching `- [ ] ` line is found: rewrite it as `- [x] `, preserving surrounding indentation and content. Write the file back. Exit 0 with `checked`.
7. If multiple `- [ ] ` lines match the substring (ambiguous): exit 2 with `error: ambiguous — N lines match`.

**Exit codes**: `0` success (checked or already-checked), `1` not found, `2` ambiguous, `3` usage error.

**Idempotent**: running twice on the same criterion is safe.

**Fence-awareness** is mandatory — many requirement docs include code samples with literal `- [ ]` strings that must not be flipped.

### FR-7: `checkbox-flip-all.sh <doc-path> <section-heading>`

**Purpose**: Flip every unchecked checkbox (`- [ ]` → `- [x]`) inside a single named section of a requirement doc.

**Inputs**:
- `<doc-path>` — path to a requirement-doc markdown file.
- `<section-heading>` — the exact heading text without the leading `## ` (e.g., `Acceptance Criteria`).

**Behavior**:
1. Read the file.
2. Locate the section: the `## <section-heading>` line. If not found: exit 1 with `error: section not found`.
3. Section ends at the next `## ` heading or EOF.
4. Walk the section line-by-line, tracking fenced-code-block state (same rules as FR-6).
5. For each `- [ ] ` line outside a fenced block: rewrite as `- [x] `.
6. Count the number of lines flipped and print `checked N lines` to stdout.
7. Write the file back.
8. If zero `- [ ]` lines were found in the section: exit 0 with `checked 0 lines` (idempotent).

**Exit codes**: `0` success, `1` section not found, `2` usage error.

FR-6 operates on a single criterion; FR-7 operates on an entire section. Callers that need to check off "all ACs at once" after a feature completes use FR-7; callers that flip criteria one-at-a-time as tasks land use FR-6.

### FR-8: `commit-work.sh <type> <category> <description>`

**Purpose**: Emit a canonical commit with a typed, categorized conventional-commits message.

**Inputs**:
- `<type>` — one of `chore`, `fix`, `feat`, `qa`, `docs`, `test`, `refactor`, `perf`, `style`, `build`, `ci`, `revert`.
- `<category>` — the bracketed category / work-item ID (e.g., `FEAT-020`, `CHORE-032`, or a freeform category like `release`, `workflow`).
- `<description>` — the subject-line body.

**Behavior**:
1. Stage nothing (callers are responsible for `git add`).
2. Run `git commit -m "<type>(<category>): <description>"`.
3. On success: print the short SHA of the new commit to stdout, exit 0.
4. On failure (nothing staged, hook failure, signing error, etc.): exit 1 with the git error passed through on stderr.

**Exit codes**: `0` success, `1` commit failure, `2` usage error.

**No auto-staging**: keeping staging and committing in separate scripts preserves fine-grained control over which files land in which commit.

### FR-9: `create-pr.sh <type> <ID> <summary> [--closes <issueRef>]`

**Purpose**: Push the current branch and open a PR with the canonical body template.

**Inputs**:
- `<type>` — `feat`, `chore`, or `fix`.
- `<ID>` — full work-item ID (`FEAT-020`, `CHORE-032`, `BUG-010`).
- `<summary>` — freeform PR subject.
- `--closes <issueRef>` (optional) — a GitHub (`#N`) or Jira (`PROJ-123`) reference to append as a `Closes …` line in the PR body.

**Behavior**:
1. Read the current branch with `git rev-parse --abbrev-ref HEAD`.
2. Push: `git push -u origin <branch>`.
3. Assemble the PR title as `<type>(<ID>): <summary>`.
4. Assemble the PR body from the canonical template (subject summary, `Closes …` when provided, and the standard "Test plan" / "Generated with Claude Code" trailer). The body template lives in `plugins/lwndev-sdlc/scripts/assets/pr-body.tmpl`; variables are substituted with `sed`/`envsubst` style placeholders.
5. Run `gh pr create --title "<title>" --body "<body>"`.
6. On success: print the PR URL (stdout from `gh pr create`) to stdout, exit 0.
7. On failure: exit 1 with the gh/git error on stderr.

**Exit codes**: `0` success, `1` push or PR-create failure, `2` usage error.

The `--closes` flag accepts either `#N` (GitHub) or a Jira key (`PROJ-123`); the script uses the exact token verbatim — it does not validate the issue exists.

### FR-10: `branch-id-parse.sh <branch-name>`

**Purpose**: Classify a branch name into its work-item identity.

**Inputs**: One positional argument: the branch name.

**Behavior**:
1. Apply three regexes in order:
   - `^feat/(FEAT-[0-9]+)-` → emit `{"id": "FEAT-NNN", "type": "feature", "dir": "requirements/features"}`
   - `^chore/(CHORE-[0-9]+)-` → emit `{"id": "CHORE-NNN", "type": "chore", "dir": "requirements/chores"}`
   - `^fix/(BUG-[0-9]+)-` → emit `{"id": "BUG-NNN", "type": "bug", "dir": "requirements/bugs"}`
2. On match: print the JSON object to stdout, exit 0.
3. On no match: exit 1 with `error: branch name does not match any work-item pattern`.

**Exit codes**: `0` matched, `1` no match, `2` usage error.

The JSON output shape lets callers consume it with `jq -r '.id'` etc. instead of parsing shell strings.

## Non-Functional Requirements

### NFR-1: Shell-first implementation

All ten scripts are implemented as POSIX-compatible shell (`bash` with `set -euo pipefail`). This matches the existing precedent (`capability-discovery.sh`, `persona-loader.sh`, `workflow-state.sh`, `stop-hook.sh`) and keeps the plugin free of Node / Python runtime dependencies.

Exception: the JSON-emitting scripts (FR-10, and any future internal JSON) use `jq` if installed; fall back to hand-assembled JSON with proper string escaping if `jq` is unavailable.

### NFR-2: Test coverage via bats fixtures

Each script ships an adjacent bats (Bash Automated Testing System) test file verifying exit codes and stdout/stderr shapes. Tests live in `plugins/lwndev-sdlc/scripts/tests/<script-name>.bats`. Every externally-observable behavior in each FR has at least one test case.

Minimum coverage per script:
- Happy-path exit code + stdout shape.
- One representative error path per documented exit code.
- Idempotency test for scripts marked idempotent (FR-1, FR-5, FR-6, FR-7).
- Fence-aware correctness test for FR-6 and FR-7 (construct a fixture with literal `- [ ]` inside a fenced block and verify it is not flipped).
- Usage-error test (missing arg) for all.

### NFR-3: Invocation convention

Adopters invoke scripts as:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/<name>.sh" [args…]
```

`${CLAUDE_PLUGIN_ROOT}` is the environment variable Claude Code sets to the resolved plugin directory. The plugin README notes the convention. Scripts do not rely on `PATH`; callers always use the absolute path.

### NFR-4: Error messages are actionable

Every non-zero exit must print a single one-line diagnostic to stderr starting with `error:`. Multi-line output is permitted only for the ambiguous-match case (FR-3, FR-6), and is structured so callers can `tail` the candidates from stderr.

### NFR-5: No global mutations outside explicit args

Scripts never modify `$PWD`, never export environment variables, and never touch files outside the paths derivable from their arguments. This makes composition safe: callers can invoke any script from any working directory without surprises.

### NFR-6: Prose replacement lands in the same PR as script introduction

This is a hard requirement adopted from #180's conventions section: "adopters replace prose in the SAME PR (no dangling scripts without callers)". When a PR adds `resolve-requirement-doc.sh`, every skill that currently has the "Glob `requirements/<type>/{ID}-*.md`, error if not found…" prose must be edited in the same PR to call the script instead. This is tracked as acceptance criteria AC-11 through AC-20 below.

### NFR-7: Forward compatibility

Script contracts (argv shape, exit codes, stdout format) are treated as stable once merged. Future changes that are additive (new optional flags) require no caller updates; breaking changes require either a major-version bump of the plugin or co-landing caller updates.

## Dependencies

- `bash` 3.2+ (macOS default)
- `git` (already a hard dependency of the plugin)
- `gh` (already a hard dependency)
- `jq` (soft — used by FR-10; falls back to hand-assembled JSON)
- `bats-core` (dev-only; for running the test fixtures via `npm test` or direct `bats <file>`)

No new runtime dependencies introduced beyond what `lwndev-sdlc` already requires.

## Edge Cases

1. **Empty `requirements/{type}/` directory**: FR-1 returns `001` (not an error).
2. **Title that slugifies to empty** (e.g., title is `"!!"`): FR-2 exits 1. FR-4 propagates the failure.
3. **ID with lowercase prefix** (`feat-020`): FR-3 treats this as a usage error (exit 3). Callers must uppercase.
4. **Multiple files match one ID** (e.g., `FEAT-001-a.md` and `FEAT-001-b.md` both present): FR-3 exits 2 with candidates listed on stderr.
5. **Working tree has uncommitted changes when `ensure-branch.sh` wants to switch**: FR-5 exits 3 with a clear error — do not stash, do not discard.
6. **Fenced code block contains `- [ ] item`**: FR-6 and FR-7 do not flip the checkbox inside the fence.
7. **Criterion text contains regex metacharacters** (`.`, `*`, `[`): FR-6 treats the matcher as a literal substring, not a regex.
8. **`git push` is rejected due to non-fast-forward** in FR-9: exit 1 with the git error passed through — do not force-push, do not pull/rebase automatically.
9. **PR already exists for the current branch** in FR-9: exit 1 with the gh error passed through (`gh pr create` fails naturally). Do not attempt to "update" the existing PR.
10. **Branch-name classifier sees a main/non-work-item branch** (e.g., `main`, `release/*`): FR-10 exits 1 with the documented "does not match any work-item pattern" message.
11. **`--closes` flag with a malformed token** (e.g., `#` with no number, or an empty string): FR-9 exits 2 with a usage error.
12. **Scripts invoked from a repo that is not the marketplace repo** (e.g., a different project that installed the plugin): FR-1, FR-3 operate on the caller's CWD — they glob `requirements/<type>/` relative to `$PWD`. This is correct: the consumer repo is where the work-item docs live, not the plugin directory.
13. **`jq` not installed** (NFR-1 fallback): FR-10 falls back to a hand-assembled JSON string. The fallback is exercised by the bats fixture with `jq` temporarily shadowed in `PATH`.

## Testing Requirements

### Unit Tests (bats)

Per NFR-2: one bats file per script under `plugins/lwndev-sdlc/scripts/tests/`. Target: ≥3 assertions per script covering the happy path, one error path, and one edge case called out above. Edge cases 3, 4, 5, 6, 7, 10, 12 have explicit dedicated cases.

### Integration Tests (existing suite)

The existing vitest suite at `scripts/__tests__/` validates plugin structure and marketplace manifest integrity. Add one test case verifying:

- `plugins/lwndev-sdlc/scripts/` exists and is non-empty.
- Each of the ten scripts exists and is executable (`fs.stat` mode check for `0o100`).
- Each script's `-h` / `--help` flag prints usage to stderr and exits non-zero (sanity check that the arg parsers wired up).

### Manual Testing

- Run a new `/orchestrating-workflows "dummy feature"` end-to-end and confirm every consumer skill that was edited in this PR now invokes the script and succeeds. Specifically exercise: `documenting-features` (FR-1), `reviewing-requirements` (FR-3), `implementing-plan-phases` (FR-4, FR-5, FR-6), `executing-chores` (FR-3, FR-4, FR-5, FR-6, FR-8, FR-9), `finalizing-workflow` (FR-7, FR-10).
- Dirty-tree test: stage a change, then run `ensure-branch.sh` for a different branch. Verify exit code 3 and no data loss.
- Fence-awareness test: use `check-acceptance.sh` on a doc whose ACs include a code sample with `- [ ]` literal text. Verify only the genuine AC is flipped.

## Acceptance Criteria

### Script infrastructure

- [ ] AC-1: `plugins/lwndev-sdlc/scripts/` directory exists at the plugin root with a README describing the invocation convention, the list of scripts, and the bats-fixture layout.
- [ ] AC-2: Each of the ten scripts (`next-id.sh`, `slugify.sh`, `resolve-requirement-doc.sh`, `build-branch-name.sh`, `ensure-branch.sh`, `check-acceptance.sh`, `checkbox-flip-all.sh`, `commit-work.sh`, `create-pr.sh`, `branch-id-parse.sh`) exists, is executable (`chmod +x`), and implements its FR exactly.
- [ ] AC-3: Every script passes `shellcheck -S warning` with no warnings.
- [ ] AC-4: `plugins/lwndev-sdlc/scripts/assets/pr-body.tmpl` exists and `create-pr.sh` substitutes variables into it correctly.
- [ ] AC-5: `plugins/lwndev-sdlc/scripts/tests/` contains a bats file per script, each with at minimum happy-path + one error path + the fence-awareness / idempotency cases called out in NFR-2.
- [ ] AC-6: `bats plugins/lwndev-sdlc/scripts/tests/*.bats` exits 0 on a clean check-out.
- [ ] AC-7: The existing vitest suite at `scripts/__tests__/` includes a new integration test covering NFR-2 bullet three (script existence + executable bit + help-flag sanity).

### Contract compliance

- [ ] AC-8: `next-id.sh FEAT` returns `020` against the `requirements/features/` directory as it exists before this PR merges (i.e., with `FEAT-001` through `FEAT-019` present). Post-merge, once this document exists on disk as `FEAT-020`, the same invocation correctly returns `021`.
- [ ] AC-9: `slugify.sh "The Quick Brown Fox Jumps"` returns `quick-brown-fox-jumps` (stopwords + token-count enforced).
- [ ] AC-10: `resolve-requirement-doc.sh FEAT-020` returns `requirements/features/FEAT-020-plugin-shared-scripts-library.md` (this doc, post-merge).

### Adopter prose replacements (NFR-6 — same PR)

Each of the following must have the legacy prose removed and replaced with a `bash "${CLAUDE_PLUGIN_ROOT}/scripts/<name>.sh" …` invocation, in the **same PR** that introduces the script. Specific SKILL.md edits are scoped to the smallest paragraph that currently describes the operation:

- [ ] AC-11: `documenting-features/SKILL.md`, `documenting-chores/SKILL.md`, `documenting-bugs/SKILL.md` — ID-allocation prose in each skill's Quick Start or Template section replaced by `next-id.sh <PREFIX>` invocation.
- [ ] AC-12: `documenting-features/SKILL.md`, `documenting-chores/SKILL.md`, `documenting-bugs/SKILL.md`, `implementing-plan-phases/SKILL.md`, `executing-chores/SKILL.md`, `executing-bug-fixes/SKILL.md` — slug-derivation prose in each skill's filename/branch section replaced by `slugify.sh "<title>"` invocation.
- [ ] AC-13: `reviewing-requirements/SKILL.md` (all three modes), `creating-implementation-plans/SKILL.md`, `implementing-plan-phases/SKILL.md`, `executing-chores/SKILL.md`, `executing-bug-fixes/SKILL.md`, `executing-qa/SKILL.md`, `finalizing-workflow/SKILL.md` — ID→file resolution prose replaced by `resolve-requirement-doc.sh <ID>`.
- [ ] AC-14: `implementing-plan-phases/SKILL.md`, `executing-chores/SKILL.md`, `executing-bug-fixes/SKILL.md` — branch-name construction prose replaced by `build-branch-name.sh <type> <ID> <summary>`.
- [ ] AC-15: `implementing-plan-phases/SKILL.md`, `executing-chores/SKILL.md`, `executing-bug-fixes/SKILL.md` — branch-create-or-switch prose replaced by `ensure-branch.sh <branch-name>`.
- [ ] AC-16: `executing-chores/SKILL.md`, `executing-bug-fixes/SKILL.md`, `implementing-plan-phases/SKILL.md`, `finalizing-workflow/SKILL.md` — single-criterion checkbox-flip prose replaced by `check-acceptance.sh <doc> <matcher>`.
- [ ] AC-17: `finalizing-workflow/SKILL.md` (FR-4.1, the "flip all ACs" step from FEAT-019) — section-wide checkbox-flip prose replaced by `checkbox-flip-all.sh <doc> <section-heading>`.
- [ ] AC-18: `executing-chores/SKILL.md`, `executing-bug-fixes/SKILL.md` — commit-message-format prose replaced by `commit-work.sh <type> <category> <description>`.
- [ ] AC-19: `executing-chores/SKILL.md`, `executing-bug-fixes/SKILL.md`, `implementing-plan-phases/SKILL.md` — PR-creation prose replaced by `create-pr.sh <type> <ID> <summary> [--closes <issueRef>]`.
- [ ] AC-20: `finalizing-workflow/SKILL.md` (FR-2 branch classifier from FEAT-019), `orchestrating-workflows/SKILL.md` (resume detection) — branch-name classifier prose replaced by `branch-id-parse.sh <branch-name>`.

### Release & distribution

- [ ] AC-21: `plugins/lwndev-sdlc/.claude-plugin/plugin.json` does not need to change (no new skills, agents, or hooks). Verify no edit is required.
- [ ] AC-22: `npm run validate` passes on the updated plugin tree.
- [ ] AC-23: The PR bumps `lwndev-sdlc` to the next minor version (1.14.0) since adopters' behavior changes publicly observably (prose is the public interface of a skill).
- [ ] AC-24: The CHANGELOG under `plugins/lwndev-sdlc/CHANGELOG.md` records the new `scripts/` directory and lists all ten scripts.

## Future Enhancements

Out of scope for this feature — tracked in the wider #179 backlog:

- Skill-scoped scripts (`prepare-fork.sh`, `parse-findings.sh`, `finalize.sh`, etc.) that have a single owner skill.
- Agent-replacing scripts (`qa-verify-coverage.sh`, `qa-reconcile-delta.sh`) that supersede `qa-verifier` / `qa-reconciliation-agent`.
- A generic composite `new-requirement.sh` (item 1.3 in #179) that chains `next-id.sh` + `slugify.sh` + template render — composable on top of what this feature ships, but not required now.
- Linting / formatting (e.g., shellcheck-in-CI) applied to the new `scripts/` tree. Scripts must pass shellcheck at merge time (AC-3); continuous enforcement in CI is a follow-on.

## Affected Files

- `plugins/lwndev-sdlc/scripts/next-id.sh` (new)
- `plugins/lwndev-sdlc/scripts/slugify.sh` (new)
- `plugins/lwndev-sdlc/scripts/resolve-requirement-doc.sh` (new)
- `plugins/lwndev-sdlc/scripts/build-branch-name.sh` (new)
- `plugins/lwndev-sdlc/scripts/ensure-branch.sh` (new)
- `plugins/lwndev-sdlc/scripts/check-acceptance.sh` (new)
- `plugins/lwndev-sdlc/scripts/checkbox-flip-all.sh` (new)
- `plugins/lwndev-sdlc/scripts/commit-work.sh` (new)
- `plugins/lwndev-sdlc/scripts/create-pr.sh` (new)
- `plugins/lwndev-sdlc/scripts/branch-id-parse.sh` (new)
- `plugins/lwndev-sdlc/scripts/assets/pr-body.tmpl` (new)
- `plugins/lwndev-sdlc/scripts/README.md` (new)
- `plugins/lwndev-sdlc/scripts/tests/*.bats` (new — one per script)
- `plugins/lwndev-sdlc/skills/documenting-features/SKILL.md`
- `plugins/lwndev-sdlc/skills/documenting-chores/SKILL.md`
- `plugins/lwndev-sdlc/skills/documenting-bugs/SKILL.md`
- `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md`
- `plugins/lwndev-sdlc/skills/creating-implementation-plans/SKILL.md`
- `plugins/lwndev-sdlc/skills/implementing-plan-phases/SKILL.md`
- `plugins/lwndev-sdlc/skills/executing-chores/SKILL.md`
- `plugins/lwndev-sdlc/skills/executing-bug-fixes/SKILL.md`
- `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md`
- `plugins/lwndev-sdlc/skills/finalizing-workflow/SKILL.md`
- `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md`
- `plugins/lwndev-sdlc/CHANGELOG.md`
- `scripts/__tests__/` — new integration test verifying script presence and executable bit

## Completion

**Status:** Pending
