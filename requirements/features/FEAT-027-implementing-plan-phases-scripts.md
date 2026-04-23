# Feature Requirements: `implementing-plan-phases` Scripts (Items 5.1, 5.2, 5.5–5.8)

## Overview
Collapse the deterministic prose inside `implementing-plan-phases` into six skill-scoped shell scripts plus a matching SKILL.md rewrite so every per-phase invocation replaces its Step 2 / Step 3 / Step 6 / Step 7 / Step 8 / Step 9 / Step 10 (pre-PR check) prose with a single script call. The plugin-shared foundation scripts `build-branch-name.sh` (item 5.3) and `ensure-branch.sh` (item 5.4) already exist in `plugins/lwndev-sdlc/scripts/` and are dependencies, not in scope here — they are referenced from Step 4 of the current SKILL.md and remain unchanged by this feature.

## Feature ID
`FEAT-027`

## GitHub Issue
[#185](https://github.com/lwndev/lwndev-marketplace/issues/185)

## Priority
Medium — ~1,500 tokens saved per phase × 4 phases typical = ~6,000 tokens per feature workflow. `implementing-plan-phases` is the highest mechanical-density skill per invocation (it runs `N` times per feature workflow, once per phase) but each invocation's prose is already well-factored, so the per-invocation savings are modest. The cumulative savings over a typical 4-phase feature workflow push it into the same band as FEAT-022's finalize subscripts. Item 5.2 (`plan-status-marker.sh`) alone appears at rank #5 in the #179 top-10 table because it fires twice per phase (start-of-phase "in-progress" + end-of-phase "complete"). The remaining prose (implementation content itself, TDD sequencing judgment, push-failure conflict resolution) carries the model-reasoning work and stays prose.

## User Story
As the orchestrator (or a user manually invoking `/implementing-plan-phases`) executing a phase from an implementation plan, I want the deterministic phase-selection, status-marker transitions, deliverable-checkoff, deliverable verification, commit-and-push, and pre-PR completion-check work to happen in single script calls so that ~1,500 tokens per phase spent restating plan-parsing / edit / `git` / `npm` mechanics are eliminated, the per-phase contract stays uniform across standalone and orchestrated invocations, and the reasoning work the skill is actually good at (writing the implementation, sequencing tests, resolving merge conflicts during push failures) stays in prose where it belongs.

## Command Syntax

All scripts live under `${CLAUDE_PLUGIN_ROOT}/skills/implementing-plan-phases/scripts/` and follow the plugin-shared conventions established by #179 and the precedent set by FEAT-020 / FEAT-021 / FEAT-022 / FEAT-025 / FEAT-026 (shell-first, exit-code driven, stdout carries JSON or pure string, stderr for `[info]` / `[warn]` / error lines, bats-tested).

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/implementing-plan-phases/scripts/next-pending-phase.sh" <plan-file>
bash "${CLAUDE_PLUGIN_ROOT}/skills/implementing-plan-phases/scripts/plan-status-marker.sh" <plan-file> <phase-N> <state>
bash "${CLAUDE_PLUGIN_ROOT}/skills/implementing-plan-phases/scripts/check-deliverable.sh" <plan-file> <phase-N> <idx-or-text>
bash "${CLAUDE_PLUGIN_ROOT}/skills/implementing-plan-phases/scripts/verify-phase-deliverables.sh" <plan-file> <phase-N>
bash "${CLAUDE_PLUGIN_ROOT}/skills/implementing-plan-phases/scripts/commit-and-push-phase.sh" <FEAT-ID> <phase-N> <phase-name>
bash "${CLAUDE_PLUGIN_ROOT}/skills/implementing-plan-phases/scripts/verify-all-phases-complete.sh" <plan-file>
```

### Examples

```bash
# Auto-select the next phase to implement
bash "${CLAUDE_PLUGIN_ROOT}/skills/implementing-plan-phases/scripts/next-pending-phase.sh" \
  requirements/implementation/FEAT-027-implementing-plan-phases-scripts.md
# stdout: {"phase":1,"name":"Directory Scaffold + Phase Selection + Status Marker"}

# Transition phase 1 to in-progress (handles the canonical three-state enum + emoji)
bash "${CLAUDE_PLUGIN_ROOT}/skills/implementing-plan-phases/scripts/plan-status-marker.sh" \
  requirements/implementation/FEAT-027-implementing-plan-phases-scripts.md 1 in-progress
# stdout: transitioned

# Check off the 2nd deliverable in phase 1 by index
bash "${CLAUDE_PLUGIN_ROOT}/skills/implementing-plan-phases/scripts/check-deliverable.sh" \
  requirements/implementation/FEAT-027-implementing-plan-phases-scripts.md 1 2
# stdout: checked

# Or check off by literal substring match
bash "${CLAUDE_PLUGIN_ROOT}/skills/implementing-plan-phases/scripts/check-deliverable.sh" \
  requirements/implementation/FEAT-027-implementing-plan-phases-scripts.md 1 "plan-status-marker.sh"
# stdout: checked

# Run composite verification (file existence + npm test / build / coverage)
bash "${CLAUDE_PLUGIN_ROOT}/skills/implementing-plan-phases/scripts/verify-phase-deliverables.sh" \
  requirements/implementation/FEAT-027-implementing-plan-phases-scripts.md 1
# stdout: {"files":{"ok":[...],"missing":[]},"test":"pass","build":"pass","coverage":"pass"}

# Stage / commit / push the phase with canonical commit message format
bash "${CLAUDE_PLUGIN_ROOT}/skills/implementing-plan-phases/scripts/commit-and-push-phase.sh" \
  FEAT-027 1 "scripts scaffold and status marker"
# stdout: pushed feat/FEAT-027-implementing-plan-phases-scripts

# Confirm every phase is complete before PR creation
bash "${CLAUDE_PLUGIN_ROOT}/skills/implementing-plan-phases/scripts/verify-all-phases-complete.sh" \
  requirements/implementation/FEAT-027-implementing-plan-phases-scripts.md
# stdout: all phases complete
```

## Functional Requirements

### FR-1: `next-pending-phase.sh` — Auto-Select Next Pending Phase
- Signature: `next-pending-phase.sh <plan-file>`.
- Exit `2` on missing arg; exit `1` on file not found / unreadable.
- Parse the plan document for every `### Phase <N>: <name>` block and each block's `**Status:**` line.
- Recognize three canonical states (accepting each exact form the current SKILL.md documents):
  - `Pending`
  - `🔄 In Progress` (the emoji is canonical per SKILL.md Phase Structure)
  - `✅ Complete`
- **Selection rule**: return the lowest-numbered phase whose status is `Pending` AND whose prerequisites are satisfied. Prerequisites are considered satisfied when every phase with a lower number is `✅ Complete`. This mirrors the existing SKILL.md Step 2 prose ("first phase with **Status: Pending** that has all prerequisites complete") using sequential ordering — the script does not build a full DAG from free-text "Depends on Phase N" rationale lines. If a plan contains explicit `**Depends on:** Phase <N>[, Phase <M>...]` lines adjacent to the Status line, the script additionally enforces those explicit dependencies; absence of the explicit line falls back to sequential ordering. This two-tier rule covers both the common case (simple sequential plans) and the rare case (plans that explicitly declare out-of-order dependencies).
- Emit one JSON object on stdout on success:
  ```json
  {"phase":<N>,"name":"<phase-name>"}
  ```
- **Special exit states** emitted on stdout with distinctive exit codes:
  - No pending phase, all phases complete → stdout `{"phase":null,"reason":"all-complete"}`, exit `0`.
  - No pending phase, a phase is currently `🔄 In Progress` (resumable state) → stdout `{"phase":<N>,"name":"<phase-name>","reason":"resume-in-progress"}`, exit `0`. Callers (the SKILL.md + orchestrator) treat this as "continue the in-progress phase".
  - A `Pending` phase exists but its prerequisites are not satisfied → stdout `{"phase":null,"reason":"blocked","blockedOn":[<N>,<M>,...]}`, exit `0`. The `blockedOn` array lists the numbers of the phases that must complete first. Callers surface this to the user as a prompt to implement the prerequisite phase first.
- Exit codes: `0` on any recognized outcome (happy path, all-complete, resume-in-progress, blocked); `1` on unreadable or malformed plan (no `### Phase` blocks, or a block without a `**Status:**` line); `2` on missing arg.
- Replaces `implementing-plan-phases/SKILL.md` Step 2 "Identify Target Phase" prose and the "Verify prerequisites" sub-bullet — ~200 tokens × 1 invocation = ~200 tokens per phase, ~800 tokens/feature workflow at N=4.

### FR-2: `plan-status-marker.sh` — Canonical Status Transition
- Signature: `plan-status-marker.sh <plan-file> <phase-N> <state>`.
- Exit `2` on any missing or malformed arg (`<phase-N>` must be a positive integer; `<state>` must be one of the three canonical tokens).
- Accept these canonical `<state>` tokens (case-sensitive):
  - `Pending` → writes `**Status:** Pending`
  - `in-progress` → writes `**Status:** 🔄 In Progress` (script emits the emoji; callers pass the ASCII token)
  - `complete` → writes `**Status:** ✅ Complete` (script emits the emoji)
- Target the `**Status:**` line inside the `### Phase <phase-N>:` block only. The block spans from its `### Phase <N>:` heading to the next `### Phase` heading (exclusive) or end-of-file.
- YAML-agnostic, regex-based — do not parse the full plan as YAML.
- Idempotent: if the target line already matches the requested state, emit `already set` on stdout and exit `0` without rewriting. This lets callers re-run the script safely across retries.
- CRLF-safe on read (follow the `tr -d '\r'` precedent from `check-acceptance.sh`), and preserve the file's original line endings on write (do not force Unix endings).
- Fence-aware: skip `**Status:**` lines inside fenced code blocks (opened by ```` ``` ```` / ```` ~~~ ````). This matters because the SKILL.md and the existing implementation plans include **example** `**Status:**` lines inside fenced blocks (documentation of the canonical format) — those must never be flipped by the script.
- Exit codes: `0` on successful transition (`transitioned`) or idempotent no-op (`already set`); `1` on plan not found or no matching phase block or no `**Status:**` line found inside the matched block; `2` on missing or malformed args.
- Replaces `implementing-plan-phases/SKILL.md` Step 3 (to `🔄 In Progress`) + Step 9 (to `✅ Complete`) prose. Called 2× per phase (start + end), so per-phase savings: ~200 tok × 2 = ~400 tok; per feature workflow at N=4: ~1,600 tok. This is the #5 entry in the #179 top-10 table.

### FR-3: `check-deliverable.sh` — Phase-Scoped Deliverable Checkoff
- Signature: `check-deliverable.sh <plan-file> <phase-N> <idx-or-text>`.
- Exit `3` on missing or malformed args; exit `1` on file not found / unreadable. (This script adopts `check-acceptance.sh`'s exit-code shape — `2` is reserved for ambiguous text matches and `3` for usage errors; see the detailed exit-codes paragraph below and NFR-2 for the full rationale.)
- Scope matching to the `### Phase <phase-N>:` block (same bounds as FR-2). Only `- [ ]` / `- [x]` lines inside this block — and outside fenced code blocks — are considered.
- **Enhancement over `check-acceptance.sh`** (plugin-shared, already landed): `check-acceptance.sh` matches against the whole document and takes only a text substring. `check-deliverable.sh` is phase-scoped and additionally accepts a 1-based numeric index as the `<idx-or-text>` arg.
- Dispatch heuristic on `<idx-or-text>`: if the arg matches `^[0-9]+$`, treat it as a 1-based index into the phase's deliverable list (counting both `- [ ]` and `- [x]` entries in document order, ignoring any nested unchecked-boxes-inside-other-sections within the phase block). If the arg contains any non-digit character, treat it as a literal substring matcher (identical semantics to `check-acceptance.sh`).
- Fence-aware: same fence-tracking logic as `check-acceptance.sh` (both ```` ``` ```` and ```` ~~~ ```` fences, toggle on first non-whitespace run).
- Idempotent: if the target line is already `- [x]`, emit `already checked` on stdout, exit `0`. If `- [ ]`, flip to `- [x]`, emit `checked`, exit `0`.
- **Out-of-scope index handling**: if `<idx-or-text>` is numeric but exceeds the count of deliverables in the phase block, emit `error: deliverable index <N> out of range (phase has <M> deliverables)` to stderr and exit `1`.
- **Text-matching ambiguity**: ambiguity is computed over `- [ ]` lines only — `- [x]` lines in the same phase block that also contain the substring are ignored for the ambiguity check. If exactly one `- [ ]` and any number of `- [x]` lines match, the script flips the single `- [ ]` and exits `0` (`checked`). If multiple `- [ ]` lines match, emit `error: ambiguous — <K> lines match` to stderr and exit `2`. If zero `- [ ]` lines and ≥ 1 `- [x]` lines match, emit `already checked` on stdout and exit `0` (idempotent). This matches `check-acceptance.sh`'s behavior exactly so callers that already reason about that sibling script's ambiguity semantics work unchanged.
- Exit codes (aligned with `check-acceptance.sh`'s precedent, not the `0` / `1` / `2` convention used by the rest of this feature — this script deliberately adopts the sibling script's exit-code shape so callers that already branch on `check-acceptance.sh`'s codes work unchanged): `0` on `checked` / `already checked`; `1` on file not found, no phase block, deliverable not found, or numeric index out of range; `2` on ambiguous text match; `3` on missing / malformed args (the "usage error" slot). NFR-2 documents the one-off for this script.
- Replaces `implementing-plan-phases/SKILL.md` Step 6 "check off each deliverable" prose — ~100 tokens × ~5 per phase = ~500 tokens per phase, ~2,000 tokens/feature workflow at N=4.

### FR-4: `verify-phase-deliverables.sh` — Composite Phase Verification
- Signature: `verify-phase-deliverables.sh <plan-file> <phase-N>`.
- Exit `2` on missing or malformed args; exit `1` on file not found / unreadable / no phase block matching.
- Parse the phase block's `#### Deliverables` subsection for every `- [ ]` / `- [x]` entry. Extract the deliverable path from the backticked token at the start of the entry (e.g., ``- [x] `src/foo.ts` - Description`` → `src/foo.ts`). Lines without a leading backticked path are treated as non-file deliverables (documentation, prose) and skipped from the file-existence check entirely — they are not listed under `files.ok` or `files.missing` on stdout. (See Edge Case 8 for the rationale and the recommended caller pattern for non-file deliverables.)
- Run the four checks the current SKILL.md Step 7 prescribes. Execute them **sequentially** in the documented order (file existence → `npm test` → `npm run build` → `npm run test:coverage`). Parallelization is explicitly out of scope for FEAT-027 because `npm test` and `npm run test:coverage` may share a Jest process and contend over reporter output; the simpler sequential shape matches the current SKILL.md prose exactly. A future enhancement may introduce a `--parallel` flag once the contention is characterized. The checks are:
  1. **File existence**: for each deliverable path, run `[ -e "$path" ]`. Classify as `ok` (exists) or `missing`. Emit both lists on stdout.
  2. **Tests**: `npm test`. Capture exit code + tail of output (last 50 lines) for inclusion in stdout JSON.
  3. **Build**: `npm run build`. Capture exit code + tail of output.
  4. **Coverage** (optional): if the plan's `## Testing Requirements` section or the phase block itself specifies a coverage threshold, run `npm run test:coverage` and capture result. Otherwise, emit `"coverage":"skipped"`. **Detection heuristic**: "specifies a coverage threshold" means either (a) the literal token `coverage` appears inside the Testing Requirements section or the phase block, OR (b) a percentage token matching `[0-9]+%` appears in either section. The detection is grep-style and intentionally loose — false positives emit an extra coverage run (harmless), false negatives emit `coverage:"skipped"` (also harmless, per the graceful-degradation design). Callers that need mandatory coverage enforcement should invoke `npm run test:coverage` themselves alongside FR-4.
- Emit one JSON object on stdout:
  ```json
  {
    "files": {"ok": ["path1","path2"], "missing": []},
    "test":    "pass" | "fail",
    "build":   "pass" | "fail",
    "coverage": "pass" | "fail" | "skipped",
    "output": {
      "test":     "<tail-of-stdout-if-fail>",
      "build":    "<tail-of-stdout-if-fail>",
      "coverage": "<tail-of-stdout-if-fail>"
    }
  }
  ```
  The `output` keys are only populated for failing checks; passing checks omit their tail to keep stdout compact. This matches the #179 spec "emits pass/fail per check".
- **Aggregate exit code**: `0` only if `files.missing` is empty AND `test` is `pass` AND `build` is `pass` AND `coverage` is `pass` or `skipped`. Otherwise exit `1`. This lets callers check a single exit code and only read the JSON when diagnosing which sub-check failed.
- **Graceful degradation**: if `npm` is not on `PATH`, emit `[warn] verify-phase-deliverables: npm not found; skipping test/build/coverage checks.` to stderr and emit `"test":"skipped","build":"skipped","coverage":"skipped"` on stdout. Exit code is still `0` only when `files.missing` is empty.
- Exit codes: `0` on all checks passing or gracefully skipped; `1` on any failing check; `2` on missing / malformed args.
- Replaces `implementing-plan-phases/SKILL.md` Step 7 prose (the four-check Run Tests / Build Project / Check Coverage / Verify Files Exist block) — ~300 tokens × 1 invocation per phase = ~300 tokens per phase, ~1,200 tokens/feature workflow at N=4.

### FR-5: `commit-and-push-phase.sh` — Phase Commit + Push with Canonical Format
- Signature: `commit-and-push-phase.sh <FEAT-ID> <phase-N> <phase-name>`.
- Exit `2` on missing or malformed args; the `<FEAT-ID>` must match `^(FEAT|CHORE|BUG)-[0-9]+$` (accepting bug / chore IDs too, since this script is skill-scoped to `implementing-plan-phases` but the commit-message format is identical across all three chains once this skill subsumes that prose). `<phase-N>` must be a positive integer (`^[1-9][0-9]*$`). `<phase-name>` must be a non-empty string — an empty or whitespace-only `<phase-name>` is a `2` exit with `error: <phase-name> must not be empty` on stderr; callers that genuinely want an unnamed phase can pass a single-character placeholder, but the canonical commit message format expects a human-readable name.
- Build the canonical commit message: `<type-prefix>(<ID>): complete phase <N> - <phase-name>`, where `<type-prefix>` is derived from the ID prefix (`FEAT-` → `feat`, `CHORE-` → `chore`, `BUG-` → `fix`). Example: `feat(FEAT-027): complete phase 1 - scripts scaffold and status marker`.
- Execution sequence (fails fast on any error):
  1. `git status --porcelain=v1` — if empty, emit `error: no changes to commit` to stderr and exit `1`. Phase commits should never be empty; this is the sanity gate.
  2. `git add -A` — stage all tracked and untracked changes. The skill currently documents both the specific-file and the `git add .` approaches; using `-A` is the orchestrator-safe default (it picks up renames correctly).
  3. `git commit -m "<canonical message>"` — fail fast on commit hook rejection (emit the hook's stderr verbatim per the lite-narration carve-out for error messages).
  4. Determine the current branch via `git rev-parse --abbrev-ref HEAD`. Determine whether the upstream is set via `git rev-parse --abbrev-ref --symbolic-full-name @{u}` (exit `0` means upstream set; non-zero means no upstream yet).
  5. `git push [-u origin <branch>]` — use `-u origin <branch>` only on the first push (when upstream is not yet set). Subsequent pushes use a bare `git push`.
  6. On push success, emit `pushed <branch>` on stdout and exit `0`.
- **Push-failure recovery is out of scope** — if `git push` exits non-zero for any reason (network, auth, rejected, etc.), the script emits `git push`'s stderr verbatim, emits `[error] push failed; see Push Failure Recovery in SKILL.md` to stderr, and exits `1`. Conflict resolution, authentication re-login, and rebase-against-remote remain model-judgment work per the "Stays prose" clause of #179. Callers MUST NOT auto-retry the script after a push failure — after resolving the conflict, invoke `git push` directly (re-running `commit-and-push-phase.sh` on a clean tree would trip the "no changes to commit" sanity gate at step 1). See Edge Case 11 for the full caller pattern.
- Exit codes: `0` on successful stage-commit-push; `1` on empty diff, commit failure, or push failure; `2` on missing / malformed args.
- Replaces `implementing-plan-phases/SKILL.md` Step 8 (Stage Changed Files, Commit with Phase-Traceable Message, Push to Remote) prose — ~300 tokens × 1 invocation per phase = ~300 tokens per phase, ~1,200 tokens/feature workflow at N=4.

### FR-6: `verify-all-phases-complete.sh` — Pre-PR Completion Check
- Signature: `verify-all-phases-complete.sh <plan-file>`.
- Exit `2` on missing arg; exit `1` on file not found / unreadable.
- Grep every `**Status:**` line in the plan (outside fenced code blocks — example status lines inside fences are ignored) and classify.
- Emit one of three outputs on stdout:
  - All phases `✅ Complete` → `all phases complete` + exit `0`.
  - Any phase in `🔄 In Progress` or `Pending` → JSON `{"incomplete":[{"phase":<N>,"name":"...","status":"Pending|in-progress"}]}` + exit `1`.
  - Plan contains zero `### Phase` blocks (malformed) → `[error] no phase blocks found in plan` to stderr + exit `1`.
- Exit codes: `0` only when every phase status is `✅ Complete`; `1` when any phase is non-complete or plan is malformed; `2` on missing arg.
- Replaces `implementing-plan-phases/SKILL.md` Step 10 pre-PR "Check All Phases Are Complete" prose — ~100 tokens × 1 invocation per feature workflow = ~100 tokens/feature workflow. Low absolute savings, but the script is a narrow one-liner so the cost of shipping it is low and it closes the last prose path in the skill's Step 10 block.

### FR-7: SKILL.md Prose Replacement
- Rewrite `plugins/lwndev-sdlc/skills/implementing-plan-phases/SKILL.md` to replace the mechanical prose in Step 2, Step 3, Step 6 (deliverable checkoff only — the TDD / Implementation / Code Organization prose stays), Step 7, Step 8, Step 9, and Step 10 (pre-PR check only — `gh pr create` via `create-pr.sh` already exists and is unchanged) with one-paragraph pointers at the corresponding scripts. The rewritten SKILL.md must retain:
  - The top-level `When to Use`, `Arguments`, `Quick Start`, `Output Style`, `Fork-to-orchestrator return contract`, `Workflow` checklist, `Phase Structure`, `Branch Naming`, `Verification`, and `References` sections — these are the skill contract and are unchanged.
  - Step 4 (Branch Strategy) prose — it already references `build-branch-name.sh` + `ensure-branch.sh` (plugin-shared, landed via FEAT-020 / FEAT-021 foundation work, not this feature).
  - Step 5 (Load Steps into Todos) prose — TodoWrite usage is not a script candidate.
  - The Test-Driven Development, Code Organization, Reusing Existing Code, and Following Code Organization prose inside the old Step 6 — these are model-reasoning concerns.
  - The "Push Failure Recovery" prose inside the old Step 8 — per FR-5, conflict resolution stays in prose.
- Rewrite `plugins/lwndev-sdlc/skills/implementing-plan-phases/references/step-details.md` in parallel: the same six steps' prose blocks collapse into script-pointer paragraphs with the same retention rules. The reference doc stays in sync with SKILL.md because it is the expanded form of the same material.
- **Correct a pre-existing mislabel in `step-details.md`** while rewriting Step 8: the current file's line 286 reads `**Important:** Do not proceed to **Step 10 (Update Plan Status)** until the push succeeds.` "Update Plan Status" is Step 9 — Step 10 is "Create Pull Request". The label must be corrected to `**Step 9 (Update Plan Status)**` as part of this feature's SKILL.md / references rewrite. This drift has been present since the Step 8 / Step 9 split and is not a FEAT-027 regression, but it lives inside prose the FEAT-027 rewrite touches, so fixing it is in scope.
- **Update the retained Push Failure Recovery prose** inside Step 8 to document the do-not-re-run-the-script caller pattern from Edge Case 11: after `commit-and-push-phase.sh` emits a push-failure error, the caller resolves the conflict (via the existing `git fetch origin` + `git rebase` + `git push` inline sequence documented in Push Failure Recovery) and then invokes `git push` directly — NOT via re-running the script, because the clean `git status` after resolution would trip the script's "no changes to commit" sanity gate. This is a new paragraph added to the retained Push Failure Recovery block, not a rewrite of the existing prose.
- Also update `plugins/lwndev-sdlc/skills/implementing-plan-phases/references/workflow-example.md` only where it demonstrates the mechanical prose — the walkthrough example itself stays intact, but any literal-prose recreation of Step 2 / 3 / 6 / 7 / 8 / 9 / 10 mechanics is replaced by a reference to the script. If the walkthrough does not touch those mechanical blocks, no edit is needed.
- Remove the following prose blocks (each now implemented by a FEAT-027 script):
  - Step 2 "Auto-select / Verify prerequisites / Extract metadata" — now FR-1.
  - Step 3 "Update Implementation Doc Status (**Change** / **To** / **Example edit**)" — now FR-2.
  - Step 6 "check off the deliverable in the implementation plan" sub-bullet — now FR-3 (the rest of Step 6 stays).
  - Step 7 "Run Tests / Build Project / Check Coverage / Verify Files Exist" — now FR-4.
  - Step 8 "Stage Changed Files / Commit with Phase-Traceable Message / Push to Remote" (keeping only Push Failure Recovery) — now FR-5.
  - Step 9 "Update Plan Status (**Change** / **To**)" — now FR-2 with `<state>=complete`.
  - Step 10 "Check All Phases Are Complete" sub-block — now FR-6. The rest of Step 10 (Create the Pull Request, PR title format) is unchanged because it already relies on `create-pr.sh`.
- Net SKILL.md size reduction target: ≥ 20% of current line count. The skill becomes a workflow-orchestration + implementation-judgment document; the scripts carry the deterministic work. (The reduction target is slightly lower than FEAT-026's 25% because the retained prose — TDD, code organization, push-failure recovery — is substantive; FEAT-026's retained prose was smaller per-step.)

### FR-8: Caller Updates
- The orchestrator's `implementing-plan-phases` fork invocations are unchanged — the orchestrator dispatches via `Agent` + SKILL.md prose, which now points at the scripts internally. No orchestrator edits required for FR-1 through FR-6.
- No other skills or agents are modified by this feature — the scripts are a drop-in replacement for what `implementing-plan-phases` already did inline.
- The existing plugin-shared scripts `build-branch-name.sh`, `ensure-branch.sh`, `check-acceptance.sh`, `create-pr.sh`, `resolve-requirement-doc.sh`, `slugify.sh`, `next-id.sh`, `branch-id-parse.sh`, `prepare-fork.sh`, and `commit-work.sh` are untouched. `check-deliverable.sh` (FR-3) is a sibling to `check-acceptance.sh`, not a replacement — the existing plugin-shared script remains the correct choice for non-phase-scoped checkoff in `executing-chores` / `executing-bug-fixes` / `finalizing-workflow`.

## Output Format

Per-script output contracts are specified in each FR. Summarized for quick reference:

| Script | Stdout (success) | Stdout (special / skip) | Stderr |
|--------|-------------------|--------------------------|--------|
| `next-pending-phase.sh` | JSON `{phase, name}` | JSON `{phase:null, reason}` for all-complete / blocked; JSON `{phase, name, reason:"resume-in-progress"}` for in-progress | `[error]` on malformed plan |
| `plan-status-marker.sh` | `transitioned` | `already set` (idempotent) | `[error]` on no matching phase |
| `check-deliverable.sh` | `checked` | `already checked` (idempotent) | `[error]` on ambiguous / not found |
| `verify-phase-deliverables.sh` | JSON `{files, test, build, coverage, output?}` | `coverage:"skipped"` when not specified; `test/build/coverage:"skipped"` when `npm` missing | `[warn]` on `npm` missing |
| `commit-and-push-phase.sh` | `pushed <branch>` | — | `[error]` on empty diff / commit hook failure / push failure (with underlying `git` stderr) |
| `verify-all-phases-complete.sh` | `all phases complete` | JSON `{incomplete:[...]}` on any non-complete phase | `[error]` on no phase blocks |

The `[info]` / `[warn]` / `[error]` stderr lines are load-bearing structured logs and must not be stripped by the orchestrator's lite-narration rules.

## Non-Functional Requirements

### NFR-1: Graceful Degradation Preserved
- `verify-phase-deliverables.sh` (FR-4) gracefully skips `npm`-based checks when `npm` is missing, emitting `[warn]` and marking those checks `skipped`. File-existence checks still run; the overall exit code is `0` only when `files.missing` is empty.
- `commit-and-push-phase.sh` (FR-5) does NOT gracefully skip push failures — those are hard errors, matching the current SKILL.md contract ("Do not proceed to Step 10 until the push succeeds"). The orchestrator's forked-step contract preserves this: a push failure surfaces as a `failed |` return line to the parent orchestrator, which pauses the workflow.
- The remaining scripts (FR-1, FR-2, FR-3, FR-6) touch only the plan document — no external dependencies that can fail gracefully.

### NFR-2: Consistent Exit-Code Conventions
All six scripts follow the plugin-shared convention (per #179 "Conventions" section and the precedent set by FEAT-020 / FEAT-021 / FEAT-022 / FEAT-025 / FEAT-026):
- `0` = success OR idempotent no-op OR intentional skip (graceful degradation).
- `1` = caller input problem that is not arg-shape (file not found, plan malformed, deliverable not found, push failed, etc.).
- `2` = missing or malformed args.

**Exception**: `check-deliverable.sh` (FR-3) deliberately adopts the exit-code shape of its sibling `check-acceptance.sh` rather than the generic convention — `2` = ambiguous text match, `3` = missing / malformed args. The rationale is that `check-deliverable.sh` is a drop-in sibling of an existing plugin-shared script; diverging on exit codes would silently break any caller that already branches on `check-acceptance.sh`'s codes (currently none inside this plugin, but the invariant matters for the plugin-shared script pair). All other FEAT-027 scripts follow the generic convention.

No script returns a custom code outside these two conventions.

### NFR-3: Test Coverage
- Every script ships a bats test fixture under `plugins/lwndev-sdlc/skills/implementing-plan-phases/scripts/tests/` covering:
  - Valid inputs for each recognized case (every selection outcome in FR-1; every state in FR-2; index and text matching in FR-3; each sub-check outcome in FR-4; clean and dirty-tree commits in FR-5; all-complete and incomplete plans in FR-6).
  - Arg-validation failures (`2` exits) and file-not-found failures (`1` exits).
  - Idempotent-no-op paths for FR-2 and FR-3.
  - Graceful-degradation path for FR-4 (`npm` absent via `PATH` manipulation inside the bats fixture). Follow the pattern established by `plugins/lwndev-sdlc/skills/reviewing-requirements/scripts/tests/verify-references.bats` (FEAT-026) for `gh`-absence testing: a per-test `setup()` creates a fixture-local `STUB_DIR` (e.g., `STUB_DIR="${FIXTURE_DIR}/stubs"` where `FIXTURE_DIR="$(mktemp -d)"` — fixture-local, NOT `$BATS_TMPDIR`) populated with no `npm` binary. Each `run` invocation passes the stub-prefixed PATH inline (e.g., `PATH="${STUB_DIR}:${PATH}" run bash "$SCRIPT" ...`); this isolates PATH per-invocation via subshell so the parent shell's PATH is never mutated. A matching `teardown()` deletes `FIXTURE_DIR` (no explicit `PATH` save/restore is needed because PATH was never mutated in the parent shell). Mirror the exact hook names and invocation shape from that file rather than re-deriving them — deviation has previously caused bats-fixture-setup bugs in this plugin.
  - Edge-case inputs: plan with no `### Phase` blocks, phase block with no `**Status:**` line, phase block with `**Status:**` lines nested inside fenced code blocks, deliverable without a backticked path prefix, plan with a `**Depends on:**` line for FR-1.
  - **Fence-awareness**: at least one bats fixture per fence-sensitive script (FR-2, FR-3, FR-6) includes a fenced code block containing example `**Status:**` / `- [ ]` lines that MUST NOT be touched.
- Test layout follows the existing precedent: skill-scoped scripts live in `plugins/lwndev-sdlc/skills/implementing-plan-phases/scripts/tests/`, plugin-shared scripts in `plugins/lwndev-sdlc/scripts/tests/`.

### NFR-4: Token Savings Measurement
- Pre- and post-feature token counts on a representative 4-phase feature workflow are captured. The savings figure (~6,000 tokens/feature workflow at N=4, breakdown: ~800 from FR-1, ~1,600 from FR-2, ~2,000 from FR-3, ~1,200 from FR-4, ~1,200 from FR-5, ~100 from FR-6 = ~6,900 total; absorb the gap into the #179 "~1,500 tok/phase" estimate's tolerance) is an estimate carried forward from #179 and #185. Post-feature the target is to confirm the measured delta falls within ±30% of the estimate. Methodology: paired workflow runs before/after the feature lands, token counts pulled from the Claude Code conversation state (same methodology as FEAT-022 NFR-5 and FEAT-025 NFR-4 and FEAT-026 NFR-4).

### NFR-5: Backwards-Compatible Skill Arguments
- The `implementing-plan-phases` skill's public invocation shape (`/implementing-plan-phases <plan-file> [phase-number]`) is unchanged. The SKILL.md is the public contract; the scripts are the implementation.
- The skill's fork-to-orchestrator return contract (`done | artifact=<path> | <note>` / `failed | <reason>`) is unchanged. Scripts do not emit this line — the SKILL.md prose still composes it from the script outputs, and the orchestrator's parser is untouched.
- The skill's standalone-invocation behavior (when a user runs `/implementing-plan-phases` directly, not via the orchestrator) is preserved: Step 10 (Create Pull Request) still runs in the standalone path. The orchestrator's "skip Step 10" carve-out in the fork prompt (documented in the current SKILL.md) is unchanged.

### NFR-6: Script Location and Discoverability
- All six scripts live under `plugins/lwndev-sdlc/skills/implementing-plan-phases/scripts/`. This is a new subdirectory (the skill currently has no `scripts/` directory of its own — all scripts it invokes are plugin-shared under `plugins/lwndev-sdlc/scripts/`).
- Bats fixtures live under `plugins/lwndev-sdlc/skills/implementing-plan-phases/scripts/tests/` alongside any fixture subdirectories the tests need (e.g., `scripts/tests/fixtures/minimal-plan.md`).
- Scripts are executable (`chmod +x`) and begin with `#!/usr/bin/env bash` + `set -euo pipefail`.
- Each script has a top-of-file comment block documenting its purpose, signature, exit codes, and any optional dependencies (`jq` where applicable), following the `check-acceptance.sh` precedent.

## Dependencies

- `build-branch-name.sh` + `ensure-branch.sh` (plugin-shared) — already landed with the foundation work; not in scope for FEAT-027. Used by `implementing-plan-phases/SKILL.md` Step 4 (Branch Strategy), which is unchanged by this feature.
- `check-acceptance.sh` (plugin-shared) — already landed. Sibling to FR-3's `check-deliverable.sh`. The existing script is not modified; it remains the correct choice for non-phase-scoped checkoff in other skills.
- `create-pr.sh` (plugin-shared) — already landed. Called by Step 10 of the current SKILL.md. Unchanged by this feature.
- `resolve-requirement-doc.sh` (plugin-shared) — already landed via FEAT-020 (#180, closed). Used by SKILL.md Step 1 (Locate Implementation Plan). Unchanged.
- `gh` CLI — already required as a general plugin dependency. Not used directly by any FEAT-027 script — the PR-creation and issue-fetch paths go through `create-pr.sh` and `managing-work-items` respectively.
- `git` — already required. Used by FR-5 (`git add / commit / push / status / rev-parse`).
- `npm` — already required as a project dependency. Used by FR-4 (`npm test / build / test:coverage`). Gracefully degrades per NFR-1 if missing.
- `jq` — optional. Precedent: `prepare-fork.sh` uses `jq`; `check-acceptance.sh` is pure bash. FR-1, FR-4, FR-6 will lean on `jq` for JSON assembly; declare it as optional in each script's top comment block.
- `awk`, `sed`, `grep`, `tr` — POSIX baseline, available on every supported platform.

## Edge Cases

1. **Empty `<plan-file>` arg**: every script exits `2` with a usage error on stderr. The plan path is the public contract; callers supplying empty strings are arg bugs.
2. **`<plan-file>` points at a non-implementation-plan document** (e.g., a random markdown file): FR-1 / FR-6 exit `1` if no `### Phase` blocks are found. FR-2 / FR-3 / FR-4 exit `1` if no phase block matches the supplied `<phase-N>`. No heuristic check that the file is actually an implementation plan.
3. **Phase number exceeds plan's phase count**: FR-2 / FR-3 / FR-4 exit `1` with `error: no phase <N> in plan`. Callers (the SKILL.md) surface this to the user as a phase-selection prompt, mirroring the existing "display available phases and ask the user to choose" prose.
4. **Plan with a phase block that has no `**Status:**` line** (malformed): FR-1 exits `1` with `[error] phase <N> has no **Status:** line`. FR-2 exits `1` with the same error when that phase is targeted. A malformed plan is a pre-FEAT-027 drift issue and should be surfaced, not silently skipped.
5. **`**Status:**` line appearing inside a fenced code block only** (documentation, not a real phase status): FR-1 / FR-2 / FR-6 treat the block as if it had no status — they skip fenced content. If this leaves a phase without a real status, FR-1 exits `1` as in edge case 4.
6. **Dependency declared on a phase whose number is higher** (forward dependency, circular or out-of-order): FR-1's explicit-dependency layer flags the phase as `blocked` in stdout JSON. Callers surface the blocked state to the user; the script does not attempt to resolve circular dependencies.
7. **Multiple `### Phase <N>:` headings with the same number** (duplicate, malformed): FR-1 / FR-2 / FR-3 / FR-4 target the first occurrence. `[warn] duplicate phase <N> detected; using first occurrence` is emitted to stderr. Callers should surface the warning and/or deduplicate the plan.
8. **Phase block's deliverables list contains a non-file entry** (prose, not a backticked path): FR-4 skips the entry from the file-existence check entirely — it is not listed under `files.ok` or `files.missing`. The entry remains checkable via FR-3 text matching. The FR-4 JSON output is therefore narrower than the phase's deliverable count when non-file entries are present; callers that need a full deliverable-count sanity check should additionally parse the phase block themselves. (No `files.total` is emitted.)
9. **Deliverable path with spaces or special characters**: FR-3 accepts any literal substring (no regex special-character interpretation). FR-4 uses `[ -e "$path" ]` with quoted expansion, so paths with spaces are handled correctly.
10. **`git status` reports no changes before Step 8 commit** (e.g., the phase's implementation was a no-op or already committed by an earlier run): FR-5 exits `1` with `error: no changes to commit`. Callers decide whether to treat this as a genuine error (phase mistakenly marked done) or to skip the commit and proceed (phase re-run with no new work). The current SKILL.md does not handle this case explicitly; FR-5's fail-fast behavior is a strict interpretation of Step 8's "Always commit and push" contract.
11. **`git push` rejected because remote has new commits**: FR-5 exits `1` with `git`'s stderr verbatim. Callers surface the conflict to the user. **Required caller pattern** (do NOT re-run the script): resolve the conflict outside the script via `git fetch origin` + `git rebase origin/<branch>`, then invoke `git push` directly. Re-running `commit-and-push-phase.sh` is NOT safe after resolution — the script's step-1 sanity gate (`git status --porcelain=v1` empty → `error: no changes to commit`) will trip on a clean tree and exit `1` without pushing. FR-7 requires this pattern be documented in the retained Push Failure Recovery prose of SKILL.md Step 8.
12. **`npm test` or `npm run build` hangs indefinitely** (e.g., a test process that never exits): FR-4 runs these commands in the foreground and will hang with them. There is no built-in timeout. Callers that need a timeout should invoke the script inside `timeout <Nm>`. This matches the current SKILL.md behavior (the prose also runs `npm test` without a timeout). Adding a timeout flag is a Future Enhancement.
13. **`verify-all-phases-complete.sh` called on a plan mid-workflow** (Phase 1 ✅ Complete, Phase 2 🔄 In Progress, Phase 3 Pending): emits JSON `{"incomplete":[{"phase":2,"name":"...","status":"in-progress"},{"phase":3,"name":"...","status":"Pending"}]}` + exit `1`. Callers (the SKILL.md Step 10) pause PR creation.
14. **Plan with fenced `Status:` lines inside `workflow-example.md`-style embedded examples**: since the plan document is the actual `.md` file in `requirements/implementation/`, not a walkthrough reference, this edge case is unlikely in practice but is covered by the fence-awareness requirement in FR-2 / FR-3 / FR-6.

## Testing Requirements

### Unit Tests
- One bats file per script under `plugins/lwndev-sdlc/skills/implementing-plan-phases/scripts/tests/`. Each covers:
  - All valid input classes enumerated in the script's FR.
  - Every documented exit code (`0` success, `0` idempotent-no-op, `0` graceful-skip, `1` where applicable, `2` arg errors for FR-1 / FR-2 / FR-4 / FR-5 / FR-6; `2` ambiguous + `3` arg errors for FR-3 per the NFR-2 exception).
  - Fence-awareness (FR-2, FR-3, FR-6): fixture with `**Status:**` / `- [ ]` lines inside a fenced block that MUST NOT be flipped.
  - Idempotent-no-op paths (FR-2, FR-3).
  - Graceful-degradation path (FR-4: `npm` absent).
  - Edge cases: plan with no `### Phase` blocks, phase with no `**Status:**` line, phase block with `**Status:**` in a nested section, `**Depends on:**` line, duplicate phase numbers.
- Fixture layout: `scripts/tests/fixtures/minimal-plan.md`, `scripts/tests/fixtures/multi-phase-plan.md`, `scripts/tests/fixtures/fenced-status-plan.md`, etc.

### Integration Tests
- End-to-end invocation of `/implementing-plan-phases FEAT-027 1` against a fixture plan. Verify:
  - FR-1 auto-selects the correct phase (or the explicit phase-1 arg overrides it).
  - FR-2 transitions the phase to `🔄 In Progress`.
  - FR-3 flips each deliverable to `- [x]` as the phase proceeds.
  - FR-4 reports all checks passing on the fixture.
  - FR-5 produces a commit with the canonical message format and pushes to a test remote.
  - FR-2 transitions the phase to `✅ Complete`.
- End-to-end invocation of the final phase, confirming FR-6 gates PR creation on all-complete status. PR creation itself continues to go through `create-pr.sh` (unchanged).
- Token-count measurement per NFR-4 on a representative 4-phase feature workflow.

### Manual Testing
- Run a full feature workflow end-to-end (`/orchestrating-workflows #<issue>`) against a feature whose plan has ≥ 4 phases. Confirm every fork invocation of `implementing-plan-phases` produces artifacts identical to the pre-feature run. A visual diff of one pre- and one post-feature workflow's phase-1 output on the same plan is the acceptance gate.
- Manually invoke `/implementing-plan-phases <plan-file> <phase-number>` in standalone mode (not via the orchestrator). Confirm Step 10 (Create Pull Request) still runs after the final phase, since the orchestrator's "skip Step 10" carve-out does not apply in standalone mode.
- Exercise push-failure recovery: force a rejected push (push a conflicting commit to the remote from another branch), invoke the skill, observe FR-5 fail fast with `git`'s stderr surfaced. Resolve the conflict via `git fetch origin` + `git rebase origin/<branch>`, then invoke `git push` directly (NOT via re-running the skill — a clean tree would trip the FR-5 step-1 "no changes to commit" sanity gate). Observe successful completion after the direct push.

## Future Enhancements
- **Timeout flag for FR-4**: add `--timeout <N>` to `verify-phase-deliverables.sh` so long-running `npm test` runs can be bounded. Not in scope for FEAT-027 — the current SKILL.md behavior also has no timeout, so deferring does not regress behavior.
- **Configurable commit-message format for FR-5**: some projects may want `chore(FEAT-027): ...` or `refactor(FEAT-027): ...` instead of the default `feat(...)` prefix. Not in scope — the current SKILL.md hardcodes `feat(...)` (and `chore(...)` / `fix(...)` for the sibling executing-* skills), so deferring matches existing behavior. The `<FEAT-ID>` prefix-based dispatch in FR-5 already covers the `feat|chore|fix` variants; only custom prefixes beyond those three are deferred.
- **Shared matcher with `executing-chores` / `executing-bug-fixes`**: the phase-scoped deliverable-checkoff logic in FR-3 overlaps with the acceptance-criteria checkoff logic in the sibling executing-* skills. #179 item 6.4 already extracts the shared non-phase-scoped form as `check-acceptance.sh` (landed). If phase-scoped checkoff turns out to be useful in other executing-* contexts, the implementation can be factored into a `lib/scope-aware-checkbox.sh` sourced by both. Not in scope for FEAT-027 — speculative abstraction.

## Acceptance Criteria

- [ ] `next-pending-phase.sh` implements FR-1; handles the four selection outcomes (happy path, all-complete, resume-in-progress, blocked); parses both sequential and explicit `**Depends on:**` dependency forms; bats tests pass.
- [ ] `plan-status-marker.sh` implements FR-2; handles the three canonical states with emoji emission; idempotent no-op path emits `already set`; fence-aware; bats tests pass.
- [ ] `check-deliverable.sh` implements FR-3; phase-scoped; accepts both numeric index and literal substring matcher; idempotent; fence-aware; exit-code shape matches `check-acceptance.sh` (`2`=ambiguous, `3`=missing-arg); bats tests pass.
- [ ] `verify-phase-deliverables.sh` implements FR-4; runs file-existence + npm test + npm run build + npm run test:coverage (optional); aggregates into single exit code; gracefully degrades when `npm` is missing; bats tests pass.
- [ ] `commit-and-push-phase.sh` implements FR-5; produces canonical commit message format; handles first-push vs subsequent-push upstream set logic; fails fast on push error with `git` stderr surfaced verbatim; bats tests pass.
- [ ] `verify-all-phases-complete.sh` implements FR-6; emits `all phases complete` on success or JSON `{incomplete:[...]}` on any non-complete phase; fence-aware; bats tests pass.
- [ ] `plugins/lwndev-sdlc/skills/implementing-plan-phases/SKILL.md` is rewritten per FR-7; public contract (When to Use, Arguments, Quick Start, Output Style, Fork-to-orchestrator return contract, Workflow, Phase Structure, Branch Naming, Verification, References) retained; Steps 2 / 3 / 6-checkoff-sub / 7 / 8-commit-push / 9 / 10-check bodies replaced with script pointers; net line-count reduction ≥ 20%.
- [ ] `plugins/lwndev-sdlc/skills/implementing-plan-phases/references/step-details.md` is updated to match the SKILL.md rewrite (same retention rules, same script pointers). The pre-existing mislabel on the current file's line 286 (`**Step 10 (Update Plan Status)**` → `**Step 9 (Update Plan Status)**`) is corrected. The retained Push Failure Recovery prose documents the do-not-re-run-the-script caller pattern from Edge Case 11.
- [ ] FR-8 is satisfied: no changes to orchestrator fork-invocation shape; no other skill files modified; `plugins/lwndev-sdlc/scripts/` directory unchanged.
- [ ] No changes to the skill's fork-to-orchestrator return contract (NFR-5 preserved).
- [ ] Integration test: a live feature workflow against a fixture plan produces artifacts identical to pre-feature (visual diff on phase-1 output).
- [ ] Token-savings measurement per NFR-4 confirms the estimate within ±30%.
- [ ] `npm test` and `npm run validate` pass on the release branch.
