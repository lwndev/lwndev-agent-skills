# Feature Requirements: `managing-work-items` Full Scripting (Items 8.1–8.6)

## Overview
Collapse the `managing-work-items` skill's deterministic prose into six shell scripts so every inline invocation from the orchestrator becomes a single script call. Ships all six skill-scoped scripts under `plugins/lwndev-sdlc/skills/managing-work-items/scripts/` plus the corresponding SKILL.md updates that replace prose detection / rendering / link-generation / extraction with the scripts.

## Feature ID
`FEAT-025`

## GitHub Issue
[#183](https://github.com/lwndev/lwndev-marketplace/issues/183)

## Priority
Medium — ~2,200–2,800 tokens saved per workflow run. This skill has no LLM-reasoning component today (its SKILL.md is a reference document the orchestrator executes inline), so converting it to scripts is a clean mechanical win with no quality trade-off. Row 3 in the #179 top-10 savings table covers `post-issue-comment.sh` alone at 1,800–2,400 tok/workflow; the full item 8 set (8.1–8.6) aggregates to ~2,200–2,800 tok/workflow per the #179 per-skill catalogue.

## User Story
As the orchestrator invoking `managing-work-items` at workflow integration points (phase-start, phase-end, work-start, work-end, bug-start, bug-end, fetch, extract-ref, pr-link), I want each invocation to be a single deterministic script call so that ~2,200–2,800 tokens per workflow spent repeating gh/acli/MCP routing prose is eliminated, the inline invocation contract stays uniform across call sites, and graceful degradation (NFR-1) continues to govern every failure mode.

## Command Syntax

All scripts live under `${CLAUDE_PLUGIN_ROOT}/skills/managing-work-items/scripts/` and follow the plugin-shared conventions from #179 (shell-first, exit-code driven, stdout carries JSON or pure string, stderr for warnings/errors, bats-tested).

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/managing-work-items/scripts/backend-detect.sh" <issue-ref>
bash "${CLAUDE_PLUGIN_ROOT}/skills/managing-work-items/scripts/extract-issue-ref.sh" <requirements-doc>
bash "${CLAUDE_PLUGIN_ROOT}/skills/managing-work-items/scripts/pr-link.sh" <issue-ref>
bash "${CLAUDE_PLUGIN_ROOT}/skills/managing-work-items/scripts/render-issue-comment.sh" <backend> <type> <context-json>
bash "${CLAUDE_PLUGIN_ROOT}/skills/managing-work-items/scripts/post-issue-comment.sh" <issue-ref> <type> <context-json>
bash "${CLAUDE_PLUGIN_ROOT}/skills/managing-work-items/scripts/fetch-issue.sh" <issue-ref>
```

### Examples

```bash
# Detect backend from a reference
bash "${CLAUDE_PLUGIN_ROOT}/skills/managing-work-items/scripts/backend-detect.sh" "#183"
# stdout: {"backend":"github","issueNumber":183}

bash "${CLAUDE_PLUGIN_ROOT}/skills/managing-work-items/scripts/backend-detect.sh" "PROJ-123"
# stdout: {"backend":"jira","projectKey":"PROJ","issueNumber":123}

# Generate a PR-body auto-close fragment
bash "${CLAUDE_PLUGIN_ROOT}/skills/managing-work-items/scripts/pr-link.sh" "#183"
# stdout: Closes #183

# Post a phase-start comment (composite; handles backend detection + template render + post)
bash "${CLAUDE_PLUGIN_ROOT}/skills/managing-work-items/scripts/post-issue-comment.sh" "#183" phase-start \
  '{"phase":1,"name":"Core scripts","steps":["..."],"deliverables":["..."],"workItemId":"FEAT-025"}'
```

## Functional Requirements

### FR-1: `backend-detect.sh` — Issue-Reference Classifier
- Signature: `backend-detect.sh <issue-ref>`.
- Accept the issue reference as a single positional argument. Exit `2` on missing or empty arg.
- Apply the two detection regexes in order:
  1. `^#([0-9]+)$` → GitHub. Emit `{"backend":"github","issueNumber":<N>}`.
  2. `^([A-Z][A-Z0-9]*)-([0-9]+)$` → Jira. Emit `{"backend":"jira","projectKey":"<KEY>","issueNumber":<N>}`.
- When neither regex matches, emit `null` (literal, not a JSON `null` object — a stdout line containing just `null`) and exit `0`. An unmatched reference is **not** an error — it signals "no tracking possible for this reference" and the caller skips silently.
- Exit codes: `0` on any recognized or unrecognized reference (including the `null` case); `2` on missing arg.
- Replaces managing-work-items `SKILL.md` FR-1 (Backend Detection) prose entirely. The SKILL.md FR-1 section is rewritten as a one-paragraph pointer at this script.

### FR-2: `extract-issue-ref.sh` — Requirement-Document Extraction
- Signature: `extract-issue-ref.sh <requirements-doc>`.
- Read the requirement document at the supplied path. Locate the first heading matching any of `## GitHub Issue`, `## Issue`, or `## Issue Tracker` (case-sensitive, line-start).
- Within the content until the next `##`-level heading, scan for markdown-link patterns:
  - `[#N](URL)` → emit `#N`.
  - `[PROJ-NNN](URL)` (matching `^[A-Z][A-Z0-9]*-[0-9]+$`) → emit `PROJ-NNN` verbatim.
- Emit the first match to stdout (no trailing newline-only shape — a single-line reference). If the section is missing, empty, or contains no matching link, emit nothing and exit `0`. (Empty stdout + exit `0` is the "no reference found" contract; it is **not** an error — callers use absence to skip tracking.)
- Exit codes: `0` on any outcome (found or not-found); `1` if the file does not exist or is unreadable; `2` on missing arg.
- Replaces managing-work-items `SKILL.md` FR-7 (Issue Reference Extraction from Documents) prose.

### FR-3: `pr-link.sh` — PR-Body Auto-Close Fragment
- Signature: `pr-link.sh <issue-ref>`.
- Internally invoke `backend-detect.sh` (FR-1) to classify the reference.
- Emit the backend-appropriate fragment:
  - GitHub (`backend == "github"`): `Closes #N` followed by a single newline.
  - Jira (`backend == "jira"`): the raw issue key (e.g., `PROJ-123`) followed by a single newline. No `Closes` keyword — Jira auto-transitions from the branch name, not the PR body (per existing managing-work-items `SKILL.md` FR-6).
  - `null` (no recognized reference): empty stdout (no newline).
- Exit codes: `0` for all three cases (including the empty-output case — absence is not an error); `2` on missing arg.
- Must be deterministic: same input always produces identical output. No network calls, no filesystem reads beyond the argv and the `backend-detect.sh` subprocess invocation. The backend-detect subprocess is itself pure (no network, no file reads), so the overall function is pure in the functional-programming sense.
- Replaces managing-work-items `SKILL.md` FR-6 (PR Body Issue Link Generation).

### FR-4: `render-issue-comment.sh` — Template Rendering
- Signature: `render-issue-comment.sh <backend> <type> <context-json>`.
- `<backend>` is one of `github` or `jira` (matches the `backend-detect.sh` output field). Invalid backend → exit `2`.
- `<type>` is one of the six managing-work-items comment types: `phase-start`, `phase-completion`, `work-start`, `work-complete`, `bug-start`, `bug-complete`. Invalid type → exit `2`.
- `<context-json>` is a JSON string with the template variables. Invalid JSON → exit `2` with the parser error on stderr.
- Load the template body:
  - `backend == "github"` or `backend == "jira"` via `acli`-fallback path: load the matching markdown template block from `plugins/lwndev-sdlc/skills/managing-work-items/references/github-templates.md`.
  - `backend == "jira"` via Rovo MCP path: load the matching ADF-JSON template block from `plugins/lwndev-sdlc/skills/managing-work-items/references/jira-templates.md`.
  - The `jira` path's tier selection (Rovo MCP vs `acli`) is resolved inside `post-issue-comment.sh` (FR-5). `render-issue-comment.sh` exposes tier selection via a fourth optional argument `<tier>` (`rovo` or `acli`; default `acli` for the markdown path); callers that have already picked a tier pass it through. An explicit stdin pipe is **not** supported — the arg contract is tighter and easier to unit-test.
- Substitute template variables:
  - **Markdown templates**: replace `<PLACEHOLDER>` with the scalar value; expand list placeholders (`<DELIVERABLES>`, `<STEPS>`, `<CRITERIA>`, `<ROOT_CAUSES>`, etc.) as markdown bullet lists using `- ` prefixes.
  - **ADF JSON templates**: replace `{placeholder}` scalar values; generate ADF `listItem`/`bulletList` node trees for list variables. Output must be valid ADF JSON — malformed substitution → exit `1` with the validator error on stderr.
- Emit the fully-rendered body on stdout (markdown or ADF JSON per the backend/tier).
- Exit codes: `0` success; `1` on rendering error (template missing, malformed ADF substitution, unknown placeholder after substitution left in output); `2` on invalid args.
- Replaces managing-work-items `SKILL.md` FR-5 (Comment Type Routing / Rendering Process) prose.

### FR-5: `post-issue-comment.sh` — End-to-End Comment Flow (Composite)
- Signature: `post-issue-comment.sh <issue-ref> <type> <context-json>`.
- Composite script that replaces ~60 lines of orchestrator-adjacent prose per invocation. Sequence:
  1. Call `backend-detect.sh <issue-ref>` (FR-1). If output is `null`, log `[info] No issue reference provided, skipping issue operations.` to stderr and exit `0` silently. This is the "no-reference skip" path — not an error. The string matches the managing-work-items `SKILL.md` Detection Logic wording verbatim (NFR-1 zero-divergence requirement).
  2. Pre-flight the backend:
     - **GitHub**: verify `command -v gh` and `gh auth status` succeed. On failure emit the existing warning verbatim to stderr (copied verbatim from the managing-work-items `SKILL.md` Graceful Degradation table — backtick formatting and ASCII double-hyphens preserved so the grep-level zero-divergence requirement in NFR-1 holds): `[warn] GitHub CLI (\`gh\`) not found on PATH. Skipping GitHub issue operations.` or `[warn] GitHub CLI not authenticated -- run \`gh auth login\` to enable issue tracking.` Exit `0` (graceful-degradation skip).
     - **Jira**: pick the tier (Rovo MCP → `acli` → skip) following the existing `managing-work-items` `SKILL.md` "Tier Detection Logic" and "Jira-Specific Error Handling" tables. Fall-through `[warn]` lines are emitted verbatim. A Tier-3 skip is exit `0`.
  3. Call `render-issue-comment.sh <backend> <type> <context-json> [<tier>]` (FR-4). On exit `1` (render failure), emit `[warn] Failed to render <type> comment for <issue-ref>: <stderr>. Skipping.` to stderr and exit `0`.
  4. Post via the selected backend:
     - GitHub: `gh issue comment <N> --body "<rendered>"`.
     - Jira Tier 1 (Rovo MCP): `addCommentToJiraIssue(cloudId, issueIdOrKey, adf-json)`.
     - Jira Tier 2 (`acli`): `acli jira workitem comment-create --key <KEY> --body "<rendered-markdown>"`.
     On command failure, emit the command's stderr prefixed `[warn] <tier>: <command> failed: ...` and exit `0` (graceful degradation — **never** block workflow progression per NFR-1).
- Exit codes:
  - `0` on success, on the no-reference skip, on any graceful-degradation skip, on a render-failure skip, or on a backend-command-failure skip. (Issue operations are supplementary; non-zero exit would be a regression.)
  - `2` on malformed args (missing `<type>`, invalid JSON in `<context-json>`).
- Idempotency: comments are safe to retry (NFR-3 preserved from managing-work-items `SKILL.md`). A duplicate comment is acceptable — the caller does not need to track prior posts.
- Replaces managing-work-items `SKILL.md` end-to-end comment flow (the full Workflow section + its call-site prose in `orchestrating-workflows/references/issue-tracking.md`).

### FR-6: `fetch-issue.sh` — Pre-Fill Fetch
- Signature: `fetch-issue.sh <issue-ref>`.
- Invoke `backend-detect.sh` to classify. On `null`, emit `null` to stdout and exit `0` (consistent with FR-1 semantics).
- Pre-flight the backend exactly as FR-5 step 2 (same `[warn]` emission, same exit-`0`-on-skip contract).
- Fetch the issue:
  - GitHub: `gh issue view <N> --json title,body,labels,state,assignees`. Emit the JSON verbatim to stdout.
  - Jira Tier 1: `getJiraIssue(cloudId, issueIdOrKey)`. Emit a normalized JSON shape on stdout: `{"title":"...","body":"...","labels":[...],"state":"...","assignees":[...]}` (projected from the Jira fields so the caller does not need to know which backend produced the data).
  - Jira Tier 2: `acli jira workitem view --key <KEY>`. Parse the structured text output into the same normalized JSON shape.
- On fetch failure (issue not found, network error, auth failure, rate limit), emit the backend's existing graceful-degradation warning verbatim to stderr and exit `0` with empty stdout — the caller treats empty stdout as "no data, proceed without pre-fill" (matching the current skill's "log + skip" behavior).
- Exit codes: `0` in every non-malformed-arg case (success, no-reference, graceful-degradation skip); `2` on missing arg.
- Replaces the GitHub Fetch Operation sub-section and the Jira Fetch Operation sub-section of managing-work-items `SKILL.md`, and the `documenting-features` pre-fill delegation point (line 38: "Direct `gh` CLI usage for issue fetch is replaced by `managing-work-items`" — now delegated through `fetch-issue.sh`). `documenting-chores` and `documenting-bugs` do not currently delegate issue fetches through managing-work-items and remain unchanged.

