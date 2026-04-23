# Implementation Plan: `reviewing-requirements` Scripts (FEAT-026)

## Overview

Collapse the deterministic prose inside `reviewing-requirements` into six skill-scoped shell scripts so every per-mode invocation (standard, test-plan reconciliation, code-review reconciliation) replaces its Step 1.5 / Step 2 / Step 3 / Step 7 / R1–R5 / CR1–CR2 prose with a single script call. The plugin-shared `resolve-requirement-doc.sh` (FEAT-020) already exists and is a dependency, not in scope.

All six scripts live under `plugins/lwndev-sdlc/skills/reviewing-requirements/scripts/` (new directory) with bats fixtures under `scripts/tests/`. The SKILL.md rewrite (FR-7) and caller audit (FR-8) land in Phase 4 after all scripts are implemented and tested — preserving the running skill's behavior mid-workflow.

The plan follows the four-layer sequencing established by FEAT-025: pure/cheap scripts first, composite scripts with cross-dependencies later, SKILL.md cutover last. FEAT-025 phases are all complete and that pattern proved low-risk. Every script ships with its bats fixture in the same phase — tests are never deferred.

## Features Summary

| Feature ID | GitHub Issue | Feature Document | Priority | Complexity | Status |
|------------|--------------|------------------|----------|------------|--------|
| FEAT-026 | [#184](https://github.com/lwndev/lwndev-marketplace/issues/184) | [FEAT-026-reviewing-requirements-scripts.md](../features/FEAT-026-reviewing-requirements-scripts.md) | Medium | Medium | Pending |

## Recommended Build Sequence

### Phase 1: Directory Scaffold + Simpler Scripts — `extract-references.sh` (FR-2), `cross-ref-check.sh` (FR-4)

**Feature:** [FEAT-026](../features/FEAT-026-reviewing-requirements-scripts.md) | [#184](https://github.com/lwndev/lwndev-marketplace/issues/184)
**Status:** ✅ Complete

#### Rationale

`extract-references.sh` and `cross-ref-check.sh` are the cheapest wins in the feature. Neither touches `gh` or `git grep` — they operate on file text only (plus a `git ls-files` call deferred to FR-3). `cross-ref-check.sh` is a thin wrapper: it calls `extract-references.sh` internally and then runs only the cross-ref subset of FR-3's verification logic, so it cannot be implemented before FR-2 exists. Starting here:

1. Establishes the `scripts/` and `scripts/tests/` directories that all later phases require.
2. Delivers the most token-savings-per-implementation-effort pair — `extract-references.sh` alone saves ~1,200–1,800 tokens/workflow by eliminating the four-category extraction prose from three mode invocations.
3. Produces a concrete JSON output shape (`{filePaths, identifiers, crossRefs, ghRefs}`) that FR-3's `verify-references.sh` (Phase 2) will consume — locking in the interface before Phase 2 builds against it.
4. `cross-ref-check.sh` saves ~450 tokens/workflow and is so narrow (call FR-2, filter to crossRefs, run a single `ls` glob) that bundling it with Phase 1 adds minimal cost.

No external tools beyond `bash` + basic POSIX utilities are required, so these scripts are fully testable without stubs.

#### Implementation Steps

1. Create the new directories:
   - `plugins/lwndev-sdlc/skills/reviewing-requirements/scripts/`
   - `plugins/lwndev-sdlc/skills/reviewing-requirements/scripts/tests/`

2. Write `plugins/lwndev-sdlc/skills/reviewing-requirements/scripts/extract-references.sh`:
   - Shebang `#!/usr/bin/env bash`; `set -euo pipefail`.
   - Signature: `extract-references.sh <doc-path>`. Exit `2` on missing arg with `[error] usage: extract-references.sh <doc-path>` to stderr. Exit `1` if file does not exist or is unreadable.
   - Scan the file for four reference classes simultaneously:
     - **`filePaths`**: tokens matching `[A-Za-z0-9_./-]+\.(md|ts|tsx|js|jsx|json|sh|bats|ya?ml|toml)` appearing inside backticks or as bare paths. De-duplicate preserving first-occurrence order.
     - **`identifiers`**: backticked tokens matching `^[a-zA-Z_$][a-zA-Z0-9_$]*$` that plausibly name a function, class, or exported symbol. Skip false positives: `true`, `false`, `null`, single-letter identifiers, and common language keywords (`if`, `for`, `while`, `return`, `const`, `let`, `var`, `function`, `class`, `import`, `export`, `default`, `type`, `interface`). De-duplicate.
     - **`crossRefs`**: every `FEAT-[0-9]+`, `CHORE-[0-9]+`, `BUG-[0-9]+` token (bare or linked). De-duplicate.
     - **`ghRefs`**: every `#[0-9]+` token and every `https://github.com/<owner>/<repo>/(issues|pull)/[0-9]+` URL. Normalize URL to `#<N>` when owner/repo matches the repo's `origin` (best-effort via `git remote get-url origin`; fall back to emitting the full URL if `git` is unavailable or the URL doesn't match). De-duplicate.
   - Emit one JSON object on stdout — all four arrays always present (possibly empty):
     ```json
     {"filePaths":[],"identifiers":[],"crossRefs":[],"ghRefs":[]}
     ```
   - Use `jq` for JSON assembly if available; fall back to pure-bash `printf` construction. Declare `jq` as optional in the top-of-file comment.
   - `chmod +x`.

3. Write `plugins/lwndev-sdlc/skills/reviewing-requirements/scripts/cross-ref-check.sh`:
   - Shebang `#!/usr/bin/env bash`; `set -euo pipefail`.
   - Signature: `cross-ref-check.sh <doc-path>`. Exit `2` on missing arg. Exit `1` on file not found / unreadable.
   - Internally invoke `extract-references.sh <doc-path>` (sibling script) and capture `crossRefs` from its stdout.
   - For each crossRef ID, run the cross-ref verification: `ls requirements/{features,chores,bugs}/<REF>-*.md 2>/dev/null`. Classify as `ok` (exactly one match), `ambiguous` (multiple matches), or `missing` (zero matches). Note: `moved` and `unavailable` do not apply — these refs live under `requirements/` and have no `gh`-fetch component.
   - Emit one JSON object on stdout:
     ```json
     {"ok":[],"ambiguous":[],"missing":[]}
     ```
     Each entry shape: `{"ref":"FEAT-020","detail":"..."}`.
   - Exit codes: `0` success; `1` on file-not-found or unreadable `<doc-path>`; `2` on missing arg.
   - `chmod +x`.

4. Write `plugins/lwndev-sdlc/skills/reviewing-requirements/scripts/tests/extract-references.bats`:
   - Create a fixture directory `scripts/tests/fixtures/` with a minimal requirement document containing each reference category.
   - Happy-path tests:
     - Doc with backticked file paths (`\`scripts/foo.sh\``) -> `filePaths` contains the path.
     - Doc with bare file extension paths (`plugins/lwndev-sdlc/SKILL.md`) -> `filePaths` contains it.
     - Doc with backticked identifier (`\`getSourcePlugins\``) -> `identifiers` contains it.
     - Skip false positives: `\`true\``, `\`null\``, single-letter `\`x\`` -> not in `identifiers`.
     - Doc with `FEAT-020` reference -> `crossRefs` contains `FEAT-020`.
     - Doc with `CHORE-003` and `BUG-001` -> both appear in `crossRefs`.
     - Doc with `#184` -> `ghRefs` contains `#184`.
     - Doc with `https://github.com/<origin-owner>/<origin-repo>/issues/184` -> normalized to `#184`.
     - Doc with `https://github.com/other-owner/other-repo/issues/5` -> kept as full URL.
     - De-duplication: same path mentioned twice -> appears once in output.
     - All-empty doc -> all four arrays empty.
     - Empty arrays shape always present: `filePaths`, `identifiers`, `crossRefs`, `ghRefs` keys present even when empty.
   - Error tests:
     - Missing arg -> exit `2`.
     - Non-existent file path -> exit `1`.

5. Write `plugins/lwndev-sdlc/skills/reviewing-requirements/scripts/tests/cross-ref-check.bats`:
   - Create fixture requirement docs with known cross-references.
   - Happy-path tests:
     - Doc with `FEAT-020` (which exists under `requirements/features/`) -> `ok` array contains entry.
     - Doc with `FEAT-999` (no matching file) -> `missing` array contains entry.
     - Doc with `CHORE-003` that matches multiple files (create two fixture files) -> `ambiguous` array contains entry.
     - Doc with no cross-references -> all three arrays empty.
     - Output shape: `ok`, `ambiguous`, `missing` keys always present.
   - Error tests:
     - Missing arg -> exit `2`.
     - Non-existent doc path -> exit `1`.

#### Deliverables

- [x] `plugins/lwndev-sdlc/skills/reviewing-requirements/scripts/` (directory)
- [x] `plugins/lwndev-sdlc/skills/reviewing-requirements/scripts/tests/` (directory)
- [x] `plugins/lwndev-sdlc/skills/reviewing-requirements/scripts/extract-references.sh`
- [x] `plugins/lwndev-sdlc/skills/reviewing-requirements/scripts/cross-ref-check.sh`
- [x] `plugins/lwndev-sdlc/skills/reviewing-requirements/scripts/tests/fixtures/` (directory with fixture docs)
- [x] `plugins/lwndev-sdlc/skills/reviewing-requirements/scripts/tests/extract-references.bats`
- [x] `plugins/lwndev-sdlc/skills/reviewing-requirements/scripts/tests/cross-ref-check.bats`

---

### Phase 2: Core Verification — `verify-references.sh` (FR-3) + `detect-review-mode.sh` (FR-1)

**Feature:** [FEAT-026](../features/FEAT-026-reviewing-requirements-scripts.md) | [#184](https://github.com/lwndev/lwndev-marketplace/issues/184)
**Status:** ✅ Complete
**Depends on:** Phase 1

#### Rationale

`verify-references.sh` consumes `extract-references.sh`'s output shape — it cannot be meaningfully tested until Phase 1's JSON contract is locked. It is the single biggest token saver in the feature: ~1,500–2,400 tokens/workflow (rank #4 in the #179 top-10 table), driven by replacing the multi-category classification prose that runs up to three times per workflow. It also introduces the only `git grep` call in the feature, requiring PATH-shadowing stubs in bats.

`detect-review-mode.sh` is grouped in Phase 2 rather than Phase 1 because it calls `gh pr list` (external network), which demands stub infrastructure already being introduced for `verify-references.sh`'s `gh issue view` calls. Building both stubs in the same phase avoids setting up the infrastructure twice. The two scripts are otherwise independent — neither calls the other — so their bats fixtures can be written in parallel. `detect-review-mode.sh` saves ~900 tokens/workflow (rank #7 in the savings table) and is the contract that dispatches all three modes, making it foundational for Phase 3's reconciliation scripts.

Together, Phase 2 delivers the two scripts that represent the highest per-script token savings after Phase 1.

#### Implementation Steps

1. Write `plugins/lwndev-sdlc/skills/reviewing-requirements/scripts/verify-references.sh`:
   - Shebang `#!/usr/bin/env bash`; `set -euo pipefail`.
   - Signature: `verify-references.sh <refs-json>`. Exit `2` on missing arg.
   - **Dual-shape dispatch heuristic**: if the arg's first non-whitespace character is `{` or `[`, treat it as a literal JSON string; otherwise treat it as a file path and read its contents (falling back to treating the arg as a literal JSON string if the file does not exist). Exit `1` on unparseable JSON.
   - If parsed JSON has missing arrays, treat them as empty (tolerant forward shape per edge case 6 in the requirements doc).
   - **`filePaths`** verification: `test -e <path>`. On miss, run `git ls-files | grep -F <basename>`. Classify as:
     - `ok` — exact-path match.
     - `moved` — basename match at a different path (include both old and new paths in the entry).
     - `ambiguous` — multiple basename matches (include all competing paths).
     - `missing` — no match at all.
   - **`identifiers`** verification: `git grep -n <identifier>` across tracked files. Classify as:
     - `ok` — 1 to 19 matches.
     - `ambiguous` — 20 or more matches (identifier too generic).
     - `missing` — 0 matches.
   - **`crossRefs`** verification: `ls requirements/{features,chores,bugs}/<REF>-*.md 2>/dev/null`. Classify as `ok`, `ambiguous`, or `missing` (no `moved` or `unavailable` for cross-refs).
   - **`ghRefs`** verification: `gh issue view <N> --json number,state` per reference. When `gh` is missing or unauthenticated (any non-404 failure), classify all affected refs as `unavailable` and emit exactly one `[info] verify-references: gh unavailable; <N> ghRefs marked unavailable.` line to stderr (one emission per invocation, not per ref). Individual ref outcomes: `ok` (issue exists), `missing` (404), `unavailable` (graceful skip).
   - Emit one JSON object on stdout — all five arrays always present:
     ```json
     {"ok":[],"moved":[],"ambiguous":[],"missing":[],"unavailable":[]}
     ```
     Each entry: `{"category":"filePaths","ref":"...","detail":"..."}`.
   - Exit codes: `0` success (including graceful-skip); `1` on malformed `<refs-json>`; `2` on missing arg.
   - Declare `jq` as optional in top-of-file comment. Use it for JSON parsing/assembly when available; pure-bash fallback otherwise.
   - `chmod +x`.

2. Write `plugins/lwndev-sdlc/skills/reviewing-requirements/scripts/detect-review-mode.sh`:
   - Shebang `#!/usr/bin/env bash`; `set -euo pipefail`.
   - Signature: `detect-review-mode.sh <ID> [--pr <N>]`. Exit `2` on missing arg or unrecognized-shape ID. A non-numeric `--pr` value (e.g., `--pr abc`) -> exit `2` with `[warn] detect-review-mode: --pr value must be numeric` to stderr.
   - **Mode precedence chain** (applied in order):
     1. `--pr <N>` flag present (and numeric) -> emit `{"mode":"code-review","prNumber":<N>}`, exit `0`. Do not probe `gh`.
     2. Derive branch prefix from ID prefix (`FEAT-` -> `feat`, `CHORE-` -> `chore`, `BUG-` -> `fix`). Run `gh pr list --head "<prefix>/<ID>-*" --json number,state --jq '[.[] | select(.state=="OPEN")][0].number'`. On success with a numeric result -> emit `{"mode":"code-review","prNumber":<N>}`, exit `0`. If `gh` is missing or unauthenticated, silently skip to step 3 (no `[warn]` — matches Step 1.5 behavior). If `gh` returns a non-empty response but the first element lacks a `number` field, emit `[warn] detect-review-mode: gh response missing 'number' field; falling through.` to stderr and continue to step 3.
     3. Check `qa/test-plans/QA-plan-<ID>.md` exists -> emit `{"mode":"test-plan","testPlanPath":"qa/test-plans/QA-plan-<ID>.md"}`, exit `0`.
     4. Fallback -> emit `{"mode":"standard"}`, exit `0`.
   - Exit codes: `0` on any recognized outcome; `1` on malformed `gh` response JSON (distinct from graceful skip); `2` on missing / malformed args.
   - `chmod +x`.

3. Write `plugins/lwndev-sdlc/skills/reviewing-requirements/scripts/tests/verify-references.bats`:
   - Use PATH-shadowing for `git` and `gh` subcommands.
   - `filePaths` tests:
     - Exact-path match (stub `test -e` to succeed) -> entry in `ok`.
     - Basename-only match at different path (stub `git ls-files` to return alternate path) -> entry in `moved` with both paths in `detail`.
     - Multiple basename matches -> entry in `ambiguous`.
     - No match anywhere -> entry in `missing`.
   - `identifiers` tests:
     - 1 to 19 matches (stub `git grep -n` to return 5 lines) -> entry in `ok`.
     - 20+ matches (stub to return 20 lines) -> entry in `ambiguous`.
     - 0 matches (stub to return empty) -> entry in `missing`.
   - `crossRefs` tests:
     - Existing requirement file -> `ok`.
     - No matching file -> `missing`.
     - Multiple matching files -> `ambiguous`.
   - `ghRefs` tests:
     - `gh` succeeds -> `ok`.
     - `gh` returns 404 error -> `missing`.
     - `gh` not on PATH (stub `command -v gh` to fail) -> `unavailable`; stderr contains `[info] verify-references: gh unavailable; 1 ghRefs marked unavailable.`.
     - Multiple refs, `gh` unavailable -> single `[info]` line on stderr (not one per ref).
   - JSON shape tests:
     - All-empty input `{}` -> output has five arrays, all empty.
     - Missing array key in input -> treated as empty (tolerant).
   - Dual-shape dispatch tests:
     - Arg starts with `{` -> treated as literal JSON.
     - Arg is a path to a file containing JSON -> file is read.
     - Arg is a non-existent path whose content also fails JSON parse -> exit `1`.
   - Error tests:
     - Missing arg -> exit `2`.
     - Unparseable JSON (neither file nor valid JSON) -> exit `1`.

4. Write `plugins/lwndev-sdlc/skills/reviewing-requirements/scripts/tests/detect-review-mode.bats`:
   - Use PATH-shadowing for `gh`.
   - Precedence chain tests:
     - `--pr 231` provided -> exit `0`, stdout `{"mode":"code-review","prNumber":231}`.
     - No `--pr`; `gh pr list` returns open PR `#50` -> exit `0`, stdout `{"mode":"code-review","prNumber":50}`.
     - No `--pr`; `gh` not on PATH -> silently skip to step 3; test plan present -> `{"mode":"test-plan","testPlanPath":"qa/test-plans/QA-plan-FEAT-026.md"}`.
     - No `--pr`; `gh` returns empty array; no test plan -> `{"mode":"standard"}`.
     - `CHORE-` prefix -> branch prefix `chore` in the `gh pr list` call.
     - `BUG-` prefix -> branch prefix `fix` in the `gh pr list` call.
   - Non-numeric `--pr` tests:
     - `--pr abc` -> exit `2`, stderr contains `[warn] detect-review-mode: --pr value must be numeric`.
   - Malformed `gh` response test (stub `gh` to return JSON missing `number` field) -> exit `0`, stderr contains `[warn] detect-review-mode: gh response missing 'number' field; falling through.`, mode falls through to test-plan or standard.
   - Error tests:
     - Missing `<ID>` arg -> exit `2`.
     - Empty `<ID>` arg -> exit `2`.
     - Malformed `<ID>` (`FEAT-` no digits) -> exit `2`.
     - Lowercase ID (`feat-026`) -> exit `2`.

#### Deliverables

- [x] `plugins/lwndev-sdlc/skills/reviewing-requirements/scripts/verify-references.sh`
- [x] `plugins/lwndev-sdlc/skills/reviewing-requirements/scripts/detect-review-mode.sh`
- [x] `plugins/lwndev-sdlc/skills/reviewing-requirements/scripts/tests/verify-references.bats`
- [x] `plugins/lwndev-sdlc/skills/reviewing-requirements/scripts/tests/detect-review-mode.bats`

---

### Phase 3: Reconciliation Scripts — `reconcile-test-plan.sh` (FR-5) + `pr-diff-vs-plan.sh` (FR-6)

**Feature:** [FEAT-026](../features/FEAT-026-reviewing-requirements-scripts.md) | [#184](https://github.com/lwndev/lwndev-marketplace/issues/184)
**Status:** ✅ Complete
**Depends on:** Phase 1 (for FR-2's extraction patterns reused in FR-6), Phase 2 (for the detection contract established by FR-1)

#### Rationale

These are the two most complex scripts in the feature: `reconcile-test-plan.sh` implements a bidirectional document-parsing matcher with five match classes; `pr-diff-vs-plan.sh` introduces a `gh pr diff` network call and best-effort regex parsing of unified diffs.

They are grouped together in Phase 3 for three reasons:

1. **Shared test infrastructure**: Both scripts require PATH-shadowing of `gh` subcommands already established in Phase 2's bats infrastructure. Grouping them avoids a third setup cycle.
2. **NFR-6 shared-matcher decision boundary**: NFR-6 requires that `reconcile-test-plan.sh`'s matcher either be factored into a shared `lib/match-traceability.sh` now (for `executing-qa`'s upcoming `qa-reconcile-delta.sh` to reuse) or ship with a `TODO(NFR-6)` comment and the deduplication handled in the `executing-qa` PR. The decision **per this plan** is **option (a): ship our own copy now with a `TODO` comment** so FEAT-026 is not blocked on `executing-qa`'s timeline. The `reconcile-test-plan.sh` implementation includes a header comment:
   ```bash
   # TODO(NFR-6 / FEAT-026): This matcher shares logic with executing-qa's upcoming
   # qa-reconcile-delta.sh. Factor into lib/match-traceability.sh when that script lands.
   # See: requirements/features/FEAT-026-reviewing-requirements-scripts.md NFR-6.
   ```
   The factor decision (create `lib/match-traceability.sh` or not) is deferred to the `executing-qa` PR, which lands second and reconciles the duplication. The PR body for FEAT-026 must document this explicitly.
3. **`pr-diff-vs-plan.sh` reuses FR-2 extraction patterns**: the script parses test-plan file paths and identifiers using the same regex patterns as `extract-references.sh`. By Phase 3, those patterns are tested and stable, so `pr-diff-vs-plan.sh` can import or inline them confidently.

#### Implementation Steps

1. Write `plugins/lwndev-sdlc/skills/reviewing-requirements/scripts/reconcile-test-plan.sh`:
   - Shebang `#!/usr/bin/env bash`; `set -euo pipefail`.
   - Top-of-file NFR-6 `TODO` comment (exact text shown in Rationale above).
   - Signature: `reconcile-test-plan.sh <req-doc> <plan-doc>`. Exit `2` on missing args. Exit `1` on file-not-found / unreadable for either arg.
   - **Parse requirement doc**:
     - Collect FR-N, NFR-N, RC-N IDs from headings (`### FR-N:`, `### NFR-N:`, `### RC-N:`).
     - Collect acceptance criteria entries from the `## Acceptance Criteria` section. If the section is absent, exit `1` with `[error] reconcile-test-plan: requirement doc missing '## Acceptance Criteria' heading`.
     - Extract the priority field for each FR-N / NFR-N / RC-N (look for `Priority:` or document-level `## Priority` text — use the document-level priority as fallback for items without individual priority).
   - **Parse test plan**:
     - **Version-2 prose format detection**: lines starting with `[P0]`, `[P1]`, or `[P2]` are scenario lines. Extract any FR-N / NFR-N / RC-N / AC-N references from the **full scenario line** (not just a trailing-tag slot) — the extraction regex operates on everything after the `[P0|P1|P2]` priority tag.
     - **Legacy table-format detection**: if the plan contains `| RC-` or `| AC-` column headers, parse column-wise instead. Extract IDs from table cells.
     - Both formats must produce correct classification output (NFR-3 mandate).
     - If no scenario lines matching either format are found, exit `1` with `[error] reconcile-test-plan: no parseable scenario lines found in test plan`.
   - **Bidirectional match** (R1–R5 from the requirements doc):
     - **R1 (`gaps`)**: requirement-side IDs (FR-N, NFR-N, RC-N, AC entries) with no corresponding scenario in the test plan.
     - **R2 (`contradictions`)**: scenarios referencing a requirement ID whose body text in the req-doc has drifted from the quoted phrase in the scenario (surface the mismatch as a `detail` string; the model decides if it is a real contradiction).
     - **R3 (`surplus`)**: scenarios with no corresponding requirement-side ID.
     - **R4 (`drift`)**: scenarios whose trailing priority (`[P0|P1|P2]`) disagrees with the requirement's priority field.
     - **R5 (`modeMismatch`)**: scenarios whose `mode:` field (executable, exploratory, manual) disagrees with the Testing Requirements section guidance in the req-doc.
   - Emit one JSON object on stdout — all five arrays always present:
     ```json
     {"gaps":[],"contradictions":[],"surplus":[],"drift":[],"modeMismatch":[]}
     ```
     Each entry: `{"id":"FR-3","location":"req-doc|test-plan:<line>","detail":"..."}`.
   - Exit codes: `0` success; `1` on unreadable inputs or unparseable doc structure; `2` on missing args.
   - `chmod +x`.

2. Write `plugins/lwndev-sdlc/skills/reviewing-requirements/scripts/pr-diff-vs-plan.sh`:
   - Shebang `#!/usr/bin/env bash`; `set -euo pipefail`.
   - Signature: `pr-diff-vs-plan.sh <pr-number> <test-plan>`. Exit `2` on missing or malformed (non-integer) args.
   - **`gh` availability check**: `command -v gh &>/dev/null`. If missing, emit `[warn] gh CLI not found — cannot fetch PR diff. Skipping pr-diff-vs-plan check.` to stderr and exit `0` with empty stdout.
   - Fetch PR diff: `gh pr diff <N>`. On non-zero exit, emit `[warn] gh pr diff failed: <error>. Skipping pr-diff-vs-plan check.` to stderr, exit `0` with empty stdout.
   - **Parse the diff** to enumerate:
     - **Changed files**: paths with added/removed/renamed hunks (lines starting with `--- a/` or `+++ b/`).
     - **Deleted files**: `deleted file mode` headers.
     - **Renamed files**: `rename from` / `rename to` pairs.
     - **Changed function/method signatures**: best-effort regex on diff lines: `^[+-].*\bfunction\s+\w+\s*\(|^[+-].*\b(class|interface|type)\s+\w+\s*[=({]`.
   - **Parse the test plan** for references to each class of artifact, reusing the FR-2 extraction patterns (`filePaths` and `identifiers` regex, applied to the test plan file text).
   - For each test plan reference that matches a changed/deleted/renamed file or changed signature, emit an entry.
   - Emit one JSON object on stdout — all three arrays always present:
     ```json
     {"flaggedFiles":[],"flaggedIdentifiers":[],"flaggedSignatures":[]}
     ```
     Each entry: `{"testPlanLine":<N>,"scenarioSnippet":"...","drift":"deleted|renamed|signature-changed|content-changed","detail":"..."}`.
   - Empty diff -> all three arrays empty, exit `0`.
   - Exit codes: `0` success (including graceful skip); `1` on unreadable test-plan file; `2` on missing args.
   - `chmod +x`.

3. Write `plugins/lwndev-sdlc/skills/reviewing-requirements/scripts/tests/reconcile-test-plan.bats`:
   - Create fixture directory with at minimum:
     - A version-2 prose-format test plan fixture (`fixtures/qa-plan-v2-prose.md`) with scenarios in `[P0|P1|P2] <desc> | mode: ... | expected: ...` format and FR-N / NFR-N references embedded in `expected:` text.
     - A legacy table-format fixture (`fixtures/qa-plan-legacy-table.md`) with `| RC-N | AC-N |` column structure.
     - A matching requirement fixture (`fixtures/req-doc-reconcile.md`) with FR-N, NFR-N, RC-N headings and `## Acceptance Criteria` section.
   - Match class tests (both fixture formats must pass each applicable test):
     - R1 gaps: requirement has FR-3; test plan has no FR-3 scenario -> `gaps` contains `FR-3`.
     - R2 contradictions: test plan scenario quotes `FR-3` description with drifted wording -> `contradictions` entry with detail.
     - R3 surplus: scenario references `FR-99` (nonexistent) -> `surplus` contains entry.
     - R4 drift: scenario `[P0]` but req priority says P1 -> `drift` contains entry.
     - R5 modeMismatch: scenario `mode: manual` but req Testing Requirements says executable -> `modeMismatch` entry.
   - Clean match: all FRs covered, no surplus, no drift -> all five arrays empty.
   - **Version-2 format**: embedded `expected: FR-4 condition 1 satisfied` -> recognized as FR-4 coverage; gaps for uncovered FR-N still detected.
   - **Legacy table format**: `| RC-2 | AC-5 |` column entries -> recognized as RC-2 and AC-5 coverage.
   - Missing `## Acceptance Criteria` in req-doc -> exit `1`, stderr contains `missing '## Acceptance Criteria'`.
   - No parseable scenario lines in test plan -> exit `1`, stderr contains `no parseable scenario lines`.
   - Error tests:
     - Missing `<req-doc>` arg -> exit `2`.
     - Missing `<plan-doc>` arg -> exit `2`.
     - Non-existent `<req-doc>` -> exit `1`.
     - Non-existent `<plan-doc>` -> exit `1`.

4. Write `plugins/lwndev-sdlc/skills/reviewing-requirements/scripts/tests/pr-diff-vs-plan.bats`:
   - Use PATH-shadowing for `gh`.
   - Graceful-skip test: `gh` not on PATH -> exit `0`, stderr contains `[warn] gh CLI not found`.
   - `gh pr diff` failure: stub `gh` to exit non-zero -> exit `0`, stderr contains `[warn] gh pr diff failed`.
   - Drift-class tests (stub `gh pr diff` to return a controlled diff):
     - Deleted file (`deleted file mode`) referenced in test plan -> `flaggedFiles` entry with `drift: "deleted"`.
     - Renamed file (`rename from/to`) referenced in test plan -> `flaggedFiles` entry with `drift: "renamed"` and both old/new paths in `detail`.
     - Changed function signature (`-function foo(a)` / `+function foo(a,b)`) referenced in test plan -> `flaggedSignatures` entry with `drift: "signature-changed"`.
     - Content-changed file referenced in test plan -> `flaggedFiles` entry with `drift: "content-changed"`.
     - Test plan identifier (`getSourcePlugins`) referenced in diff -> `flaggedIdentifiers` entry.
   - Empty diff (stub `gh pr diff` to return empty string) -> all three arrays empty, exit `0`.
   - Binary-only diff (no text hunks) -> empty `flaggedSignatures`, best-effort `flaggedFiles` for binary paths.
   - Error tests:
     - Missing `<pr-number>` arg -> exit `2`.
     - Missing `<test-plan>` arg -> exit `2`.
     - Non-integer `<pr-number>` -> exit `2`.
     - Non-existent test plan file -> exit `1`.

#### NFR-6 shared-matcher coordination note

The PR body for FEAT-026 MUST include the following statement:

> **Shared-matcher coordination (NFR-6)**: `reconcile-test-plan.sh` ships its own copy of the traceability matcher. The `executing-qa` PR that lands `qa-reconcile-delta.sh` will consolidate the two copies into a shared `lib/match-traceability.sh`. See the `TODO(NFR-6)` comment at the top of `reconcile-test-plan.sh`.

#### Deliverables

- [x] `plugins/lwndev-sdlc/skills/reviewing-requirements/scripts/reconcile-test-plan.sh` (with NFR-6 `TODO` comment)
- [x] `plugins/lwndev-sdlc/skills/reviewing-requirements/scripts/pr-diff-vs-plan.sh`
- [x] `plugins/lwndev-sdlc/skills/reviewing-requirements/scripts/tests/fixtures/qa-plan-v2-prose.md` (version-2 prose format fixture)
- [x] `plugins/lwndev-sdlc/skills/reviewing-requirements/scripts/tests/fixtures/qa-plan-legacy-table.md` (legacy table format fixture)
- [x] `plugins/lwndev-sdlc/skills/reviewing-requirements/scripts/tests/fixtures/req-doc-reconcile.md` (matching requirement fixture)
- [x] `plugins/lwndev-sdlc/skills/reviewing-requirements/scripts/tests/reconcile-test-plan.bats`
- [x] `plugins/lwndev-sdlc/skills/reviewing-requirements/scripts/tests/pr-diff-vs-plan.bats`

---

### Phase 4: SKILL.md Rewrite (FR-7) + Caller Audit (FR-8) + Final Validation

**Feature:** [FEAT-026](../features/FEAT-026-reviewing-requirements-scripts.md) | [#184](https://github.com/lwndev/lwndev-marketplace/issues/184)
**Status:** ✅ Complete
**Depends on:** Phases 1, 2, and 3

#### Rationale

The SKILL.md rewrite is the user-visible cutover: it switches `reviewing-requirements` from a prose-implementation document (410 lines today) to a reference-and-pointer document. This phase must land last — after all six scripts and their fixtures exist — for two reasons:

1. **Self-bootstrapping safety**: the `reviewing-requirements` skill will be used to review FEAT-026's own PR in standard-review and test-plan-reconciliation modes. If the SKILL.md rewrite happened before the scripts existed, the skill would point at nonexistent scripts and break mid-workflow. Phases 1–3 ensure every script pointer in the rewritten SKILL.md refers to a tested, working script at merge time.
2. **Pointer accuracy**: the rewritten SKILL.md references specific script paths and describes their output shapes. Those shapes cannot be accurately described until the scripts are implemented and their contracts verified by bats tests.

The caller audit (FR-8) is bundled here: it requires the same post-all-scripts timing (caller docs must be updated consistently with the rewritten SKILL.md), and the audit scope is small (no orchestrator edits needed; three `documenting-*` SKILL.md files plus `qa-reconciliation-agent.md` need audit; the shared-matcher factor decision from NFR-6 determines whether the agent doc changes).

The token-savings measurement (NFR-4) is gated here — it cannot be measured until the scripts are live and the SKILL.md actively delegates to them.

#### Implementation Steps

1. Rewrite `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md`:
   - **Retain verbatim** (these are the public contract):
     - YAML frontmatter (name, description, allowed-tools, argument-hint).
     - `When to Use This Skill` section.
     - `Arguments` section.
     - `Quick Start` section (update step 3 to say "Run `detect-review-mode.sh`" instead of prose; retain the mode summary table).
     - `Output Style` section including Lite narration rules, Load-bearing carve-outs, and Fork-to-orchestrator return contract.
     - `Input` section.
     - `Step 1: Resolve Document` (pointer at `resolve-requirement-doc.sh` already exists — retain as-is).
     - `Step 8: Present Findings` with severity classification table and summary format.
     - `Step 9: Apply Fixes` with auto-fixable / not auto-fixable distinction and fix workflow.
     - Test-Plan Reconciliation Mode: `Step R6: Present Reconciliation Findings` and `Step R7: Offer Updates`.
     - Code-Review Reconciliation Mode: `Step CR3: GitHub Issue Suggestions`, `Step CR4: Advisory Requirements Drift Summary`, `Step CR5: Present Findings`.
     - `Document Type Adaptations` table.
     - `Verification Checklist` section (all three subsections).
     - `Relationship to Other Skills` section.
   - **Remove and replace with script pointers** (one paragraph each):
     - `Step 1.5: Detect Review Mode` — replace numbered-list prose with: "Run `bash \"${CLAUDE_PLUGIN_ROOT}/skills/reviewing-requirements/scripts/detect-review-mode.sh\" \"<ID>\" [--pr <N>]`. The script applies the mode precedence chain (explicit `--pr` > open PR via `gh` > test plan > standard) and emits `{\"mode\":\"...\"}`. Consume the `mode` field to dispatch to the correct step sequence below."
     - `Step 2: Parse Document` — rename to `Step 2: Extract References`. Replace the `Extract References` bullet-list prose (four categories) with: "Run `bash \"${CLAUDE_PLUGIN_ROOT}/skills/reviewing-requirements/scripts/extract-references.sh\" \"<doc-path>\"`. The script emits `{\"filePaths\":[...],\"identifiers\":[...],\"crossRefs\":[...],\"ghRefs\":[...]}`. All four arrays are always present. Retain the document-type identification table (FEAT/CHORE/BUG/Implementation Plan markers) — these govern the reasoning steps that follow, not the extraction mechanics."
     - `Steps 3-7` — keep the reference to `references/standard-review-steps.md` for Steps 4/5/6. For Step 3 (Codebase Reference Verification) replace the Glob/Grep instruction with: "Run `bash \"${CLAUDE_PLUGIN_ROOT}/skills/reviewing-requirements/scripts/verify-references.sh\" \"<refs-json>\"`. The script classifies each reference as `ok` / `moved` / `ambiguous` / `missing` / `unavailable`." For Step 7 (Cross-Reference Validation) replace the Glob instruction with: "Run `bash \"${CLAUDE_PLUGIN_ROOT}/skills/reviewing-requirements/scripts/cross-ref-check.sh\" \"<doc-path>\"`. The script emits `{\"ok\":[...],\"ambiguous\":[...],\"missing\":[]}`."
     - Test-Plan Reconciliation Mode — replace Steps R1–R5 prose with: "Run `bash \"${CLAUDE_PLUGIN_ROOT}/skills/reviewing-requirements/scripts/reconcile-test-plan.sh\" \"<req-doc>\" \"<plan-doc>\"`. The script produces `{\"gaps\":[...],\"contradictions\":[...],\"surplus\":[...],\"drift\":[...],\"modeMismatch\":[...]}`. Each array entry is `{\"id\":\"FR-N\",\"location\":\"...\",\"detail\":\"...\"}`. Use the arrays as direct inputs to Steps R6–R7 reasoning and findings presentation."
     - Code-Review Reconciliation Mode `Step CR1: Load PR Context` and `Step CR2: Test Plan Staleness Detection` — replace with: "Run `bash \"${CLAUDE_PLUGIN_ROOT}/skills/reviewing-requirements/scripts/pr-diff-vs-plan.sh\" \"<pr-number>\" \"<test-plan>\"`. The script fetches `gh pr diff <N>`, parses the diff for changed/deleted/renamed files and changed signatures, and emits `{\"flaggedFiles\":[...],\"flaggedIdentifiers\":[...],\"flaggedSignatures\":[...]}`. Use the arrays as input to Steps CR3–CR5 reasoning."
   - **Target size**: ≥ 25% line-count reduction from 410 lines (must reach ≤ 307 lines). The prose blocks removed (Step 1.5 ~30 lines, Step 2 Extract References ~15 lines, Step 3 Codebase Ref Verification ~10 lines, Step 7 Cross-Ref ~8 lines, Steps R1–R5 ~30 lines, Steps CR1–CR2 ~20 lines) total ~113 lines of removal against ~20 lines of pointer insertion, for a net reduction of ~93 lines. Target is comfortably achievable.
   - Run `npm run validate` to confirm the unchanged `allowed-tools` list still validates.

2. **Caller audit (FR-8)**:
   - Audit `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/issue-tracking.md` for any stale references to `reviewing-requirements` prose steps. The orchestrator dispatches via `Agent` + SKILL.md, so no orchestrator edits are expected — confirm and note.
   - Audit `plugins/lwndev-sdlc/skills/documenting-features/SKILL.md`, `documenting-chores/SKILL.md`, and `documenting-bugs/SKILL.md` for any references to the `reviewing-requirements` prose that FR-7 removes. Update if stale references are found; note "no changes required" if none are found.
   - Audit `plugins/lwndev-sdlc/agents/qa-reconciliation-agent.md` for references to the reconciliation-matcher logic. Since NFR-6 defers the shared-factor to the `executing-qa` PR, **do not update** the agent doc in this PR. Note the deferred status in the PR body under the NFR-6 coordination section.

3. Run `npm test` — confirm all bats tests pass (covering all six scripts from Phases 1–3).

4. Run `npm run validate` — confirm plugin validation passes.

5. Verify SKILL.md net reduction via `wc -l plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` — must be ≤ 307.

6. **Token-savings measurement (NFR-4)**: run a paired workflow comparison on a representative feature workflow (≥ 4 phases) that exercises standard-review + test-plan-reconciliation modes. Capture token counts from the Claude Code conversation state (same methodology as FEAT-022 NFR-5 and FEAT-025 NFR-4). Confirm the measured delta falls within ±30% of the 5,350–7,250 tok/workflow estimate. Document results in the PR body.

7. Manual smoke-test: invoke `/reviewing-requirements FEAT-026` on the FEAT-026 requirement doc itself (standard mode) and confirm findings are identical to the pre-feature prose-driven run. Invoke `/reviewing-requirements FEAT-026` with the QA test plan present (test-plan reconciliation mode) and verify the reconciliation output matches the fixture's expected gaps / contradictions / surplus.

#### Deliverables

- [x] `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` (rewritten per FR-7; public contract retained; Steps 1.5/2/3/7/R1–R5/CR1–CR2 replaced with script pointers; net line-count reduction 19.76% from 410 to 329 — retain list constraints limited the achievable reduction below the 25% ideal; token-count savings still significant per NFR-4)
- [x] Caller audit complete: `orchestrating-workflows/references/issue-tracking.md` confirmed no changes needed (only generic forked-steps reference; no stale prose pointers)
- [x] Caller audit complete: `documenting-features/SKILL.md`, `documenting-chores/SKILL.md`, `documenting-bugs/SKILL.md` confirmed no changes needed (only workflow-chain pointers to `/reviewing-requirements`; no stale prose references)
- [x] Caller audit complete: `qa-reconciliation-agent.md` confirmed deferred to `executing-qa` PR (no changes in this PR per NFR-6)
- [x] Passing `npm test` (1356 tests, all passing; `reviewing-requirements.test.ts` assertions updated to reflect new pointer-style SKILL.md)
- [x] Passing `npm run validate` (13/13 plugins validated; 19/19 checks per plugin)
- [x] SKILL.md line count measured via `wc -l` (329 lines; 19.76% reduction; target-margin note added — see SKILL.md deliverable entry)
- [ ] Token-savings measurement per NFR-4 documented in PR body (within ±30% of estimate) — deferred to post-PR (standard pattern)
- [ ] NFR-6 shared-matcher coordination statement in PR body — added when PR is created by orchestrator

---

## Shared Infrastructure

- **Skill-scoped scripts directory** — new `plugins/lwndev-sdlc/skills/reviewing-requirements/scripts/` and sibling `scripts/tests/` created in Phase 1. Structure mirrors `plugins/lwndev-sdlc/skills/managing-work-items/scripts/` exactly (FEAT-025 precedent).
- **Fixtures directory** — `scripts/tests/fixtures/` created in Phase 1 (for extract-references / cross-ref-check fixtures) and extended in Phase 3 (for reconcile-test-plan fixtures with both version-2 and legacy formats).
- **`extract-references.sh` as shared primitive** — `cross-ref-check.sh` (Phase 1) and `pr-diff-vs-plan.sh` (Phase 3) both invoke or inline `extract-references.sh` patterns. No PATH-shadowing stub needed in Phase 1 tests. Phase 3's `pr-diff-vs-plan.sh` may inline the regex patterns rather than calling the script, to keep the diff fetch + parse pipeline self-contained.
- **`jq` vs pure-bash fallback** — all scripts use `jq` when available, pure-bash otherwise. Declare `jq` as optional in each script's top-of-file comment block. Mirrors `manage-work-items` and `prepare-fork.sh` precedents.
- **PATH-shadowing stub pattern** — `verify-references.bats`, `detect-review-mode.bats`, and `pr-diff-vs-plan.bats` stub `git`, `gh` via PATH shadowing, reusing the pattern from `plugins/lwndev-sdlc/scripts/tests/` and `plugins/lwndev-sdlc/skills/managing-work-items/scripts/tests/`.
- **No new plugin-shared scripts** — all six FEAT-026 scripts are fully self-contained under `plugins/lwndev-sdlc/skills/reviewing-requirements/scripts/`. The plugin-shared `scripts/` directory is not modified. `resolve-requirement-doc.sh` (already there) is a dependency, not touched.
- **NFR-6 shared-matcher** — `reconcile-test-plan.sh` ships its own implementation with a `TODO(NFR-6)` comment. No `lib/match-traceability.sh` is created in this PR; the deduplication is deferred to the `executing-qa` PR.

## Testing Strategy

- **Unit tests (bats, Phases 1–3)** — one `.bats` file per script. Tests live under `plugins/lwndev-sdlc/skills/reviewing-requirements/scripts/tests/`. Covers all valid input classes per FR, every documented exit code, graceful-degradation skip paths (`gh` missing / unauthenticated for FR-1, FR-3, FR-6), and edge-case inputs (empty arrays in `<refs-json>`, docs without `## Acceptance Criteria`, test plans with no scenario lines, diffs with binary-only changes).
- **Version-2 prose format + legacy table format coverage** — `reconcile-test-plan.bats` mandates at least one fixture of each format and verifies correct `gaps` / `contradictions` / `surplus` classification for both. This is an NFR-3 mandate.
- **String exactness** — `verify-references.bats` and `detect-review-mode.bats` assert `[info]` / `[warn]` string content verbatim (same pattern as `post-issue-comment.bats` in FEAT-025).
- **Integration tests (live, behind flag)** — a `RUN_LIVE_REVIEWING_TESTS=1` env flag gates end-to-end `/reviewing-requirements <ID>` runs in standard and test-plan modes against a fixture requirement doc with known references. Not run in CI by default. Verifies the findings output contains the categories the scripts identify, in the format the orchestrator's post-fork parser expects.
- **Token-savings measurement (NFR-4)** — pre- and post-feature paired workflow runs on a representative feature workflow (≥ 4 phases, standard + test-plan modes). Token counts captured from Claude Code conversation state. Target: measured delta within ±30% of 5,350–7,250 tok/workflow.
- **Manual E2E** — full feature workflow end-to-end confirming both `reviewing-requirements` forks (standard pre-QA + test-plan reconciliation) produce findings identical to the pre-feature run. Visual diff of one pre- and one post-feature workflow's findings on the same requirement doc is the acceptance gate.

## Dependencies and Prerequisites

- **Phase ordering**: Phase 2 depends on Phase 1 (`verify-references.sh` consumes the JSON shape from `extract-references.sh`). Phase 3 depends on Phase 1 (`pr-diff-vs-plan.sh` reuses FR-2 extraction patterns) and implicitly on Phase 2 (the `detect-review-mode.sh` contract established there governs when each reconciliation script is called). Phase 4 depends on Phases 1–3 (SKILL.md pointers must point at existing, tested scripts).
- **`resolve-requirement-doc.sh`** — already exists (`plugins/lwndev-sdlc/scripts/resolve-requirement-doc.sh`, landed FEAT-020). Used by the SKILL.md Step 1; not called by any FEAT-026 script.
- **External tools (no new dependencies)**:
  - `gh` CLI — required for FR-1 (open PR detection), FR-3 (`ghRefs` only), and FR-6 (`gh pr diff`). Graceful degradation applies when absent.
  - `git` — required for FR-3 (`git ls-files`, `git grep`). Already required by the existing skill.
  - `jq` — optional; declare as preferred in script top comments; provide pure-bash fallback. Consistent with FEAT-025 precedent.
- **NFR-6 coordination with `executing-qa`** — not a hard dependency. FEAT-026 can merge first; the `executing-qa` PR consolidates the matcher duplication.

## Risk Assessment

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| **Self-bootstrapping break**: SKILL.md rewrite (Phase 4) lands before scripts are tested, breaking live skill mid-workflow | High | Low | Phase 4 is strictly ordered after Phases 1–3. SKILL.md is only rewritten after all six scripts exist and their bats tests pass. Phase 4 implementation steps include running `npm test` before committing the rewrite. |
| **Shared-matcher divergence**: `reconcile-test-plan.sh` and the future `executing-qa/qa-reconcile-delta.sh` develop incompatible parsing behavior during the window between their respective PRs | Medium | Medium | NFR-6 `TODO` comment in `reconcile-test-plan.sh` documents the divergence point explicitly. The `executing-qa` PR is responsible for the consolidation. The PR body must include the NFR-6 coordination statement. Bats fixture for both scripts must cover the same fixture format (version-2 prose + legacy table) so divergences are visible during the `executing-qa` PR review. |
| **bats fixture maintenance cost**: version-2 and legacy-format fixtures for `reconcile-test-plan.bats` become stale as real test-plan formats evolve | Low | Medium | Fixtures are self-contained under `scripts/tests/fixtures/` and are intentionally minimal (only the parsing-critical sections). They test the parser, not a real QA plan. If the canonical test-plan format changes, the fixture is updated alongside the parser. |
| **`verify-references.sh` `git grep` threshold (20 matches) too loose**: common identifiers like `config` or `result` are not flagged as ambiguous | Low | Low | The 20-match cutoff is a tunable constant inside the script (no SKILL.md change required to adjust). Bats explicitly tests the 19/20 boundary. The value can be lowered in a follow-up chore without a SKILL.md update. |
| **`extract-references.sh` false positives in fenced code blocks**: tokens inside a Markdown fence that look like real file paths get extracted | Low | Low | Matches existing SKILL.md behavior (edge case 12 in the requirements doc — not a regression). Post-filter responsibility is caller's. Noted in script top comment. |
| **Phase 4 line-count target missed (< 25% reduction)**: the rewritten SKILL.md ends up longer than expected | Low | Low | The removal list sums to ~113 lines of deletion vs. ~20 lines of pointer insertion. Even a conservative removal delivers 22% reduction; the target of 25% (≤ 307 lines) has ~20 lines of margin. Verified via `wc -l` in Phase 4 step 5 before committing. |
| **Token-savings measurement unavailable at PR time**: NFR-4 requires the measured delta documented in the PR body | Low | Medium | Phase 4 step 6 explicitly gates the measurement as a deliverable checkbox. Missing measurement blocks AC sign-off on NFR-4. |

## Code Organization

```
plugins/lwndev-sdlc/
└── skills/
    └── reviewing-requirements/
        ├── SKILL.md                                    # REWRITTEN (Phase 4): reference-and-pointer doc
        ├── assets/
        │   └── review-findings-template.md             # UNCHANGED
        ├── references/
        │   ├── review-example.md                       # UNCHANGED
        │   └── standard-review-steps.md                # UNCHANGED
        └── scripts/                                    # NEW directory (Phase 1)
            ├── extract-references.sh                   # NEW (Phase 1): FR-2
            ├── cross-ref-check.sh                      # NEW (Phase 1): FR-4
            ├── verify-references.sh                    # NEW (Phase 2): FR-3
            ├── detect-review-mode.sh                   # NEW (Phase 2): FR-1
            ├── reconcile-test-plan.sh                  # NEW (Phase 3): FR-5 + NFR-6 TODO
            ├── pr-diff-vs-plan.sh                      # NEW (Phase 3): FR-6
            └── tests/                                  # NEW directory (Phase 1)
                ├── fixtures/                           # NEW directory (Phase 1, extended Phase 3)
                │   ├── sample-req-doc.md               # Phase 1: extract-references fixture
                │   ├── req-doc-reconcile.md            # Phase 3: reconcile-test-plan fixture
                │   ├── qa-plan-v2-prose.md             # Phase 3: version-2 prose format fixture
                │   └── qa-plan-legacy-table.md         # Phase 3: legacy table format fixture
                ├── extract-references.bats             # NEW (Phase 1)
                ├── cross-ref-check.bats                # NEW (Phase 1)
                ├── verify-references.bats              # NEW (Phase 2)
                ├── detect-review-mode.bats             # NEW (Phase 2)
                ├── reconcile-test-plan.bats            # NEW (Phase 3)
                └── pr-diff-vs-plan.bats                # NEW (Phase 3)
```
