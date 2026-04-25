# Feature Requirements: `orchestrating-workflows` Findings / Resume / Remainder Scripts (Items 9.1, 9.3–9.8)

## Overview
Collapse the remaining orchestrator prose hot-spots outside `prepare-fork.sh` into seven skill-scoped helpers plus one new subcommand on the existing `workflow-state.sh`. Item 9.2 (`prepare-fork.sh`) already landed with FEAT-021 and is not in scope; the algorithmic core of the FEAT-014 model-selection policy already lives inside `workflow-state.sh` and is also not in scope. This feature closes the remaining clerical-prose ceremony around argv parsing, findings ingestion, the Decision-Flow branch, post-fork PR-number resolution, workflow init, resume preconditions, and the last unscripted path between pause and resume (`modelOverride` edit).

## Feature ID
`FEAT-028`

## GitHub Issue
[#186](https://github.com/lwndev/lwndev-marketplace/issues/186)

## Priority
Medium — ~1,500–2,500 tokens saved per feature workflow (9.2 was the dominant contributor and is already shipped). Savings compound across resume-paths (9.7), every reviewing-requirements fork (9.3 + 9.4), every executing-chores / executing-bug-fixes fork (9.5), and every workflow start (9.1 + 9.6). The orchestrator is the hottest file in the plugin; every line of prose removed here is paid back on every single run.

## User Story
As the orchestrator executing any of the three workflow chains (feature / chore / bug), I want the argv-parsing ceremony at workflow start, the findings-ingestion ceremony after every `reviewing-requirements` fork, the PR-number extraction ceremony after every `executing-*` fork, the workflow-init composite ceremony, the resume-precondition ceremony, and the `modelOverride` edit path on pause/resume to be one-line script invocations so that (a) ~1,500–2,500 tokens of mechanical prose per workflow are eliminated, (b) the documented flows become testable end-to-end under bats, and (c) the orchestrator SKILL.md and its references become what they already aspire to be — a dispatch + judgment document, not an instruction manual for `jq` and `grep`.

## Command Syntax

All scripts in scope land under `${CLAUDE_PLUGIN_ROOT}/skills/orchestrating-workflows/scripts/`. Item 9.8 adds a new subcommand to the existing `workflow-state.sh`. All follow the plugin-shared conventions from #179 (shell-first, exit-code driven, stdout carries JSON or a single primitive, stderr for warnings/errors, bats-tested).

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/orchestrating-workflows/scripts/parse-model-flags.sh" "$@"
bash "${CLAUDE_PLUGIN_ROOT}/skills/orchestrating-workflows/scripts/parse-findings.sh" <subagent-output-file>
bash "${CLAUDE_PLUGIN_ROOT}/skills/orchestrating-workflows/scripts/findings-decision.sh" <ID> <stepIndex> <counts-json>
bash "${CLAUDE_PLUGIN_ROOT}/skills/orchestrating-workflows/scripts/resolve-pr-number.sh" <branch> [subagent-output-file]
bash "${CLAUDE_PLUGIN_ROOT}/skills/orchestrating-workflows/scripts/init-workflow.sh" <TYPE> <artifact-path>
bash "${CLAUDE_PLUGIN_ROOT}/skills/orchestrating-workflows/scripts/check-resume-preconditions.sh" <ID>
bash "${CLAUDE_PLUGIN_ROOT}/skills/orchestrating-workflows/scripts/workflow-state.sh" set-model-override <ID> <tier>
```

### Examples

```bash
# 9.1: strip model-selection flags from the full argv and recover the positional token
bash "${CLAUDE_PLUGIN_ROOT}/skills/orchestrating-workflows/scripts/parse-model-flags.sh" \
  --model sonnet --model-for reviewing-requirements:opus '#186'
# stdout: {"cliModel":"sonnet","cliComplexity":null,"cliModelFor":{"reviewing-requirements":"opus"},"positional":"#186"}

# 9.3: parse a reviewing-requirements subagent output dump into counts + individual findings
bash "${CLAUDE_PLUGIN_ROOT}/skills/orchestrating-workflows/scripts/parse-findings.sh" \
  /tmp/rr-output-FEAT-028.txt
# stdout: {"counts":{"errors":0,"warnings":2,"info":1},"individual":[{"id":"W1","severity":"warning","category":"reference","description":"..."},...]}

# 9.4: resolve the Decision Flow branch for a given set of counts
bash "${CLAUDE_PLUGIN_ROOT}/skills/orchestrating-workflows/scripts/findings-decision.sh" \
  FEAT-028 1 '{"errors":0,"warnings":2,"info":1}'
# stdout: {"action":"prompt-user","reason":"feature chain or high-complexity chore|bug","type":"feature","complexity":"medium"}

# 9.5: extract PR number from subagent output with gh pr list fallback
bash "${CLAUDE_PLUGIN_ROOT}/skills/orchestrating-workflows/scripts/resolve-pr-number.sh" \
  feat/FEAT-028-orchestrating-workflows-findings-resume /tmp/exec-chores-output.txt
# stdout: 232

# 9.6: one-call workflow init for a feature chain
bash "${CLAUDE_PLUGIN_ROOT}/skills/orchestrating-workflows/scripts/init-workflow.sh" \
  feature requirements/features/FEAT-028-orchestrating-workflows-findings-resume.md
# stdout: {"id":"FEAT-028","type":"feature","complexity":"medium","issueRef":"#186"}

# 9.7: gate the Resume Procedure decision tree
bash "${CLAUDE_PLUGIN_ROOT}/skills/orchestrating-workflows/scripts/check-resume-preconditions.sh" FEAT-028
# stdout: {"type":"feature","status":"paused","pauseReason":"plan-approval","currentStep":3,"chainTable":"feature","complexityStage":"init","complexity":"medium"}

# 9.8: persist a modelOverride tier upgrade between pause and resume
bash "${CLAUDE_PLUGIN_ROOT}/skills/orchestrating-workflows/scripts/workflow-state.sh" \
  set-model-override FEAT-028 opus
# stdout: (empty)  stderr: [info] modelOverride set to opus for FEAT-028
```

## Functional Requirements

### FR-1: `parse-model-flags.sh` — Argv Partition

- Signature: `parse-model-flags.sh "$@"` (accepts the orchestrator's full argv list).
- Strip the three recognised FEAT-014 FR-8 flags plus their arguments from the argv list. Positional arguments survive. Unknown flags exit `2`.
  - `--model <tier>` — hard blanket override. `<tier>` is one of `haiku` / `sonnet` / `opus`; other values exit `2`.
  - `--complexity <tier>` — soft blanket override. `<tier>` is one of `haiku` / `sonnet` / `opus` **or** `low` / `medium` / `high` (the latter mapped via `low→haiku`, `medium→sonnet`, `high→opus`); other values exit `2`.
  - `--model-for <step>:<tier>` — hard per-step override. `<step>` is a non-empty step-name string; `<tier>` validated as above. The flag may repeat; the final map keyed by `<step>` preserves every entry (later entries overwrite earlier ones for the same step).
- The flags are positional-independent: a flag and its argument may appear before, after, or interleaved with the positional token. Flags still adhere to the two-token shape (`--model sonnet`, not `--model=sonnet`); the `=` form is explicitly out of scope and exits `2`.
- Emit a single JSON object on stdout with all four fields always present (JSON `null` for the three flag fields when not provided; empty string for `positional` when no positional argument was passed):
  ```json
  {"cliModel":"sonnet|haiku|opus|null","cliComplexity":"sonnet|haiku|opus|null","cliModelFor":{"<step>":"<tier>"}|null,"positional":"<token-or-empty-string>"}
  ```
- Exit codes: `0` success (including empty argv); `2` on unknown flag, malformed tier, missing flag argument, or more than one surviving positional token.
- Replaces SKILL.md `## Arguments → Model-Selection Flags (FEAT-014 FR-8)` parsing-rules prose — ~200 tokens × 1 invocation/workflow.

### FR-2: `parse-findings.sh` — Reviewing-Requirements Output Parser

- Signature: `parse-findings.sh <subagent-output-file>`.
- Accept one positional arg: a path to a file containing the full raw return text of a `reviewing-requirements` subagent fork. Exit `2` on missing arg; exit `1` on file-not-found or unreadable.
- Scan the file for the canonical summary line. Anchor the regex on the `Found **N errors**, **N warnings**, **N info**` substring (not line-start) per `references/reviewing-requirements-flow.md` — test-plan mode prepends a mode prefix. If no summary line is found, emit counts `{errors:0,warnings:0,info:0}` (matches the flow's "No issues found" normalisation).
- Scan the file for individual findings matching the documented pattern: `**[{W|I}{N}] {category} — {description}**` (em dash `—` preferred, ASCII `--` accepted as fallback). Bold markers optional. For each match extract:
  - `id` — severity+number token (e.g., `"W1"`, `"I3"`)
  - `severity` — `"warning"` for `W`, `"info"` for `I`; error findings are not parsed here (errors block and are presented separately, not recorded under `auto-advanced`)
  - `category` — text between `]` and the dash, trimmed
  - `description` — text from the dash to the end of the line, trimmed and stripped of trailing bold markers
- Emit one JSON object on stdout:
  ```json
  {"counts":{"errors":0,"warnings":0,"info":0},"individual":[{"id":"W1","severity":"warning","category":"...","description":"..."}]}
  ```
  `counts` is always present; `individual` is always an array (possibly empty). Callers rely on the shape, not presence.
- Exit codes: `0` success (including zero-findings / zero-matches); `1` on file-not-found / unreadable; `2` on missing arg.
- Emit `[warn] parse-findings: counts non-zero but no individual findings parsed — recording counts only.` to stderr when `counts.warnings + counts.info > 0` but `individual` is empty, matching the existing flow's `record-findings --details-file` fallback. The warn is **scoped to warning/info counts only** — errors are intentionally not parsed into `individual[]` (errors block at the orchestrator layer and are handled separately), so an error-only output (`counts.errors > 0, counts.warnings == 0, counts.info == 0, individual == []`) must NOT emit the warn. The condition is literally `counts.warnings + counts.info > 0 && individual is empty`.
- Replaces `references/reviewing-requirements-flow.md` "Parsing Findings" prose + "Parsing Individual Findings for `auto-advanced` Decisions" procedure — ~400–600 tokens × 2–3 reviewing-requirements fork invocations per workflow.

### FR-3: `findings-decision.sh` — Decision-Flow Resolver

- Signature: `findings-decision.sh <ID> <stepIndex> <counts-json>`.
- Accept three positional args: the workflow ID (`FEAT-NNN` / `CHORE-NNN` / `BUG-NNN`), the zero-based step index, and a counts JSON object in the shape emitted by FR-2's `counts` field. Exit `2` on any missing or malformed arg. The `<stepIndex>` arg is accepted for caller-audit consistency and is echoed into any stderr `[info]` / `[warn]` line the script emits; it does not affect the Decision Flow branch or the output JSON shape. Keeping it in the signature lines up with every other `workflow-state.sh`-interacting subcommand (`record-findings`, `record-model-selection`, etc.) so callers do not have to special-case this one script.
- Read the workflow state file at `.sdlc/workflows/<ID>.json` to pull `type` (feature / chore / bug) and `complexity` (low / medium / high). Exit `1` if the state file does not exist or is unreadable.
- Apply the three-way Decision Flow documented in `references/reviewing-requirements-flow.md`:
  1. **Zero findings** (`errors == 0 && warnings == 0 && info == 0`) → `action: "advance"`, `reason: "zero findings"`.
  2. **Errors present** (`errors > 0`) → `action: "pause-errors"`, `reason: "errors present"`. This action signals the orchestrator to set the gate, display findings, and present the apply-fixes / pause options.
  3. **Warnings / info only** (`errors == 0 && (warnings > 0 || info > 0)`) → apply the chain-type + complexity gate:
     - `type` is `chore` or `bug` AND `complexity` is `low` or `medium` → `action: "auto-advance"`, `reason: "chore|bug chain with complexity <= medium"`.
     - Otherwise (`type == feature` OR `complexity == high`) → `action: "prompt-user"`, `reason: "feature chain or high-complexity chore|bug"`.
- Emit one JSON object on stdout:
  ```json
  {"action":"advance|auto-advance|prompt-user|pause-errors","reason":"<one-line>","type":"feature|chore|bug","complexity":"low|medium|high"}
  ```
- Exit codes: `0` success (any of the four actions); `1` on missing / unreadable state file, malformed state file (missing `type` or `complexity` fields after FR-13 migration), or unparseable counts JSON; `2` on missing / malformed args.
- Replaces `references/reviewing-requirements-flow.md` "Decision Flow" three-way branch prose — ~300 tokens × 2–3 reviewing-requirements fork invocations per workflow.

### FR-4: `resolve-pr-number.sh` — Post-Fork PR-Number Extraction

- Signature: `resolve-pr-number.sh <branch> [subagent-output-file]`.
- Accept one required arg (`<branch>`) and one optional arg (`<subagent-output-file>`). Exit `2` on missing `<branch>`.
- Resolution strategy, in order — the first to produce a numeric match wins:
  1. If `<subagent-output-file>` is supplied and exists, scan the file for `#<digits>` tokens and `https://github.com/<owner>/<repo>/pull/<N>` URLs. Pick the **last** match (forks tend to echo the final PR number near end-of-output). If multiple candidates disagree, the last candidate is canonical.
  2. If step 1 produced no match, fall back to `gh pr list --head "<branch>" --json number,state --jq '[.[] | select(.state=="OPEN")][0].number'`. An empty / null result falls through.
  3. If neither source yields a number, emit empty stdout and exit `1`.
- Emit the resolved PR number as a bare integer on stdout (no JSON, no newline-terminated array). Consumers substitute it directly into `set-pr {ID} {pr-number} {branch}`.
- Exit codes: `0` on a resolved number; `1` when no source yielded a match (orchestrator surfaces the failure; the chore/bug executor's own `gh pr create` output is normally present, so this exit is rare); `2` on missing `<branch>` arg; `0` on a graceful-skip where the subagent output file path was provided but does not exist and the `gh pr list` fallback succeeded (file-not-found is non-fatal at this call site).
- `gh` missing or unauthenticated → exit `1` with `[warn] resolve-pr-number: gh unavailable; could not fall back to gh pr list.` to stderr. Consumers halt with `fail` per the existing step-execution-details contract.
- Replaces the post-fork PR-number extraction prose in `references/step-execution-details.md` (chore step 4 items 1–2; bug step 4 items 1–2) — ~150 tokens × 2 fork sites per workflow (chore OR bug chain; also applies to the feature-chain PR-creation site in a follow-up, out of scope here). Feature-chain PR creation's extraction lives in PR-Creation prose and is left as prose for now since the subagent contract is clearer there; the script is available for a future adopter.

### FR-5: `init-workflow.sh` — New-Workflow Composite

- Signature: `init-workflow.sh <TYPE> <artifact-path>`.
- Accept two positional args: `<TYPE>` (one of `feature` / `chore` / `bug`) and `<artifact-path>` (the requirement document produced by step 1 of the chain). Exit `2` on missing or malformed args; exit `1` on `<artifact-path>` not found / unreadable or on a TYPE / filename prefix mismatch.
- Composite over existing `workflow-state.sh` subcommands and skill-scoped helpers. The script derives `CLAUDE_PLUGIN_ROOT` from `"$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"` — three-levels-up from its `scripts/` directory to reach the plugin root at `plugins/lwndev-sdlc/` (two extra levels vs. `prepare-fork.sh`, which lives at `plugins/lwndev-sdlc/scripts/` and uses one level up from its `BASH_SOURCE`). This lets cross-skill script paths resolve without requiring the caller to export the variable:
  1. Extract the workflow ID from the artifact filename. Regex per TYPE: `FEAT-[0-9]+` / `CHORE-[0-9]+` / `BUG-[0-9]+`. If the regex does not match, exit `1` with `[warn] init-workflow: could not extract <TYPE-prefix> ID from filename`.
  2. `mkdir -p .sdlc/workflows` (idempotent).
  3. `workflow-state.sh init <ID> <TYPE>`.
  4. `workflow-state.sh classify-init <ID> <artifact-path>` → capture tier on stdout.
  5. `workflow-state.sh set-complexity <ID> <tier>`.
  6. `echo "<ID>" > .sdlc/workflows/.active` — write the active marker **before** `advance` so a stop-hook firing mid-composite still finds it (matches the existing `chain-procedures.md` New-Workflow Procedure ordering).
  7. `workflow-state.sh advance <ID> <artifact-path>`.
  8. Extract the issue reference from the artifact via `"${CLAUDE_PLUGIN_ROOT}/skills/managing-work-items/scripts/extract-issue-ref.sh" <artifact-path>` (graceful — an empty / unavailable ref is non-fatal and does not abort init). Capture stdout.
- Emit one JSON object on stdout (all four fields present; `issueRef` is an empty string when no reference was found):
  ```json
  {"id":"FEAT-028","type":"feature","complexity":"medium","issueRef":"#186"}
  ```
- Exit codes: `0` on a successful init (including empty issueRef); `1` on a downstream subcommand failure (relayed verbatim to stderr); `2` on missing / malformed args.
- The `.sdlc/workflows/.active` write is the orchestrator's active-marker for resume by branch name; writing it here removes a step from every New-Workflow procedure.
- Replaces `references/chain-procedures.md` sections "New Feature Workflow Procedure → 1. Write Active Marker / 3. Read Allocated ID and Extract Issue Reference / 4. Initialize State / 5. Advance Step 1 and Continue" plus the mirror sections for chore and bug chains — ~300 tokens × 1 invocation per new workflow.

### FR-6: `check-resume-preconditions.sh` — Resume Gate

- Signature: `check-resume-preconditions.sh <ID>`.
- Accept one positional arg: the workflow ID. Exit `2` on missing / malformed ID; exit `1` when `.sdlc/workflows/<ID>.json` does not exist.
- Composite over existing `workflow-state.sh` subcommands:
  1. `workflow-state.sh status <ID>` — implicitly performs the FR-13 state-file migration if needed. Capture `status`, `currentStep`, and `pauseReason` from the JSON output.
  2. `workflow-state.sh resume-recompute <ID>` — upgrade-only re-computation of work-item complexity per FEAT-014 FR-12. Relays the subcommand's own stderr (including any `[model] Work-item complexity upgraded ...` line) verbatim.
  3. Read the state file's `type` field (`feature` / `chore` / `bug`) to determine the chain-step-sequence table the orchestrator should consult on resume.
  4. Read the state file's `complexity` and `complexityStage` fields.
- Emit one JSON object on stdout:
  ```json
  {
    "type": "feature|chore|bug",
    "status": "in-progress|paused|failed|complete",
    "pauseReason": "plan-approval|pr-review|review-findings|null",
    "currentStep": 3,
    "chainTable": "feature|chore|bug",
    "complexity": "low|medium|high",
    "complexityStage": "init|post-plan"
  }
  ```
  `pauseReason` is JSON `null` when `status != "paused"`. `chainTable` is a convenience alias for `type` (they always match) — the orchestrator's step-sequence dispatch is keyed by `chainTable`. The bats coverage for this script MUST assert `chainTable == type` for each tested workflow type so the alias invariant is guarded against accidental drift; without this assertion, a future edit could desync the two fields and break dispatch.
- Exit codes: `0` on any recognised resume state (including `complete` and `failed`); `1` on missing / unreadable state file, malformed JSON output from a downstream subcommand, or a downstream subcommand's non-zero exit; `2` on missing / malformed args.
- **Escape-hatch contract preserved**: the script does not re-read the requirement document nor downgrade `complexity`. Users who want to lower the complexity tier between pause and resume must run `workflow-state.sh set-complexity <ID> <lower-tier>` before re-invoking the orchestrator — per FEAT-014 FR-12 and the existing escape-hatch documented in `references/chain-procedures.md` Resume Procedure. FR-7 (`set-model-override`) is an orthogonal soft-override path writing a different state field (`modelOverride`); it does not substitute for the complexity escape hatch. This is not a regression; it codifies the existing contract.
- Replaces `references/chain-procedures.md` "Resume Procedure" steps 1–5 prose — ~400 tokens × 1 invocation per resume. Resume paths are rarer than new-workflow paths per invocation, but every pause point creates the potential for a resume, so the savings accrue across the lifecycle of long-running feature chains.

### FR-7: `workflow-state.sh set-model-override` — New Subcommand

- Signature: `workflow-state.sh set-model-override <ID> <tier>`.
- New subcommand added to the existing `workflow-state.sh`. Accept two positional args: the workflow ID and the target tier (`haiku` / `sonnet` / `opus` — bare tiers, **not** `low` / `medium` / `high` labels). Exit `2` on missing / malformed args; exit `1` on missing state file.
- Behaviour: updates the state file's top-level `modelOverride` field to the given tier. Implementation mirrors the existing `set-complexity` subcommand's state-file-locking + in-place write pattern (line 1654-ish in `workflow-state.sh`). The subcommand **does not** validate against baseline locks — `modelOverride` is a soft override that the `resolve-tier` chain already gates. Users wanting a hard override use `--model` / `--model-for` at invocation; this subcommand is the pause/resume surface for soft upgrades.
- Emit nothing on stdout (no JSON); write one `[info] modelOverride set to <tier> for <ID>` line to stderr confirming the write. Consumers chain subsequent commands without parsing stdout.
- Exit codes: `0` on a successful write; `1` on state-file missing / unwritable or a jq failure; `2` on missing / malformed args (including unrecognised tier).
- **Downgrade is permitted**: setting a lower tier (e.g., `opus → sonnet`) writes the lower value. This is the *explicit* pause/resume downgrade path FEAT-014 FR-12 cites; the resume-recompute's upgrade-only guard prevents document-edit-driven downgrades, but a user-authored downgrade via this subcommand is allowed and documented. That is the whole point of the escape hatch.
- Replaces the `jq '.modelOverride = "opus"'` manual-edit incantation documented in `references/model-selection.md` Migration Option 4b — ~150 tokens × 1 invocation per manual migration. The papercut is called out by name in that reference today; this FR closes it.

### FR-8: SKILL.md + References Prose Replacement

Rewrite the orchestrator SKILL.md and four of its reference documents to replace the mechanical prose implemented by FR-1 through FR-7 with one-line script-invocation pointers.

Per-file edit surface (minimal, scoped to the prose each FR replaces — no incidental rewrites):

- `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md`
  - `## Arguments → Model-Selection Flags (FEAT-014 FR-8)` "Parsing rules" paragraph → one-line `parse-model-flags.sh` invocation + a pointer at the JSON output shape. FR-1.
  - `## Quick Start` steps 3–5 for feature / chore / bug new-workflow start → collapse each into a single `init-workflow.sh` pointer. FR-5. The three steps currently enumerate the active-marker write, ID read, state init, complexity classify, and advance-step-1 in-line; all five collapse into one script call.
- `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/reviewing-requirements-flow.md`
  - `## Parsing Findings` section body → one-line `parse-findings.sh` pointer. FR-2.
  - `## Decision Flow` three-way branch (items 1, 2, 3) → one-line `findings-decision.sh` pointer; retain the `action`-to-orchestrator-behavior mapping as a short table (zero findings → advance; auto-advance → log + advance; prompt-user → set-gate + display + prompt; pause-errors → set-gate + display + apply-fixes / pause choice). The mapping stays prose because the orchestrator does the user-interaction work, not the script. FR-3.
  - `### Parsing Individual Findings for `auto-advanced` Decisions` subsection → one-line pointer at `parse-findings.sh`'s `individual` field. FR-2.
- `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/chain-procedures.md`
  - New Feature / Chore / Bug Workflow Procedure sections → each collapses into a single `init-workflow.sh` pointer with the JSON output shape inlined. FR-5.
  - Resume Procedure steps 1–5 → one-line `check-resume-preconditions.sh` pointer with the JSON output shape inlined. Step 6 ("Use the appropriate step sequence table ...") stays prose. FR-6.
- `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/step-execution-details.md`
  - Chore chain step 4 items 1–2 (PR-number extraction + `gh pr list` fallback) → one-line `resolve-pr-number.sh` pointer. FR-4.
  - Bug chain step 4 items 1–2 (same pattern) → one-line `resolve-pr-number.sh` pointer. FR-4.
  - Feature-chain PR-Creation prose stays as-is (see FR-4 rationale).
- `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/model-selection.md`
  - Migration Option 4b: replace the `jq '.modelOverride = "opus"'` snippet with a `workflow-state.sh set-model-override` pointer. FR-7.

Net SKILL.md + references line-count reduction target: ≥ 8%. The orchestrator is already heavily scripted (`workflow-state.sh` has 20+ subcommands and `prepare-fork.sh` is landed), so the raw percentage is smaller than FEAT-026's ≥ 25% — the remaining prose is concentrated and already lean in places. The line-count target is a soft ceiling; the contract is "every prose body FR-1 through FR-7 target is replaced".

### FR-9: Caller Audit and No-Op Confirmation

- Existing orchestrator-internal invocations (`workflow-state.sh` subcommands, `prepare-fork.sh`) use the `${CLAUDE_SKILL_DIR}/scripts/...` and `${CLAUDE_PLUGIN_ROOT}/scripts/...` forms already established in SKILL.md and its references; those call sites are unchanged. The seven new scripts added by this feature are invoked via `${CLAUDE_PLUGIN_ROOT}/skills/orchestrating-workflows/scripts/...` (the canonical skill-scoped form — equivalent at runtime to `${CLAUDE_SKILL_DIR}/scripts/...` since `CLAUDE_SKILL_DIR = ${CLAUDE_PLUGIN_ROOT}/skills/orchestrating-workflows`, but spelled in the longer form for consistency with the cross-skill script paths elsewhere in the orchestrator's prose). The SKILL.md prose tells the model which script to call and when.
- No other skills or agents consume the orchestrator's scripts directly — this is a closed-world change. `finalizing-workflow`'s `finalize.sh` composes over `${CLAUDE_PLUGIN_ROOT}/scripts/branch-id-parse.sh` (not any of the new scripts). `managing-work-items/scripts/extract-issue-ref.sh` is called **by** FR-5 but itself is unchanged; its public contract is unaffected.
- No changes to `plugins/lwndev-sdlc/agents/` are required. The agents do not consume orchestrator-internal scripts.

## Output Format

Per-script output contracts are specified in each FR. Summarized for quick reference:

| Script | Stdout (success) | Stdout (skip / not-found) | Stderr |
|--------|------------------|----------------------------|--------|
| `parse-model-flags.sh` | JSON `{cliModel, cliComplexity, cliModelFor, positional}` | same shape with `null` / empty-string fields | — |
| `parse-findings.sh` | JSON `{counts, individual}` | same shape with zero counts and empty array | `[warn]` when counts non-zero but individual parse yields empty |
| `findings-decision.sh` | JSON `{action, reason, type, complexity}` | N/A (always an action) | — |
| `resolve-pr-number.sh` | bare integer PR number | empty stdout on exit 1 | `[warn]` on gh unavailable |
| `init-workflow.sh` | JSON `{id, type, complexity, issueRef}` | N/A (init always yields a full record) | downstream subcommand `[warn]` / `[info]` lines relayed |
| `check-resume-preconditions.sh` | JSON `{type, status, pauseReason, currentStep, chainTable, complexity, complexityStage}` | N/A (any state is a recognised response) | `[model]` upgrade line from `resume-recompute` relayed |
| `workflow-state.sh set-model-override` | empty | empty | `[info] modelOverride set to <tier> for <ID>` |

The `[info]` / `[warn]` / `[model]` lines are load-bearing structured logs and must not be stripped by the orchestrator's lite-narration rules.

## Non-Functional Requirements

### NFR-1: Graceful Degradation Preserved

- `resolve-pr-number.sh` (FR-4): `gh` missing / unauthenticated falls through to exit `1` with a `[warn]` line; the fallback is intentionally not a silent success because the orchestrator genuinely cannot `set-pr` without a number. This matches the existing prose behaviour (the orchestrator halts and surfaces the missing-PR condition to the user).
- `init-workflow.sh` (FR-5): `extract-issue-ref.sh` returning empty (no issue-reference section, or `managing-work-items` gracefully degrading on a missing `gh` / `jira` backend) is non-fatal — `issueRef` in the output JSON is an empty string, and the orchestrator's issue-tracking skip-behaviour logic already handles empty refs per `references/issue-tracking.md`.
- `check-resume-preconditions.sh` (FR-6): `resume-recompute` internally degrades gracefully when the requirement document is missing (retains the persisted complexity per FEAT-014 FR-12 NFR-5). This script is a pass-through; degradation behaviour is inherited.

### NFR-2: Consistent Exit-Code Conventions

All seven items follow the plugin-shared convention (per #179 "Conventions" and precedents FEAT-020 / FEAT-021 / FEAT-022 / FEAT-025 / FEAT-026 / FEAT-027):

- `0` = success OR intentional skip (graceful degradation).
- `1` = caller input problem that is **not** arg-shape (file not found, missing state file, malformed JSON input, unresolvable PR number).
- `2` = missing or malformed args (including unknown flags for FR-1, malformed tier strings for FR-1 / FR-7).

No script returns a custom code outside this set.

### NFR-3: Test Coverage

- Every new script ships a bats test fixture under `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/tests/` covering:
  - Valid inputs for each recognised case (each flag permutation for FR-1; each counts permutation × each Decision-Flow branch for FR-3; each PR-number resolution source for FR-4; each chain type for FR-5 and FR-6; each tier for FR-7).
  - Arg-validation failures (`2` exits) and file-not-found / state-missing failures (`1` exits).
  - Graceful-degradation paths: `gh` missing for FR-4; empty `issueRef` extraction for FR-5; missing-document retained-complexity path for FR-6.
  - Parser edge cases: FR-1 flag repetition (same flag twice, same-step overwrite for `--model-for`); FR-2 em-dash vs ASCII-dash fallback, bold vs unbold individual findings, test-plan mode prefix on the summary line, zero-findings and "No issues found" normalisations; FR-3 zero-counts edge case (should map to `action: "advance"` even though the flow's item 1 reads as a match-on-all-zeros).
- Item 9.8 extends `workflow-state.sh`. New `set-model-override` cases are added to the existing `scripts/__tests__/workflow-state.test.ts` vitest suite (matching the script's existing test framework — TypeScript/Vitest, not bats — for consistency with the rest of `workflow-state.sh`'s coverage): success each tier, malformed tier rejection (`2`), missing state file (`1`), downgrade permitted, idempotent repeat write.
- Test layout follows the FEAT-026 / FEAT-027 precedent: skill-scoped scripts under `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/tests/*.bats`. Plugin-shared tests (none here — all scripts are skill-scoped) would live under `plugins/lwndev-sdlc/scripts/tests/`.

### NFR-4: Token-Savings Measurement

Pre- and post-feature token counts on a representative feature workflow and a representative resume path are captured. The savings estimate (~1,500–2,500 tok/workflow, breakdown below) is carried forward from #179 item 9 totals minus the already-shipped 9.2 share (~4,000–6,000 tok):

| FR | Per-invocation | Invocations / workflow | Per-workflow |
|---:|---:|---:|---:|
| FR-1 (9.1) | ~200 | 1 | ~200 |
| FR-2 (9.3) | ~400–600 | 2–3 | ~800–1,800 |
| FR-3 (9.4) | ~300 | 2–3 | ~600–900 |
| FR-4 (9.5) | ~150 | 0–2 (chore / bug / future feature) | ~0–300 |
| FR-5 (9.6) | ~300 | 1 | ~300 |
| FR-6 (9.7) | ~400 | 0–1 (only on resume) | ~0–400 |
| FR-7 (9.8) | ~150 | 0–1 (only on manual override) | ~0–150 |

Post-feature target: the measured delta on a representative feature workflow (4 phases, no resume, one `reviewing-requirements` auto-advance gate, one PR creation) falls within ±30% of the estimate. Methodology mirrors FEAT-026 NFR-4 — paired runs, token counts pulled from Claude Code conversation state.

### NFR-5: Backwards-Compatible Skill Arguments

- The orchestrator's public invocation shape (`/orchestrating-workflows [--model <tier>] [--complexity <tier>] [--model-for <step>:<tier>] [<ID>|#<N>|<title>]`) is unchanged. FR-1 is a pure refactor of an internal parsing step; the user-visible flag set is identical.
- The fork-to-orchestrator return contract (documented in SKILL.md `## Output Style`) is unchanged. FR-2 / FR-3 consume the contract; they do not amend it.
- `workflow-state.sh` public subcommand list gains `set-model-override` (FR-7). No existing subcommand is removed, renamed, or re-shaped.
- `.sdlc/workflows/<ID>.json` schema is unchanged. FR-7 writes an existing field (`modelOverride`); FR-5 exercises existing subcommands; FR-6 reads existing fields.

### NFR-6: No New External Dependencies

- The scripts use `jq`, `git`, `gh`, and bash — all already required by the plugin. No new binaries are introduced.
- `jq` is the canonical JSON emitter for every stdout payload. FR-1 / FR-2 / FR-3 / FR-5 / FR-6 all declare `jq` in their top comment block. FR-4 emits a bare integer (no JSON). FR-7 emits nothing on stdout.

## Dependencies

- `workflow-state.sh` — existing; FR-3, FR-5, FR-6, and FR-7 compose over its subcommands (`status`, `init`, `classify-init`, `set-complexity`, `advance`, `resume-recompute`).
- `managing-work-items/scripts/extract-issue-ref.sh` — existing (FEAT-025); FR-5 invokes it. No version bump.
- `prepare-fork.sh` (FEAT-021) — adjacent, not a dependency. The seven scripts here are orthogonal to the pre-fork ceremony; they run before (FR-1, FR-5) or after (FR-2, FR-3, FR-4) forks, not during.
- FEAT-015 (findings-handling-spiral-fix) — algorithm source for FR-3's Decision Flow and the chore/bug auto-advance gate. No runtime call; FR-3 encapsulates the FEAT-015 gate semantics verbatim. Named here so reviewers can trace the three-way branch logic back to its authoritative spec.
- `gh` CLI — already required; FR-4 uses it as a fallback.
- `git` — already required; not directly invoked by these scripts but indirectly through `workflow-state.sh` subcommands.
- No cross-skill shared-matcher coordination (unlike FEAT-026's NFR-6). All seven items are internal to `orchestrating-workflows`.

## Edge Cases

1. **FR-1 `--model opus --model sonnet` (repeated blanket hard)**: last flag wins. `cliModel` = `"sonnet"`. Repetition is not an error; the user can override at the command line the same way they'd override any CLI flag.
2. **FR-1 `--model-for reviewing-requirements:opus --model-for reviewing-requirements:sonnet`**: last per-step entry wins for the same step. `cliModelFor` = `{"reviewing-requirements":"sonnet"}`.
3. **FR-1 positional token appears between flags** (`--model opus #186 --complexity high`): positional is recovered correctly — the parser is positional-independent.
4. **FR-1 two positional tokens** (`--model opus #186 FEAT-001`): exit `2`. The orchestrator expects at most one positional argument.
5. **FR-1 `--model=sonnet` (equals-sign form)**: exit `2`. The two-token form is the only supported shape.
6. **FR-2 subagent return with no summary line** (pure "No issues found" text): counts all zero, `individual` empty, exit `0`. Matches the flow's normalisation.
7. **FR-2 summary line with ASCII double-hyphen instead of em dash**: parser accepts both. `W1 category -- description` matches alongside `W1 category — description`.
8. **FR-2 test-plan-mode output with prefix** (`"Test-plan reconciliation for FEAT-028: Found **N errors**, ..."`): anchor-on-substring regex handles the prefix cleanly.
9. **FR-3 counts with errors > 0 AND warnings > 0**: `action` is `pause-errors`. Errors take precedence; warnings are surfaced inside the errors flow, not independently.
10. **FR-3 state file missing `complexity` field** (pre-FEAT-014 state file): the FR-13 migration inside `workflow-state.sh status` backfills `complexity = "medium"`. FR-3 reads the migrated value. If migration hasn't run yet (caller bypassed `status`), FR-3 exits `1` — callers must invoke `status` first (and the orchestrator's Resume Procedure already does).
11. **FR-4 subagent output contains `#123` inside a quoted code block** (e.g., "`#123` is an example"): the parser picks the **last** occurrence, which is the final PR number the executor prints at end-of-output. If the quoted example happens to be the only `#N` in the output, that's a caller bug (the executor failed to print its PR number) — the `gh pr list` fallback catches it.
12. **FR-4 `gh pr list` returns multiple OPEN PRs on the same branch** (possible if a prior run left a stale PR): the JQ filter picks the first. This is the documented behaviour from the existing prose.
13. **FR-5 artifact filename with a malformed prefix** (e.g., `requirements/features/FEAT-feature.md`): ID extraction regex fails, exit `1`. The `next-id.sh` script guarantees the correct shape for newly-created artifacts, so this exit is reserved for hand-edited paths.
14. **FR-5 invocation with a TYPE that doesn't match the filename prefix** (e.g., `init-workflow.sh chore requirements/features/FEAT-028-...md`): exit `1` with a `[warn]` line. The filename is the source of truth.
15. **FR-6 workflow in `complete` status**: exit `0` with `status: "complete"` and `pauseReason: null`. The orchestrator handles terminal states in main-context prose (not in scope for FR-6).
16. **FR-6 workflow in `failed` status**: exit `0` with `status: "failed"`. The orchestrator's retry dispatch in the Resume Procedure consumes this value and re-invokes the failed step. No special handling in the script.
17. **FR-7 downgrade** (`modelOverride` currently `opus`, call sets `sonnet`): the write succeeds. This is the intended escape-hatch path per FEAT-014 FR-12.
18. **FR-7 setting to current value** (`modelOverride` already `sonnet`, call sets `sonnet`): idempotent write, exit `0`. No `[warn]` — the operation is harmless.
19. **FR-7 tier is `low` / `medium` / `high`** (a label instead of a bare tier): exit `2`. `modelOverride` is stored as a bare tier; callers wanting label semantics should use `set-complexity` instead.
20. **FR-3 never called on `complexity == low` chore / bug chains**: `step-execution-details.md` specifies the CHORE-031 skip path for chore/bug step 2 — when persisted complexity is `low`, the orchestrator calls `advance` directly without spawning a `reviewing-requirements` fork or calling `record-findings`. `findings-decision.sh` is therefore unreachable in that state. The script's internal three-way branch for `type in {chore,bug} && complexity == low` still needs correct logic (counts → `auto-advance` per the gate) and bats coverage, because the branch is reachable **if the orchestrator ever loosens the skip condition** and the script must not regress in isolation. The bats coverage for this case validates the script's internal contract; the orchestrator's gating is verified separately via the step-execution-details prose.

## Testing Requirements

### Unit Tests

- One bats file per script under `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/tests/`:
  - `parse-model-flags.bats` — each flag (hard blanket / soft blanket / hard per-step); repetition; equals-sign rejection; two-positional rejection; unknown-flag rejection; interleaved positional.
  - `parse-findings.bats` — summary parsing (canonical / test-plan prefix / zero-findings / "No issues found"); individual parsing (em dash / ASCII dash / bold / unbold); counts-nonzero-individual-empty warn emission.
  - `findings-decision.bats` — zero findings; errors > 0; warnings-only feature chain; warnings-only chore chain at low/medium complexity; warnings-only chore chain at high complexity; warnings-only bug chain parallel to chore; missing state file; malformed counts.
  - `resolve-pr-number.bats` — subagent output with `#N`; subagent output with full URL; subagent output with multiple `#N` (last wins); subagent output empty + `gh pr list` success; subagent output empty + `gh pr list` empty; `gh` missing fallback warn; missing branch arg.
  - `init-workflow.bats` — each TYPE (feature / chore / bug); TYPE/filename-prefix mismatch; missing artifact; empty issueRef success path; `managing-work-items/extract-issue-ref.sh` returning `#N`.
  - `check-resume-preconditions.bats` — in-progress / paused (each of the three pauseReason values) / failed / complete; upgrade emission from `resume-recompute` relayed correctly; missing state file.
- Item 9.8 extensions under the existing `scripts/__tests__/workflow-state.test.ts` vitest suite — new cases for `set-model-override` (success each tier, downgrade, missing state, malformed tier, unknown subcommand regression guard).

### Integration Tests

- End-to-end `/orchestrating-workflows <title>` invocation on a test fixture that exercises:
  - FR-1 parsing with each supported flag shape and the positional token.
  - FR-5 `init-workflow.sh` composite invocation (one of the three chain types per run).
  - FR-2 + FR-3 in the `reviewing-requirements` step 2 fork — verify findings ingestion, Decision-Flow resolution, and `record-findings` write match the pre-feature behaviour on identical input.
  - FR-4 in the chore-chain step 4 executor fork — verify PR number extraction.
  - FR-6 in a resume path — pause at `plan-approval`, manually exit, re-invoke with the ID, verify the orchestrator consumes `check-resume-preconditions.sh` output correctly.
- Token-count measurement per NFR-4 on a representative feature workflow (no resume) and a representative resume path.

### Manual Testing

- Run a full feature workflow end-to-end against a fixture and visually diff the pre- and post-feature orchestrator output. Every `reviewing-requirements` fork's findings block should render identically; every state-file write should be structurally identical.
- Exercise FR-7 (`set-model-override`) manually between a paused workflow and its resume. Verify `check-resume-preconditions.sh` output reflects the expected tier on re-invocation and that the subsequent fork's `prepare-fork.sh` echo line shows the overridden tier.
- Deliberately break FR-4 by pointing it at a subagent output file lacking any `#N` token and with `gh pr list` returning empty — verify the orchestrator halts with a readable error and does not silently advance state.

## Acceptance Criteria

- [x] `parse-model-flags.sh` implements FR-1; strips the three flags positional-independently; emits the canonical JSON shape; bats tests pass.
- [x] `parse-findings.sh` implements FR-2; parses summary line with anchor-on-substring regex and individual findings with em-dash + ASCII-dash fallback; emits counts + individual JSON; bats tests pass.
- [x] `findings-decision.sh` implements FR-3; resolves the three-way Decision Flow including the chain-type + complexity gate; emits the `action`/`reason`/`type`/`complexity` JSON; bats tests pass.
- [x] `resolve-pr-number.sh` implements FR-4; subagent-output-first-with-last-match-wins + `gh pr list` fallback + `[warn]` on `gh` missing; emits bare integer; bats tests pass.
- [x] `init-workflow.sh` implements FR-5; composes `mkdir` + `workflow-state.sh init / classify-init / set-complexity / advance` + active-marker + `extract-issue-ref.sh`; emits `{id,type,complexity,issueRef}`; bats tests pass.
- [x] `check-resume-preconditions.sh` implements FR-6; pass-through over `workflow-state.sh status` + `resume-recompute`; emits the seven-field JSON and relays `[model]` upgrade lines; bats tests pass.
- [x] `workflow-state.sh set-model-override` implements FR-7 as a new subcommand; downgrade permitted; emits the `[info]` confirmation on stderr; vitest cases added to `scripts/__tests__/workflow-state.test.ts` pass.
- [x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` is updated per FR-8: `Model-Selection Flags` parsing-rules paragraph collapsed to a `parse-model-flags.sh` pointer; `Quick Start` steps 3–5 collapsed to an `init-workflow.sh` pointer.
- [x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/reviewing-requirements-flow.md` is updated per FR-8: `Parsing Findings` and `Parsing Individual Findings for auto-advanced Decisions` collapsed to `parse-findings.sh` pointers; `Decision Flow` collapsed to a `findings-decision.sh` pointer with a short `action`-to-orchestrator-behavior mapping retained.
- [x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/chain-procedures.md` is updated per FR-8: New Feature / Chore / Bug Workflow Procedures collapsed to `init-workflow.sh` pointers; Resume Procedure steps 1–5 collapsed to a `check-resume-preconditions.sh` pointer; step 6 prose retained.
- [x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/step-execution-details.md` is updated per FR-8: chore step 4 and bug step 4 PR-number extraction items collapsed to `resolve-pr-number.sh` pointers; feature-chain PR-Creation prose retained.
- [x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/model-selection.md` Migration Option 4b is updated per FR-8 to point at `workflow-state.sh set-model-override` instead of the raw `jq` edit.
- [x] No changes to orchestrator fork-invocation shape, findings-summary-line format, state-file schema, or cross-skill APIs (NFR-5 preserved).
- [x] FR-9 verified: no other skills or agents consume the new `orchestrating-workflows` scripts; `npm run validate` confirms closed-world change.
- [x] Integration test: a live feature workflow against a fixture produces orchestrator output identical to pre-feature on the same inputs (visual diff).
- [x] Token-savings measurement per NFR-4 confirms the estimate within ±30%.
- [x] `npm test` and `npm run validate` pass on the release branch.

## Completion

**Status:** `Complete`

**Completed:** 2026-04-25

**Pull Request:** [#233](https://github.com/lwndev/lwndev-marketplace/pull/233)