### FR-7: SKILL.md Prose Replacement
- Rewrite `plugins/lwndev-sdlc/skills/managing-work-items/SKILL.md` to replace FR-1 (Backend Detection), FR-5 (Comment Type Routing rendering process), FR-6 (PR link generation), and FR-7 (Issue Reference Extraction) with one-paragraph pointers at the corresponding scripts. The rendered SKILL.md must retain:
  - The Arguments table (operation/issue-ref/--type/--context) — this remains the invocation contract for callers and is unchanged.
  - The Operations table — same four operations, each now pointing at its implementing script.
  - The Jira-Specific Error Handling and Graceful Degradation tables — the scripts emit the exact `[warn]` strings these tables document; the tables remain the source of truth for the exact phrasing.
  - The Output Style section (lite narration rules, load-bearing carve-outs, Inline execution note) — unchanged.
- Remove the following prose blocks (each now implemented by a FEAT-025 script):
  - "Detection Logic" numbered-list prose — now FR-1 (`backend-detect.sh`).
  - "Rendering Process" numbered-list prose — now FR-4 (`render-issue-comment.sh`).
  - "PR Body Issue Link Generation" table body — now FR-3 (`pr-link.sh`). The table header stays as a backend-reference summary.
  - "Extraction Logic" numbered-list prose — now FR-2 (`extract-issue-ref.sh`).
  - "Workflow" numbered-list prose — now the composition inside FR-5 (`post-issue-comment.sh`).
  - GitHub Backend "Fetch Operation" sub-section (inside the current SKILL.md FR-2 Backend) — now FR-6 (`fetch-issue.sh`). The `gh issue view` command signature stays as a reference example in the GitHub Backend section header.
  - Jira Backend "Jira Fetch Operation" sub-section (inside the current SKILL.md FR-3 Backend) — now FR-6. The Tier Detection Logic, Jira Comment Operation, and Jira-Specific Error Handling tables within Jira Backend are retained.
  - "Implementation Pattern" bash example block (lines 293–312 of the current SKILL.md) — replace with a one-line pointer at `post-issue-comment.sh`.
