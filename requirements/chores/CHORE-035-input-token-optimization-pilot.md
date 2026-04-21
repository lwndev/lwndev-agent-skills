# Chore: Input Token Optimization Pilot

## Chore ID

`CHORE-035`

## GitHub Issue

[#197](https://github.com/lwndev/lwndev-marketplace/issues/197)

## Category

`refactoring`

## Description

Pilot an input-token reduction pass on `orchestrating-workflows/SKILL.md` by compressing prose to *lite* style (drop filler, hedging, and pleasantries while keeping articles and full sentences), migrating heavy narrative sections into `references/`, and collapsing the three per-chain step-sequence tables into a single parameterized table plus a per-chain deltas note. Capture baseline/post measurements and learnings so the same pattern can be rolled out to the remaining twelve `lwndev-sdlc` skills in a follow-up chore. Sister effort to CHORE-034 (output token optimization), which targeted runtime output; this chore targets the instruction surface loaded on every invocation and fork.

## Affected Files

- `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` — compress prose to lite style; keep as a thin dispatcher with heavy narrative sections pointing to `references/`
- `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/chain-procedures.md` — receive any relocated chain-procedure narrative that was previously inlined in SKILL.md
- `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/step-execution-details.md` — receive any relocated step-execution narrative that was previously inlined in SKILL.md
- *(may create)* `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/*.md` — one or more new reference files if a relocated section does not fit an existing reference document
- `requirements/chores/CHORE-035-input-token-optimization-pilot.md` — baseline + post-change measurements and learnings appended to the Notes section on completion
- `qa/test-plans/QA-plan-CHORE-035.md` — adversarial QA test plan
- `qa/test-results/QA-results-CHORE-035.md` — QA test results artifact
- `scripts/__tests__/qa-CHORE-035.spec.ts` — QA test implementation (if applicable)

## Acceptance Criteria

- [ ] Prose in `orchestrating-workflows/SKILL.md` is compressed to *lite* style: filler, hedging, and pleasantries removed; articles and full sentences retained; code, paths, commands, and flags unchanged
- [ ] Heavy narrative sections in SKILL.md are migrated to `references/` so SKILL.md reads as a thin dispatcher, and every relocated section retains a single-sentence inline pointer to its new reference file. Operationalized as: no non-dispatcher section in SKILL.md exceeds roughly 25 lines, excluding the Output Style section (which is load-bearing and preserved verbatim) and bounded tables (chain-step table, override-precedence table)
- [ ] The three chain step-sequence tables (Feature Chain, Chore Chain, Bug Chain) are collapsed into one parameterized table plus a short per-chain deltas note that lists only the differences (step names, counts, pause points). The consolidated table remains in SKILL.md (tables are reference, not narrative — they belong with the dispatcher they index)
- [ ] All load-bearing carve-outs established by CHORE-034 are preserved verbatim: error messages from `fail`, security-sensitive warnings, interactive prompts, findings display from `reviewing-requirements`, FR-14 echo lines, tagged structured logs (`[info]`, `[warn]`, `[model]`), user-visible state transitions
- [ ] The Output Style section installed by CHORE-034 is preserved in full and placed immediately after Quick Start
- [ ] The fork-to-orchestrator return contract (three canonical shapes plus `reviewing-requirements` exception) is preserved in full
- [ ] All internal SKILL.md anchors and cross-skill references still resolve after the relocation
- [ ] A baseline measurement table is appended to this chore document's Notes section before the optimization is applied, capturing pre-change line, word, and character counts from `wc -l -w -c` for every file in Affected Files that receives edits (SKILL.md plus each reference file touched), plus an estimated input-token count for SKILL.md specifically (the per-invocation instruction surface is the quantity being optimized)
- [ ] A post-change measurement table is appended using the same files and method for apples-to-apples comparison
- [ ] A delta table reports pre/post differences per file and in aggregate (lines, words, chars), following the CHORE-034 format
- [ ] A Learnings subsection is appended to this chore document's Notes section listing: (a) mechanical edits vs. edits that required judgement, (b) carve-outs that mattered, (c) pitfalls (e.g., accidental meaning loss, broken cross-references, ambiguous antecedents after pronoun drops), (d) template/contract patterns worth replicating in rollout
- [ ] A follow-up GitHub issue is filed describing the rollout scope (remaining twelve skills: `documenting-features`, `documenting-chores`, `documenting-bugs`, `reviewing-requirements`, `creating-implementation-plans`, `implementing-plan-phases`, `documenting-qa`, `executing-qa`, `executing-chores`, `executing-bug-fixes`, `managing-work-items`, `finalizing-workflow`) and cross-links CHORE-035 and the pilot learnings
- [ ] `npm run validate` passes (SKILL.md frontmatter and reference links still resolve)
- [ ] `npm test` passes (no behavioral regressions)

## Completion

**Status:** `Pending`

**Completed:** YYYY-MM-DD

**Pull Request:** [#N](https://github.com/lwndev/lwndev-marketplace/pull/N)

## Notes

### Scope boundary with CHORE-034

CHORE-034 installed the *Output Style* section, the fork-to-orchestrator return contract, and lite-narration rules that govern runtime **output**. This chore tackles runtime **input** — the static SKILL.md text loaded into context on every orchestrator invocation and every forked sub-agent spawn. The two are orthogonal: CHORE-034 added instruction surface (net +~7%) to reduce runtime output; this chore reduces the instruction surface itself while preserving the output-style rules CHORE-034 established. None of the CHORE-034 directives may be removed or weakened.

**Sibling effort cross-links**: CHORE-034 tracked output tokens and shipped as issue [#198](https://github.com/lwndev/lwndev-marketplace/issues/198) (closed). The output-token rollout to the remaining twelve skills is tracked in issue [#200](https://github.com/lwndev/lwndev-marketplace/issues/200) (open). The input-token rollout (filed per the follow-up acceptance criterion) will be its own issue so the two axes remain independently trackable.

### Compression ground rules (inherited from CHORE-034 carve-outs)

The following must NOT be stripped by the lite rules even if they look like narration:

- Error messages from `fail` calls
- Security-sensitive warnings (destructive-operation confirmations, baseline-bypass warnings)
- Interactive prompts (plan-approval pause, findings-decision prompts)
- Findings display from `reviewing-requirements`
- FR-14 echo lines and tagged structured logs (`[info]`, `[warn]`, `[model]`)
- User-visible state transitions (pause, advance, resume announcements)
- Code blocks, command lines, flags, file paths, anchor identifiers, and table headers
- The Output Style section installed by CHORE-034

### Measurement methodology

Measurements are captured via `wc -l -w -c` against the files in scope, matching the CHORE-034 approach. An estimated input-token count is additionally captured for `SKILL.md` using an input-token estimator (Anthropic's `/v1/messages/count_tokens` endpoint is preferred since it targets the Claude tokenizer directly; a BPE-compatible estimator may be used as a fallback — the estimator chosen is recorded in the Baseline Measurements subsection). Both measurements are taken on the `main` branch before any edits land on the chore branch, and again after all edits are applied.

### Parameterized chain-step table

The three per-chain step-sequence tables duplicate a large amount of structure. They are consolidated into one parameterized table keyed by chain type (`feature`, `chore`, `bug`) with columns for step name, skill, and context. Per-chain deltas (different step counts for features because of the phase loop, different pause points) are captured in a short deltas note immediately below the unified table. The deltas note preserves every piece of information the three tables conveyed — nothing is lost, only deduplicated.

### Baseline Measurements

Captured pre-change via `wc -l -w -c` against the three in-scope files on the chore branch before any edits.

| File | Lines | Words | Chars |
|---|---:|---:|---:|
| `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` | 466 | 5246 | 38653 |
| `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/chain-procedures.md` | 180 | 1271 | 10007 |
| `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/step-execution-details.md` | 210 | 1945 | 15883 |
| **Total** | **856** | **8462** | **64543** |

**Input-token estimate for SKILL.md**: `ANTHROPIC_API_KEY` was not set in the executor environment, so the `chars / 4` rule-of-thumb fallback estimator was used (documented in the measurement methodology). Estimate: `38653 / 4 ≈ 9663 input tokens` for SKILL.md. This is the per-invocation instruction surface loaded on every orchestrator invocation and every forked sub-agent spawn — the quantity this chore is optimizing.

### Post-Change Measurements

*To be populated after optimization is applied.*

### Learnings

*To be populated after optimization is applied.*
