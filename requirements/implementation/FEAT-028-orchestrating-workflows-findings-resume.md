# Implementation Plan: `orchestrating-workflows` Findings / Resume / Remainder Scripts (FEAT-028)

## Overview

Collapse the remaining orchestrator prose hot-spots into seven skill-scoped helpers plus one new subcommand on the existing `workflow-state.sh`. FEAT-021 already shipped `prepare-fork.sh` (item 9.2 — the dominant contributor); this feature closes the remaining items: argv parsing (FR-1), findings ingestion (FR-2), Decision-Flow resolution (FR-3), post-fork PR-number extraction (FR-4), workflow init composite (FR-5), resume gate (FR-6), `modelOverride` persistence (FR-7), prose replacement in SKILL.md + four reference docs (FR-8), and caller audit (FR-9).

All six new scripts land under `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/` (the `tests/` subdirectory is new — the skill currently has only `stop-hook.sh` and `workflow-state.sh` at that level). `workflow-state.sh` gains one new subcommand. Tests for the six new scripts are bats fixtures under `scripts/tests/`; the `set-model-override` extension is covered by new cases in the existing `scripts/__tests__/workflow-state.test.ts` vitest suite.

The plan follows the four-layer sequencing proven by FEAT-025 / FEAT-026 / FEAT-027: pure scripts without external tool dependencies first, composite scripts with `workflow-state.sh` and `gh` dependencies next, the `workflow-state.sh` subcommand extension isolated in its own phase (different test framework), and the SKILL.md + references cutover last. Every script ships with its bats fixture in the same phase — tests are never deferred.

## Features Summary