- Net SKILL.md size reduction target: ≥ 30% of current line count. The removal list above sums to ~95+ lines against the current 338-line file, landing above the 30% floor. The skill becomes a reference-and-pointer document; the scripts carry the implementation.

### FR-8: Caller Updates
- `orchestrating-workflows/references/issue-tracking.md` is updated so every example that shows an inline gh/acli/MCP invocation instead calls the corresponding script. The existing mechanism-failure log examples retain their exact `[warn]` strings (which now come from the scripts verbatim — no diverging source of truth).
- Line 36 of `orchestrating-workflows/references/issue-tracking.md` contains the pointer `managing-work-items/SKILL.md:287-306`; after this feature ships that block is replaced by a one-line pointer at `post-issue-comment.sh`, so the cross-reference is updated to point at `plugins/lwndev-sdlc/skills/managing-work-items/scripts/post-issue-comment.sh` instead.
- `documenting-features/SKILL.md` line 38 (the "Direct `gh` CLI usage for issue fetch is replaced by `managing-work-items`" note) is updated to mention that the delegation is now `fetch-issue.sh`. `documenting-chores/SKILL.md` and `documenting-bugs/SKILL.md` do not currently contain equivalent delegation notes (confirmed during FEAT-025 standard review); no updates required in those files.
- No other skills are modified in this PR — the scripts are a drop-in replacement for what managing-work-items already did inline.

