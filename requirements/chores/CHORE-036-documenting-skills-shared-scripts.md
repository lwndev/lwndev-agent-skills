# Chore: Documenting Skills Shared Scripts

## Chore ID

`CHORE-036`

## GitHub Issue

[#188](https://github.com/lwndev/lwndev-marketplace/issues/188)

## Category

`refactoring`

## Description

Extract mechanical shell from `documenting-features`, `documenting-chores`, and `documenting-bugs` SKILL.md files into three shared scripts (items 1.3, 1.4, 1.5 from #179): `new-requirement.sh` composes ID allocation + slugification + template render, `validate-categories.sh` enforces the chore (5 values) and bug (6 values) category enums, and `validate-rc-traceability.sh` enforces the bug-document `(RC-N)` tag ↔ acceptance-criterion round-trip.

## Affected Files

New scripts:
- `plugins/lwndev-sdlc/scripts/new-requirement.sh`
- `plugins/lwndev-sdlc/scripts/validate-categories.sh`
- `plugins/lwndev-sdlc/skills/documenting-bugs/scripts/validate-rc-traceability.sh`

New bats tests (alongside the scripts):
- `plugins/lwndev-sdlc/scripts/tests/new-requirement.bats`
- `plugins/lwndev-sdlc/scripts/tests/validate-categories.bats`
- `plugins/lwndev-sdlc/skills/documenting-bugs/scripts/tests/validate-rc-traceability.bats`

SKILL.md files updated to call the scripts and drop the replaced prose:
- `plugins/lwndev-sdlc/skills/documenting-features/SKILL.md`
- `plugins/lwndev-sdlc/skills/documenting-chores/SKILL.md`
- `plugins/lwndev-sdlc/skills/documenting-bugs/SKILL.md`

Template assets read by `new-requirement.sh` (existing, no content change expected):
- `plugins/lwndev-sdlc/skills/documenting-features/assets/feature-requirements.md` (planned but not modified)
- `plugins/lwndev-sdlc/skills/documenting-chores/assets/chore-document.md` (planned but not modified)
- `plugins/lwndev-sdlc/skills/documenting-bugs/assets/bug-document.md` (planned but not modified)
- `qa/test-plans/QA-plan-CHORE-036.md`
- `qa/test-results/QA-results-CHORE-036.md`
- `requirements/chores/CHORE-036-documenting-skills-shared-scripts.md`
- `scripts/__tests__/qa-CHORE-036.test.ts`
- `scripts/__tests__/shared-scripts.test.ts`

## Acceptance Criteria

### `new-requirement.sh` (item 1.3)

- [x] Script signature: `new-requirement.sh <FEAT|CHORE|BUG> <title> [--issue <ref>] [--category <name>] [--severity <name>]`
- [x] Composes `next-id.sh` and `slugify.sh`; does not duplicate their logic
- [x] Writes `requirements/<features|chores|bugs>/{TYPE}-{NNN}-{slug}.md` populated from the matching template (FEAT → `feature-requirements.md`, CHORE → `chore-document.md`, BUG → `bug-document.md`)
- [x] Substitutes against the templates' existing placeholder patterns in-place (no template content change required): `XXX` → `NNN`, `[Brief Title]`/`[Feature Name]` → title, `[#N](https://github.com/org/repo/issues/N)` → resolved issue link when `--issue` is provided, category enum line → the picked category when `--category` is provided. The script does NOT introduce new mustache-style markers (`{{ID}}`, etc.) in the templates.
- [x] Echoes the written path on stdout as a single line followed by a trailing newline (matches `next-id.sh` convention; the path is consumed on a terminal, not piped into a slug builder)
- [x] When `--category` is provided AND `<TYPE>` is `CHORE` or `BUG`, the value is validated via `validate-categories.sh` before write; rejection exits non-zero with `error: <message>` on stderr
- [x] When `--category` is provided AND `<TYPE>` is `FEAT`, the script rejects the flag with exit `2` and `error: --category not accepted for FEAT (features have no category enum)` on stderr (mirrors the `--severity` non-BUG rule for CLI surface honesty)
- [x] When `--issue` is provided, the GitHub Issue section in the rendered document is filled with `[#N](https://github.com/<org>/<repo>/issues/N)`; `<org>` and `<repo>` are derived by parsing `git remote get-url origin` (e.g., `git@github.com:lwndev/lwndev-marketplace.git` → `lwndev/lwndev-marketplace`). If the remote is missing or the URL does not match `[git@|https://]github.com[:|/]<org>/<repo>(\.git)?`, fall back to the raw `#N` ref without a URL. The bats fixture sets a controlled `origin` remote to assert the URL form deterministically.
- [x] When `--issue` is omitted, the GitHub Issue section is left in template state (placeholder line preserved)
- [x] `--severity` only accepted when `<TYPE>` is `BUG`; rejected otherwise with exit `2` and `error: --severity only accepted for BUG` on stderr
- [x] Exit codes: `0` success, `1` filesystem/template error, `2` usage/validation error
- [x] Re-runs allocate a fresh ID (monotonic) and never overwrite a prior file: a second invocation with identical args produces a new file at `{TYPE}-{NNN+1}-{slug}.md`

### `validate-categories.sh` (item 1.4)

- [x] Script signature: `validate-categories.sh <FEAT|CHORE|BUG> <category>`
- [x] Accepts the five chore values: `dependencies`, `documentation`, `refactoring`, `configuration`, `cleanup`
- [x] Accepts the six bug values: `runtime-error`, `logic-error`, `ui-defect`, `performance`, `security`, `regression`
- [x] When `<TYPE>` is `FEAT`, exits `0` (features have no category enum) without printing. The CLI-level rejection of `--category` for FEAT lives in `new-requirement.sh`, not here — this script is callable directly and a no-op result for FEAT is the correct lower-level behavior
- [x] Rejection emits `error: invalid <type> category '<category>' (expected: <allowed1>, <allowed2>, ...)` on stderr (matches the `error: <message>` convention from `next-id.sh`/`slugify.sh`)
- [x] Exit codes: `0` valid (or N/A for FEAT), `2` invalid type or unknown category

### `validate-rc-traceability.sh` (item 1.5, scoped to documenting-bugs)

- [x] Script signature: `validate-rc-traceability.sh <bug-doc-path>`
- [x] Parses `## Root Cause(s)` block for `RC-N` IDs and `## Acceptance Criteria` block for `(RC-N)` tags
- [x] **Acceptance-criterion line definition**: a line counts as an AC bullet only if it matches the regex `^- \[[ x]\] ` AND falls within the section starting at `## Acceptance Criteria` and ending at the next `^## ` heading. Lines outside that section, the section heading itself, prose paragraphs, and example bullets inside HTML comments (`<!-- ... -->`) are excluded.
- [x] **Root-cause ID parsing**: RC IDs are extracted from the `## Root Cause(s)` section using the regex `\bRC-[0-9]+\b`, scoped between the `## Root Cause(s)` heading and the next `^## ` heading.
- [x] Emits stdout JSON with the shape `{"missingRCs": ["RC-2", ...], "untaggedACs": ["<criterion text>", ...]}`
- [x] `missingRCs` lists RC IDs declared in the Root Cause section that are referenced by zero acceptance criteria (each AC reference is `(RC-N)` matching `\(RC-[0-9]+\)`)
- [x] `untaggedACs` lists acceptance-criterion lines (per the regex above) that have no `(RC-N)` tag at all
- [x] When the document satisfies the round-trip rule, both arrays are empty and the exit code is `0`
- [x] **Unparseable document definition**: exit `2` is reserved for usage errors and these structural problems — file unreadable, missing `## Root Cause(s)` section entirely, missing `## Acceptance Criteria` section entirely. An empty Root Cause section (heading present, no `RC-N` tokens) or an empty Acceptance Criteria section (heading present, no AC bullets) is parseable; the script returns `0` if both arrays are vacuously empty or `1` if one section is empty while the other has content (round-trip violated).
- [x] Exit codes: `0` round-trip satisfied (both arrays empty), `1` violations present (JSON still printed for the caller), `2` usage error or unparseable document (per the definition above)

### Skill integration

- [x] `documenting-features/SKILL.md`, `documenting-chores/SKILL.md`, and `documenting-bugs/SKILL.md` invoke `new-requirement.sh` instead of describing the ID allocation, slug, template-render, and write steps in prose. The invocation replaces the current "Quick Start" mechanical steps and the explicit `next-id.sh` / `slugify.sh` calls in those skills.
- [x] `documenting-chores/SKILL.md` and `documenting-bugs/SKILL.md` invoke `validate-categories.sh` from their **Verification Checklist** section (the existing checklist already has a "Category matches the type of work" item; replace that prose item with a `validate-categories.sh` invocation that emits an error if the chosen category is invalid). The category enum table itself stays in the SKILL.md as user-facing documentation.
- [x] `documenting-bugs/SKILL.md` invokes `validate-rc-traceability.sh` from its Verification Checklist (the existing "every RC has ≥1 AC; every AC has `(RC-N)` tag" item) instead of describing the regex-parse rule in prose
- [x] Replaced prose is removed (not just supplemented) so the token-reduction target from #188 is realized
- [x] Existing skill-flow contracts (artifact paths, return-contract shapes) are unchanged

### Tests

- [x] Each script ships a bats fixture covering: happy path, every documented exit code, and at least one rejection case for each validation branch
- [x] `npm test` (or the project's bats invocation) passes locally with the new fixtures included
- [x] No existing test fails as a side effect of the SKILL.md edits

### Cross-cutting

- [x] All three scripts are executable (`chmod +x`) and start with `#!/usr/bin/env bash`
- [x] Scripts use `set -euo pipefail` and follow the conventions established by `next-id.sh` / `slugify.sh` (header comment with usage, exit codes, behavior notes; `error: <message>` on stderr for rejections; trailing newline on stdout when the value is a path/ID consumed on a terminal — `slugify.sh`'s no-trailing-newline behavior is the exception, not the rule, because its output is concatenated into filenames)
- [x] No script depends on `jq` for stdout JSON emission unless the existing scripts already require it; if `jq` is introduced, document the dependency in the script header

## Completion

**Status:** `Complete`

**Completed:** 2026-04-29

**Pull Request:** [#250](https://github.com/lwndev/lwndev-marketplace/pull/250)

## Notes

- Items 1.1 (`next-id.sh`) and 1.2 (`slugify.sh`) already exist under `plugins/lwndev-sdlc/scripts/` and are not in scope here. `new-requirement.sh` calls them as subroutines; do not re-implement.
- Stays prose (do NOT script away): FR/NFR authoring, user story content, edge cases, root-cause investigation narrative, severity judgment.
- `new-requirement.sh` is plugin-shared because all three documenting skills consume it. `validate-categories.sh` is plugin-shared for the same reason. `validate-rc-traceability.sh` is skill-scoped to `documenting-bugs` because no other skill consumes it.
- Template rendering inside `new-requirement.sh` substitutes against the templates' existing placeholder patterns in-place — `XXX` for the ID, `[Brief Title]` / `[Feature Name]` for the title, the GitHub URL placeholder line for the issue link, and the category enum line for the chosen category. The templates themselves are NOT modified to introduce new mustache markers; this keeps CHORE-036 a script-only addition. Content authoring (FRs, RCs, edge cases) remains the model's job after the file is written.
- The `--severity` flag is reserved for bugs and the `--category` flag is rejected for features; both rules live in `new-requirement.sh` (not in `validate-categories.sh`). Rejecting them on the wrong type keeps the CLI surface honest and gives the bats fixture a deterministic rejection branch to test.
- The bats test directory pattern follows the existing layout: `plugins/lwndev-sdlc/scripts/tests/<script>.bats` for plugin-shared, `plugins/lwndev-sdlc/skills/<skill>/scripts/tests/<script>.bats` for skill-scoped.
- Parent issue #179 documents the broader prose-to-script audit; this chore is a single slice (items 1.3 / 1.4 / 1.5) and should not expand scope into other items in that backlog.
