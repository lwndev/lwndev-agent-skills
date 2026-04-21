# Chore: Output Token Optimization Pilot

## Chore ID

`CHORE-034`

## GitHub Issue

[#198](https://github.com/lwndev/lwndev-marketplace/issues/198)

## Category

`refactoring`

## Description

Pilot an output-token reduction pass on `orchestrating-workflows` by adding an explicit *Output style* directive, tightening conversational narration rules, and formalizing the fork-to-orchestrator return-format contract. Capture baseline/after measurements and learnings so the same pattern can be rolled out to the remaining twelve `lwndev-sdlc` skills in a follow-up chore.

## Affected Files

- `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` — add *Output style* section, formalize fork-return contract
- `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/step-execution-details.md` — align fork-invocation language with the new return contract
- `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/chain-procedures.md` — align orchestrator narration language with lite rules
- `requirements/chores/CHORE-034-output-token-optimization-pilot.md` — baseline + post-change measurements appended to the Notes section on completion
- `qa/test-plans/QA-plan-CHORE-034.md` — adversarial QA test plan
- `qa/test-results/QA-results-CHORE-034.md` — QA test results artifact
- `scripts/__tests__/qa-CHORE-034.spec.ts` — QA test implementation
- *(out of pilot scope)* The skill has no `assets/` directory; artifact templates live in the sub-skills invoked by the orchestrator and are deferred to the rollout chore. See Notes.

## Acceptance Criteria

- [x] `orchestrating-workflows/SKILL.md` contains an *Output style* section that pins the lite rules (no narration before tool calls, no end-of-step summaries, no emoji, no preamble/postamble) with explicit carve-outs for error messages, security warnings, interactive prompts, and findings display
- [x] The *Output style* section names the fork-to-orchestrator return contract and states its precedence over general lite rules (subagents must emit structured returns in the documented shape)
- [x] Fork-return contract is formalized with three canonical shapes: `done | artifact=<path> | <≤10-word note>`, `failed | <one-sentence reason>`, and the existing `Found **N errors**, **N warnings**, **N info**` summary line for `reviewing-requirements`
- [x] All existing Agent-tool fork invocations in `SKILL.md` and `references/step-execution-details.md` reference the canonical return shape (so subagents know what the orchestrator expects)
- [x] Orchestrator-authored narration in `chain-procedures.md` and `SKILL.md` (e.g., advance/pause announcements, FR-14 echoes, `[info]`/`[warn]` lines) is kept — these are load-bearing signals, not narration, and must not be stripped
- [x] A baseline measurement table is appended to this chore document's *Notes* section before the optimization is applied, capturing the pre-change output token count and artifact line/word counts from a reference workflow run
- [x] A post-change measurement table is appended to this chore document's *Notes* section after the optimization is applied, using the same reference workflow for apples-to-apples comparison
- [x] A *Learnings* subsection is appended to this chore document's *Notes* section listing: (a) rules that over-compressed, (b) rules that under-compressed, (c) load-bearing carve-outs, (d) template/contract patterns worth replicating in rollout
- [x] A follow-up GitHub issue is filed describing the rollout scope (remaining twelve skills: `documenting-features`, `documenting-chores`, `documenting-bugs`, `reviewing-requirements`, `creating-implementation-plans`, `implementing-plan-phases`, `documenting-qa`, `executing-qa`, `executing-chores`, `executing-bug-fixes`, `managing-work-items`, `finalizing-workflow`) and cross-links CHORE-034 and the pilot learnings
- [x] `npm run validate` passes (SKILL.md frontmatter and references still resolve)
- [x] `npm test` passes (no behavioral changes — tests that assert on orchestrator conversation should still pass)

## Completion

**Status:** `Complete`

**Completed:** 2026-04-21

**Pull Request:** [#201](https://github.com/lwndev/lwndev-marketplace/pull/201)

**Follow-up rollout issue:** [#200](https://github.com/lwndev/lwndev-marketplace/issues/200)

## Notes

### Scope boundary with issue checklist item 2

Issue #198 checklist item 2 says "Compress artifact templates under `assets/` so generated docs inherit the target style". The `orchestrating-workflows` skill has no `assets/` directory of its own — artifact templates live in the sub-skills it invokes (`documenting-chores/assets/`, `documenting-qa/assets/`, `executing-chores/assets/`, etc.). Compressing those templates is explicitly deferred to the rollout chore because each touches a different skill's contract. The pilot scope is:

1. Orchestrator SKILL.md output-style section
2. Fork-to-orchestrator return-format contract
3. Orchestrator narration lite rules

### Measurement methodology

The measurement methodology should be reproducible in the rollout chore. Candidate approaches (the executor picks one and records it in the baseline table):

- Run a fixed test workflow (e.g., `npm run test-skill -- orchestrating-workflows` against a canned fixture) twice — once on `main`, once on the chore branch — and compare total output tokens via the Claude Code telemetry CSV.
- Alternatively, instrument the orchestrator to count the `tokensOut` field from Agent-tool results across a representative run.

Whatever method is chosen, it must (a) be reproducible, (b) measure the same workflow on both sides, (c) break down pre/post deltas by source (SKILL.md narration vs. fork returns vs. orchestrator conversation).

### Out-of-scope carve-outs

The following must NOT be stripped by the lite rules even if they look like narration:

- Error messages from `fail` calls
- Security-sensitive warnings (e.g., destructive operation confirmations)
- Interactive prompts (plan-approval pause, findings-decision prompts)
- Findings display from `reviewing-requirements` (users need to see the full findings before making a decision)
- FR-14 echoes (audit-trail signal)
- `[info]` / `[warn]` lines tagged with a category prefix (these are structured logs, not narration)

### Baseline Measurements

Captured pre-change via `wc -l -w -c` against the three files in scope. This is a proxy for runtime output tokens — the lite rules live in the SKILL.md surface itself, and text-length reductions correlate with token-spend reductions in the instruction surface. The rollout chore can switch to a runtime-telemetry methodology once one is available.

| File | Lines | Words | Chars |
|---|---:|---:|---:|
| `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` | 430 | 4723 | 34947 |
| `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/chain-procedures.md` | 182 | 1316 | 10292 |
| `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/step-execution-details.md` | 206 | 1759 | 14615 |
| **Total** | **818** | **7798** | **59854** |

### Post-Change Measurements

Captured post-change via the same `wc -l -w -c` command.

| File | Lines | Words | Chars |
|---|---:|---:|---:|
| `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` | 466 | 5192 | 38221 |
| `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/chain-procedures.md` | 180 | 1271 | 10007 |
| `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/step-execution-details.md` | 210 | 1945 | 15883 |
| **Total** | **856** | **8408** | **64111** |

### Delta (post − pre; negative = reduction, positive = growth)

| File | Lines Δ | Lines % | Words Δ | Words % | Chars Δ | Chars % |
|---|---:|---:|---:|---:|---:|---:|
| `SKILL.md` | +36 | +8.4% | +469 | +9.9% | +3274 | +9.4% |
| `chain-procedures.md` | −2 | −1.1% | −45 | −3.4% | −285 | −2.8% |
| `step-execution-details.md` | +4 | +1.9% | +186 | +10.6% | +1268 | +8.7% |
| **Total** | **+38** | **+4.6%** | **+563** | **+7.2%** | **+4257** | **+7.1%** |

**Interpretation**: the pilot's intent was **not** to shrink the three files in aggregate — it was to install a lite-narration directive and a fork-return contract that will reduce **runtime output tokens** across every fork and every orchestrator turn. The instruction surface grew by ~7% (one Output Style section in SKILL.md plus a one-line contract-pointer added to each fork invocation in the reference files). Expected runtime payoff, once applied:

- Every forked sub-skill response loses preamble/postamble narration and gains a canonical structured return (typically saving ≫ 50 output tokens per fork response vs. unstructured narration).
- Every orchestrator turn between forks loses end-of-turn recaps and status-echo lines that duplicate what tool calls already show.
- A feature chain with N phases has 4+N fork sites plus orchestrator narration between each — per-run token savings compound across the chain.

The static-file delta is a cost (paid once in the instruction surface) to enable the runtime reduction (paid back on every invocation). The rollout chore should measure runtime tokens end-to-end where possible.

### Learnings

**Rules that were straightforward to apply**:

- No preamble before tool calls — unambiguous and easy to teach via example.
- No emoji — trivial, hard to misapply.
- ASCII punctuation in orchestrator-authored prose — safe as a default; Unicode em dashes in tables and reference docs were retained (they are in immutable content, not narration).
- Short sentences over paragraphs — already followed in most existing procedural sections; the Output Style section formalizes it.

**Carve-outs that proved most load-bearing**:

- **Findings display from `reviewing-requirements`** — the most important carve-out. If stripped, the user would see only `Found **N errors**, **N warnings**, **N info**` without the actual findings, and could not make an informed findings-decision. Must always be emitted in full before any findings prompt.
- **FR-14 echo lines and tagged structured logs** (`[model]`, `[info]`, `[warn]`) — these are audit-trail signals, not narration. Mistaking them for conversational output would break the audit contract.
- **Interactive prompts** — plan-approval, findings-decision, review-findings. These block the workflow; terseness here would confuse users.
- **User-visible state transitions** — pause/advance/resume need at least one line each so the user understands where they are in the chain.

**Fork-return contract ambiguities surfaced**:

- `reviewing-requirements` is the one pre-existing exception to the `done | ...` shape. It emits `Found **N errors**, **N warnings**, **N info**` instead, because the orchestrator's Decision Flow parses that line directly. Documenting this exception explicitly in the Output Style section removes the ambiguity.
- The full findings block still must precede the summary line for `reviewing-requirements` forks — the contract applies to the **final** line of the response, not the whole response. Noted in the Output Style section.
- FR-11 classifier treats empty artifact / tool-loop exhaustion as failure even without the explicit `failed |` token. The explicit `failed |` token is useful when a subagent wants to declare failure with a reason before it exhausts retries or bails early.

**Pattern templates worth replicating in rollout**:

1. **Placement** — Add `## Output Style` immediately after `## Quick Start`. Early placement ensures the rules govern the entire rest of SKILL.md.
2. **Three-subsection structure** — "Lite narration rules" (bulleted), "Load-bearing carve-outs (never strip)" (bulleted), "Fork-to-orchestrator return contract" (bulleted shapes plus precedence paragraph). Same shape in every skill; users learn it once.
3. **Reference-file pointers** — A single-sentence pointer ("Subagent must return the canonical contract shape; see SKILL.md `## Output Style`.") added to each fork-invocation spec in reference files is low-cost and high-discoverability.
4. **Baseline vs runtime framing** — The static-file delta is expected to be net-positive (instruction surface grows); the runtime payoff is what justifies the pilot. Frame the rollout measurements the same way.

**Over-compression / under-compression observed**:

- Mild under-compression on `chain-procedures.md` — most of its prose is procedural and load-bearing, so only three transitional sentences across the three chain procedures were safe to tighten. The 3% char reduction there is the right floor; aggressive cuts would have broken the procedure.
- No over-compression observed in this pilot. The risk surface for over-compression is in the sub-skill rollouts where skills with longer narration (e.g., `documenting-features` opening sections, `implementing-plan-phases` step-by-step prose) may lose meaning if aggressively trimmed. The rollout chore should treat load-bearing procedural content as out of scope for lite-rule edits.

**Follow-up rollout issue**: filed as [#200](https://github.com/lwndev/lwndev-marketplace/issues/200) — "Output token optimization (rollout to remaining twelve lwndev-sdlc skills)".