## Output Format

Per-script output contracts are specified in each FR. Summarized for quick reference:

| Script | Stdout (success) | Stdout (skip/not-found) | Stderr |
|--------|-------------------|-------------------------|--------|
| `backend-detect.sh` | JSON object `{backend, issueNumber[, projectKey]}` | `null` | — |
| `extract-issue-ref.sh` | `#N` or `PROJ-NNN` | empty | — |
| `pr-link.sh` | `Closes #N\n` or `PROJ-NNN\n` | empty | — |
| `render-issue-comment.sh` | rendered markdown or ADF JSON | N/A | render errors |
| `post-issue-comment.sh` | empty (success is silent) | empty | `[info]` / `[warn]` lines |
| `fetch-issue.sh` | normalized JSON `{title, body, labels, state, assignees}` | `null` or empty | fetch warnings |

All `[info]` / `[warn]` lines are load-bearing per the managing-work-items Output Style section — they are emitted verbatim and the orchestrator's lite-narration rules do **not** strip them.

## Non-Functional Requirements

### NFR-1: Graceful Degradation Preserved
- Every script that touches external state (FR-5, FR-6) preserves the existing managing-work-items NFR-1 contract: failure logs and **skips** rather than halting. The only non-zero exits are `2` (caller arg errors) and, for FR-2, `1` (file-not-found on the requirement-doc arg — a caller error, not a runtime-environment failure).
- The `[warn]` / `[info]` strings emitted by the scripts must match the managing-work-items `SKILL.md` Error Handling / Graceful Degradation tables exactly. A grep-level diff between "strings the tables document" and "strings the scripts emit" must show zero divergence after this feature merges.

