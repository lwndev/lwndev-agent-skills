# Implementation Plan: Plugin-Shared Scripts Library Foundation

## Overview

This plan establishes `plugins/lwndev-sdlc/scripts/` as a new plugin-shared script layer holding ten cross-cutting shell utilities that every SDLC skill currently reproduces as prose. The ten scripts (`next-id.sh`, `slugify.sh`, `resolve-requirement-doc.sh`, `build-branch-name.sh`, `ensure-branch.sh`, `check-acceptance.sh`, `checkbox-flip-all.sh`, `commit-work.sh`, `create-pr.sh`, `branch-id-parse.sh`) each implement a single deterministic operation with a defined CLI contract (positional args, exit codes, stdout shape). Each script ships with a bats test fixture and, per NFR-6, prose replacements across every consumer SKILL.md land in the same PR.

The work phases around natural script-family groupings (stateless utilities → requirement-doc + branch surgery → checkbox + commit/PR → adopter prose edits → integration test). A `pr-body.tmpl` asset, a `scripts/README.md`, ten bats fixtures under `scripts/tests/`, and a new vitest integration test in `scripts/__tests__/` round out the deliverables. The plugin version bump and CHANGELOG entry (AC-23, AC-24) are deferred to the `/releasing-plugins` skill and are out of scope for this implementation PR.

## Features Summary

