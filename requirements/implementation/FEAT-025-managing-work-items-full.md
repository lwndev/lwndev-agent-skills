# Implementation Plan: `managing-work-items` Full Scripting (FEAT-025)

## Overview

Collapse the `managing-work-items` skill's deterministic prose into six shell scripts so every inline invocation from the orchestrator becomes a single script call. The work ships all six skill-scoped scripts under `plugins/lwndev-sdlc/skills/managing-work-items/scripts/`, bats fixtures for every script under `scripts/tests/`, and a SKILL.md rewrite that replaces the implementation prose with one-paragraph pointers at the scripts. Two caller files are updated to reflect the new script-delegation model.

The plan sequences the work as four phases following the natural dependency layers in the feature. Phase 1 delivers the three pure, no-network scripts (backend-detect, extract-issue-ref, pr-link) together with their bats fixtures -- these are fully testable in isolation. Phase 2 delivers the template renderer (render-issue-comment), which depends only on the Layer-A scripts and the existing template reference files. Phase 3 delivers the two composite scripts (post-issue-comment, fetch-issue), which depend on both Layer A and Layer B. Phase 4 collapses the SKILL.md prose and updates the two caller files.

Every script ships with its bats fixture in the same phase -- tests are never deferred.

## Features Summary

| Feature ID | GitHub Issue | Feature Document | Priority | Complexity | Status |
|------------|--------------|------------------|----------|------------|--------|
| FEAT-025 | [#183](https://github.com/lwndev/lwndev-marketplace/issues/183) | [FEAT-025-managing-work-items-full.md](../features/FEAT-025-managing-work-items-full.md) | Medium | Medium | Pending |

## Recommended Build Sequence

### Phase 1: Pure Layer-A Scripts -- `backend-detect.sh`, `extract-issue-ref.sh`, `pr-link.sh` (FR-1, FR-2, FR-3)

**Feature:** [FEAT-025](../features/FEAT-025-managing-work-items-full.md) | [#183](https://github.com/lwndev/lwndev-marketplace/issues/183)
**Status:** ✅ Complete

#### Rationale

These three scripts have no external dependencies (no network, no filesystem beyond `extract-issue-ref.sh`'s input doc, no Jira or GitHub API). They are pure in the functional-programming sense: same input, same output, deterministic. Building them first establishes the foundational detection and generation contracts that every subsequent script depends on. `pr-link.sh` depends on `backend-detect.sh`, and both `render-issue-comment.sh` (Phase 2) and the composite scripts (Phase 3) depend on the same detection output. Landing this layer in isolation keeps the diff tight around "pure string matching and extraction" with no risk of external-command failures confounding test results. The bats fixtures for these three scripts are also the simplest in the feature -- PATH-shadowing is not required since there are no subcommand calls to stub (except `pr-link.sh`'s subprocess invocation of `backend-detect.sh`, which is a real script-to-script call and does not require stubbing once Phase 1 is complete).

#### Implementation Steps

1. Create the new directory `plugins/lwndev-sdlc/skills/managing-work-items/scripts/` and a sibling `scripts/tests/` subdirectory for bats fixtures.

2. Write `plugins/lwndev-sdlc/skills/managing-work-items/scripts/backend-detect.sh`:
   - Shebang `#!/usr/bin/env bash`; `set -euo pipefail`.
   - Accept a single positional arg `<issue-ref>`. On missing or empty arg, exit `2` with `[error] usage: backend-detect.sh <issue-ref>` on stderr.
   - Trim leading/trailing whitespace from the arg before applying regexes. Post-trim empty -> exit `2` (edge case 2/3 from the requirements doc).
   - Apply regex 1 (`^#([0-9]+)$`) -> emit `{"backend":"github","issueNumber":<N>}`, exit `0`.
   - Apply regex 2 (`^([A-Z][A-Z0-9]*)-([0-9]+)$`) -> emit `{"backend":"jira","projectKey":"<KEY>","issueNumber":<N>}`, exit `0`. The `[A-Z0-9]*` suffix in the character class covers alphanumeric project keys (`PROJ2-123`, `AB1-456`).
   - No regex match -> emit the literal string `null` on stdout, exit `0`. This is not an error.
   - `chmod +x`.

3. Write `plugins/lwndev-sdlc/skills/managing-work-items/scripts/extract-issue-ref.sh`:
   - Shebang `#!/usr/bin/env bash`; `set -euo pipefail`.
   - Accept a single positional arg `<requirements-doc>`. On missing arg, exit `2`. If the file does not exist or is unreadable, exit `1` with `[error] extract-issue-ref: file not found: <path>` on stderr.
   - Scan the file line-by-line for a heading matching one of `## GitHub Issue`, `## Issue`, or `## Issue Tracker` (exact case, line-start match via `^## (GitHub Issue|Issue|Issue Tracker)$`).
   - Within the content between that heading and the next `##`-level heading (or EOF), scan for markdown-link patterns:
     - `[#N](URL)` -> emit `#N`, exit `0`.
     - `[PROJ-NNN](URL)` where PROJ-NNN matches `^[A-Z][A-Z0-9]*-[0-9]+$` -> emit `PROJ-NNN`, exit `0`.
   - Emit the first match only (edge case 11 from requirements doc).
   - If the section is missing, empty, or contains no matching link, emit nothing and exit `0`. Empty stdout + exit `0` is the "no reference found" contract.
   - `chmod +x`.

4. Write `plugins/lwndev-sdlc/skills/managing-work-items/scripts/pr-link.sh`:
   - Shebang `#!/usr/bin/env bash`; `set -euo pipefail`.
   - Accept a single positional arg `<issue-ref>`. On missing arg, exit `2`.
   - Invoke `backend-detect.sh <issue-ref>` (sibling script in the same directory). Capture its stdout.
   - If stdout is `null` -> emit empty stdout (no newline), exit `0`.
   - If `backend == "github"` -> emit `Closes #N` followed by a single newline, exit `0`.
   - If `backend == "jira"` -> emit the raw issue key (e.g., `PROJ-123`) followed by a single newline, exit `0`. No `Closes` keyword per the requirements doc FR-3 rationale.
   - Use `jq -r` to parse backend-detect output when jq is available; fall back to pure-bash string parsing when it is not (matching the `branch-id-parse.sh` precedent).
   - `chmod +x`.

5. Write `plugins/lwndev-sdlc/skills/managing-work-items/scripts/tests/backend-detect.bats`:
   - GitHub ref happy path: `#183` -> exit `0`, stdout contains `"backend":"github"` and `"issueNumber":183`.
   - Jira ref happy path: `PROJ-123` -> exit `0`, stdout contains `"backend":"jira"`, `"projectKey":"PROJ"`, `"issueNumber":123`.
   - Alphanumeric project key: `PROJ2-456` -> exit `0`, stdout contains `"projectKey":"PROJ2"`.
   - Short alphanumeric key: `AB1-789` -> exit `0`, stdout contains `"projectKey":"AB1"`.
   - No-match: `foo` -> exit `0`, stdout is exactly `null`.
   - No-match: `#abc` -> exit `0`, stdout is `null`.
   - No-match: `proj-123` (lowercase) -> exit `0`, stdout is `null` (edge case 4).
   - No-match: `PROJ_123` (underscore separator) -> exit `0`, stdout is `null` (edge case 4).
   - Missing arg -> exit `2`.
   - Empty arg -> exit `2` (edge case 1).
   - Whitespace-only arg -> exit `2` (edge case 2).
   - Leading/trailing whitespace with valid ref (` #183 `) -> trim -> match -> exit `0` (edge case 3).

6. Write `plugins/lwndev-sdlc/skills/managing-work-items/scripts/tests/extract-issue-ref.bats`:
   - Section heading `## GitHub Issue` with `[#119](URL)` -> emit `#119`, exit `0`.
   - Section heading `## Issue` -> emit reference, exit `0`.
   - Section heading `## Issue Tracker` -> emit reference, exit `0`.
   - Jira reference `[PROJ-123](URL)` in section -> emit `PROJ-123`, exit `0`.
   - Multiple links in section -> emit first match only (edge case 11).
   - Section heading present but empty content -> empty stdout, exit `0`.
   - No matching section in doc -> empty stdout, exit `0` (edge case 10).
   - Missing arg -> exit `2`.
   - File does not exist -> exit `1`.

7. Write `plugins/lwndev-sdlc/skills/managing-work-items/scripts/tests/pr-link.bats`:
   - GitHub ref `#183` -> stdout `Closes #183\n`, exit `0`.
   - Jira ref `PROJ-123` -> stdout `PROJ-123\n`, exit `0`.
   - Unrecognized ref `foo` (backend-detect emits `null`) -> empty stdout, exit `0`.
   - Missing arg -> exit `2`.
   - Idempotency: two calls with same input produce identical stdout.

#### Deliverables

- [x] `plugins/lwndev-sdlc/skills/managing-work-items/scripts/backend-detect.sh`
- [x] `plugins/lwndev-sdlc/skills/managing-work-items/scripts/extract-issue-ref.sh`
- [x] `plugins/lwndev-sdlc/skills/managing-work-items/scripts/pr-link.sh`
- [x] `plugins/lwndev-sdlc/skills/managing-work-items/scripts/tests/backend-detect.bats`
- [x] `plugins/lwndev-sdlc/skills/managing-work-items/scripts/tests/extract-issue-ref.bats`
- [x] `plugins/lwndev-sdlc/skills/managing-work-items/scripts/tests/pr-link.bats`

---

### Phase 2: Template Renderer -- `render-issue-comment.sh` (FR-4)

**Feature:** [FEAT-025](../features/FEAT-025-managing-work-items-full.md) | [#183](https://github.com/lwndev/lwndev-marketplace/issues/183)
**Status:** ✅ Complete

#### Rationale

`render-issue-comment.sh` is the Layer-B script -- it depends on the Layer-A `backend-detect.sh` output shape (specifically the `backend` field) but adds the template-loading and variable-substitution logic that Phase 1 scripts do not need. Isolating the renderer in its own phase keeps the review focused on "template loading, variable substitution, markdown bullet expansion, ADF JSON generation" without mixing in the network and auth complexity that arrives in Phase 3. The renderer is also the script whose bats fixture is most complex (six comment types x two backend paths x list-expansion + missing-variable cases), so giving it a dedicated phase ensures the test surface is complete before the composite scripts depend on it. The renderer is exercised by `post-issue-comment.sh` (Phase 3) only after this phase's tests pass.

#### Implementation Steps

1. Write `plugins/lwndev-sdlc/skills/managing-work-items/scripts/render-issue-comment.sh`:
   - Shebang `#!/usr/bin/env bash`; `set -euo pipefail`.
   - Signature: `render-issue-comment.sh <backend> <type> <context-json> [<tier>]`.
   - Validate `<backend>`: must be `github` or `jira`; otherwise exit `2` with `[error] render-issue-comment: invalid backend: <value>` on stderr.
   - Validate `<type>`: must be one of the six types (`phase-start`, `phase-completion`, `work-start`, `work-complete`, `bug-start`, `bug-complete`); otherwise exit `2` with `[error] render-issue-comment: invalid type: <value>`.
   - Validate `<context-json>`: parse with `jq` (or pure-bash fallback); on parse failure exit `2` with the parser error on stderr.
   - Optional fourth arg `<tier>`: accepted values `rovo` or `acli`; default `acli` when absent.
   - Template loading:
     - `backend == "github"` OR (`backend == "jira"` AND `tier == "acli"`): load the markdown template block matching `<type>` from `${CLAUDE_PLUGIN_ROOT}/skills/managing-work-items/references/github-templates.md`.
     - `backend == "jira"` AND `tier == "rovo"`: load the ADF JSON template block matching `<type>` from `${CLAUDE_PLUGIN_ROOT}/skills/managing-work-items/references/jira-templates.md`.
     - If the template block for `<type>` is missing from the file, exit `1` with `[error] render-issue-comment: template not found for type '<type>' in <file>` on stderr (edge case 12).
   - Variable substitution for markdown templates:
     - Replace `<PLACEHOLDER>` tokens with scalar values from `<context-json>`.
     - Expand list placeholders (`<DELIVERABLES>`, `<STEPS>`, `<CRITERIA>`, `<ROOT_CAUSES>`, `<VERIFICATION_RESULTS>`, `<ROOT_CAUSE_RESOLUTIONS>`) by iterating the corresponding JSON array and emitting one `- <item>` line per element.
     - Unknown variable in `<context-json>` (one not referenced by any placeholder in the template): emit `[warn] render-issue-comment: unused context variable: <key>` on stderr; rendering continues (edge case 14).
     - Missing variable (placeholder present in template but key absent from `<context-json>`): leave placeholder unsubstituted; after full substitution scan for remaining `<[A-Z_]+>` tokens; if any found, exit `1` with `[error] render-issue-comment: unresolved placeholder(s): <tokens> in rendered output` on stderr. No partial output emitted (edge case 15).
   - Variable substitution for ADF JSON templates:
     - Replace `{placeholder}` scalar values; generate ADF `listItem`/`bulletList` node trees for list variables.
     - After substitution, validate the JSON is well-formed (pipe through `jq .` or equivalent); on failure exit `1` with the validator error on stderr (edge case 13).
   - Emit the fully-rendered body on stdout, exit `0`.
   - `chmod +x`.

2. Write `plugins/lwndev-sdlc/skills/managing-work-items/scripts/tests/render-issue-comment.bats`:
   - GitHub backend, `phase-start` type, valid context JSON -> exit `0`, stdout is non-empty rendered markdown.
   - All six comment types with GitHub backend -> exit `0` for each.
   - Jira backend, `acli` tier, `phase-start` -> exit `0`, markdown output (uses github-templates.md path).
   - Jira backend, `rovo` tier, `phase-start` -> exit `0`, ADF JSON output.
   - Markdown list expansion: context with `"steps":["a","b","c"]` -> stdout contains `- a`, `- b`, `- c` lines.
   - ADF list expansion: `rovo` tier with list variable -> stdout contains `bulletList` and `listItem` nodes.
   - Unknown context variable -> exit `0`, stderr contains `[warn] render-issue-comment: unused context variable:`.
   - Missing required variable -> exit `1`, stderr contains `unresolved placeholder`.
   - Malformed JSON in `<context-json>` -> exit `2`.
   - Invalid backend -> exit `2`.
   - Invalid type -> exit `2`.
   - Missing backend arg -> exit `2`.
   - Template file missing for type (use an invalid type that passes validation but has no template block) -> exit `1`.
   - Idempotency: same context-json -> identical stdout for the same backend+type combination.
   - ADF malformed substitution (unescaped quote injected via context value) -> exit `1`, stderr contains validator error.

#### Deliverables

- [x] `plugins/lwndev-sdlc/skills/managing-work-items/scripts/render-issue-comment.sh`
- [x] `plugins/lwndev-sdlc/skills/managing-work-items/scripts/tests/render-issue-comment.bats`

---

### Phase 3: Composite Scripts -- `post-issue-comment.sh` + `fetch-issue.sh` (FR-5, FR-6)

**Feature:** [FEAT-025](../features/FEAT-025-managing-work-items-full.md) | [#183](https://github.com/lwndev/lwndev-marketplace/issues/183)
**Status:** ✅ Complete

#### Rationale

These two scripts are the composite Layer-C scripts that depend on all of Layer A and, in the case of `post-issue-comment.sh`, on the Layer-B renderer as well. They are also the two scripts that interact with external systems (GitHub CLI, Jira Rovo MCP, acli) and therefore need the most careful handling of graceful degradation, `[warn]` string exactness, and the no-block-workflow invariant. Grouping them together in one phase is appropriate: both scripts follow the same detect -> preflight -> execute pattern, both use the same `[warn]` table from the existing `SKILL.md`, and both have the same "exit `0` on every skip path" contract. The pair shares a testing approach (PATH-shadowing stubs for `gh`, stubs for MCP tools) and fixture infrastructure that benefits from being developed together. Splitting them across phases would not improve testability and would introduce a window where `post-issue-comment.sh` exists without `fetch-issue.sh`, which would make the Phase 4 SKILL.md rewrite incomplete.

#### Implementation Steps

1. Write `plugins/lwndev-sdlc/skills/managing-work-items/scripts/post-issue-comment.sh`:
   - Shebang `#!/usr/bin/env bash`; `set -euo pipefail`.
   - Signature: `post-issue-comment.sh <issue-ref> <type> <context-json>`. On missing `<type>` or `<context-json>` args, exit `2`. On malformed JSON in `<context-json>`, exit `2` with parser error on stderr.
   - Step 1 -- Backend detection: invoke `backend-detect.sh <issue-ref>`. Capture stdout. If output is `null`, emit `[info] No issue reference provided, skipping issue operations.` to stderr and exit `0` (verbatim match to the managing-work-items SKILL.md Detection Logic wording per NFR-1).
   - Step 2 -- GitHub pre-flight (when `backend == "github"`):
     - `command -v gh &>/dev/null` fails -> emit `[warn] GitHub CLI (\`gh\`) not found on PATH. Skipping GitHub issue operations.` to stderr (backtick formatting preserved verbatim per NFR-1), exit `0`.
     - `gh auth status &>/dev/null 2>&1` fails -> emit `[warn] GitHub CLI not authenticated -- run \`gh auth login\` to enable issue tracking.` to stderr (verbatim per NFR-1), exit `0`.
   - Step 2 -- Jira pre-flight (when `backend == "jira"`): pick tier using the existing Tier Detection Logic from `SKILL.md` (Rovo MCP responsive -> Tier 1; acli on PATH -> Tier 2; otherwise Tier 3 skip). Fall-through `[warn]` lines emitted verbatim from the Jira-Specific Error Handling table. Tier-3 skip is exit `0`.
   - Step 3 -- Render: invoke `render-issue-comment.sh <backend> <type> <context-json> [<tier>]`. On exit `1` (render failure), emit `[warn] Failed to render <type> comment for <issue-ref>: <stderr>. Skipping.` to stderr, exit `0`.
   - Step 4 -- Post:
     - GitHub: `gh issue comment <N> --body "<rendered>"`. On non-zero exit, emit `[warn] gh: gh issue comment failed: <gh-stderr>` to stderr, exit `0`.
     - Jira Tier 1: `addCommentToJiraIssue(cloudId, issueIdOrKey, adf-json)`. On failure, emit warn and fall through to Tier 2.
     - Jira Tier 2: `acli jira workitem comment-create --key <KEY> --body "<rendered-markdown>"`. On non-zero exit, emit `[warn] acli: acli command failed: <acli-stderr>` to stderr, exit `0`.
   - Success is silent stdout (empty). All diagnostic output is stderr only.
   - `chmod +x`.

2. Write `plugins/lwndev-sdlc/skills/managing-work-items/scripts/fetch-issue.sh`:
   - Shebang `#!/usr/bin/env bash`; `set -euo pipefail`.
   - Signature: `fetch-issue.sh <issue-ref>`. On missing arg, exit `2`.
   - Backend detection: invoke `backend-detect.sh <issue-ref>`. If output is `null`, emit `null` to stdout, exit `0`.
   - GitHub pre-flight: identical to `post-issue-comment.sh` step 2 (same `[warn]` strings, same exit-`0`-on-skip contract).
   - Jira pre-flight: identical to `post-issue-comment.sh` step 2.
   - Fetch:
     - GitHub: `gh issue view <N> --json title,body,labels,state,assignees`. Emit the JSON verbatim to stdout, exit `0`.
     - Jira Tier 1: `getJiraIssue(cloudId, issueIdOrKey)`. Project to normalized shape `{"title":"...","body":"...","labels":[...],"state":"...","assignees":[...]}`, emit on stdout.
     - Jira Tier 2: `acli jira workitem view --key <KEY>`. Parse structured text into the same normalized JSON shape.
   - On fetch failure (any tier): emit the backend's existing graceful-degradation warning verbatim to stderr (from the Graceful Degradation table), exit `0` with empty stdout.
   - `chmod +x`.

3. Write `plugins/lwndev-sdlc/skills/managing-work-items/scripts/tests/post-issue-comment.bats`:
   - No-reference path (`null` from backend-detect stub) -> exit `0`, stderr contains `[info] No issue reference provided, skipping issue operations.`.
   - `gh` not on PATH (stub `command -v gh` to fail) -> exit `0`, stderr contains `[warn] GitHub CLI (\`gh\`) not found on PATH. Skipping GitHub issue operations.` (backtick formatting verified verbatim).
   - `gh` not authenticated (stub `gh auth status` to fail) -> exit `0`, stderr contains `[warn] GitHub CLI not authenticated -- run \`gh auth login\` to enable issue tracking.`.
   - Jira ref, Tier 1 Rovo MCP not available, Tier 2 acli also not on PATH -> Tier 3 skip, exit `0`, stderr contains `No Jira backend available`.
   - Jira ref, Tier 1 fails (stub), Tier 2 acli present -> falls through to acli, exit `0`.
   - Render failure (stub `render-issue-comment.sh` exits `1`) -> exit `0`, stderr contains `[warn] Failed to render`.
   - `gh issue comment` fails non-zero -> exit `0`, stderr contains `[warn] gh: gh issue comment failed`.
   - Happy path GitHub: all stubs pass, `gh issue comment` succeeds -> exit `0`, empty stdout.
   - Missing `<type>` arg -> exit `2`.
   - Missing `<context-json>` arg -> exit `2`.
   - Malformed JSON in `<context-json>` -> exit `2`.
   - Idempotency: duplicate invocation is safe (comments safe to retry per NFR-3).

4. Write `plugins/lwndev-sdlc/skills/managing-work-items/scripts/tests/fetch-issue.bats`:
   - No-reference path -> exit `0`, stdout is `null`.
   - `gh` not on PATH -> exit `0`, stderr contains `[warn] GitHub CLI (\`gh\`) not found on PATH. Skipping GitHub issue operations.`, empty stdout.
   - GitHub happy path: stub `gh issue view` -> exit `0`, stdout is JSON with `title`, `body`, `labels`, `state`, `assignees` fields.
   - Jira Tier 1 happy path: stub getJiraIssue -> exit `0`, stdout is normalized JSON shape.
   - Jira Tier 2 fallback (Tier 1 stub fails, Tier 2 acli stub succeeds) -> exit `0`, normalized JSON on stdout.
   - Fetch failure (stub `gh issue view` exits non-zero) -> exit `0`, empty stdout, stderr contains graceful-degradation warning verbatim.
   - Issue not found (stub `gh` returns 404-equivalent non-zero) -> exit `0`, empty stdout, stderr contains skip notice.
   - Missing arg -> exit `2`.

#### Deliverables

- [x] `plugins/lwndev-sdlc/skills/managing-work-items/scripts/post-issue-comment.sh`
- [x] `plugins/lwndev-sdlc/skills/managing-work-items/scripts/fetch-issue.sh`
- [x] `plugins/lwndev-sdlc/skills/managing-work-items/scripts/tests/post-issue-comment.bats`
- [x] `plugins/lwndev-sdlc/skills/managing-work-items/scripts/tests/fetch-issue.bats`

---

### Phase 4: SKILL.md Rewrite + Caller Updates (FR-7, FR-8)

**Feature:** [FEAT-025](../features/FEAT-025-managing-work-items-full.md) | [#183](https://github.com/lwndev/lwndev-marketplace/issues/183)
**Status:** Pending

#### Rationale

The SKILL.md rewrite and caller updates are the user-visible cutover: they switch managing-work-items from a prose-implementation document to a reference-and-pointer document. This phase must land last -- after all six scripts and their fixtures exist (Phases 1-3) -- so the pointers in SKILL.md point at working, tested scripts. The two caller file updates (issue-tracking.md and documenting-features/SKILL.md) are bundled in this phase because they describe the new delegation points and must be consistent with the rewritten SKILL.md at merge time. Separating them across phases would create a window where caller docs refer to prose that no longer exists. The net SKILL.md line-count reduction (>= 30%) is verifiable after Phase 4 is complete.

#### Implementation Steps

1. Rewrite `plugins/lwndev-sdlc/skills/managing-work-items/SKILL.md`:
   - Retain verbatim: frontmatter (name, description, allowed-tools), "When to Use This Skill" section, the Arguments table (`<operation>`, `<issue-ref>`, `--type`, `--context`), the Operations table (fetch/comment/pr-link/extract-ref), the Jira-Specific Error Handling table, the Graceful Degradation table, the Output Style section (all subsections including Inline execution note).
   - Remove the following prose blocks (replaced by scripts):
     - "Detection Logic" numbered list under Backend Detection (FR-1) -> replace with one-paragraph pointer: "Backend detection is implemented by `${CLAUDE_PLUGIN_ROOT}/skills/managing-work-items/scripts/backend-detect.sh`."
     - "Rendering Process" numbered list under Comment Type Routing -> replace with one-paragraph pointer at `render-issue-comment.sh`.
     - "PR Body Issue Link Generation" table body under FR-6 -> replace the body rows with a one-paragraph pointer at `pr-link.sh`. Retain the table header line as a backend-reference summary.
     - "Extraction Logic" numbered list under Issue Reference Extraction -> replace with one-paragraph pointer at `extract-issue-ref.sh`.
     - "Workflow" numbered list -> replace with one-paragraph pointer at `post-issue-comment.sh`.
     - GitHub Backend "Fetch Operation" sub-section body -> replace with one-paragraph pointer at `fetch-issue.sh`. Retain the `gh issue view` command signature as a reference example line.
     - Jira Backend "Jira Fetch Operation" sub-section -> replace with one-paragraph pointer at `fetch-issue.sh`. Retain the Tier Detection Logic, Jira Comment Operation, and Jira-Specific Error Handling tables within Jira Backend.
     - "Implementation Pattern" bash example block (lines 293-312 of the current 338-line file) -> replace with one line: "See `${CLAUDE_PLUGIN_ROOT}/skills/managing-work-items/scripts/post-issue-comment.sh` for the full graceful-degradation implementation."
   - Verify net line count is <= 236 (338 current * 0.70 = 236.6 ceiling, i.e., >= 30% reduction). The prose blocks removed sum to ~100+ lines against the 338-line file.
   - Run `npm run validate` to confirm the unchanged `allowed-tools` list still validates.

2. Update `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/issue-tracking.md`:
   - Replace inline examples that show `gh`/`acli`/Rovo MCP invocations directly with the equivalent script calls. For example, the `extract-ref` operation example currently shows a pseudocode `Read` + scan; replace with `bash "${CLAUDE_PLUGIN_ROOT}/skills/managing-work-items/scripts/extract-issue-ref.sh" "<doc-path>"`.
   - Update the cross-reference on line 36 (the pointer `managing-work-items/SKILL.md:287-306`) to instead point at `plugins/lwndev-sdlc/skills/managing-work-items/scripts/post-issue-comment.sh`.
   - Retain all mechanism-failure `[warn]` string examples verbatim -- they now come from the scripts, not the prose, but the example text is unchanged.
   - Do not change any other content (narrative prose, tables, the "How to Invoke" section structure, or the "Rejected alternatives" subsection).

3. Update `plugins/lwndev-sdlc/skills/documenting-features/SKILL.md`:
   - Line 38 currently reads: "Direct `gh` CLI usage for issue fetch is replaced by `managing-work-items`, which handles GitHub Issues (`#N`) and Jira (`PROJ-123`) with auto-detection and graceful degradation."
   - Update to: "Direct `gh` CLI usage for issue fetch is now delegated through `fetch-issue.sh` (`${CLAUDE_PLUGIN_ROOT}/skills/managing-work-items/scripts/fetch-issue.sh`), which handles GitHub Issues (`#N`) and Jira (`PROJ-123`) with auto-detection and graceful degradation."
   - Confirm `documenting-chores/SKILL.md` and `documenting-bugs/SKILL.md` do not contain equivalent delegation notes requiring updates (per FR-8 confirmation they do not).

4. Run `npm test` and `npm run validate` to confirm all tests pass and validation succeeds on the release branch.

5. Verify net SKILL.md reduction via `wc -l` on the rewritten file -- must be <= 236 lines.

6. Manual smoke-test: run a representative managing-work-items call through the orchestrator (post a `phase-start` comment on a test issue) and confirm the comment lands with the expected body, matching the pre-FEAT-025 prose-driven output.

#### Deliverables

- [ ] `plugins/lwndev-sdlc/skills/managing-work-items/SKILL.md` (rewritten per FR-7; net line reduction >= 30%)
- [ ] `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/issue-tracking.md` (script-delegation examples; cross-reference updated)
- [ ] `plugins/lwndev-sdlc/skills/documenting-features/SKILL.md` (fetch-issue.sh delegation note updated)
- [ ] Passing `npm test` and `npm run validate`

---

## Shared Infrastructure

- **Skill-scoped scripts directory** -- new `plugins/lwndev-sdlc/skills/managing-work-items/scripts/` and sibling `scripts/tests/` created in Phase 1. Structure mirrors `plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/` exactly.
- **Template reference files** -- `plugins/lwndev-sdlc/skills/managing-work-items/references/github-templates.md` and `references/jira-templates.md` are consumed by `render-issue-comment.sh` (Phase 2); these files already exist and are not modified by FEAT-025.
- **`backend-detect.sh` as shared primitive** -- `pr-link.sh` (Phase 1), `post-issue-comment.sh` (Phase 3), and `fetch-issue.sh` (Phase 3) all invoke `backend-detect.sh` as a subprocess. No PATH-shadowing stub is needed in tests for Phase 1 and Phase 2 because the real `backend-detect.sh` is available (tests are run against real Phase 1 scripts). Phase 3 tests may stub `backend-detect.sh` where the test scenario requires controlling its output independently of the input ref.
- **`[warn]` / `[info]` string exactness** -- the Graceful Degradation and Jira-Specific Error Handling tables in SKILL.md are the canonical source of truth. Every script that emits these strings must match the table text at the character level (backticks, double-hyphens, exact phrasing). A grep-level diff between table text and script emit must show zero divergence (NFR-1).
- **jq vs pure-bash fallback** -- scripts use `jq` when available, pure-bash string operations otherwise. This matches the `branch-id-parse.sh` and `prepare-fork.sh` precedents. Declare `jq` as optional in each script's top-of-file comment block where used.
- **PATH-shadowing stub pattern** -- bats fixtures in Phase 3 stub `gh`, `acli`, and Rovo MCP tools via PATH shadowing, reusing the pattern from `plugins/lwndev-sdlc/scripts/tests/` and `plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/tests/`.
- **No new plugin-shared scripts** -- all six FEAT-025 scripts are fully self-contained under `plugins/lwndev-sdlc/skills/managing-work-items/scripts/`. The plugin-shared `scripts/` directory is not modified.

## Testing Strategy

- **Unit tests (bats, Phases 1-3)** -- one `.bats` file per script, covering all valid input classes, every documented exit code, template rendering edge cases, regex edge cases, and graceful-degradation skip paths. Tests live under `plugins/lwndev-sdlc/skills/managing-work-items/scripts/tests/`.
- **String exactness tests** -- `post-issue-comment.bats` and `fetch-issue.bats` assert `[warn]` and `[info]` string content verbatim (including backtick formatting) to enforce NFR-1 zero-divergence requirement.
- **Idempotency tests** -- `render-issue-comment.bats` and `pr-link.bats` assert identical stdout for two successive calls with the same input.
- **Integration tests (live, behind flag)** -- a `RUN_LIVE_ISSUE_TESTS=1` env flag gates end-to-end `post-issue-comment.sh` and `fetch-issue.sh` tests against a throwaway GitHub issue. Not run in CI by default (rate-limit and auth sensitive). Covers at minimum one `phase-start` and one `phase-completion` round-trip, and one `fetch-issue.sh` round-trip verifying the normalized JSON shape.
- **Manual E2E** -- run a complete feature workflow end-to-end and confirm every issue-comment integration point (phase-start x N, phase-end x N, work-start, work-complete) posts the same comment body as pre-FEAT-025, visually diffed against one pre-feature and one post-feature comment on a live issue.
- **Token savings measurement (NFR-4)** -- pre- and post-feature token counts on a representative 4-phase feature workflow captured during the manual E2E run. Target: measured delta falls within ±30% of the ~2,200-2,800 tok/workflow estimate.

## Dependencies and Prerequisites

- **Phase ordering**: Phase 2 depends on Phase 1 (render-issue-comment invokes backend-detect for tier selection; tests use the real backend-detect.sh). Phase 3 depends on Phases 1 and 2 (composite scripts call all Layer-A and Layer-B scripts). Phase 4 depends on Phases 1-3 (SKILL.md pointers must point at existing, working scripts).
- **Existing template reference files** -- `references/github-templates.md` and `references/jira-templates.md` must exist before Phase 2 can implement `render-issue-comment.sh`. Both exist today and are unchanged by this feature.
- **External tools (already required, no new deps)**:
  - `gh` CLI: required for GitHub operations in `post-issue-comment.sh` and `fetch-issue.sh`. Graceful-degradation applies if absent.
  - `acli` and Rovo MCP: optional (Jira tiered fallback). No new dependency.
  - `jq`: optional for JSON parsing. Declare as preferred in script top comments; provide pure-bash fallback.
- **No Node/TypeScript changes** -- shell-only, consistent with the `plugins/lwndev-sdlc/scripts/` convention. `npm test` runs the bats suite as a side effect of the existing test runner configuration; no new test runner setup required.

## Risk Assessment

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| `[warn]` / `[info]` string in a script diverges from the SKILL.md table (breaks NFR-1 zero-divergence) | High | Medium | `post-issue-comment.bats` and `fetch-issue.bats` assert verbatim string content including backtick and double-hyphen characters. A pre-merge grep diff between SKILL.md table text and script source is a Phase 4 checklist item. |
| `render-issue-comment.sh` ADF substitution produces invalid JSON for certain user-supplied context values (e.g., unescaped quotes in name fields) | High | Medium | ADF output is validated with `jq .` (or equivalent) before emit. Exit `1` on any malformed result; `post-issue-comment.sh` converts this to a skip (exit `0`). `render-issue-comment.bats` includes an unescaped-quote injection test. |
| `backend-detect.sh` regex admits a pathological input that should emit `null` but instead matches (e.g., `#0`, single-digit valid ref, all-caps project key with numbers like `A2B-3`) | Low | Low | Regex is anchored `^...$`; bats covers alphanumeric project keys, lowercase rejection, underscore rejection, and edge-case ref formats. |
| SKILL.md rewrite inadvertently removes the Graceful Degradation or Jira-Specific Error Handling tables, breaking caller documentation | High | Low | Phase 4 implementation steps explicitly list retained sections. Post-rewrite visual diff checked against the table headings as a smoke-test. |
| Phase 4 line-count target missed (< 30% reduction) | Low | Low | The removal list in FR-7 sums to ~100+ lines against the 338-line file. Verified via `wc -l` in Phase 4 step 5 before committing. |
| `extract-issue-ref.sh` matches the wrong heading variant (e.g., matching `## GitHub Issue URL` when only exact variants are intended) | Low | Low | Regex uses `^## (GitHub Issue|Issue|Issue Tracker)$` with end-anchor, rejecting longer variants. Bats covers all three valid headings and confirms no false match. |
| Phase 3 composite scripts prove difficult to test without a real Jira instance | Medium | Medium | Jira-tier paths are stubbed via PATH shadowing and a stub MCP invocation pattern (consistent with FEAT-022's `finalize.bats` approach). Live Jira tests are gated behind a separate env flag. |
| Token savings measurement unavailable at PR time (NFR-4 requires it reported) | Low | Medium | Phase 4 step 6 manual smoke-test explicitly captures token counts. Missing measurement is a Phase 4 deliverable checkbox that blocks AC sign-off. |

## Success Criteria

Per-feature (FEAT-025) -- all acceptance criteria from the requirements document:

- `backend-detect.sh` implements FR-1; handles both regexes and the null path; exits `2` on missing/empty arg; bats tests pass.
- `extract-issue-ref.sh` implements FR-2; scans all three heading variants; emits first match or empty; exits `1` on missing file; bats tests pass.
- `pr-link.sh` implements FR-3; pure function; emits `Closes #N`, `PROJ-NNN`, or empty; idempotent; bats tests pass.
- `render-issue-comment.sh` implements FR-4; renders markdown (all six types) and ADF (Jira rovo tier); emits unknown-variable warning; exits `1` on missing variable; bats tests pass.
- `post-issue-comment.sh` implements FR-5; composite detect -> render -> post sequence; exits `0` on every skip path; all `[warn]`/`[info]` strings match the SKILL.md tables verbatim; bats tests pass.
- `fetch-issue.sh` implements FR-6; normalized JSON shape across GitHub and Jira tiers; exits `0` on every skip path; bats tests pass.
- `plugins/lwndev-sdlc/skills/managing-work-items/SKILL.md` rewritten per FR-7; Arguments, Operations, Error Handling, Graceful Degradation, and Output Style sections retained; FR-1/5/6/7 bodies replaced with script pointers; net line-count reduction >= 30%.
- `orchestrating-workflows/references/issue-tracking.md` updated per FR-8; examples invoke scripts; cross-reference updated; mechanism-failure `[warn]` strings unchanged.
- `documenting-features/SKILL.md` note updated to reference `fetch-issue.sh` per FR-8.
- Integration test (behind `RUN_LIVE_ISSUE_TESTS=1`): `post-issue-comment.sh` and `fetch-issue.sh` round-trip against a throwaway GitHub issue passes.
- Token-savings measurement per NFR-4 confirms the estimate within ±30%.
- `npm test` and `npm run validate` pass on the release branch.

## Code Organization

```
plugins/lwndev-sdlc/
└── skills/
    ├── managing-work-items/
    │   ├── SKILL.md                              # REWRITTEN (Phase 4): reference-and-pointer doc
    │   ├── references/
    │   │   ├── github-templates.md               # UNCHANGED: consumed by render-issue-comment.sh
    │   │   └── jira-templates.md                 # UNCHANGED: consumed by render-issue-comment.sh
    │   └── scripts/                              # NEW directory (Phase 1)
    │       ├── backend-detect.sh                 # NEW (Phase 1): FR-1 pure backend classifier
    │       ├── extract-issue-ref.sh              # NEW (Phase 1): FR-2 requirement doc extraction
    │       ├── pr-link.sh                        # NEW (Phase 1): FR-3 PR-body fragment generator
    │       ├── render-issue-comment.sh           # NEW (Phase 2): FR-4 template renderer
    │       ├── post-issue-comment.sh             # NEW (Phase 3): FR-5 composite comment flow
    │       ├── fetch-issue.sh                    # NEW (Phase 3): FR-6 issue pre-fill fetch
    │       └── tests/                            # NEW directory (Phase 1)
    │           ├── backend-detect.bats           # NEW (Phase 1)
    │           ├── extract-issue-ref.bats        # NEW (Phase 1)
    │           ├── pr-link.bats                  # NEW (Phase 1)
    │           ├── render-issue-comment.bats     # NEW (Phase 2)
    │           ├── post-issue-comment.bats       # NEW (Phase 3)
    │           └── fetch-issue.bats              # NEW (Phase 3)
    ├── orchestrating-workflows/
    │   └── references/
    │       └── issue-tracking.md                 # UPDATED (Phase 4): script-delegation examples
    └── documenting-features/
        └── SKILL.md                              # UPDATED (Phase 4): fetch-issue.sh delegation note
```