### NFR-2: Consistent Exit-Code Conventions
- All six scripts follow the plugin-shared convention (per #179 "Conventions" section):
  - `0` = success OR intentional skip (graceful degradation).
  - `1` = caller input problem that is not an arg-shape problem (file not found, malformed ADF post-substitution).
  - `2` = missing or malformed args.
- No script returns a custom code outside this set.

### NFR-3: Test Coverage
- Every script ships a bats (or equivalent) test fixture covering:
  - Valid inputs for each recognized case (GitHub reference, Jira reference, null reference, each of the six comment types).
  - Arg-validation failures (`2` exits).
  - Graceful-degradation paths (gh missing, gh unauthenticated, Jira tiers 1/2 failing through to tier 3).
  - Idempotent rendering: same context-json → identical stdout for rendering scripts.
- Test fixtures live under `plugins/lwndev-sdlc/skills/managing-work-items/scripts/tests/`. Precedent: `plugins/lwndev-sdlc/scripts/tests/prepare-fork.bats` (plugin-shared scripts layout) and `plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/tests/check-idempotent.bats` (skill-scoped scripts layout — matches this feature's structure).

### NFR-4: Token Savings Measurement
- Pre- and post-feature token counts on a representative feature workflow (≥ 4 phases, issue-tracked) are captured. The savings figure (~2,200–2,800 tok/workflow) is an estimate carried forward from #179; post-feature the target is to confirm the estimate falls within ±30% of the measured delta. Measurement uses the same methodology as FEAT-022's NFR-5 (tokens-consumed comparison across a paired workflow run before/after).

### NFR-5: Backwards-Compatible SKILL.md Arguments
- The rewritten managing-work-items `SKILL.md` retains the existing `<operation> <issue-ref> [--type <type>] [--context <json>]` invocation shape. Callers that invoke by operation name (`fetch`, `comment`, `pr-link`, `extract-ref`) continue to work — the orchestrator decides whether to invoke the script directly or route through the SKILL.md shape. The skill arguments are the public contract; the scripts are the implementation.

## Dependencies

- `gh` CLI — already required for GitHub operations; no new dependency.
- `acli` and Rovo MCP — already optional (Jira tiered fallback); no new dependency.
- `jq` — optional for JSON manipulation inside the scripts. If adopted, declare in each script's top comment block; otherwise use pure-bash string substitution (precedent: `prepare-fork.sh` uses jq; `slugify.sh` is pure bash).
- No new plugin-shared scripts required (#179 item 8 does not depend on 1–7 or 9–11). The scripts are fully self-contained under `plugins/lwndev-sdlc/skills/managing-work-items/scripts/`.

## Edge Cases

1. **Empty issue-ref arg**: FR-1 exits `2`. FR-3 / FR-5 / FR-6 propagate exit `2`. Callers supplying empty refs are arg-shape bugs.
2. **Whitespace-only issue-ref**: treat as empty → exit `2`. Do not silently trim and match.
3. **Reference format with trailing/leading whitespace** (`" #183 "`): FR-1 must trim before applying the regex; post-trim empty → exit `2`.
4. **Malformed Jira key** (`proj-123` lowercase, `PROJ_123` underscore): FR-1 emits `null`. Callers skip. (Matches existing managing-work-items behavior.)
5. **Reference to a closed GitHub issue**: `gh issue comment` posts successfully on closed issues (GitHub allows this). No special-case needed.
6. **Reference to a non-existent GitHub issue**: `gh issue comment` exits non-zero. FR-5 emits the existing `[warn]` and skips.
7. **Rate-limited GitHub**: same as #6. No retry — skip immediately per the managing-work-items `SKILL.md` Graceful Degradation table ("GitHub API rate limit reached. Skipping issue operation. Do not retry.").
8. **Jira cloudId not configured**: Tier 1 fails with the existing `Rovo MCP authorization failed` warning → fall through to Tier 2.
9. **`acli` installed but not logged in**: Tier 2 fails with the existing `acli authentication error` warning → skip.
10. **Requirement document without `## GitHub Issue` section**: FR-2 emits empty stdout + exit `0`. Caller interprets absence as "no tracking" and skips.
11. **Multiple matching links in the GitHub Issue section**: FR-2 emits the **first** match. Callers that need all refs are out of scope for this feature (they do not exist in the current codebase).
12. **Comment type / backend combination not in the template files**: FR-4 exits `1` with the template-missing error on stderr. FR-5 converts this to a skip (still exit `0`). This condition is a codebase bug, not a runtime failure — the caller sees a warning but the workflow continues.
13. **ADF JSON substitution produces invalid JSON** (e.g., unescaped quote in a user-supplied `name` field): FR-4 exits `1` with the validator error. FR-5 skips.
14. **`<context-json>` contains a variable the template does not reference**: warning on stderr from FR-4 (for observability), but rendering succeeds with the unreferenced variable ignored. Unknown-variable is not an error.
15. **`<context-json>` is missing a variable the template references**: FR-4 leaves the placeholder unsubstituted and exits `1`. Pre-substitution-complete validation catches this; the scripts do not emit half-rendered comments.

## Testing Requirements

### Unit Tests
- One bats file per script. Each covers:
  - All valid input classes (GitHub ref, Jira ref, null, each comment type, each backend).
  - Every documented exit code (`0` success, `0` skip variants, `1` where applicable, `2` arg errors).
  - Template rendering: markdown bullet-list expansion, ADF `listItem` generation, unknown-variable warning, missing-variable exit `1`.
  - `backend-detect.sh`: regex edge cases (leading/trailing whitespace, lowercase refs, underscore-separated, alphanumeric project keys `PROJ2-123` / `AB1-456`).
  - `extract-issue-ref.sh`: all three heading variants, first-match selection, absent-section behavior.

### Integration Tests
- End-to-end `post-issue-comment.sh` flow against a throwaway GitHub issue in a test repo (hidden behind a `RUN_LIVE_ISSUE_TESTS=1` env flag to avoid rate limits in CI). At minimum one `phase-start` and one `phase-completion` round-trip verifying the rendered comment lands with the expected body.
- `fetch-issue.sh` round-trip against the same throwaway issue, verifying the normalized JSON shape matches what `documenting-features` expects for pre-fill.

### Manual Testing
- Run a complete feature workflow (`/orchestrating-workflows #<issue>`) end-to-end and confirm every issue-comment integration point (phase-start × N, phase-end × N, work-start, work-complete) posts the same comment body as pre-feature, only faster. A visual diff of one pre- and one post-feature workflow's comment bodies on a live issue is the acceptance gate.

## Acceptance Criteria

- [x] `backend-detect.sh` implements FR-1; handles the two documented regexes; emits JSON or `null`; bats tests pass.
- [x] `extract-issue-ref.sh` implements FR-2; scans the three heading variants; emits the first match or empty; bats tests pass.
- [x] `pr-link.sh` implements FR-3; pure function; emits `Closes #N`, `PROJ-NNN`, or empty; bats tests pass.
- [x] `render-issue-comment.sh` implements FR-4; renders markdown and ADF paths; unknown-placeholder warning emitted; missing-variable exit `1`; bats tests pass.
- [x] `post-issue-comment.sh` implements FR-5; composite sequence (detect → render → post); graceful degradation on every external-command failure; all `[warn]` / `[info]` strings match the managing-work-items SKILL.md tables verbatim; bats tests pass.
- [x] `fetch-issue.sh` implements FR-6; normalized JSON shape across GitHub / Jira backends; graceful degradation preserved; bats tests pass.
- [x] `plugins/lwndev-sdlc/skills/managing-work-items/SKILL.md` is rewritten per FR-7; Arguments, Operations, Error Handling, Graceful Degradation, and Output Style sections retained; FR-1/5/6/7 bodies replaced with script pointers; net line-count reduction ≥ 30%.
- [x] `orchestrating-workflows/references/issue-tracking.md` examples are updated per FR-8 to invoke the scripts; mechanism-failure `[warn]` strings unchanged.
- [x] `documenting-features`, `documenting-chores`, `documenting-bugs` SKILL.md notes about `managing-work-items` delegation are updated per FR-8 (one-line pointers).
- [x] Integration test: a live feature workflow against a throwaway issue posts the same comment bodies as pre-feature (visual diff).
- [x] Token-savings measurement per NFR-4 confirms the estimate within ±30%.
- [x] `npm test` and `npm run validate` pass on the release branch.

## Completion

**Status:** `Complete`

**Completed:** 2026-04-23

**Pull Request:** [#225](https://github.com/lwndev/lwndev-marketplace/pull/225)
