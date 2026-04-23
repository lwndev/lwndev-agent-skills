# Feature Requirements: `reviewing-requirements` Scripts (Items 3.2–3.7)

## Overview
Collapse the deterministic prose inside `reviewing-requirements` into six skill-scoped shell scripts plus a minimal SKILL.md rewrite so every per-mode invocation (standard, test-plan reconciliation, code-review reconciliation) replaces its step-1.5 / step-2 / step-3 / step-7 / R1–R5 / CR1–CR2 prose with a single script call. The plugin-shared foundation script `resolve-requirement-doc.sh` (item 3.1) already landed with FEAT-020 (issue #180, closed) and is a dependency, not in scope here.

## Feature ID
`FEAT-026`

## GitHub Issue
[#184](https://github.com/lwndev/lwndev-marketplace/issues/184)

## Priority
Medium — ~5,350–7,250 tokens saved per workflow run. `reviewing-requirements` has the highest savings-per-workflow of any single skill after the orchestrator forks because it runs up to 3× per workflow (standard pre-QA, test-plan reconciliation, code-review reconciliation). Items 3.3 and 3.4 appear at ranks #7 and #4 respectively in the #179 top-10 savings table. The remaining prose (severity classification, gap analysis, inconsistency detection, auto-fix selection, CR3 draft comments, CR4 advisory drift narrative) carries the model-reasoning work and stays prose.

## User Story
As the orchestrator (or a user manually invoking `/reviewing-requirements`) executing a review in any of the three supported modes, I want the deterministic reference-extraction, reference-verification, mode-detection, cross-ref-check, test-plan-reconciliation matching, and PR-diff-vs-plan work to happen in a single script call so that ~5,350–7,250 tokens per workflow spent restating glob/grep/gh mechanics are eliminated, the mode-dispatch contract stays uniform across the three invocations, and the reasoning work the skill is actually good at (severity, gap analysis, inconsistency, auto-fix decisions, draft comments, drift narrative) stays in prose where it belongs.

## Command Syntax

All scripts live under `${CLAUDE_PLUGIN_ROOT}/skills/reviewing-requirements/scripts/` and follow the plugin-shared conventions from #179 (shell-first, exit-code driven, stdout carries JSON or pure string, stderr for warnings/errors, bats-tested).

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/reviewing-requirements/scripts/detect-review-mode.sh" <ID> [--pr <N>]
bash "${CLAUDE_PLUGIN_ROOT}/skills/reviewing-requirements/scripts/extract-references.sh" <doc-path>
bash "${CLAUDE_PLUGIN_ROOT}/skills/reviewing-requirements/scripts/verify-references.sh" <refs-json>
bash "${CLAUDE_PLUGIN_ROOT}/skills/reviewing-requirements/scripts/cross-ref-check.sh" <doc-path>
bash "${CLAUDE_PLUGIN_ROOT}/skills/reviewing-requirements/scripts/reconcile-test-plan.sh" <req-doc> <plan-doc>
bash "${CLAUDE_PLUGIN_ROOT}/skills/reviewing-requirements/scripts/pr-diff-vs-plan.sh" <pr-number> <test-plan>
```

### Examples

```bash
# Detect review mode for an ID, with optional explicit PR number
bash "${CLAUDE_PLUGIN_ROOT}/skills/reviewing-requirements/scripts/detect-review-mode.sh" FEAT-026
# stdout: {"mode":"standard"}

bash "${CLAUDE_PLUGIN_ROOT}/skills/reviewing-requirements/scripts/detect-review-mode.sh" FEAT-026 --pr 231
# stdout: {"mode":"code-review","prNumber":231}

# Extract every reference-shaped token from a requirement document
bash "${CLAUDE_PLUGIN_ROOT}/skills/reviewing-requirements/scripts/extract-references.sh" \
  requirements/features/FEAT-026-reviewing-requirements-scripts.md
# stdout: {"filePaths":[...],"identifiers":[...],"crossRefs":[...],"ghRefs":[...]}

# Verify those references against the codebase + GitHub
bash "${CLAUDE_PLUGIN_ROOT}/skills/reviewing-requirements/scripts/verify-references.sh" "$(<refs.json)"
# stdout: {"ok":[...],"moved":[...],"ambiguous":[...],"missing":[...]}

# Reconcile requirement doc vs test plan (bidirectional)
bash "${CLAUDE_PLUGIN_ROOT}/skills/reviewing-requirements/scripts/reconcile-test-plan.sh" \
  requirements/features/FEAT-026-reviewing-requirements-scripts.md \
  qa/test-plans/QA-plan-FEAT-026.md
# stdout: {"gaps":[...],"contradictions":[...],"surplus":[...]}
```

## Functional Requirements

### FR-1: `detect-review-mode.sh` — Mode Precedence Resolver
- Signature: `detect-review-mode.sh <ID> [--pr <N>]`.
- Accept the workflow ID (`FEAT-NNN`, `CHORE-NNN`, `BUG-NNN`) as the first positional argument. Exit `2` on missing or unrecognized-shape ID.
- Apply the mode-precedence chain below, preserving `reviewing-requirements/SKILL.md` Step 1.5's ordering (PR takes precedence over test plan). The script matches SKILL.md Step 1.5 for precedence and for the `gh pr list` branch-glob pattern; it intentionally diverges on `--pr` validation — SKILL.md documents a `gh pr view` existence check + non-numeric rejection with fallback to branch detection; this script accepts the flag as an explicit user override and does not probe `gh` for existence. Non-numeric values are treated as arg-shape errors instead of silently falling through (see the non-numeric clause in the exit-code section):
  1. `--pr <N>` flag present → emit `{"mode":"code-review","prNumber":<N>}`. Do not probe `gh` for existence; the flag is the explicit user override and takes precedence over any other signal.
  2. Open PR found via `gh pr list --head "<prefix>/<ID>-*" --json number,state --jq '[.[] | select(.state=="OPEN")][0].number'`, where `<prefix>` is `feat` / `chore` / `fix` selected from the ID's prefix (`FEAT-` → `feat`, `CHORE-` → `chore`, `BUG-` → `fix`) — matching the three glob patterns `reviewing-requirements/SKILL.md` Step 1.5 documents today (`feat/{ID}-*`, `chore/{ID}-*`, `fix/{ID}-*`). Emit `{"mode":"code-review","prNumber":<N>}`. Note: `build-branch-name.sh` is NOT invoked here — it requires a `<summary>` argument the detector does not have. The detector derives only the branch *prefix* (`<type>/<ID>-`) and uses a `--head` glob, following the convention `build-branch-name.sh` defines rather than calling the script itself.
  3. Test plan exists at `qa/test-plans/QA-plan-<ID>.md` → emit `{"mode":"test-plan","testPlanPath":"qa/test-plans/QA-plan-<ID>.md"}`.
  4. Fallback → emit `{"mode":"standard"}`.
- Exit codes: `0` on any recognized outcome (including the `standard` fallback); `1` on a `gh`-lookup failure that is *not* a graceful skip (e.g., malformed `gh` response JSON — should not happen with `--json`, but the guard is documented); `2` on missing / malformed args. A non-numeric `--pr` value (e.g., `--pr abc`) is a malformed arg → exit `2` with `[warn] detect-review-mode: --pr value must be numeric` to stderr.
- When `gh` is missing or unauthenticated, step 2 is silently skipped (the `gh pr list` call) and the detector falls through to step 3 (test plan check) and then `standard`. No `[warn]` line — this is the existing Step 1.5 behavior. The orchestrator's mechanism-failure warnings for `gh` live in `managing-work-items`, not here.
- Replaces `reviewing-requirements/SKILL.md` Step 1.5 (Detect Review Mode) prose — ~300 tokens × 3 modes = ~900 tokens/workflow.

### FR-2: `extract-references.sh` — Reference Token Extraction
- Signature: `extract-references.sh <doc-path>`.
- Read the requirement document at the supplied path. Exit `1` if the file does not exist or is unreadable; exit `2` on missing arg.
- Scan for four reference classes simultaneously, each emitted as a JSON array on the final stdout object:
  - **`filePaths`**: tokens matching `[A-Za-z0-9_./-]+\.(md|ts|tsx|js|jsx|json|sh|bats|ya?ml|toml)` that appear either inside backticks or as bare paths. De-duplicate preserving first-occurrence order.
  - **`identifiers`**: backticked tokens matching `^[a-zA-Z_$][a-zA-Z0-9_$]*$` that plausibly name a function, class, or exported symbol. Skip common false positives (`true`, `false`, `null`, single-letter identifiers, language keywords). De-duplicate.
  - **`crossRefs`**: every `FEAT-[0-9]+`, `CHORE-[0-9]+`, `BUG-[0-9]+` token (bare or linked). De-duplicate.
  - **`ghRefs`**: every `#[0-9]+` token and every full-URL `https://github.com/<owner>/<repo>/(issues|pull)/[0-9]+` link. Normalize to `#<N>` when the URL owner/repo matches the repo's `origin` (best-effort — fall back to emitting the full URL). De-duplicate.
- Emit one JSON object on stdout:
  ```json
  {"filePaths":[],"identifiers":[],"crossRefs":[],"ghRefs":[]}
  ```
  All four arrays are always present (possibly empty) — consumers rely on the shape, not presence.
- Exit codes: `0` success (including all-empty output); `1` on file-not-found / unreadable; `2` on missing arg.
- Replaces `reviewing-requirements/SKILL.md` Step 2 "Extract References" prose — ~400–600 tokens × 3 modes = ~1,200–1,800 tokens/workflow.

### FR-3: `verify-references.sh` — Reference Verification Loop
- Signature: `verify-references.sh <refs-json>`.
- Accept a single positional arg that is **either** a path to a file containing the JSON **or** the JSON itself passed as a string. This dual shape mirrors how the orchestrator and skill compose the upstream `extract-references.sh` output — sometimes it's piped through a file, sometimes passed inline. **Dispatch heuristic**: if the arg's first non-whitespace character is `{` or `[`, treat it as a literal JSON string; otherwise treat it as a file path and `Read` the contents (falling back to treating the arg as a literal JSON string if the file does not exist). The heuristic is unambiguous because JSON emitted by FR-2 always begins with `{` while any plausible file path does not. Exit `2` on missing arg; exit `1` on unparseable JSON.
- For each of the four categories in the input JSON, run the verification strategy documented in `reviewing-requirements/SKILL.md` Step 3:
  - **`filePaths`**: exact-path `test -e`. On miss, run a basename-fallback glob under the repo root (`git ls-files | grep -F <basename>`). Classify as `ok` (exact match), `moved` (basename match at a different path — include both paths in the output entry), `ambiguous` (multiple basename matches), or `missing`.
  - **`identifiers`**: `git grep -n <identifier>` across tracked files. Classify as `ok` (≥ 1 match, < 20 matches), `ambiguous` (≥ 20 matches — the identifier is too generic to be a useful reference), or `missing` (0 matches). The 20-match threshold is a new implementation decision introduced by this feature — the existing SKILL.md prose classifies as `Ambiguous` on "multiple locations" without specifying a numeric cutoff. Codifying 20 here avoids flagging every usage of common tokens like `config` or `result` as errors while preserving the SKILL.md's intent. If implementation experience shows this threshold is too loose or too strict, it is tunable inside this script without SKILL.md changes.
  - **`crossRefs`** (FEAT-/CHORE-/BUG-): `ls requirements/{features,chores,bugs}/<REF>-*.md`. Classify as `ok` (exactly one match), `ambiguous` (multiple), or `missing` (zero).
  - **`ghRefs`**: `gh issue view <N> --json number,state` per reference. When `gh` is missing, unauthenticated, or the per-call invocation fails with a non-404 error, classify each affected reference as `unavailable` and emit a single `[info] verify-references: gh unavailable; <N> ghRefs marked unavailable.` line to stderr (one emission per invocation, regardless of how many refs were affected). This matches the Output Format table's Stderr column. Classify individual refs as `ok` (issue exists regardless of state), `missing` (404), or `unavailable` (the graceful-skip case).
- Emit one JSON object on stdout:
  ```json
  {"ok":[...],"moved":[...],"ambiguous":[...],"missing":[...],"unavailable":[...]}
  ```
  Each entry is an object of shape `{"category":"filePaths","ref":"...","detail":"..."}` so the caller can surface the category + ref + (for moved/ambiguous) the new or competing paths.
- Exit codes: `0` success (any non-empty or empty classification); `1` on malformed `<refs-json>`; `2` on missing arg. Graceful-degradation skips (gh missing / unauthenticated) are exit `0`.
- Replaces `reviewing-requirements/SKILL.md` Step 3 (Verification Loop) prose — ~500–800 tokens × 3 modes = ~1,500–2,400 tokens/workflow. This is the #4 entry in the #179 top-10 table.

### FR-4: `cross-ref-check.sh` — Cross-Reference Subset
- Signature: `cross-ref-check.sh <doc-path>`.
- A focused subset of FR-2 + FR-3 for callers that only need `FEAT-`/`CHORE-`/`BUG-` cross-reference verification (Step 7 of the SKILL.md) without the full four-category extraction + verification round-trip.
- Internally invoke `extract-references.sh` (FR-2) to obtain the `crossRefs` array, then run only the cross-ref portion of `verify-references.sh` (FR-3).
- Emit one JSON object on stdout with only the four verification classes restricted to cross-refs:
  ```json
  {"ok":[...],"ambiguous":[...],"missing":[...]}
  ```
  (`moved` and `unavailable` do not apply to cross-refs — they live under `requirements/` and have no `gh`-fetch component.)
- Exit codes: `0` success; `1` on file-not-found / unreadable `<doc-path>`; `2` on missing arg.
- Replaces `reviewing-requirements/SKILL.md` Step 7 cross-ref-only code path — ~150 tokens × 3 modes = ~450 tokens/workflow. Lower savings than FR-2 + FR-3, but the script is a narrow one-liner so the cost of shipping it is low, and callers who would otherwise re-run the full extract + verify pipeline for a crossRefs-only check benefit disproportionately.

### FR-5: `reconcile-test-plan.sh` — Test-Plan Reconciliation Matcher
- Signature: `reconcile-test-plan.sh <req-doc> <plan-doc>`.
- Accept two positional args: the requirement-document path and the test-plan-document path. Exit `2` on either missing; exit `1` on either file-not-found / unreadable.
- Parse traceability IDs from both documents:
  - **Requirement doc**: collect FR-N, NFR-N, RC-N (for bug docs), and every entry inside the `## Acceptance Criteria` section.
  - **Test plan**: collect every scenario line (`[P0|P1|P2] <desc> | mode: ... | expected: ...`) and extract any `FR-N` / `NFR-N` / `RC-N` / `AC-N` trailing-tag references inside the scenario body.
- Run the bidirectional match documented in `reviewing-requirements/SKILL.md` Steps R1–R5:
  - **R1 (`gaps`)**: requirement-side IDs with no corresponding test-plan scenario.
  - **R2 (`contradictions`)**: test-plan scenarios referencing a requirement ID whose semantics in the requirement doc have shifted since the test plan was drafted (detected as a mismatch between the quoted phrase in the scenario and the matching FR/NFR/RC body text — the script surfaces the mismatch; the model decides if it's a real contradiction).
  - **R3 (`surplus`)**: test-plan scenarios with no corresponding requirement-side ID.
  - **R4 (`drift`)**: scenarios whose trailing priority (`[P0|P1|P2]`) disagrees with the requirement's priority field.
  - **R5 (`mode-mismatch`)**: scenarios whose `mode:` field (executable, exploratory, manual) disagrees with the requirement-doc Testing Requirements section guidance.
- Emit one JSON object on stdout:
  ```json
  {"gaps":[],"contradictions":[],"surplus":[],"drift":[],"modeMismatch":[]}
  ```
  Each entry is `{"id":"FR-3","location":"req-doc|test-plan:<line>","detail":"..."}`.
- Share matcher logic with `executing-qa`'s upcoming `qa-reconcile-delta.sh` (#184 explicitly calls this out; #179 item 3.6 + item 7.4 flag it as a single shared implementation). The shared matcher is implemented once and the two scripts are thin callers — either by factoring a `lib/match-traceability.sh` sourced by both, or by having one script call the other. The decision between those two shapes is made during implementation based on which composes more cleanly with existing `executing-qa` scripts; the public contract of FR-5 is unchanged either way.
- **Version-2 test-plan format compatibility**: all current test plans under `qa/test-plans/` use the version-2 prose format in which FR-N / NFR-N / RC-N references often appear embedded inside the scenario's `expected:` text (e.g., `expected: FR-4 condition 1 satisfied`) rather than as formal trailing tags. The matcher MUST detect these embedded references in addition to formal trailing tags so bidirectional traceability holds on version-2 plans. The parser's extraction regex for IDs operates on the full scenario line (everything after the `[P0|P1|P2]` priority tag), not just a trailing-tag slot. A table-format plan (legacy, still seen on some older bug docs) is detected by the presence of `| RC-` / `| AC-` column headers and parsed column-wise. NFR-3 MUST include at least one fixture of each format (version-2 prose + legacy table) in the bats coverage.
- Exit codes: `0` success (any match / no match); `1` on unreadable input files or unparseable document structure (missing `## Acceptance Criteria` heading, no scenario lines matching the canonical format); `2` on missing args.
- Replaces `reviewing-requirements/SKILL.md` Steps R1–R5 (Test-Plan Reconciliation Mode) prose — ~800–1,200 tokens × 1 invocation (test-plan mode only).

### FR-6: `pr-diff-vs-plan.sh` — PR Diff vs Test-Plan Drift Detector
- Signature: `pr-diff-vs-plan.sh <pr-number> <test-plan>`.
- Accept two positional args: the PR number (integer) and the test-plan path. Exit `2` on missing or malformed args.
- Fetch the PR diff: `gh pr diff <N>`. On `gh` missing, emit `[warn] gh CLI not found — cannot fetch PR diff. Skipping pr-diff-vs-plan check.` to stderr and exit `0` with empty stdout (graceful degradation, consistent with the orchestrator's Step 1.5 degradation path).
- Parse the diff to enumerate:
  - **Changed files**: paths with added/removed/renamed hunks.
  - **Deleted files**: paths with a `deleted file mode` header.
  - **Renamed files**: paths appearing in `rename from` / `rename to` pairs.
  - **Changed function / method signatures**: best-effort regex scan for `^[+-].*\bfunction\s+\w+\s*\(|^[+-].*\b(class|interface|type)\s+\w+\s*[=({]`.
- Parse the test plan for references to each of the above classes of artifact (file paths and identifier tokens, reusing the FR-2 extraction patterns).
- Emit one JSON object on stdout:
  ```json
  {"flaggedFiles":[...],"flaggedIdentifiers":[...],"flaggedSignatures":[...]}
  ```
  Each entry is `{"testPlanLine":N,"scenarioSnippet":"...","drift":"deleted|renamed|signature-changed|content-changed","detail":"..."}`.
- Exit codes: `0` success (including the graceful-skip); `1` on unreadable test-plan file; `2` on missing args.
- **Post-FEAT-017 note**: the orchestrator no longer auto-invokes code-review reconciliation mode — FEAT-017 removed it from all three chain step-sequence tables. Code-review mode (and therefore `pr-diff-vs-plan.sh`) remains reachable via the manual `/reviewing-requirements {ID} --pr {prNumber}` invocation, which is the contract FR-1 preserves. The "1× per workflow" savings estimate in #184 therefore applies to manual invocations; automated workflows do not hit this script unless the user explicitly requests the mode.
- Replaces `reviewing-requirements/SKILL.md` Steps CR1–CR2 (Code-Review Reconciliation Mode) prose — ~500 tokens × 1 invocation (manual code-review mode only).

### FR-7: SKILL.md Prose Replacement
- Rewrite `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` to replace the mechanical prose in Step 1.5, Step 2, Step 3, Step 7, Steps R1–R5, and Steps CR1–CR2 with one-paragraph pointers at the corresponding scripts. The rewritten SKILL.md must retain:
  - The top-level `When to Use`, `Arguments`, `Quick Start`, `Output Style`, `Input`, and `Relationship to Other Skills` sections — these are the skill contract and are unchanged.
  - The mode summary inside the `Detect Review Mode` section (name of each mode, its trigger, its typical flow) — the script emits the mode; the SKILL.md explains what each mode means to the reader.
  - The `Present Findings` (Step 8), `Apply Fixes` (Step 9), and the per-step reasoning prose that stays prose per #179 ("Stays prose"): severity classification, gap analysis, inconsistency detection, auto-fix selection, CR3 draft comments, CR4 advisory drift narrative.
  - The `Document Type Adaptations` and `Verification Checklist` sections.
- Remove the following prose blocks (each now implemented by a FEAT-026 script):
  - "Step 1.5 Mode Precedence" numbered-list prose — now FR-1 (`detect-review-mode.sh`).
  - "Step 2 Extract References" bullet-list prose (the four-category extraction rules) — now FR-2 (`extract-references.sh`).
  - "Step 3 Verification Loop" prose (classify every reference as Ok / Moved / Ambiguous / Missing) — now FR-3 (`verify-references.sh`).
  - "Step 7 Cross-Reference Check" numbered-list prose — now FR-4 (`cross-ref-check.sh`).
  - "Steps R1–R5" reconciliation-matcher prose inside the Test-Plan Reconciliation Mode section — now FR-5 (`reconcile-test-plan.sh`).
  - "Steps CR1–CR2" PR-diff-vs-plan prose inside the Code-Review Reconciliation Mode section — now FR-6 (`pr-diff-vs-plan.sh`).
- Net SKILL.md size reduction target: ≥ 25% of current line count. The skill becomes a mode-dispatch + judgment-authoring document; the scripts carry the deterministic work.

### FR-8: Caller Updates
- The orchestrator's `reviewing-requirements` fork invocations are unchanged — the orchestrator dispatches via `Agent` + SKILL.md prose, which now points at the scripts internally. No orchestrator edits required for FR-1 through FR-6.
- `qa-reconciliation-agent.md` in `plugins/lwndev-sdlc/agents/` already references the reconciliation-matcher logic; FEAT-026 does not change the agent's contract. If the shared matcher from FR-5 is factored into a `lib/` script, the agent's reference prose is updated to point at that shared library (coordinated with the `executing-qa` `qa-reconcile-delta.sh` work — see "Dependencies").
- No other skills or agents are modified in this PR — the scripts are a drop-in replacement for what `reviewing-requirements` already did inline.

## Output Format

Per-script output contracts are specified in each FR. Summarized for quick reference:

| Script | Stdout (success) | Stdout (skip/not-found) | Stderr |
|--------|-------------------|-------------------------|--------|
| `detect-review-mode.sh` | JSON `{mode, prNumber?, testPlanPath?}` | N/A (always a mode) | — |
| `extract-references.sh` | JSON `{filePaths, identifiers, crossRefs, ghRefs}` | same shape with empty arrays | — |
| `verify-references.sh` | JSON `{ok, moved, ambiguous, missing, unavailable}` | same shape with empty arrays | gh unavailable `[info]` line |
| `cross-ref-check.sh` | JSON `{ok, ambiguous, missing}` | same shape with empty arrays | — |
| `reconcile-test-plan.sh` | JSON `{gaps, contradictions, surplus, drift, modeMismatch}` | same shape with empty arrays | — |
| `pr-diff-vs-plan.sh` | JSON `{flaggedFiles, flaggedIdentifiers, flaggedSignatures}` | empty stdout (graceful skip) | `[warn]` on graceful skip |

The `[info]` / `[warn]` lines are load-bearing structured logs and must not be stripped by the orchestrator's lite-narration rules.

## Non-Functional Requirements

### NFR-1: Graceful Degradation Preserved
- Three scripts touch `gh`: `detect-review-mode.sh` (FR-1, open-PR detection), `verify-references.sh` (FR-3, `ghRefs` category only), and `pr-diff-vs-plan.sh` (FR-6, `gh pr diff`). All three follow the existing SKILL.md contract: `gh` missing or unauthenticated falls through to a sensible default — standard mode for FR-1, empty output with `[warn]` for FR-6, and `unavailable` classification (rather than `missing`) for the `ghRefs` in FR-3. None blocks the workflow on `gh` failure.
- The `unavailable` classification in FR-3 preserves the existing SKILL.md Step 3 distinction between "we couldn't check" and "we checked and it's gone", so the orchestrator's findings Decision Flow still sees the right severity signal.

### NFR-2: Consistent Exit-Code Conventions
All six scripts follow the plugin-shared convention (per #179 "Conventions" section and the precedent set by FEAT-020 / FEAT-021 / FEAT-022 / FEAT-025):
- `0` = success OR intentional skip (graceful degradation).
- `1` = caller input problem that is not arg-shape (file not found, malformed JSON input, unparseable document structure).
- `2` = missing or malformed args.

No script returns a custom code outside this set.

### NFR-3: Test Coverage
- Every script ships a bats test fixture under `plugins/lwndev-sdlc/skills/reviewing-requirements/scripts/tests/` covering:
  - Valid inputs for each recognized case (every mode in FR-1; every reference category in FR-2/FR-3; every match class in FR-5; every drift class in FR-6).
  - Arg-validation failures (`2` exits) and file-not-found failures (`1` exits).
  - Graceful-degradation paths: `gh` missing / unauthenticated for FR-1, FR-3, FR-6.
  - Edge-case inputs: docs with no `## Acceptance Criteria`, test plans with no scenario lines, diffs with binary-only changes, empty arrays in `<refs-json>` for FR-3.
  - **Test-plan format coverage for `reconcile-test-plan.sh` (FR-5)**: at least one version-2 prose-format test-plan fixture (FR-N / NFR-N / RC-N references embedded in `expected:` prose) AND at least one legacy table-format fixture (explicit `| RC-N | AC-N |` column entries). Both formats must produce correct `gaps` / `contradictions` / `surplus` classifications.
- Test layout follows the existing precedent: `plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/tests/check-idempotent.bats` (skill-scoped scripts) and `plugins/lwndev-sdlc/scripts/tests/prepare-fork.bats` (plugin-shared scripts).

### NFR-4: Token Savings Measurement
- Pre- and post-feature token counts on a representative feature workflow (≥ 4 phases) and on a standalone test-plan reconciliation run are captured. The savings figure (~5,350–7,250 tok/workflow for a full feature run that exercises standard + test-plan modes; up to +500 more for a manual code-review invocation) is an estimate carried forward from #179. Post-feature the target is to confirm the estimate falls within ±30% of the measured delta. Methodology: paired workflow runs before/after the feature lands, token counts pulled from the Claude Code conversation state (same methodology as FEAT-022 NFR-5 and FEAT-025 NFR-4).

### NFR-5: Backwards-Compatible Skill Arguments
- The `reviewing-requirements` skill's public invocation shape (`/reviewing-requirements <ID> [--pr N]`) is unchanged. Only `--pr` is a public flag today; mode selection is otherwise automatic per Step 1.5 detection (see FR-1). Callers — orchestrator Agent forks, users invoking `/reviewing-requirements` manually, or test harnesses — continue to work. The SKILL.md is the public contract; the scripts are the implementation.
- The findings summary line the orchestrator's post-fork parser expects (`Found **N errors**, **N warnings**, **N info**`) is unchanged. Scripts do not emit this line — the SKILL.md's prose still composes it from the script outputs, and the fork-to-orchestrator return contract is preserved.

### NFR-6: Shared Matcher Coordination
- FR-5's test-plan-reconciliation matcher shares logic with `executing-qa`'s upcoming `qa-reconcile-delta.sh` (#179 item 7.4). The two scripts land in either order, but the shared implementation (either a `lib/match-traceability.sh` sourced by both, or one script invoking the other) must exist before the second of the two merges. The PR that lands second reconciles the duplication; the PR that lands first ships its own copy of the matcher with a `TODO(FEAT-026 / FEAT-XXX): factor shared matcher` comment pointing at this NFR.

## Dependencies

- `resolve-requirement-doc.sh` (plugin-shared) — already landed via FEAT-020 (#180, closed). Not in scope for FEAT-026. Used by the SKILL.md's Step 1 (Resolve Document) but not directly by any of the scripts in this feature.
- `gh` CLI — already required; no new dependency. Used by FR-1, FR-3 (`ghRefs` only), and FR-6.
- `git` — already required; no new dependency. Used by FR-3 (`git ls-files`, `git grep`).
- `jq` — optional for JSON manipulation inside the scripts. Precedent: `prepare-fork.sh` uses `jq`; `slugify.sh` is pure bash. FR-2 / FR-3 / FR-5 / FR-6 will lean on `jq` for output assembly; declare it in each script's top comment block.
- Coordination with `executing-qa` shared matcher (NFR-6 above). Not a hard dependency on an unshipped script — FEAT-026 can land first with a copy; the `executing-qa` work consolidates.

## Edge Cases

1. **Empty `<ID>` arg**: FR-1 exits `2`. FR-4 does not take an ID; FR-3 / FR-5 / FR-6 take file paths and exit `2` on missing path.
2. **Malformed `<ID>`** (e.g., `FEAT-` with no digits, `feat-026` lowercase): FR-1 exits `2`. The ID shape is the public contract; callers supplying malformed IDs are arg bugs.
3. **`<doc-path>` points at a non-requirement document** (e.g., a random markdown file): FR-2 emits whatever it finds; no heuristic check that the file is actually a requirement doc. FR-4 and FR-5 similarly trust the caller. This matches the existing skill's behavior (the skill assumes the orchestrator hands it a well-formed requirement doc).
4. **Requirement doc without `## Acceptance Criteria`**: FR-5 exits `1` with an error on stderr — the matcher cannot reconcile without at least one acceptance-criteria section. The SKILL.md-level review still surfaces this via its gap-analysis prose.
5. **Test plan with no scenario lines matching `[P0|P1|P2]`**: FR-5 exits `1`. A test plan with zero parseable scenarios is a malformed plan.
6. **`<refs-json>` passed as a file path that does not exist**: FR-3 attempts to read the file, fails, then treats the arg as a literal JSON string. If *that* also fails to parse, exit `1` with the parser error. If the string parses but has the wrong shape (missing one of the four expected arrays), treat missing arrays as empty — the shape is tolerant forward, strict backward.
7. **`gh pr list --head <branch>` returns an empty array**: FR-1 falls through to the next precedence step (test plan check, then `standard` mode). No error.
7a. **`gh pr list` returns a non-empty array but the first element lacks a `number` field** (malformed `gh` response — should not happen with `--json number,state` but the guard is documented): FR-1 emits `[warn] detect-review-mode: gh response missing 'number' field; falling through.` to stderr and continues to the next precedence step.
8. **`gh pr diff <N>` succeeds but returns an empty diff** (the PR has no changes — unlikely but possible): FR-6 emits the empty-arrays shape and exits `0`. No flagging.
9. **`<pr-number>` refers to a closed / merged PR**: `gh pr diff` still succeeds. FR-6 runs its analysis against the closed PR's diff. Callers decide if that's meaningful.
10. **Test plan referencing a file that has been renamed (not deleted) in the PR diff**: FR-6 flags it under `flaggedFiles` with `drift: "renamed"` and includes both the old and new paths in `detail`. The model decides whether the test plan needs updating.
11. **Identifier reference that appears 20+ times in the repo** (e.g., `config`): FR-3 classifies as `ambiguous`. The SKILL.md's severity prose decides whether to surface the ambiguity as an error, warning, or info.
12. **Requirement doc with Markdown code fences containing reference-shaped tokens** (e.g., a `FEAT-999` inside a fenced code example): FR-2 extracts them same as any other token — the extractor does not distinguish fenced vs inline context. Callers that need to exclude fenced content must post-filter. (Existing skill behavior — not a regression.)
13. **Test plan with scenarios that reference a requirement ID using a non-canonical format** (e.g., `FR_3` underscore, `FR3` no-hyphen): FR-5 does not match these. Canonical format (`FR-3`, `NFR-3`, `RC-3`, `AC-3`) is required. The SKILL.md's existing stop-hook-level validation already enforces this, so drift here would be a pre-existing skill bug, not a FEAT-026 regression.
14. **PR diff containing only binary-file changes** (e.g., a screenshot): FR-6 emits empty `flaggedSignatures` and does the best-effort file-path match for `flaggedFiles`. Identifiers and signatures do not apply to binary diffs.

## Testing Requirements

### Unit Tests
- One bats file per script. Each covers:
  - All valid input classes enumerated in the script's FR.
  - Every documented exit code (`0` success, `0` skip variants, `1` where applicable, `2` arg errors).
  - `extract-references.sh`: each of the four reference categories individually; de-duplication; fenced-vs-inline tokens.
  - `verify-references.sh`: `ok` / `moved` / `ambiguous` / `missing` / `unavailable` classifications for each category.
  - `detect-review-mode.sh`: each of the four precedence branches.
  - `reconcile-test-plan.sh`: each of the five match classes (`gaps`, `contradictions`, `surplus`, `drift`, `modeMismatch`).
  - `pr-diff-vs-plan.sh`: each of the four drift classes (`deleted`, `renamed`, `signature-changed`, `content-changed`); the graceful-skip path.

### Integration Tests
- End-to-end `/reviewing-requirements <ID>` invocation in standard mode against a fixture requirement doc with known file-path / identifier / cross-ref / gh-ref references. Verify the findings output surfaces the categories the scripts identify, in the same format the orchestrator's post-fork parser expects.
- End-to-end `/reviewing-requirements <ID>` invocation in test-plan mode against a fixture (requirement doc + test plan). Verify the reconciliation output matches the fixture's expected gaps / contradictions / surplus.
- Token-count measurement per NFR-4 on a representative workflow.

### Manual Testing
- Run a full feature workflow end-to-end (`/orchestrating-workflows #<issue>`) and confirm every `reviewing-requirements` fork (standard pre-QA + test-plan reconciliation) produces findings identical to the pre-feature run. A visual diff of one pre- and one post-feature workflow's findings on the same requirement doc is the acceptance gate.
- Manually invoke `/reviewing-requirements <ID> --pr <N>` on a live PR to exercise FR-6's code-review reconciliation path; confirm the drift output matches expectations on a diff with at least one renamed file and one changed function signature.

## Acceptance Criteria

- [ ] `detect-review-mode.sh` implements FR-1; handles the four-step precedence chain; emits JSON with `mode` and optional fields; bats tests pass.
- [ ] `extract-references.sh` implements FR-2; emits the four-array shape with de-duplication and first-occurrence ordering; bats tests pass.
- [ ] `verify-references.sh` implements FR-3; classifies each reference as `ok` / `moved` / `ambiguous` / `missing` / `unavailable`; preserves graceful degradation on `gh` failure; bats tests pass.
- [ ] `cross-ref-check.sh` implements FR-4; composes FR-2 + FR-3 over cross-refs only; bats tests pass.
- [ ] `reconcile-test-plan.sh` implements FR-5; produces `gaps` / `contradictions` / `surplus` / `drift` / `modeMismatch`; shares matcher logic with the `executing-qa` counterpart per NFR-6; bats tests pass.
- [ ] `pr-diff-vs-plan.sh` implements FR-6; enumerates file / identifier / signature drift; preserves graceful degradation on `gh` missing; bats tests pass.
- [ ] FR-8 (Caller Updates) is satisfied: no changes to orchestrator fork-invocation shape; if the shared-matcher factor from NFR-6 lands in this PR, `plugins/lwndev-sdlc/agents/qa-reconciliation-agent.md` is updated to point at the shared library; all three `documenting-*` skill files and the orchestrator's `issue-tracking.md` are audited for stale references and updated if needed.
- [ ] `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` is rewritten per FR-7; public contract (When to Use, Arguments, Quick Start, Output Style, Input, Relationship to Other Skills) retained; Steps 1.5 / 2 / 3 / 7 / R1–R5 / CR1–CR2 bodies replaced with script pointers; net line-count reduction ≥ 25%.
- [ ] No changes to orchestrator fork-invocation shape or findings-summary-line format (NFR-5 preserved).
- [ ] Integration test: a live feature workflow against a fixture produces findings identical to pre-feature (visual diff).
- [ ] Token-savings measurement per NFR-4 confirms the estimate within ±30%.
- [ ] Shared-matcher coordination plan with `executing-qa` per NFR-6 is documented in the PR body (either a commitment to land the shared `lib/` factor in this PR, or a `TODO` pointing at NFR-6 and the reconciling PR).
- [ ] `npm test` and `npm run validate` pass on the release branch.