| Feature ID | GitHub Issue | Feature Document | Priority | Complexity | Status |
|------------|--------------|------------------|----------|------------|--------|
| FEAT-020 | [#180](https://github.com/lwndev/lwndev-marketplace/issues/180) | [FEAT-020-plugin-shared-scripts-library.md](../features/FEAT-020-plugin-shared-scripts-library.md) | High | High | Pending |

## Recommended Build Sequence

### Phase 1: Foundation Layout + Trivial Scripts

**Feature:** [FEAT-020](../features/FEAT-020-plugin-shared-scripts-library.md) | [#180](https://github.com/lwndev/lwndev-marketplace/issues/180)
**Status:** ✅ Complete

#### Rationale

The stateless, zero-dependency scripts (`next-id.sh`, `slugify.sh`, `branch-id-parse.sh`) are the safest to write first: they have no cross-script calls, their bats tests can be fully authored in isolation, and `slugify.sh` is a transitive dependency of `build-branch-name.sh` (Phase 2). Creating the directory skeleton and README in Phase 1 also establishes the `${CLAUDE_PLUGIN_ROOT}/scripts/` invocation convention that all later phases reference. Nothing in Phase 1 touches any existing SKILL.md, so it can be reviewed cleanly as a "new files only" diff.

#### Implementation Steps

1. **Create `plugins/lwndev-sdlc/scripts/` directory** with `plugins/lwndev-sdlc/scripts/tests/` and `plugins/lwndev-sdlc/scripts/assets/` subdirectories.

2. **Write `plugins/lwndev-sdlc/scripts/README.md`** documenting:
   - The invocation convention (`bash "${CLAUDE_PLUGIN_ROOT}/scripts/<name>.sh" [args…]`).
   - Why scripts are not on `PATH` (callers always use the absolute path).
   - A table listing all ten scripts with a one-line description each.
   - The bats-fixture layout (`scripts/tests/<script-name>.bats`).
   - How to run bats locally (`bats plugins/lwndev-sdlc/scripts/tests/*.bats`).
   - The `jq`-fallback note for `branch-id-parse.sh` (NFR-1).

3. **Write `plugins/lwndev-sdlc/scripts/next-id.sh`** (FR-1):
   - `set -euo pipefail`.
   - Accept one positional arg: `FEAT`, `CHORE`, or `BUG`; exit 2 on missing/invalid.
   - Map type → directory (`requirements/features/`, `requirements/chores/`, `requirements/bugs/`).
   - Glob `{dir}/{TYPE}-[0-9]+-*.md`; if no files, print `001` and exit 0.
   - Parse numeric suffix from each filename, take max, add 1, zero-pad to 3 digits.
   - Print the zero-padded number to stdout. No side effects.
   - `chmod +x`.

4. **Write `plugins/lwndev-sdlc/scripts/slugify.sh`** (FR-2):
   - `set -euo pipefail`.
   - Accept one positional arg: freeform title string; exit 2 on missing.
   - Lowercase, strip non-ASCII, replace runs of non-alphanumeric with `-`, trim leading/trailing `-`.
   - Drop stopwords (`a`, `an`, `the`, `of`, `for`, `to`, `and`, `or`) as whole tokens.
   - Take the first four remaining tokens, join with `-`.
   - If result is empty, exit 1 with `error: slug is empty after normalization`.
   - Print slug to stdout (no trailing newline). `chmod +x`.

5. **Write `plugins/lwndev-sdlc/scripts/branch-id-parse.sh`** (FR-10):
   - `set -euo pipefail`.
   - Accept one positional arg: branch name; exit 2 on missing.
   - Apply three regexes in order: `^feat/(FEAT-[0-9]+)-`, `^chore/(CHORE-[0-9]+)-`, `^fix/(BUG-[0-9]+)-`.
   - On match, emit JSON `{"id": "…", "type": "…", "dir": "…"}`. Use `jq` if available; fall back to hand-assembled JSON with proper string escaping.
   - On no match, exit 1 with `error: branch name does not match any work-item pattern`.
   - `chmod +x`.

6. **Write `plugins/lwndev-sdlc/scripts/tests/next-id.bats`** (NFR-2):
   - Happy path: create a temp `requirements/features/` directory with synthetic `FEAT-001-*.md` through `FEAT-003-*.md`; assert output is `004`.
   - Empty directory: assert output is `001`.
   - Missing arg: assert exit 2 and `error:` on stderr.
   - Invalid type (`BUG`-prefix typo, lowercase): assert exit 2.
   - Idempotency: running twice without writing a new file returns the same value.
   - AC-8 contract: with 19 files (`FEAT-001` through `FEAT-019`) present, assert output is `020`.

7. **Write `plugins/lwndev-sdlc/scripts/tests/slugify.bats`** (NFR-2):
   - Happy path: `"The Quick Brown Fox Jumps"` → `quick-brown-fox-jumps` (AC-9 contract).
   - Stopword stripping: `"The Art of War"` → `art-war`.
   - Token truncation: six-word title keeps only first four non-stopword tokens.
   - All-stopword title: exit 1 with `error:`.
   - Punctuation-only title (`"!!"`): exit 1.
   - Missing arg: exit 2.
   - Determinism: same input called twice → same output.

8. **Write `plugins/lwndev-sdlc/scripts/tests/branch-id-parse.bats`** (NFR-2):
   - Happy path `feat/FEAT-001-scaffold-skill` → JSON with `id=FEAT-001`, `type=feature`, `dir=requirements/features`.
   - Happy path `chore/CHORE-023-cleanup` → `type=chore`, `dir=requirements/chores`.
   - Happy path `fix/BUG-011-null-crash` → `type=bug`, `dir=requirements/bugs`.
   - `main` → exit 1 with `error: branch name does not match any work-item pattern`.
   - `release/lwndev-sdlc-v1.13.0` → exit 1 (non-matching).
   - `bug/BUG-011-foo` → exit 1 (non-canonical prefix).
   - Missing arg: exit 2.
   - `jq`-absent fallback: shadow `jq` in `PATH`; assert valid JSON still emitted.

9. **Run `shellcheck -S warning` on all three scripts** and fix any warnings (AC-3).

10. **Run `bats plugins/lwndev-sdlc/scripts/tests/*.bats`** to confirm all fixtures pass (AC-6).

#### Deliverables

- [x] `plugins/lwndev-sdlc/scripts/` directory created
- [x] `plugins/lwndev-sdlc/scripts/tests/` directory created
- [x] `plugins/lwndev-sdlc/scripts/assets/` directory created
- [x] `plugins/lwndev-sdlc/scripts/README.md` — invocation convention, script table, bats layout
- [x] `plugins/lwndev-sdlc/scripts/next-id.sh` — executable, FR-1 compliant
- [x] `plugins/lwndev-sdlc/scripts/slugify.sh` — executable, FR-2 compliant
- [x] `plugins/lwndev-sdlc/scripts/branch-id-parse.sh` — executable, FR-10 compliant, jq fallback
- [x] `plugins/lwndev-sdlc/scripts/tests/next-id.bats` — happy path + error + idempotency + AC-8
- [x] `plugins/lwndev-sdlc/scripts/tests/slugify.bats` — happy path + stopwords + AC-9
- [x] `plugins/lwndev-sdlc/scripts/tests/branch-id-parse.bats` — all patterns + jq-absent fallback

#### Acceptance Criteria Closed

- AC-1 (scripts directory + README)
- AC-2 (partial: `next-id.sh`, `slugify.sh`, `branch-id-parse.sh` exist and are executable)
- AC-3 (partial: three scripts pass shellcheck)
- AC-5 (partial: bats files for the three scripts)
- AC-6 (partial: three bats files pass)
- AC-8 (`next-id.sh FEAT` returns `020` against current requirements/)
- AC-9 (`slugify.sh "The Quick Brown Fox Jumps"` returns `quick-brown-fox-jumps`)

#### Dependencies

None — this is the first phase.

---

### Phase 2: Requirement-Doc + Branch Surgery Scripts

**Feature:** [FEAT-020](../features/FEAT-020-plugin-shared-scripts-library.md) | [#180](https://github.com/lwndev/lwndev-marketplace/issues/180)
**Status:** ✅ Complete

#### Rationale

`resolve-requirement-doc.sh` has the broadest consumer footprint (nine callers across seven skills) and is needed by the adopter prose edits in Phase 4. `build-branch-name.sh` depends on `slugify.sh` from Phase 1, and `ensure-branch.sh` is semantically paired with `build-branch-name.sh` — callers always call them in sequence. Grouping all three here keeps the "how do I get onto the right branch?" story complete before tackling the scripts that run on that branch. Each script gets a full bats fixture including the edge cases that touch git state.

#### Implementation Steps

1. **Write `plugins/lwndev-sdlc/scripts/resolve-requirement-doc.sh`** (FR-3):
   - `set -euo pipefail`.
   - Accept one positional arg: ID of the form `FEAT-NNN`, `CHORE-NNN`, or `BUG-NNN`; exit 3 on malformed/missing.
   - Parse prefix, map to directory. Glob `requirements/<dir>/{ID}-*.md` relative to `$PWD`.
   - Exactly one match → print path to stdout, exit 0.
   - Zero matches → `error: no file matches {ID}` on stderr, exit 1.
   - Multiple matches → `error: ambiguous — multiple files match {ID}:` then each candidate, exit 2.
   - `chmod +x`.

2. **Write `plugins/lwndev-sdlc/scripts/build-branch-name.sh`** (FR-4):
   - `set -euo pipefail`.
   - Accept three positional args: `<type>`, `<ID>`, `<summary>`; exit 2 on missing or invalid type.
   - Validate `<type>` is one of `feat`, `chore`, `fix`.
   - Invoke `bash "${BASH_SOURCE%/*}/slugify.sh" "$summary"` to slugify the summary; propagate exit 1 on slug failure.
   - Emit `<type>/<ID>-<slug>` to stdout, exit 0.
   - `chmod +x`.

3. **Write `plugins/lwndev-sdlc/scripts/ensure-branch.sh`** (FR-5):
   - `set -euo pipefail`.
   - Accept one positional arg: target branch name; exit 2 on missing.
   - Read current branch with `git rev-parse --abbrev-ref HEAD`.
   - If equal to target: print `on <branch>`, exit 0.
   - Else check `git show-ref --verify --quiet refs/heads/<branch>`:
     - Exists → `git checkout <branch>`, print `switched to <branch>`, exit 0.
     - Does not exist → `git checkout -b <branch>`, print `created <branch>`, exit 0.
   - If git checkout fails due to dirty tree (detect via exit code + stderr), exit 3 with `error: uncommitted changes prevent branch switch`.
   - `chmod +x`.

4. **Write `plugins/lwndev-sdlc/scripts/tests/resolve-requirement-doc.bats`** (NFR-2):
   - Happy path: temp directory with one `FEAT-001-foo.md`; assert path printed and exit 0.
   - AC-10 contract: assert `FEAT-020` resolves to this feature's own doc path (post-merge fixture).
   - Zero matches: assert exit 1 and `error: no file matches`.
   - Multiple matches: assert exit 2 and `error: ambiguous` with candidate list on stderr.
   - Lowercase ID (`feat-001`): assert exit 3 (malformed).
   - Missing arg: assert exit 3.

5. **Write `plugins/lwndev-sdlc/scripts/tests/build-branch-name.bats`** (NFR-2):
   - Happy path: `feat FEAT-001 "scaffold skill"` → `feat/FEAT-001-scaffold-skill`.
   - Stopword summary: `feat FEAT-001 "The Art of War"` → `feat/FEAT-001-art-war`.
   - Invalid type (`foobar`): exit 2.
   - Empty summary (all stopwords): assert exit 1 propagated from slugify.
   - Missing args: exit 2.

6. **Write `plugins/lwndev-sdlc/scripts/tests/ensure-branch.bats`** (NFR-2):
   - Happy path (already on target branch): assert `on <branch>` printed and exit 0.
   - Branch exists, not current: assert `switched to <branch>` and exit 0 (using a synthetic repo).
   - Branch does not exist: assert `created <branch>` and exit 0.
   - Dirty working tree blocks switch: assert exit 3 and `error: uncommitted changes`.
   - Idempotency: calling twice with the same branch is safe (exit 0 both times).
   - Missing arg: exit 2.

7. **Run `shellcheck -S warning` on all three scripts** and fix any warnings.

8. **Run `bats plugins/lwndev-sdlc/scripts/tests/*.bats`** to confirm all six fixtures pass.

#### Deliverables

- [x] `plugins/lwndev-sdlc/scripts/resolve-requirement-doc.sh` — executable, FR-3 compliant
- [x] `plugins/lwndev-sdlc/scripts/build-branch-name.sh` — executable, FR-4 compliant, calls slugify via `${BASH_SOURCE%/*}`
- [x] `plugins/lwndev-sdlc/scripts/ensure-branch.sh` — executable, FR-5 compliant
- [x] `plugins/lwndev-sdlc/scripts/tests/resolve-requirement-doc.bats` — happy + error + ambiguous + AC-10
- [x] `plugins/lwndev-sdlc/scripts/tests/build-branch-name.bats` — happy + error paths
- [x] `plugins/lwndev-sdlc/scripts/tests/ensure-branch.bats` — happy + dirty-tree + idempotency

#### Acceptance Criteria Closed

- AC-2 (partial: `resolve-requirement-doc.sh`, `build-branch-name.sh`, `ensure-branch.sh` added)
- AC-3 (partial: three more scripts pass shellcheck)
- AC-5 (partial: three more bats fixtures)
- AC-6 (partial: six bats files now pass)
- AC-10 (`resolve-requirement-doc.sh FEAT-020` resolves correctly post-merge)

#### Dependencies

- Phase 1 complete (`slugify.sh` must exist before `build-branch-name.sh` can call it)

---

### Phase 3: Checkbox + Commit/PR Scripts

**Feature:** [FEAT-020](../features/FEAT-020-plugin-shared-scripts-library.md) | [#180](https://github.com/lwndev/lwndev-marketplace/issues/180)
**Status:** Pending

#### Rationale

The checkbox scripts (`check-acceptance.sh`, `checkbox-flip-all.sh`) are the most complex to implement correctly — both require fence-aware line walking, and FR-6 must handle regex-metacharacter literals safely. The commit/PR scripts (`commit-work.sh`, `create-pr.sh`) depend on existing `git` and `gh` tooling that is already a hard dependency of the plugin. The `pr-body.tmpl` asset is authored in this phase as it is only consumed by `create-pr.sh`. Grouping all four scripts here means their bats fixtures can share fence-awareness test fixtures, keeping the test helper DRY. All four are independent of each other's implementation, so they can be written in parallel if two authors are available.

#### Implementation Steps

1. **Write `plugins/lwndev-sdlc/scripts/check-acceptance.sh`** (FR-6):
   - `set -euo pipefail`.
   - Accept two positional args: `<doc-path>`, `<criterion-id-or-substring>`; exit 3 on missing.
   - Read the file. Walk line-by-line, tracking fenced-code-block state (toggle on ` ``` ` or ` ~~~ `; handle nested fences).
   - Find the first `- [ ] ` line **outside** a fenced block that contains the matcher as a literal substring (not regex).
   - If none found and no `- [x] ` line matches either: exit 1 with `error: criterion not found`.
   - If matching `- [x] ` found (already ticked): print `already checked`, exit 0.
   - If matching `- [ ] ` found: rewrite as `- [x] `, preserving indentation and content; write back. Print `checked`, exit 0.
   - If multiple `- [ ] ` lines match: exit 2 with `error: ambiguous — N lines match`.
   - `chmod +x`.

2. **Write `plugins/lwndev-sdlc/scripts/checkbox-flip-all.sh`** (FR-7):
   - `set -euo pipefail`.
   - Accept two positional args: `<doc-path>`, `<section-heading>`; exit 2 on missing.
   - Read file. Locate `## <section-heading>` line; if not found, exit 1 with `error: section not found`.
   - Section ends at next `## ` heading or EOF.
   - Walk section line-by-line, tracking fenced-code-block state (same rules as FR-6).
   - For each `- [ ] ` outside a fenced block, rewrite as `- [x] `.
   - Count lines flipped. Print `checked N lines`. Write file back.
   - If zero flips: exit 0 with `checked 0 lines` (idempotent).
   - `chmod +x`.

3. **Write `plugins/lwndev-sdlc/scripts/commit-work.sh`** (FR-8):
   - `set -euo pipefail`.
   - Accept three positional args: `<type>`, `<category>`, `<description>`; exit 2 on missing or invalid type.
   - Validate `<type>` against the allowed list (`chore`, `fix`, `feat`, `qa`, `docs`, `test`, `refactor`, `perf`, `style`, `build`, `ci`, `revert`).
   - Run `git commit -m "<type>(<category>): <description>"`. Do not stage anything.
   - On success: print the short SHA (`git rev-parse --short HEAD`) to stdout, exit 0.
   - On failure: pass git stderr through unchanged, exit 1.
   - `chmod +x`.

4. **Write `plugins/lwndev-sdlc/scripts/assets/pr-body.tmpl`** (AC-4):
   - Template with placeholders (`${TYPE}`, `${ID}`, `${SUMMARY}`, `${CLOSES_LINE}`, `${GENERATED_WITH}`) for: summary paragraph, optional `Closes …` line, "Test plan" checklist stub, and "Generated with Claude Code" trailer.
   - Design the substitution markers to be compatible with `envsubst` or simple `sed` replacement.

5. **Write `plugins/lwndev-sdlc/scripts/create-pr.sh`** (FR-9):
   - `set -euo pipefail`.
   - Accept `<type>`, `<ID>`, `<summary>`, and optional `--closes <issueRef>`; exit 2 on missing required args, malformed `--closes` token (empty string or bare `#`).
   - Validate `<type>` is one of `feat`, `chore`, `fix`.
   - Read current branch: `git rev-parse --abbrev-ref HEAD`.
   - `git push -u origin <branch>`; on failure, exit 1 with git error.
   - Assemble PR title as `<type>(<ID>): <summary>`.
   - Substitute template variables into `pr-body.tmpl` (locate template via `${BASH_SOURCE%/*}/assets/pr-body.tmpl`); include `Closes <issueRef>` line only when `--closes` was provided.
   - Run `gh pr create --title "<title>" --body "<body>"`; on success, print PR URL; on failure, exit 1 with gh error.
   - `chmod +x`.

6. **Write `plugins/lwndev-sdlc/scripts/tests/check-acceptance.bats`** (NFR-2):
   - Happy path: temp doc with `- [ ] AC-1: some criterion`; assert `checked` printed and box flipped.
   - Already-checked idempotency: same criterion already `- [x]`; assert `already checked`, exit 0.
   - Fence-awareness: doc with `- [ ] criterion` inside a fenced block; assert the fenced box is NOT flipped, only the outer one is.
   - Criterion not found: exit 1.
   - Ambiguous match: two `- [ ]` lines match substring; exit 2.
   - Regex-metacharacter in matcher (`AC-1.2` with literal dot): assert literal match, no regex interpretation.
   - Missing arg: exit 3.

7. **Write `plugins/lwndev-sdlc/scripts/tests/checkbox-flip-all.bats`** (NFR-2):
   - Happy path: flip all `- [ ]` in `## Acceptance Criteria` section; assert `checked N lines`.
   - Idempotency: no `- [ ]` lines present; assert `checked 0 lines`, exit 0.
   - Section not found: exit 1 with `error: section not found`.
   - Fence-awareness: `- [ ]` inside fenced block in the section must not be flipped.
   - Section boundary: assert `- [ ]` lines after the next `## ` heading are not touched.
   - Missing arg: exit 2.

8. **Write `plugins/lwndev-sdlc/scripts/tests/commit-work.bats`** (NFR-2):
   - Happy path in a temp git repo with a staged file: assert exit 0 and a short SHA printed.
   - Nothing staged: assert exit 1 with git error on stderr.
   - Invalid type (`badtype`): exit 2.
   - Missing args: exit 2.
   - Verify commit message format is `<type>(<category>): <description>` (inspect via `git log -1 --format=%s`).

9. **Write `plugins/lwndev-sdlc/scripts/tests/create-pr.bats`** (NFR-2):
   - Happy path (mock `git push` and `gh pr create` as stubs): assert PR URL printed, exit 0.
   - `--closes #42` included: assert `Closes #42` appears in assembled body.
   - `--closes` with empty string: exit 2.
   - `git push` fails: exit 1; `gh pr create` not invoked.
   - `gh pr create` fails: exit 1.
   - Invalid type: exit 2.
   - Missing required args: exit 2.

10. **Run `shellcheck -S warning` on all four scripts** and fix any warnings.

11. **Run `bats plugins/lwndev-sdlc/scripts/tests/*.bats`** to confirm all ten fixtures pass.

#### Deliverables

- [ ] `plugins/lwndev-sdlc/scripts/check-acceptance.sh` — executable, FR-6 compliant, fence-aware
- [ ] `plugins/lwndev-sdlc/scripts/checkbox-flip-all.sh` — executable, FR-7 compliant, fence-aware
- [ ] `plugins/lwndev-sdlc/scripts/commit-work.sh` — executable, FR-8 compliant, no auto-staging
- [ ] `plugins/lwndev-sdlc/scripts/assets/pr-body.tmpl` — template with typed placeholders
- [ ] `plugins/lwndev-sdlc/scripts/create-pr.sh` — executable, FR-9 compliant, uses pr-body.tmpl
- [ ] `plugins/lwndev-sdlc/scripts/tests/check-acceptance.bats` — happy + already-checked + fence + ambiguous + metachar
- [ ] `plugins/lwndev-sdlc/scripts/tests/checkbox-flip-all.bats` — happy + idempotent + fence + boundary
- [ ] `plugins/lwndev-sdlc/scripts/tests/commit-work.bats` — happy + nothing-staged + format
- [ ] `plugins/lwndev-sdlc/scripts/tests/create-pr.bats` — happy + closes + push-fail + gh-fail

#### Acceptance Criteria Closed

- AC-2 (complete: all ten scripts now exist and are executable)
- AC-3 (partial: four more scripts pass shellcheck; all ten now pass)
- AC-4 (`pr-body.tmpl` exists and `create-pr.sh` substitutes correctly)
- AC-5 (complete: all ten bats fixtures present)
- AC-6 (complete: `bats plugins/lwndev-sdlc/scripts/tests/*.bats` exits 0)

#### Dependencies

- Phase 1 complete (directory skeleton + `slugify.sh` for `build-branch-name.sh` tests)
- Phase 2 complete (`build-branch-name.sh` and `ensure-branch.sh` fixture patterns reused)

---

### Phase 4: Adopter Prose Replacements (AC-11 through AC-20)

**Feature:** [FEAT-020](../features/FEAT-020-plugin-shared-scripts-library.md) | [#180](https://github.com/lwndev/lwndev-marketplace/issues/180)
**Status:** Pending

#### Rationale

Per NFR-6, adopter prose replacements must land in the same PR that introduces the scripts — no dangling scripts without callers. Phase 4 is deliberately sequenced after all ten scripts exist and their bats fixtures pass, so every prose replacement references a script that is already verifiable. The edits are grouped by target script (not by target skill) to make the review diff easier to follow: a reviewer can confirm that every AC-11 edit calls `next-id.sh`, every AC-13 edit calls `resolve-requirement-doc.sh`, etc. Within each AC group, skills are edited in alphabetical order.

The replacement pattern in every skill is: identify the smallest prose paragraph (or numbered step) that describes the operation, remove the prose description of the algorithm, and replace it with a `bash "${CLAUDE_PLUGIN_ROOT}/scripts/<name>.sh" …` one-liner with a brief inline note about what the script does and what exit codes the skill should handle.

#### Implementation Steps

1. **AC-11 — ID-allocation prose → `next-id.sh` (3 skills)**
   Edit each skill's "Quick Start" or template section:
   - `plugins/lwndev-sdlc/skills/documenting-features/SKILL.md`: replace "scan `requirements/features/`, find max `FEAT-NNN` suffix, return +1, pad to 3 digits" prose with `bash "${CLAUDE_PLUGIN_ROOT}/scripts/next-id.sh" FEAT`.
   - `plugins/lwndev-sdlc/skills/documenting-chores/SKILL.md`: same replacement with `CHORE`.
   - `plugins/lwndev-sdlc/skills/documenting-bugs/SKILL.md`: same replacement with `BUG`.

2. **AC-12 — Slug-derivation prose → `slugify.sh` (6 skills)**
   In the filename/branch construction steps of each skill, replace prose descriptions of lowercasing, punctuation stripping, and kebab-casing with `bash "${CLAUDE_PLUGIN_ROOT}/scripts/slugify.sh" "<title>"`:
   - `plugins/lwndev-sdlc/skills/documenting-features/SKILL.md`
   - `plugins/lwndev-sdlc/skills/documenting-chores/SKILL.md`
   - `plugins/lwndev-sdlc/skills/documenting-bugs/SKILL.md`
   - `plugins/lwndev-sdlc/skills/implementing-plan-phases/SKILL.md`
   - `plugins/lwndev-sdlc/skills/executing-chores/SKILL.md`
   - `plugins/lwndev-sdlc/skills/executing-bug-fixes/SKILL.md`

3. **AC-13 — ID→file resolution prose → `resolve-requirement-doc.sh` (7 skills)**
   Replace the "Glob `requirements/<type>/{ID}-*.md`, error if not found or multiple match" prose with `bash "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-requirement-doc.sh" "<ID>"` in Step 1 (or equivalent) of each mode/skill:
   - `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` (all three modes: standard, test-plan reconciliation, code-review reconciliation)
   - `plugins/lwndev-sdlc/skills/creating-implementation-plans/SKILL.md`
   - `plugins/lwndev-sdlc/skills/implementing-plan-phases/SKILL.md`
   - `plugins/lwndev-sdlc/skills/executing-chores/SKILL.md`
   - `plugins/lwndev-sdlc/skills/executing-bug-fixes/SKILL.md`
   - `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md`
   - `plugins/lwndev-sdlc/skills/finalizing-workflow/SKILL.md`

4. **AC-14 — Branch-name construction prose → `build-branch-name.sh` (3 skills)**
   Replace branch-name assembly prose with `bash "${CLAUDE_PLUGIN_ROOT}/scripts/build-branch-name.sh" <type> <ID> "<summary>"` in:
   - `plugins/lwndev-sdlc/skills/implementing-plan-phases/SKILL.md`
   - `plugins/lwndev-sdlc/skills/executing-chores/SKILL.md`
   - `plugins/lwndev-sdlc/skills/executing-bug-fixes/SKILL.md`

5. **AC-15 — Branch-create-or-switch prose → `ensure-branch.sh` (3 skills)**
   Replace branch creation/switch prose with `bash "${CLAUDE_PLUGIN_ROOT}/scripts/ensure-branch.sh" "<branch-name>"` in:
   - `plugins/lwndev-sdlc/skills/implementing-plan-phases/SKILL.md`
   - `plugins/lwndev-sdlc/skills/executing-chores/SKILL.md`
   - `plugins/lwndev-sdlc/skills/executing-bug-fixes/SKILL.md`

6. **AC-16 — Single-criterion checkbox-flip prose → `check-acceptance.sh` (4 skills)**
   Replace checkbox-flip prose with `bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-acceptance.sh" "<doc>" "<matcher>"` in:
   - `plugins/lwndev-sdlc/skills/executing-chores/SKILL.md`
   - `plugins/lwndev-sdlc/skills/executing-bug-fixes/SKILL.md`
   - `plugins/lwndev-sdlc/skills/implementing-plan-phases/SKILL.md`
   - `plugins/lwndev-sdlc/skills/finalizing-workflow/SKILL.md`

7. **AC-17 — Section-wide checkbox-flip prose → `checkbox-flip-all.sh` (1 skill)**
   In `finalizing-workflow/SKILL.md` (BK-4.1 from FEAT-019, the "flip all ACs" step), replace section-wide flip prose with `bash "${CLAUDE_PLUGIN_ROOT}/scripts/checkbox-flip-all.sh" "<doc>" "Acceptance Criteria"`.

8. **AC-18 — Commit-message-format prose → `commit-work.sh` (2 skills)**
   Replace commit-message-construction prose with `bash "${CLAUDE_PLUGIN_ROOT}/scripts/commit-work.sh" <type> <category> "<description>"` in:
   - `plugins/lwndev-sdlc/skills/executing-chores/SKILL.md`
   - `plugins/lwndev-sdlc/skills/executing-bug-fixes/SKILL.md`
   - Note: callers remain responsible for `git add` before invoking this script.

9. **AC-19 — PR-creation prose → `create-pr.sh` (3 skills)**
   Replace PR-creation prose with `bash "${CLAUDE_PLUGIN_ROOT}/scripts/create-pr.sh" <type> <ID> "<summary>" [--closes <issueRef>]` in:
   - `plugins/lwndev-sdlc/skills/executing-chores/SKILL.md`
   - `plugins/lwndev-sdlc/skills/executing-bug-fixes/SKILL.md`
   - `plugins/lwndev-sdlc/skills/implementing-plan-phases/SKILL.md`

10. **AC-20 — Branch-name classifier prose → `branch-id-parse.sh` (2 skills)**
    Replace the three-regex branch-classifier prose in:
    - `plugins/lwndev-sdlc/skills/finalizing-workflow/SKILL.md` (FEAT-019's BK-1 step)
    - `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` (resume detection)

11. **Run `npm run validate`** to confirm the plugin still passes validation after all SKILL.md edits.

#### Deliverables

- [ ] `plugins/lwndev-sdlc/skills/documenting-features/SKILL.md` — AC-11 (`next-id.sh`) + AC-12 (`slugify.sh`)
- [ ] `plugins/lwndev-sdlc/skills/documenting-chores/SKILL.md` — AC-11 + AC-12
- [ ] `plugins/lwndev-sdlc/skills/documenting-bugs/SKILL.md` — AC-11 + AC-12
- [ ] `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` — AC-13 (all three modes)
- [ ] `plugins/lwndev-sdlc/skills/creating-implementation-plans/SKILL.md` — AC-13
- [ ] `plugins/lwndev-sdlc/skills/implementing-plan-phases/SKILL.md` — AC-12, AC-13, AC-14, AC-15, AC-16, AC-19
- [ ] `plugins/lwndev-sdlc/skills/executing-chores/SKILL.md` — AC-12, AC-13, AC-14, AC-15, AC-16, AC-18, AC-19
- [ ] `plugins/lwndev-sdlc/skills/executing-bug-fixes/SKILL.md` — AC-12, AC-13, AC-14, AC-15, AC-16, AC-18, AC-19
- [ ] `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` — AC-13
- [ ] `plugins/lwndev-sdlc/skills/finalizing-workflow/SKILL.md` — AC-13, AC-16, AC-17, AC-20
- [ ] `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` — AC-20
- [ ] `npm run validate` passes

#### Acceptance Criteria Closed

- AC-11 (ID-allocation prose replaced in 3 skills)
- AC-12 (slug-derivation prose replaced in 6 skills)
- AC-13 (ID→file resolution prose replaced in 7 skills)
- AC-14 (branch-name construction prose replaced in 3 skills)
- AC-15 (branch-create-or-switch prose replaced in 3 skills)
- AC-16 (single-criterion checkbox-flip prose replaced in 4 skills)
- AC-17 (section-wide checkbox-flip prose replaced in `finalizing-workflow`)
- AC-18 (commit-message-format prose replaced in 2 skills)
- AC-19 (PR-creation prose replaced in 3 skills)
- AC-20 (branch-name classifier prose replaced in 2 skills)
- AC-21 (`plugin.json` unchanged — verified by `npm run validate` passing without touching it)
- AC-22 (`npm run validate` passes)

#### Dependencies

- Phase 1 complete (scripts directory exists so SKILL.md references are valid)
- Phase 2 complete (`resolve-requirement-doc.sh`, `build-branch-name.sh`, `ensure-branch.sh` exist)
- Phase 3 complete (all remaining scripts + `pr-body.tmpl` exist)

---

### Phase 5: Integration Test

**Feature:** [FEAT-020](../features/FEAT-020-plugin-shared-scripts-library.md) | [#180](https://github.com/lwndev/lwndev-marketplace/issues/180)
**Status:** Pending

#### Rationale

The vitest integration test is authored last because it asserts the existence and executable-bit of all ten scripts — a test that can only be written meaningfully once all ten scripts exist (Phase 3). The CHANGELOG and version bump (AC-23, AC-24) are handled by the `/releasing-plugins` skill when the plugin is next released and are intentionally out of scope for this implementation PR — no CHANGELOG edits or `plugin.json` version edits land here.

#### Implementation Steps

1. **Create `scripts/__tests__/shared-scripts.test.ts`** (AC-7):
   Following the conventions of existing tests (`build.test.ts`, `executing-chores.test.ts`), import from `vitest`, `node:fs`, `node:path`.

2. **Test: scripts directory exists and is non-empty**
   Assert `plugins/lwndev-sdlc/scripts/` exists and `fs.readdirSync()` returns a non-empty array.

3. **Test: each of the ten scripts exists and is executable**
   For each script name in the canonical list (`next-id.sh`, `slugify.sh`, `resolve-requirement-doc.sh`, `build-branch-name.sh`, `ensure-branch.sh`, `check-acceptance.sh`, `checkbox-flip-all.sh`, `commit-work.sh`, `create-pr.sh`, `branch-id-parse.sh`):
   - Assert the file exists at `plugins/lwndev-sdlc/scripts/<name>.sh`.
   - Assert `fs.statSync(path).mode & 0o100` is truthy (owner-executable bit set).

4. **Test: `--help` / missing-arg exits non-zero with usage on stderr**
   For each script, invoke it with no arguments via `spawnSync('bash', [scriptPath])` and assert:
   - Exit code is non-zero (2 for usage error, per each FR).
   - stderr includes `error:` or a usage line (sanity-check that arg parsers are wired up).
   Note: scripts that require git or gh context are tested only for the usage-error path (no args), not for full execution, to keep the vitest suite hermetic.

5. **Test: `pr-body.tmpl` asset exists**
   Assert `plugins/lwndev-sdlc/scripts/assets/pr-body.tmpl` exists and is non-empty.

6. **Test: bats test count matches script count**
   Assert `plugins/lwndev-sdlc/scripts/tests/` contains exactly ten `.bats` files, one per script.

7. **Run `npm test`** to confirm all new tests pass and no existing tests regress.

8. **Run `npm run validate`** to confirm the plugin tree still passes validation.

> AC-23 (version bump) and AC-24 (CHANGELOG entry) are **not** addressed in this phase — they are owned by `/releasing-plugins`, which runs on `main` after this PR merges. Do not edit `plugins/lwndev-sdlc/.claude-plugin/plugin.json` or `plugins/lwndev-sdlc/CHANGELOG.md` here.

#### Deliverables

- [ ] `scripts/__tests__/shared-scripts.test.ts` — existence + executable-bit + usage-error + asset + bats-count tests
- [ ] `npm test` exits 0 (all suites green)
- [ ] `npm run validate` exits 0

#### Acceptance Criteria Closed

- AC-7 (vitest integration test for script presence, executable bit, usage-error sanity)
- AC-21 (`plugin.json` unchanged — no new skills, agents, or hooks added)
- AC-22 (`npm run validate` passes on final tree)

> AC-23 and AC-24 are deferred to `/releasing-plugins` (next release cut) and are not closed by this PR.

#### Dependencies

- Phase 1 complete (directory skeleton)
- Phase 2 complete (all ten scripts present and shellchecked)
- Phase 3 complete (all ten scripts present and shellchecked)
- Phase 4 complete (`npm run validate` must pass before final confirmation)

---

## Shared Infrastructure

**`${CLAUDE_PLUGIN_ROOT}` invocation pattern**: Every adopter SKILL.md replacement uses `bash "${CLAUDE_PLUGIN_ROOT}/scripts/<name>.sh"`. Scripts use `${BASH_SOURCE%/*}` when calling sibling scripts internally (e.g., `build-branch-name.sh` calling `slugify.sh`), so they work regardless of CWD.

**Bats harness**: All ten fixtures live under `plugins/lwndev-sdlc/scripts/tests/`. Fixtures use temp directories (created via `mktemp -d` in `setup()`, cleaned in `teardown()`) to isolate filesystem state. Git-dependent fixtures (`ensure-branch.bats`, `commit-work.bats`) create synthetic bare repos in `setup()`. The `bats` invocation target is `bats plugins/lwndev-sdlc/scripts/tests/*.bats`.

**Fence-awareness test fixture**: Both `check-acceptance.bats` and `checkbox-flip-all.bats` share the same synthetic markdown pattern — a section containing a genuine `- [ ]` AC line followed by a fenced code block that also contains a literal `- [ ]` string. The fixture is inlined in each bats file (not shared) to avoid inter-fixture coupling.

**`shellcheck -S warning` gate**: Every script is checked before its phase is considered complete. Running `shellcheck -S warning plugins/lwndev-sdlc/scripts/*.sh` after Phase 3 must exit 0 with no warnings (AC-3).

**`npm run validate` gate**: Run after Phase 4 (prose replacements) and after Phase 5 (integration test) to confirm no edits broke the plugin's structural validation (AC-22).

## Testing Strategy

**Bats unit tests** (`plugins/lwndev-sdlc/scripts/tests/`): one file per script covering happy path, each documented error exit code, idempotency cases (FR-1, FR-5, FR-6, FR-7), fence-awareness (FR-6, FR-7), and the `jq`-absent fallback (FR-10). All bats fixtures run hermetically against temp directories with no network or hub access required.

**Vitest integration tests** (`scripts/__tests__/shared-scripts.test.ts`): filesystem-level assertions on the committed plugin tree (presence, executable bit, bats file count) plus `spawnSync`-based usage-error smoke checks. No full execution of git/gh-dependent scripts.

**Manual end-to-end** (per requirements Testing Requirements section): run a dummy feature workflow through `orchestrating-workflows` exercising `documenting-features` (FR-1), `reviewing-requirements` (FR-3), `implementing-plan-phases` (FR-4, FR-5, FR-6), `executing-chores` (FR-3, FR-4, FR-5, FR-6, FR-8, FR-9), and `finalizing-workflow` (FR-7, FR-10). Also: dirty-tree test for `ensure-branch.sh` and fence-awareness test for `check-acceptance.sh` on a doc with a code sample containing literal `- [ ]`.

## Dependencies and Prerequisites

| Dependency | Status |
|------------|--------|
| `bash` 3.2+ | Present (macOS default) |
| `git` | Present (hard dependency of lwndev-sdlc) |
| `gh` | Present (hard dependency of lwndev-sdlc) |
| `jq` (soft) | Present on most systems; FR-10 falls back to hand-assembled JSON |
| `bats-core` (dev-only) | Must be installed locally to run `bats *.bats` |
| FEAT-019 (finalizing-workflow bookkeeping) | Landed — `finalizing-workflow/SKILL.md` has BK-1 through BK-5 prose that AC-20 and AC-17 will replace |

## Risk Assessment

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| `shellcheck` warnings block merge (AC-3 gate) | High | Medium | Run `shellcheck -S warning` after each script is authored (not just at phase end); fix immediately. Common sources: unquoted variables, `[ ]` vs `[[ ]]`, `set -e` interactions. |
| `jq` absent on reviewer's machine causes `branch-id-parse.sh` bats failure | Medium | Low | Bats fixture tests the fallback explicitly by shadowing `jq` in `PATH`. Document `jq` as recommended-but-optional in README. |
| CRLF in SKILL.md files breaks fence-aware parsing in `check-acceptance.sh` / `checkbox-flip-all.sh` | High | Low | Scripts normalize line endings on read (`tr -d '\r'`) before walking lines; bats fixtures include a CRLF fixture to verify. Consistent with prior art in FEAT-019 (a8c3ab8). |
| Stopword edge cases in `slugify.sh` produce empty slug from valid-looking titles | Medium | Medium | Unit-test multiple stopword combinations. Document that FR-2 exits 1 on empty slug and that FR-4 propagates the failure — callers must handle exit 1 and prompt the user for an alternative title. |
| Prose replacements in twelve SKILL.md files introduce regressions in vitest structural tests | Medium | Medium | Run `npm test` after Phase 4 before Phase 5 to catch regressions early. Existing SKILL.md tests assert section headings and frontmatter, not the prose inside steps — low regression surface. |
| `create-pr.sh` `--closes` token accepted verbatim — malformed token silently corrupts PR body | Low | Low | Validate that `--closes` value is non-empty and not bare `#`; exit 2 on usage error. The script does not validate that the issue exists (by design, per FR-9). |
| Phase 4 edits to `finalizing-workflow/SKILL.md` conflict with FEAT-019 section structure | Medium | Low | FEAT-019 is already merged; read the current SKILL.md before editing to confirm BK-1 and BK-4.1 section positions. AC-20 replaces BK-1's classifier prose; AC-17 replaces BK-4.1's checkbox prose. |

## Success Criteria

- All ten scripts exist under `plugins/lwndev-sdlc/scripts/`, are executable, pass `shellcheck -S warning` with no warnings, and implement their FR exactly.
- `bats plugins/lwndev-sdlc/scripts/tests/*.bats` exits 0 with all fixtures green.
- `scripts/__tests__/shared-scripts.test.ts` exists and passes as part of `npm test`.
- All adopter SKILL.md files (eleven files, AC-11 through AC-20) have legacy prose replaced with script invocations.
- `npm run validate` passes on the updated plugin tree.
- `npm test` passes (full suite, no regressions).

> `plugins/lwndev-sdlc/.claude-plugin/plugin.json` and `plugins/lwndev-sdlc/CHANGELOG.md` are **not** modified by this PR. AC-23 (version bump) and AC-24 (CHANGELOG entry) are owned by `/releasing-plugins` and will land when the plugin is next released.

## Code Organization

```
plugins/lwndev-sdlc/
├── .claude-plugin/
│   └── plugin.json                    ← unchanged (version bump deferred to /releasing-plugins)
├── scripts/                           ← new (Phase 1)
│   ├── README.md                      ← invocation convention + script table (Phase 1)
│   ├── next-id.sh                     ← FR-1 (Phase 1)
│   ├── slugify.sh                     ← FR-2 (Phase 1)
│   ├── resolve-requirement-doc.sh     ← FR-3 (Phase 2)
│   ├── build-branch-name.sh           ← FR-4 (Phase 2)
│   ├── ensure-branch.sh               ← FR-5 (Phase 2)
│   ├── check-acceptance.sh            ← FR-6 (Phase 3)
│   ├── checkbox-flip-all.sh           ← FR-7 (Phase 3)
│   ├── commit-work.sh                 ← FR-8 (Phase 3)
│   ├── create-pr.sh                   ← FR-9 (Phase 3)
│   ├── branch-id-parse.sh             ← FR-10 (Phase 1)
│   ├── assets/
│   │   └── pr-body.tmpl               ← PR body template (Phase 3)
│   └── tests/
│       ├── next-id.bats               ← (Phase 1)
│       ├── slugify.bats               ← (Phase 1)
│       ├── branch-id-parse.bats       ← (Phase 1)
│       ├── resolve-requirement-doc.bats  ← (Phase 2)
│       ├── build-branch-name.bats     ← (Phase 2)
│       ├── ensure-branch.bats         ← (Phase 2)
│       ├── check-acceptance.bats      ← (Phase 3)
│       ├── checkbox-flip-all.bats     ← (Phase 3)
│       ├── commit-work.bats           ← (Phase 3)
│       └── create-pr.bats             ← (Phase 3)
├── skills/
│   ├── documenting-features/SKILL.md  ← AC-11, AC-12 (Phase 4)
│   ├── documenting-chores/SKILL.md    ← AC-11, AC-12 (Phase 4)
│   ├── documenting-bugs/SKILL.md      ← AC-11, AC-12 (Phase 4)
│   ├── reviewing-requirements/SKILL.md ← AC-13 (Phase 4)
│   ├── creating-implementation-plans/SKILL.md ← AC-13 (Phase 4)
│   ├── implementing-plan-phases/SKILL.md ← AC-12, AC-13, AC-14, AC-15, AC-16, AC-19 (Phase 4)
│   ├── executing-chores/SKILL.md      ← AC-12, AC-13, AC-14, AC-15, AC-16, AC-18, AC-19 (Phase 4)
│   ├── executing-bug-fixes/SKILL.md   ← AC-12, AC-13, AC-14, AC-15, AC-16, AC-18, AC-19 (Phase 4)
│   ├── executing-qa/SKILL.md          ← AC-13 (Phase 4)
│   ├── finalizing-workflow/SKILL.md   ← AC-13, AC-16, AC-17, AC-20 (Phase 4)
│   └── orchestrating-workflows/SKILL.md ← AC-20 (Phase 4)
└── CHANGELOG.md                       ← unchanged (v1.14.0 entry deferred to /releasing-plugins)

scripts/__tests__/
└── shared-scripts.test.ts             ← new integration test (Phase 5)
```