| Feature ID | GitHub Issue | Feature Document | Priority | Complexity | Status |
|------------|--------------|------------------|----------|------------|--------|
| FEAT-028 | [#186](https://github.com/lwndev/lwndev-marketplace/issues/186) | [FEAT-028-orchestrating-workflows-findings-resume.md](../features/FEAT-028-orchestrating-workflows-findings-resume.md) | Medium | Medium | Pending |

## Recommended Build Sequence

### Phase 1: Directory Scaffold + Pure Parsing Scripts — `parse-model-flags.sh` (FR-1), `parse-findings.sh` (FR-2)

**Feature:** [FEAT-028](../features/FEAT-028-orchestrating-workflows-findings-resume.md) | [#186](https://github.com/lwndev/lwndev-marketplace/issues/186)
**Status:** ✅ Complete

#### Rationale

`parse-model-flags.sh` and `parse-findings.sh` are the cheapest wins in the feature: both are pure parsing scripts that operate on argv / file text only, with no calls to `workflow-state.sh`, `gh`, or any other external state. They have no inter-script dependencies and can be implemented and fully tested in parallel.

Grouping them in Phase 1 for four reasons:

1. **Creates `scripts/tests/` and `scripts/tests/fixtures/`** — the subdirectories that all later phases require. Currently `scripts/` holds only `stop-hook.sh` and `workflow-state.sh` with no test infrastructure. Phase 1 establishes the bats scaffold that Phases 2–3 extend.
2. **Highest per-effort token savings**: FR-1 saves ~200 tok × 1/workflow (small but always present); FR-2 saves ~400–600 tok × 2–3 reviewing-requirements forks per workflow — the second-highest per-FR contributor after FR-3. Landing both in Phase 1 means Phase 2's `findings-decision.sh` can immediately consume FR-2's stable JSON shape without a separate interface-stabilisation phase.
3. **No stub infrastructure needed**: both scripts operate on static inputs (argv for FR-1; a text file for FR-2), so bats tests are straightforward with no PATH-shadowing stubs.
4. **Locks the `{counts, individual}` JSON contract** that FR-3 (`findings-decision.sh`) in Phase 2 consumes from the `counts` field. Locking this before Phase 2 implementation eliminates the risk of interface drift between the emitter and consumer.

#### Implementation Steps

1. Create the new directories:
   - `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/tests/`
   - `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/tests/fixtures/`

2. Write `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/parse-model-flags.sh`:
   - Shebang `#!/usr/bin/env bash`; `set -euo pipefail`.
   - Top-of-file comment: purpose, signature (`parse-model-flags.sh "$@"`), exit codes, `jq` optional.
   - Signature: accepts the orchestrator's full argv list. Iterate positional-independently.
   - Strip three recognised FEAT-014 FR-8 flags:
     - `--model <tier>` — bare tier `haiku` / `sonnet` / `opus` only; other values exit `2`.
     - `--complexity <tier>` — accepts `haiku` / `sonnet` / `opus` OR `low` / `medium` / `high` (map `low→haiku`, `medium→sonnet`, `high→opus`); store normalised bare tier.
     - `--model-for <step>:<tier>` — step is any non-empty string; tier validated same as `--model`; flag may repeat; later entries overwrite earlier for same step.
   - `=`-form (e.g., `--model=sonnet`) exits `2`.
   - Unknown flags exit `2`. Flag missing its argument exits `2`.
   - Two surviving positional tokens exit `2`.
   - Emit one JSON object on stdout with all four fields always present:
     ```json
     {"cliModel":"sonnet|null","cliComplexity":"sonnet|null","cliModelFor":{"step":"tier"}|null,"positional":"<token-or-empty-string>"}
     ```
   - Use `jq` for JSON assembly when available; pure-bash `printf` fallback.
   - `chmod +x`.

3. Write `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/parse-findings.sh`:
   - Shebang `#!/usr/bin/env bash`; `set -euo pipefail`.
   - Top-of-file comment: purpose, signature (`parse-findings.sh <subagent-output-file>`), exit codes, `jq` optional.
   - Exit `2` on missing arg; exit `1` on file-not-found / unreadable.
   - Scan for the canonical summary line using anchor-on-substring regex: `Found \*\*[0-9]+\*\* errors.*\*\*[0-9]+\*\* warnings.*\*\*[0-9]+\*\* info`. Test-plan mode's prefix is handled because the anchor is not line-start.
   - Zero-findings / "No issues found" normalization: if no summary line, emit `{"errors":0,"warnings":0,"info":0}` for counts.
   - Scan for individual findings matching: `\*?\*?\[([WI][0-9]+)\] ([^—–-]+)[—–-]+(.+)\*?\*?` (em dash preferred, ASCII `--` accepted, bold markers optional).
     - `id` — e.g., `"W1"`, `"I3"`.
     - `severity` — `"warning"` for `W`, `"info"` for `I`.
     - `category` — text between `]` and dash, trimmed.
     - `description` — text after dash to end-of-line, trimmed, trailing bold markers stripped.
   - Emit one JSON object on stdout:
     ```json
     {"counts":{"errors":0,"warnings":0,"info":0},"individual":[{"id":"W1","severity":"warning","category":"...","description":"..."}]}
     ```
   - Emit `[warn] parse-findings: counts non-zero but no individual findings parsed — recording counts only.` to stderr when `counts.warnings + counts.info > 0` and `individual` is empty. Do NOT emit when only `counts.errors > 0` (errors are not parsed into `individual[]`).
   - Exit codes: `0` success; `1` file-not-found / unreadable; `2` missing arg.
   - Use `jq` for JSON assembly when available; pure-bash fallback.
   - `chmod +x`.

4. Create fixture files for bats tests:
   - `scripts/tests/fixtures/rr-output-zero-findings.txt` — reviewing-requirements output with "No issues found" and no summary line.
   - `scripts/tests/fixtures/rr-output-canonical-summary.txt` — output with `Found **0 errors**, **2 warnings**, **1 info**` and individual `**[W1] category — description**` + `**[I1] category — description**` findings.
   - `scripts/tests/fixtures/rr-output-test-plan-prefix.txt` — test-plan-mode output with prefix: `Test-plan reconciliation for FEAT-028: Found **1 errors**, **0 warnings**, **0 info**`.
   - `scripts/tests/fixtures/rr-output-ascii-dash.txt` — individual findings using ASCII `--` instead of em dash.
   - `scripts/tests/fixtures/rr-output-counts-only.txt` — summary line with non-zero warnings but no individual findings lines (to trigger the `[warn]` stderr).
   - `scripts/tests/fixtures/rr-output-errors-only.txt` — summary line with only `errors > 0`, no warnings/info (must NOT trigger the `[warn]` stderr).

5. Write `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/tests/parse-model-flags.bats`:
   - Happy-path tests:
     - `--model sonnet '#186'` → `cliModel: "sonnet"`, `positional: "#186"`.
     - `--complexity high FEAT-028` → `cliComplexity: "opus"`, `positional: "FEAT-028"` (label mapping).
     - `--complexity opus FEAT-028` → `cliComplexity: "opus"` (bare tier accepted).
     - `--model-for reviewing-requirements:opus '#186'` → `cliModelFor: {"reviewing-requirements":"opus"}`.
     - All three flags together → all four fields populated.
     - Positional token between flags (`--model opus '#186' --complexity high`) → `positional: "#186"` recovered.
     - Empty argv → all null / empty-string fields, exit `0`.
   - Repetition tests:
     - `--model opus --model sonnet` → `cliModel: "sonnet"` (last wins).
     - `--model-for reviewing-requirements:opus --model-for reviewing-requirements:sonnet` → `{"reviewing-requirements":"sonnet"}` (last per-step wins).
   - Error tests:
     - `--model=sonnet` → exit `2` (equals-sign form).
     - Unknown flag `--foo bar` → exit `2`.
     - `--model bad-tier` → exit `2`.
     - `--complexity bad-tier` → exit `2`.
     - `--model-for step:bad-tier` → exit `2`.
     - `--model` with no following argument → exit `2`.
     - Two positional tokens (`#186 FEAT-001`) → exit `2`.

6. Write `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/tests/parse-findings.bats`:
   - Happy-path tests:
     - Zero-findings file → `counts: {errors:0, warnings:0, info:0}`, `individual: []`, exit `0`.
     - Canonical summary + individual findings → counts match, `individual` populated with correct `id` / `severity` / `category` / `description`.
     - Test-plan-mode prefix on summary line → counts extracted correctly despite prefix.
     - ASCII double-hyphen in finding → parsed identically to em dash.
     - Bold markers present → stripped from description; unbold also accepted.
   - Warn emission tests:
     - Counts with non-zero warnings + empty individual → `[warn]` line on stderr, exit `0`.
     - Counts with errors only (warnings == 0, info == 0) + empty individual → NO `[warn]` emitted.
   - JSON shape tests:
     - `counts` and `individual` keys always present even when zero / empty.
   - Error tests:
     - Missing arg → exit `2`.
     - Non-existent file → exit `1`.

#### Deliverables

- [x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/tests/` (directory)
- [x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/tests/fixtures/` (directory)
- [x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/parse-model-flags.sh`
- [x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/parse-findings.sh`
- [x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/tests/fixtures/rr-output-zero-findings.txt`
- [x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/tests/fixtures/rr-output-canonical-summary.txt`
- [x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/tests/fixtures/rr-output-test-plan-prefix.txt`
- [x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/tests/fixtures/rr-output-ascii-dash.txt`
- [x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/tests/fixtures/rr-output-counts-only.txt`
- [x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/tests/fixtures/rr-output-errors-only.txt`
- [ ] `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/tests/parse-model-flags.bats`
- [ ] `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/tests/parse-findings.bats`

---

### Phase 2: Decision-Flow + PR-Number Extraction — `findings-decision.sh` (FR-3), `resolve-pr-number.sh` (FR-4)

**Feature:** [FEAT-028](../features/FEAT-028-orchestrating-workflows-findings-resume.md) | [#186](https://github.com/lwndev/lwndev-marketplace/issues/186)
**Status:** 🔄 In Progress
**Depends on:** Phase 1

#### Rationale

`findings-decision.sh` consumes the `counts` field from `parse-findings.sh`'s output shape — locking the interface in Phase 1 before Phase 2 builds against it is the correct sequencing. `resolve-pr-number.sh` is fully independent but shares Phase 2 for two reasons:

1. **Shared stub infrastructure**: `resolve-pr-number.sh` requires a `gh` stub for the `gh pr list` fallback path. `findings-decision.sh` requires a `.sdlc/workflows/<ID>.json` state file fixture. Setting up both fixture types in Phase 2 rather than splitting them across separate phases keeps the fixture investment contained.
2. **Highest-savings phase after Phase 1**: FR-3 saves ~300 tok × 2–3 forks/workflow (second-highest aggregated savings); FR-4 saves ~150 tok × 0–2 sites. Together with Phase 1, Phases 1–2 land ~60–70% of the total per-workflow savings before Phase 3 introduces composite scripts.

`resolve-pr-number.sh` is placed here (not with the composite scripts in Phase 3) because it is not a composite: it does not call `workflow-state.sh`. Its only external dependency is `gh pr list` as a fallback, which is testable with a PATH-shadowing stub. Grouping it with the composites in Phase 3 would delay its delivery without benefit.

#### Implementation Steps

1. Create a workflow state fixture directory for bats tests:
   - `scripts/tests/fixtures/sdlc-workflows/` — contains sample `FEAT-028.json`, `CHORE-001.json`, `BUG-001.json` state files with the fields `type`, `complexity`, `status`, `currentStep`, `pauseReason`, `complexityStage` needed by FR-3 and FR-6 tests.

2. Write `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/findings-decision.sh`:
   - Shebang `#!/usr/bin/env bash`; `set -euo pipefail`.
   - Top-of-file comment: purpose, signature (`findings-decision.sh <ID> <stepIndex> <counts-json>`), exit codes, `jq` optional.
   - Exit `2` on any missing arg or malformed arg (`<counts-json>` not parseable as JSON; `<ID>` not matching `^(FEAT|CHORE|BUG)-[0-9]+$`).
   - Read `.sdlc/workflows/<ID>.json`; exit `1` if missing / unreadable or `type` / `complexity` fields absent after FR-13 migration.
   - `<stepIndex>` is echoed into any `[info]` / `[warn]` stderr lines for caller-audit consistency; it does not affect the Decision Flow branch.
   - Apply the three-way Decision Flow (FEAT-015 semantics):
     1. `errors == 0 && warnings == 0 && info == 0` → `action: "advance"`, `reason: "zero findings"`.
     2. `errors > 0` → `action: "pause-errors"`, `reason: "errors present"`.
     3. `errors == 0 && (warnings > 0 || info > 0)`:
        - `type in {chore, bug}` AND `complexity in {low, medium}` → `action: "auto-advance"`, `reason: "chore|bug chain with complexity <= medium"`.
        - Otherwise → `action: "prompt-user"`, `reason: "feature chain or high-complexity chore|bug"`.
   - Emit one JSON object on stdout:
     ```json
     {"action":"advance|auto-advance|prompt-user|pause-errors","reason":"<one-line>","type":"feature|chore|bug","complexity":"low|medium|high"}
     ```
   - Exit codes: `0` any action; `1` state file missing / unreadable / malformed / counts JSON unparseable; `2` missing / malformed args.
   - Use `jq` when available; pure-bash fallback.
   - `chmod +x`.

3. Write `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/resolve-pr-number.sh`:
   - Shebang `#!/usr/bin/env bash`; `set -euo pipefail`.
   - Top-of-file comment: purpose, signature (`resolve-pr-number.sh <branch> [subagent-output-file]`), exit codes.
   - Exit `2` on missing `<branch>` arg.
   - Resolution strategy (first match wins):
     1. If `<subagent-output-file>` supplied and exists: scan for `#<digits>` tokens and `https://github.com/<owner>/<repo>/pull/<N>` URLs; pick the **last** match.
     2. Fallback: `gh pr list --head "<branch>" --json number,state --jq '[.[] | select(.state=="OPEN")][0].number'`. Empty / null result falls through to exit `1`.
     3. If neither yields a number: empty stdout, exit `1`.
   - `gh` missing or unauthenticated → emit `[warn] resolve-pr-number: gh unavailable; could not fall back to gh pr list.` to stderr; exit `1`.
   - Non-existent `<subagent-output-file>` is non-fatal — skip to fallback (step 2).
   - Emit bare integer on stdout (no JSON, no trailing newline beyond what the shell naturally adds).
   - Exit codes: `0` resolved number; `1` no source yielded match or `gh` unavailable; `2` missing `<branch>` arg.
   - `chmod +x`.

4. Write `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/tests/findings-decision.bats`:
   - Use `mktemp -d` per-test `setup()` / `teardown()` to create a sandbox `.sdlc/workflows/` directory; run `findings-decision.sh` with `HOME` or `PWD` adjusted so it reads from the sandbox.
   - Decision-Flow branch tests:
     - Zero counts (`{errors:0,warnings:0,info:0}`) → `action: "advance"`, exit `0`.
     - Errors present (`{errors:1,warnings:0,info:0}`) → `action: "pause-errors"`, exit `0`.
     - Errors + warnings both present (`{errors:1,warnings:2,info:0}`) → `action: "pause-errors"` (errors take precedence).
     - Warnings only, feature chain (`type: "feature"`) → `action: "prompt-user"`.
     - Warnings only, chore chain, complexity `low` → `action: "auto-advance"`.
     - Warnings only, chore chain, complexity `medium` → `action: "auto-advance"`.
     - Warnings only, chore chain, complexity `high` → `action: "prompt-user"`.
     - Warnings only, bug chain, complexity `low` → `action: "auto-advance"`.
     - Warnings only, bug chain, complexity `medium` → `action: "auto-advance"`.
     - Warnings only, bug chain, complexity `high` → `action: "prompt-user"`.
     - Info only, feature chain → `action: "prompt-user"`.
     - Info only, chore chain, complexity `low` → `action: "auto-advance"`.
     - Zero counts on chore chain (reachable case) → `action: "advance"` (zero findings takes precedence over chain/complexity gate).
   - `type` and `complexity` echoed into output JSON:
     - Assert `type` field in output matches state file value.
     - Assert `complexity` field in output matches state file value.
   - Error tests:
     - Missing state file → exit `1`.
     - Missing `<ID>` arg → exit `2`.
     - Missing `<counts-json>` arg → exit `2`.
     - Malformed counts JSON (not valid JSON) → exit `1`.
     - Malformed `<ID>` (lowercase `feat-028`) → exit `2`.

5. Write `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/tests/resolve-pr-number.bats`:
   - Use PATH-shadowing for `gh` (per-test `setup()` / `teardown()` with `mktemp -d` stub directory).
   - Create subagent output fixtures:
     - `fixtures/exec-output-with-hash.txt` — file containing `#232` near the end.
     - `fixtures/exec-output-with-url.txt` — file containing a full `https://github.com/owner/repo/pull/232` URL.
     - `fixtures/exec-output-multi-hash.txt` — file with `#50` early and `#232` later (last-match-wins test).
     - `fixtures/exec-output-empty.txt` — file with no PR number tokens.
   - Subagent-output-first tests:
     - File with `#232` token → stdout `232`, exit `0`.
     - File with full GitHub URL → stdout `232`, exit `0`.
     - File with multiple `#N` → last occurrence wins; stdout `232`, exit `0`.
     - File with no PR token + `gh pr list` stub returning `232` → stdout `232`, exit `0`.
   - Fallback tests:
     - No subagent file provided + `gh pr list` stub returning `232` → stdout `232`, exit `0`.
     - No subagent file provided + `gh pr list` stub returning empty → empty stdout, exit `1`.
   - Non-existent subagent file + `gh pr list` stub returning `232` → stdout `232`, exit `0` (file-not-found non-fatal).
   - `gh` missing (no binary in stub PATH) → stderr `[warn] resolve-pr-number: gh unavailable`, exit `1`.
   - Error tests:
     - Missing `<branch>` arg → exit `2`.

#### Deliverables

- [x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/tests/fixtures/sdlc-workflows/FEAT-028.json`
- [x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/tests/fixtures/sdlc-workflows/CHORE-001.json`
- [x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/tests/fixtures/sdlc-workflows/BUG-001.json`
- [x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/tests/fixtures/exec-output-with-hash.txt`
- [x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/tests/fixtures/exec-output-with-url.txt`
- [x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/tests/fixtures/exec-output-multi-hash.txt`
- [x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/tests/fixtures/exec-output-empty.txt`
- [x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/findings-decision.sh`
- [x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/resolve-pr-number.sh`
- [x] `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/tests/findings-decision.bats`
- [ ] `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/tests/resolve-pr-number.bats`

---

### Phase 3: Composite Scripts — `init-workflow.sh` (FR-5), `check-resume-preconditions.sh` (FR-6)

**Feature:** [FEAT-028](../features/FEAT-028-orchestrating-workflows-findings-resume.md) | [#186](https://github.com/lwndev/lwndev-marketplace/issues/186)
**Status:** Pending
**Depends on:** Phase 1, Phase 2

#### Rationale

These are the two composite scripts: both call `workflow-state.sh` subcommands and read `.sdlc/workflows/<ID>.json` state. They depend on Phase 2 for the state file fixture infrastructure already established there (the sandbox `.sdlc/workflows/` pattern).

They are grouped together in Phase 3 for three reasons:

1. **Shared stub infrastructure**: both scripts invoke `workflow-state.sh` subcommands. Bats tests for both require stubs (or a controlled call into the real `workflow-state.sh` with a sandboxed state directory). Establishing the stub / sandbox pattern once in Phase 3 avoids deriving it twice.
2. **`init-workflow.sh` reuses `extract-issue-ref.sh`**: Phase 3 bats must stub `managing-work-items/scripts/extract-issue-ref.sh`. Setting up cross-skill stub infrastructure is a one-time cost in Phase 3 that `check-resume-preconditions.sh` (which calls `resume-recompute`) also benefits from.
3. **Independence from each other**: FR-5 (new-workflow path) and FR-6 (resume-gate path) are orthogonal — neither calls the other. Grouping them in Phase 3 rather than further splitting keeps the plan to four phases and avoids a trivial single-script phase.

#### Implementation Steps

1. Study the `workflow-state.sh` subcommands consumed by FR-5 and FR-6 to understand their exit codes and stdout shapes:
   - FR-5: `init`, `classify-init`, `set-complexity`, `advance`.
   - FR-6: `status`, `resume-recompute`.
   - Confirm `CLAUDE_PLUGIN_ROOT` derivation: `init-workflow.sh` sits at `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/` — three levels up from `BASH_SOURCE[0]`'s directory reaches `plugins/lwndev-sdlc/`.

2. Write `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/init-workflow.sh`:
   - Shebang `#!/usr/bin/env bash`; `set -euo pipefail`.
   - Top-of-file comment: purpose, signature (`init-workflow.sh <TYPE> <artifact-path>`), exit codes, `jq` optional, `CLAUDE_PLUGIN_ROOT` derivation note.
   - Derive `CLAUDE_PLUGIN_ROOT` via `"$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"` (three levels up: `scripts/` → `orchestrating-workflows/` → `skills/` → `lwndev-sdlc/`).
   - Exit `2` on missing / malformed args (`<TYPE>` not one of `feature` / `chore` / `bug`).
   - Exit `1` if `<artifact-path>` not found / unreadable.
   - Composite execution:
     1. Extract `ID` from the artifact filename: regex `FEAT-[0-9]+` / `CHORE-[0-9]+` / `BUG-[0-9]+` per TYPE. TYPE / filename-prefix mismatch → exit `1` with `[warn] init-workflow: could not extract <TYPE-prefix> ID from filename`.
     2. `mkdir -p .sdlc/workflows` (idempotent).
     3. `"${CLAUDE_PLUGIN_ROOT}/skills/orchestrating-workflows/scripts/workflow-state.sh" init <ID> <TYPE>`.
     4. Capture `tier` from stdout: `"${CLAUDE_PLUGIN_ROOT}/skills/orchestrating-workflows/scripts/workflow-state.sh" classify-init <ID> <artifact-path>`.
     5. `"${CLAUDE_PLUGIN_ROOT}/skills/orchestrating-workflows/scripts/workflow-state.sh" set-complexity <ID> <tier>`.
     6. `echo "<ID>" > .sdlc/workflows/.active` — write active marker before `advance`.
     7. `"${CLAUDE_PLUGIN_ROOT}/skills/orchestrating-workflows/scripts/workflow-state.sh" advance <ID> <artifact-path>`.
     8. `issue_ref=$("${CLAUDE_PLUGIN_ROOT}/skills/managing-work-items/scripts/extract-issue-ref.sh" <artifact-path>")` — graceful: empty or failed ref is non-fatal; `issueRef` becomes `""`.
   - Emit one JSON object on stdout:
     ```json
     {"id":"FEAT-028","type":"feature","complexity":"medium","issueRef":"#186"}
     ```
   - Exit codes: `0` success (including empty `issueRef`); `1` downstream subcommand failure relayed to stderr; `2` missing / malformed args.
   - Use `jq` when available; pure-bash fallback.
   - `chmod +x`.

3. Write `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/check-resume-preconditions.sh`:
   - Shebang `#!/usr/bin/env bash`; `set -euo pipefail`.
   - Top-of-file comment: purpose, signature (`check-resume-preconditions.sh <ID>`), exit codes, escape-hatch note, `jq` optional.
   - Exit `2` on missing / malformed `<ID>` (not matching `^(FEAT|CHORE|BUG)-[0-9]+$`).
   - Exit `1` if `.sdlc/workflows/<ID>.json` does not exist.
   - Composite execution:
     1. `"${CLAUDE_PLUGIN_ROOT}/skills/orchestrating-workflows/scripts/workflow-state.sh" status <ID>` — capture `status`, `currentStep`, `pauseReason` from JSON stdout.
     2. `"${CLAUDE_PLUGIN_ROOT}/skills/orchestrating-workflows/scripts/workflow-state.sh" resume-recompute <ID>` — relay its stderr verbatim (including any `[model] Work-item complexity upgraded ...` line).
     3. Read `type`, `complexity`, `complexityStage` from the state file.
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
     `pauseReason` is JSON `null` when `status != "paused"`. `chainTable` always equals `type`.
   - Exit codes: `0` any recognised state; `1` missing / unreadable state file, malformed JSON from downstream, or downstream subcommand non-zero exit; `2` missing / malformed args.
   - Use `jq` when available; pure-bash fallback.
   - `chmod +x`.

4. Create additional fixture files:
   - `scripts/tests/fixtures/feature-requirement.md` — minimal feature requirement doc with a `FEAT-028` prefix in the filename (or inline reference) and an issue reference `#186` for the `extract-issue-ref.sh` call.
   - `scripts/tests/fixtures/chore-requirement.md` — minimal chore requirement doc (`CHORE-001` prefix).
   - `scripts/tests/fixtures/bug-requirement.md` — minimal bug requirement doc (`BUG-001` prefix).
   - `scripts/tests/fixtures/requirement-no-issue.md` — minimal requirement doc with no issue-reference section (for empty `issueRef` graceful-degradation test).
   - Extend existing `sdlc-workflows/` state files with `complexityStage` and `status: "paused"` variants as needed.

5. Write `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/tests/init-workflow.bats`:
   - Use `mktemp -d` sandbox per test; set `PWD` or use `cd` within `run` calls so `.sdlc/workflows/` writes go to the sandbox.
   - Stub `workflow-state.sh`, `extract-issue-ref.sh` via PATH-shadowing or inline stub scripts in the fixture sandbox.
   - TYPE tests:
     - `feature` + feature artifact → output `{"id":"FEAT-028","type":"feature","complexity":"medium","issueRef":"#186"}`, exit `0`.
     - `chore` + chore artifact → output with `type: "chore"`, exit `0`.
     - `bug` + bug artifact → output with `type: "bug"`, exit `0`.
   - TYPE/filename-prefix mismatch:
     - `chore` TYPE + FEAT-prefixed artifact → exit `1`, stderr contains `[warn] init-workflow: could not extract`.
   - Active marker test:
     - After `feature` init, `.sdlc/workflows/.active` contains `FEAT-028`.
   - Graceful-degradation tests:
     - `extract-issue-ref.sh` returns empty → `issueRef: ""` in output, exit `0`.
     - `extract-issue-ref.sh` not found → `issueRef: ""` in output, exit `0` (non-fatal).
   - Error tests:
     - Missing args → exit `2`.
     - Unknown TYPE (`task`) → exit `2`.
     - Non-existent artifact → exit `1`.

6. Write `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/tests/check-resume-preconditions.bats`:
   - Use `mktemp -d` sandbox per test with `.sdlc/workflows/<ID>.json` state files.
   - Stub `workflow-state.sh` via PATH-shadowing to return controlled JSON for `status` and emit a controlled `[model]` line from `resume-recompute`.
   - Status tests:
     - `status: "in-progress"` → output includes `status: "in-progress"`, `pauseReason: null`, exit `0`.
     - `status: "paused"` with `pauseReason: "plan-approval"` → output includes `pauseReason: "plan-approval"`, exit `0`.
     - `status: "paused"` with `pauseReason: "pr-review"` → output includes `pauseReason: "pr-review"`, exit `0`.
     - `status: "paused"` with `pauseReason: "review-findings"` → output includes `pauseReason: "review-findings"`, exit `0`.
     - `status: "failed"` → output includes `status: "failed"`, `pauseReason: null`, exit `0`.
     - `status: "complete"` → output includes `status: "complete"`, `pauseReason: null`, exit `0`.
   - `chainTable == type` invariant:
     - For each workflow type (`feature`, `chore`, `bug`): assert `chainTable` equals `type` in output.
   - `resume-recompute` relay test:
     - Stub `resume-recompute` to emit `[model] Work-item complexity upgraded from low to medium for FEAT-028` on stderr. Assert that line appears in the script's stderr output verbatim.
   - Error tests:
     - Missing state file → exit `1`.
     - Missing arg → exit `2`.
     - Malformed ID → exit `2`.

#### Deliverables

- [ ] `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/tests/fixtures/feature-requirement.md`
- [ ] `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/tests/fixtures/chore-requirement.md`
- [ ] `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/tests/fixtures/bug-requirement.md`
- [ ] `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/tests/fixtures/requirement-no-issue.md`
- [ ] `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/init-workflow.sh`
- [ ] `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/check-resume-preconditions.sh`
- [ ] `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/tests/init-workflow.bats`
- [ ] `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/tests/check-resume-preconditions.bats`

---

### Phase 4: `workflow-state.sh set-model-override` (FR-7) + Vitest Extension

**Feature:** [FEAT-028](../features/FEAT-028-orchestrating-workflows-findings-resume.md) | [#186](https://github.com/lwndev/lwndev-marketplace/issues/186)
**Status:** Pending

#### Rationale

`workflow-state.sh` already has 1,731 lines and 20+ subcommands, each tested in the existing `scripts/__tests__/workflow-state.test.ts` vitest suite (not bats). This phase is intentionally isolated from the bats-tested scripts (Phases 1–3) for two reasons:

1. **Different test framework**: the `set-model-override` extension lands in vitest alongside the rest of `workflow-state.sh`'s coverage. Mixing bats and vitest deliverables in the same phase creates a testing-convention ambiguity for the implementer. Keeping this phase separate makes the test-framework choice unambiguous.
2. **Low-risk, self-contained change**: `set-model-override` mirrors the existing `set-complexity` subcommand's state-file-locking + in-place `jq` write pattern. Isolating it in its own phase means a reviewer can focus on a single, narrowly scoped diff without bats fixture noise.

This phase has no dependency on Phases 1–3 at runtime — `set-model-override` writes a field in the state file and emits a `[info]` line; it does not call any Phase 1–3 scripts. It is ordered after Phase 3 only so the bats infrastructure is fully established before the final SKILL.md cutover phase.

#### Implementation Steps

1. Study the `set-complexity` subcommand in `workflow-state.sh` (~line 1654) to understand the state-file-locking + in-place `jq` write pattern exactly. Note:
   - The `flock`-based locking mechanism.
   - The `jq` write-back pattern.
   - The exit code conventions (`0` success; `1` state file missing / jq failure; `2` missing / malformed args).

2. Add the `set-model-override` subcommand to `workflow-state.sh`:
   - Signature: `workflow-state.sh set-model-override <ID> <tier>`.
   - Accept `<tier>` values: `haiku` / `sonnet` / `opus` only (bare tiers — NOT `low` / `medium` / `high` labels). Unknown tier → exit `2` with `[error] set-model-override: unrecognised tier '<tier>'` to stderr.
   - Exit `2` on missing `<ID>` or `<tier>`.
   - Exit `1` if `.sdlc/workflows/<ID>.json` does not exist or is unwritable or `jq` fails.
   - Behaviour: `jq '.modelOverride = "<tier>"'` in-place write, matching the locking pattern of `set-complexity`.
   - Downgrade is permitted: the new value is written regardless of the current `modelOverride` value.
   - Idempotent: setting the same tier twice is a no-op write (no error, no special stdout).
   - Emit nothing on stdout.
   - Emit `[info] modelOverride set to <tier> for <ID>` to stderr on successful write.
   - Add `set-model-override` to the subcommand dispatch block (the `case` statement routing at the top of the command-handling section).

3. Add new test cases to `scripts/__tests__/workflow-state.test.ts`:
   - Success per tier:
     - `set-model-override FEAT-028 haiku` → state file `.modelOverride == "haiku"`, stderr contains `[info] modelOverride set to haiku for FEAT-028`.
     - `set-model-override FEAT-028 sonnet` → `.modelOverride == "sonnet"`.
     - `set-model-override FEAT-028 opus` → `.modelOverride == "opus"`.
   - Downgrade permitted:
     - Write `opus` then `sonnet` → `.modelOverride == "sonnet"` (lower value accepted).
   - Idempotent repeat:
     - Write `sonnet` twice → exit `0` both times, `.modelOverride == "sonnet"`.
   - Error cases:
     - Label tier `high` → exit `2` (labels rejected).
     - Unknown tier `ultra` → exit `2`.
     - Missing state file → exit `1`.
     - Missing `<ID>` arg → exit `2`.
     - Missing `<tier>` arg → exit `2`.
   - Unknown-subcommand regression guard:
     - `workflow-state.sh unknown-subcommand FEAT-028` → non-zero exit (existing behaviour not broken by adding the new case).

4. Run the vitest suite scoped to `workflow-state`:
   ```bash
   npm test -- --testPathPatterns=workflow-state | tail -60
   ```
   Confirm all existing cases still pass and new `set-model-override` cases pass.

#### Deliverables

- [ ] `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/workflow-state.sh` (extended with `set-model-override` subcommand)
- [ ] `scripts/__tests__/workflow-state.test.ts` (new `set-model-override` test cases added)

---

### Phase 5: SKILL.md + References Rewrite (FR-8) + Caller Audit (FR-9) + Final Validation

**Feature:** [FEAT-028](../features/FEAT-028-orchestrating-workflows-findings-resume.md) | [#186](https://github.com/lwndev/lwndev-marketplace/issues/186)
**Status:** Pending
**Depends on:** Phases 1, 2, 3, and 4

#### Rationale

The SKILL.md and four reference-doc rewrites are the user-visible cutover: they switch the orchestrator from prose-implementation sections to one-line script-invocation pointers. This phase must land last — after all six new scripts and the `set-model-override` subcommand exist and their tests pass — for the same self-bootstrapping and pointer-accuracy reasons documented in FEAT-026 Phase 4 and FEAT-027 Phase 4.

The five prose targets (SKILL.md + four reference docs) are all co-deployed in one commit so the orchestrator's reading experience is consistent after cutover. No pointer in the rewritten docs references a script or subcommand that doesn't exist at merge time.

The caller audit (FR-9) is bundled here: confirming the closed-world change requires the new scripts to exist so their invocation paths can be cross-checked against any stale prose.

#### Implementation Steps

1. Rewrite prose targets in `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md`:
   - **Retain verbatim**: YAML frontmatter, `## When to Use`, `## Output Style`, `## Quick Start` step numbers 1–2 (resolve doc + ask for issue), all step sequences for each chain type, all pause-point definitions, all `## References` pointers. The public-contract shape is unchanged.
   - **Replace with script pointers** (scoped to the prose each FR removes):
     - `## Arguments → Model-Selection Flags (FEAT-014 FR-8)` "Parsing rules" paragraph: replace the flag-description prose with: `Run \`bash "${CLAUDE_PLUGIN_ROOT}/skills/orchestrating-workflows/scripts/parse-model-flags.sh" "$@"\`. Returns \`{cliModel, cliComplexity, cliModelFor, positional}\`; exit \`2\` on unrecognised flags or malformed tiers.`
     - `## Quick Start` steps 3–5 for feature / chore / bug new-workflow start (active-marker write + ID read + state init + classify + advance): collapse each into a single `init-workflow.sh` invocation pointer. The JSON output shape `{id, type, complexity, issueRef}` is inlined inline after the invocation. Retain step numbers so callers know sequence.
   - Net line-count reduction target: ≥ 8% from 254 lines (≤ 234 lines). The prose bodies removed (~15 lines flag-parsing + ~20 lines three-chain init steps) total ~35 lines of deletion vs. ~10 lines of pointer insertion — a net of ~25 lines, or ~10%. Target is achievable with moderate margin.

2. Rewrite prose targets in `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/reviewing-requirements-flow.md`:
   - **Replace with script pointers** (scoped):
     - `## Parsing Findings` section body → one-line `parse-findings.sh` pointer; retain the `{counts, individual}` output shape description.
     - `## Decision Flow` three-way branch (items 1, 2, 3) → one-line `findings-decision.sh` pointer; retain the `action`-to-orchestrator-behavior mapping table:
       | `action` | Orchestrator behavior |
       |----------|----------------------|
       | `advance` | call `advance` + continue |
       | `auto-advance` | emit `[info]` log + call `advance` + continue |
       | `prompt-user` | set gate + display findings + prompt user |
       | `pause-errors` | set gate + display findings + offer apply-fixes / pause |
     - `### Parsing Individual Findings for \`auto-advanced\` Decisions` subsection → one-line pointer at `parse-findings.sh`'s `individual` field.
   - Net reduction target: ≥ 8% from 145 lines (≤ 133 lines).

3. Rewrite prose targets in `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/chain-procedures.md`:
   - **Replace with script pointers** (scoped):
     - New Feature Workflow Procedure steps 1/3/4/5 (active-marker, ID extraction, init, advance) → collapse into a single `init-workflow.sh` pointer with the JSON output shape inlined. Retain the surrounding prose (the PR-creation step and any model-selection context) unchanged.
     - New Chore Workflow Procedure same collapsible steps → same `init-workflow.sh` pointer.
     - New Bug Workflow Procedure same collapsible steps → same `init-workflow.sh` pointer.
     - Resume Procedure steps 1–5 (status check, resume-recompute, type read, complexity read, complexityStage read) → collapse into a single `check-resume-preconditions.sh` pointer with the seven-field JSON output shape inlined. Step 6 ("Use the appropriate step sequence table...") stays prose.
   - Net reduction target: ≥ 8% from 180 lines (≤ 165 lines).

4. Rewrite prose targets in `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/step-execution-details.md`:
   - **Replace with script pointers** (scoped):
     - Chore chain step 4 items 1–2 (PR-number extraction from subagent output + `gh pr list` fallback) → one-line `resolve-pr-number.sh` pointer. Retain step 4's other items (the `set-pr` call that consumes the number).
     - Bug chain step 4 items 1–2 (same pattern) → same `resolve-pr-number.sh` pointer.
     - Feature-chain PR-Creation prose stays as-is.
   - Net reduction target: ≥ 8% from 210 lines (≤ 193 lines).

5. Rewrite the targeted prose in `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/model-selection.md`:
   - **Replace** Migration Option 4b: replace the `jq '.modelOverride = "opus"'` manual-edit snippet with a `workflow-state.sh set-model-override` pointer. Scope: the single paragraph / code block that describes the manual `jq` edit — nothing else in `model-selection.md` is touched.
   - Net reduction target: minimal (this is one paragraph replacement in 620 lines; absolute line-count change is ~2–4 lines; the aggregate across all five files is what matters for NFR-4).

6. Caller audit (FR-9):
   - Confirm no other skills or agents in `plugins/lwndev-sdlc/skills/` or `plugins/lwndev-sdlc/agents/` consume any of the seven new orchestrator scripts directly. The audit is a grep pass — no edits expected.
   - Confirm `finalizing-workflow/scripts/finalize.sh` still composes over `${CLAUDE_PLUGIN_ROOT}/scripts/branch-id-parse.sh` (not any of the new scripts) — no change needed.
   - Confirm `managing-work-items/scripts/extract-issue-ref.sh` is called by FR-5 but is itself unchanged.
   - Run `npm run validate` to confirm the closed-world change passes plugin validation.

7. Run full bats + vitest test suite scoped to FEAT-028:
   ```bash
   npm test -- --testPathPatterns="orchestrating-workflows|workflow-state" | tail -80
   ```
   Confirm all Phase 1–4 tests pass.

8. Run `npm run validate` — confirm 13/13 plugins validated.

9. Verify net line-count reductions via `wc -l`:
   - `SKILL.md` ≤ 234 (8% from 254).
   - `reviewing-requirements-flow.md` ≤ 133 (8% from 145).
   - `chain-procedures.md` ≤ 165 (8% from 180).
   - `step-execution-details.md` ≤ 193 (8% from 210).

10. **Token-savings measurement (NFR-4)**: run a paired workflow comparison on a representative feature workflow (no resume) and a representative resume path. Capture token counts from Claude Code conversation state. Confirm the measured delta falls within ±30% of the ~1,500–2,500 tok/workflow estimate. Methodology mirrors FEAT-026 NFR-4 and FEAT-027 NFR-4. Document results in the PR body.

11. Manual smoke-test:
    - Invoke `/orchestrating-workflows --model sonnet '#186'` on a test fixture. Confirm `parse-model-flags.sh` is called at argv ingestion; confirm `init-workflow.sh` is called at new-workflow start; confirm `parse-findings.sh` + `findings-decision.sh` are called after the `reviewing-requirements` fork; confirm the orchestrator output is visually identical to a pre-feature run on the same input.
    - Pause the workflow at `plan-approval`. Run `workflow-state.sh set-model-override FEAT-028 opus`. Re-invoke. Confirm `check-resume-preconditions.sh` output reflects the expected state and `modelOverride: "opus"` is present.
    - Exercise `resolve-pr-number.sh` on a chore-chain step-4 fork output. Confirm PR number extraction and `set-pr` call succeed.

#### Deliverables

- [ ] `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` (rewritten per FR-8; public contract retained; `Model-Selection Flags` parsing-rules collapsed to `parse-model-flags.sh` pointer; `Quick Start` steps 3–5 for each chain type collapsed to `init-workflow.sh` pointer; net line-count ≤ 234)
- [ ] `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/reviewing-requirements-flow.md` (rewritten per FR-8; `Parsing Findings` + `Parsing Individual Findings` sections collapsed to `parse-findings.sh` pointers; `Decision Flow` collapsed to `findings-decision.sh` pointer with action-table retained; net line-count ≤ 133)
- [ ] `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/chain-procedures.md` (rewritten per FR-8; New Feature / Chore / Bug Workflow Procedures collapsed to `init-workflow.sh` pointers; Resume Procedure steps 1–5 collapsed to `check-resume-preconditions.sh` pointer; step 6 prose retained; net line-count ≤ 165)
- [ ] `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/step-execution-details.md` (rewritten per FR-8; chore step 4 and bug step 4 PR-number extraction collapsed to `resolve-pr-number.sh` pointers; feature-chain PR-Creation prose retained; net line-count ≤ 193)
- [ ] `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/model-selection.md` (Migration Option 4b updated to `workflow-state.sh set-model-override` pointer)
- [ ] Caller audit complete: no other skills / agents consume the new scripts; `manage-work-items/extract-issue-ref.sh` unchanged; `finalize.sh` unchanged
- [ ] Passing `npm test` (all Phase 1–4 bats + vitest cases)
- [ ] Passing `npm run validate` (13/13 plugins)
- [ ] Line-count reductions verified via `wc -l` (all four files meet ≥ 8% target)
- [ ] Token-savings measurement per NFR-4 documented in PR body (within ±30% of ~1,500–2,500 tok/workflow estimate) — deferred to post-PR (standard pattern)

---

## Shared Infrastructure

- **New `scripts/tests/` directory** — created in Phase 1. Structure mirrors `plugins/lwndev-sdlc/skills/reviewing-requirements/scripts/tests/` (FEAT-026 precedent) and `plugins/lwndev-sdlc/skills/implementing-plan-phases/scripts/tests/` (FEAT-027 precedent).
- **Fixtures directory** — `scripts/tests/fixtures/` created in Phase 1 with text-output fixtures for `parse-findings.sh`. Extended in Phase 2 with state file fixtures (`sdlc-workflows/`) and subagent-output fixtures for `resolve-pr-number.sh`. Extended in Phase 3 with requirement-doc fixtures for `init-workflow.sh`.
- **State file sandbox pattern** — per-test `mktemp -d` sandbox with `.sdlc/workflows/<ID>.json` populated, `HOME` or `PWD` adjusted. Established in Phase 2 and reused in Phase 3 without re-derivation. Mirrors the pattern already used in `workflow-state.sh`'s own vitest suite for state-file operations.
- **PATH-shadowing stub pattern** — `resolve-pr-number.bats` stubs `gh`; `init-workflow.bats` and `check-resume-preconditions.bats` stub `workflow-state.sh` and `extract-issue-ref.sh`. Follows the exact hook names and invocation shape from `plugins/lwndev-sdlc/skills/reviewing-requirements/scripts/tests/verify-references.bats` (FEAT-026) and `plugins/lwndev-sdlc/skills/implementing-plan-phases/scripts/tests/commit-and-push-phase.bats` (FEAT-027). Parent shell PATH is never mutated.
- **`CLAUDE_PLUGIN_ROOT` derivation** — `init-workflow.sh` and `check-resume-preconditions.sh` derive the plugin root via three-levels-up from `BASH_SOURCE[0]`'s directory: `scripts/` → `orchestrating-workflows/` → `skills/` → `lwndev-sdlc/`. Documented in each script's top-of-file comment. Note: `prepare-fork.sh` (FEAT-021) derives from the plugin-shared `scripts/` directory (one level up); these skill-scoped scripts need an extra two levels.
- **`jq` vs. pure-bash fallback** — FR-1, FR-2, FR-3, FR-5, FR-6 all emit JSON. All declare `jq` as optional in their top-of-file comment and use `jq` when available with a pure-bash `printf` fallback. Consistent with FEAT-025 / FEAT-026 / FEAT-027 precedent. FR-4 emits a bare integer (no JSON). FR-7 emits nothing on stdout.
- **No new plugin-shared scripts** — all six FEAT-028 scripts are self-contained under `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/`. The plugin-shared `scripts/` directory is not modified. The seven items are internal to `orchestrating-workflows` (closed-world change per FR-9).

## Testing Strategy

- **Unit tests (bats, Phases 1–3)** — one `.bats` file per script. Tests live under `plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts/tests/`. Covers all valid input classes per FR, every documented exit code, graceful-degradation paths (`gh` missing for FR-4; empty `issueRef` extraction for FR-5; missing-document retained-complexity path for FR-6), and edge-case inputs (FR-1 flag repetition, FR-2 em-dash vs ASCII-dash, FR-2 test-plan-mode prefix, FR-3 zero-counts edge case, FR-4 last-match-wins).
- **Vitest extension (Phase 4)** — new `set-model-override` cases added to the existing `scripts/__tests__/workflow-state.test.ts` suite. Covers success per tier, downgrade, idempotent repeat, missing state file, label-tier rejection, unknown-tier rejection, and unknown-subcommand regression guard.
- **`chainTable == type` invariant** — `check-resume-preconditions.bats` asserts `chainTable == type` for each workflow type (`feature`, `chore`, `bug`). Guards against field desync on future edits.
- **String exactness** — bats tests assert `[warn]` / `[info]` / `[model]` stderr strings verbatim (same pattern as FEAT-026's `verify-references.bats`).
- **Integration tests (live)** — end-to-end `/orchestrating-workflows` invocation on a test fixture exercising FR-1 (all supported flag shapes), FR-5 (`init-workflow.sh` composite), FR-2 + FR-3 in the `reviewing-requirements` step fork, FR-4 in the chore-chain step-4 executor fork, and FR-6 in a resume path.
- **Token-savings measurement (NFR-4)** — pre- and post-feature paired runs on a representative feature workflow and a resume path. Token counts from Claude Code conversation state. Target: within ±30% of ~1,500–2,500 tok/workflow estimate.
- **Manual E2E** — full feature workflow plus deliberate FR-4 failure (no `#N` token + empty `gh pr list`) to confirm the orchestrator halts with a readable error and does not silently advance state.

## Dependencies and Prerequisites

- **Phase ordering**: Phase 2 depends on Phase 1 (FR-3 consumes FR-2's `counts` JSON shape; fixture infrastructure established). Phase 3 depends on Phases 1 and 2 (state file fixture sandbox pattern; `CLAUDE_PLUGIN_ROOT` usage consistent with established scripts). Phase 4 has no runtime dependency on Phases 1–3 but is ordered after them so the bats infrastructure is complete before the final cutover. Phase 5 depends on Phases 1–4 (SKILL.md pointers must reference existing, tested scripts and subcommands).
- **`workflow-state.sh`** — existing (1,731 lines, 20+ subcommands). FR-3, FR-5, FR-6, FR-7 compose over `status`, `init`, `classify-init`, `set-complexity`, `advance`, `resume-recompute`. FR-7 extends it.
- **`managing-work-items/scripts/extract-issue-ref.sh`** — existing (FEAT-025). FR-5 invokes it. Unchanged; graceful degradation inherited.
- **`prepare-fork.sh`** (FEAT-021) — adjacent, not a dependency. The seven scripts are orthogonal (run before or after forks, not during).
- **FEAT-015 findings-handling-spiral-fix** — algorithm source for FR-3's Decision Flow. No runtime call; FR-3 encapsulates the FEAT-015 gate semantics verbatim.
- **`gh` CLI** — already required. FR-4 uses it as a fallback.
- **External tools (no new dependencies)**: `jq`, `git`, `gh`, `bash` — all already required by the plugin. No new binaries.

## Risk Assessment

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| **Self-bootstrapping break**: Phase 5 SKILL.md rewrite lands before scripts are tested, breaking the live orchestrator mid-workflow | High | Low | Phase 5 is strictly ordered after Phases 1–4. SKILL.md is only rewritten after all scripts and the vitest extension exist and tests pass. Phase 5 step 7 runs `npm test` before committing the rewrite. |
| **`CLAUDE_PLUGIN_ROOT` derivation wrong in `init-workflow.sh` / `check-resume-preconditions.sh`**: three-levels-up logic miscounted, breaking all downstream `workflow-state.sh` calls | High | Low | Phase 3 step 1 explicitly studies the `prepare-fork.sh` precedent (one level up from plugin-shared `scripts/`) to derive the correct count. The sandbox-based bats tests call the real script, so a miscounted path fails immediately in CI. |
| **FR-2 em-dash regex misses real findings in production output**: the em dash character class is too narrow | Medium | Low | `parse-findings.bats` includes both em-dash and ASCII-dash fixtures (steps 4, 6). The regex explicitly accepts both. The `[warn]` stderr mechanism catches any case where counts are non-zero but `individual` is empty, so the orchestrator is never silently wrong. |
| **FR-3 Decision Flow incorrectly gates `complexity == low` chore / bug chains**: auto-advance for a case where the orchestrator's skip condition already prevents `findings-decision.sh` from being called | Low | Medium | Bats covers the `chore + low complexity + warnings` case explicitly (Phase 2 step 4). The test validates the script's internal contract independently of the orchestrator's gating, ensuring correctness if the gating condition is ever loosened. |
| **`resolve-pr-number.sh` last-match-wins picks a code-example `#N` token**: quoted `#123` in code block is the only `#N` in the output | Low | Low | The `gh pr list` fallback catches this. The `exec-output-multi-hash.txt` fixture tests last-match-wins with a real final `#N`. The requirements doc Edge Case 11 acknowledges this as a caller bug when the executor fails to print its own PR number. |
| **Phase 5 line-count targets missed**: rewritten files end up above the ≥ 8% ceiling | Low | Low | The prose bodies targeted are clearly bounded sections. Step 9 of Phase 5 verifies via `wc -l` before committing. The 8% target is conservative relative to the removal scope (~35 lines from SKILL.md alone). |
| **Token-savings measurement unavailable at PR time**: NFR-4 paired-run methodology requires a live workflow | Low | Medium | Phase 5 step 10 gates this as a deliverable. Deferred to post-PR per the standard FEAT-025 / FEAT-026 / FEAT-027 pattern. |

## Success Criteria

- `parse-model-flags.sh` implements FR-1; strips the three flags positional-independently; emits the canonical four-field JSON; bats tests pass.
- `parse-findings.sh` implements FR-2; parses summary line with anchor-on-substring regex and individual findings with em-dash + ASCII-dash fallback; emits `{counts, individual}` JSON; `[warn]` only when `warnings + info > 0` and `individual` empty; bats tests pass.
- `findings-decision.sh` implements FR-3; resolves the three-way Decision Flow including the chain-type + complexity gate; emits the four-field `{action, reason, type, complexity}` JSON; bats tests pass.
- `resolve-pr-number.sh` implements FR-4; subagent-output-first with last-match-wins + `gh pr list` fallback + `[warn]` on `gh` missing; emits bare integer; bats tests pass.
- `init-workflow.sh` implements FR-5; composes `mkdir` + `workflow-state.sh init / classify-init / set-complexity / advance` + active-marker + `extract-issue-ref.sh` (graceful); emits `{id, type, complexity, issueRef}`; bats tests pass.
- `check-resume-preconditions.sh` implements FR-6; composes `workflow-state.sh status` + `resume-recompute`; emits the seven-field JSON; `chainTable == type` invariant guarded in bats; bats tests pass.
- `workflow-state.sh set-model-override` implements FR-7; downgrade permitted; idempotent; emits `[info]` on stderr; vitest cases added to `workflow-state.test.ts` pass.
- All five prose targets are rewritten per FR-8; net line-count reductions per Phase 5 step 9 targets met.
- FR-9 verified: no other skills or agents consume the new scripts; `npm run validate` confirms closed-world change.
- `npm test` and `npm run validate` pass on the release branch.

## Code Organization

```
plugins/lwndev-sdlc/
└── skills/
    └── orchestrating-workflows/
        ├── SKILL.md                                         # REWRITTEN (Phase 5): script pointers for flags + init
        ├── references/
        │   ├── chain-procedures.md                          # REWRITTEN (Phase 5): init-workflow + resume pointers
        │   ├── reviewing-requirements-flow.md               # REWRITTEN (Phase 5): parse-findings + decision pointers
        │   ├── step-execution-details.md                    # REWRITTEN (Phase 5): resolve-pr-number pointers
        │   ├── model-selection.md                           # UPDATED (Phase 5): set-model-override pointer in Option 4b
        │   ├── forked-steps.md                              # UNCHANGED
        │   ├── issue-tracking.md                            # UNCHANGED
        │   └── verification-and-relationships.md            # UNCHANGED
        └── scripts/
            ├── stop-hook.sh                                 # UNCHANGED
            ├── workflow-state.sh                            # EXTENDED (Phase 4): set-model-override subcommand
            ├── parse-model-flags.sh                         # NEW (Phase 1): FR-1
            ├── parse-findings.sh                            # NEW (Phase 1): FR-2
            ├── findings-decision.sh                         # NEW (Phase 2): FR-3
            ├── resolve-pr-number.sh                         # NEW (Phase 2): FR-4
            ├── init-workflow.sh                             # NEW (Phase 3): FR-5
            ├── check-resume-preconditions.sh                # NEW (Phase 3): FR-6
            └── tests/                                       # NEW directory (Phase 1)
                ├── fixtures/                                # NEW directory (Phase 1, extended Phases 2-3)
                │   ├── rr-output-zero-findings.txt          # Phase 1: parse-findings zero-findings fixture
                │   ├── rr-output-canonical-summary.txt      # Phase 1: parse-findings canonical fixture
                │   ├── rr-output-test-plan-prefix.txt       # Phase 1: parse-findings test-plan-mode fixture
                │   ├── rr-output-ascii-dash.txt             # Phase 1: parse-findings ASCII-dash fixture
                │   ├── rr-output-counts-only.txt            # Phase 1: parse-findings counts-but-no-individual fixture
                │   ├── rr-output-errors-only.txt            # Phase 1: parse-findings errors-only fixture
                │   ├── sdlc-workflows/                      # Phase 2: state file fixtures
                │   │   ├── FEAT-028.json                    # feature chain state file
                │   │   ├── CHORE-001.json                   # chore chain state file
                │   │   └── BUG-001.json                     # bug chain state file
                │   ├── exec-output-with-hash.txt            # Phase 2: resolve-pr-number hash-token fixture
                │   ├── exec-output-with-url.txt             # Phase 2: resolve-pr-number URL fixture
                │   ├── exec-output-multi-hash.txt           # Phase 2: last-match-wins fixture
                │   ├── exec-output-empty.txt                # Phase 2: no-match fixture
                │   ├── feature-requirement.md               # Phase 3: init-workflow feature artifact fixture
                │   ├── chore-requirement.md                 # Phase 3: init-workflow chore artifact fixture
                │   ├── bug-requirement.md                   # Phase 3: init-workflow bug artifact fixture
                │   └── requirement-no-issue.md              # Phase 3: empty issueRef graceful-degradation fixture
                ├── parse-model-flags.bats                   # NEW (Phase 1)
                ├── parse-findings.bats                      # NEW (Phase 1)
                ├── findings-decision.bats                   # NEW (Phase 2)
                ├── resolve-pr-number.bats                   # NEW (Phase 2)
                ├── init-workflow.bats                       # NEW (Phase 3)
                └── check-resume-preconditions.bats          # NEW (Phase 3)

scripts/
└── __tests__/
    └── workflow-state.test.ts                               # EXTENDED (Phase 4): set-model-override cases
```
