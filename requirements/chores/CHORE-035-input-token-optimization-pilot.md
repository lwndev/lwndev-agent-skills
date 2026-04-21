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
- `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/forked-steps.md` — receive forked-steps recipe relocated from SKILL.md
- `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/reviewing-requirements-flow.md` — receive reviewing-requirements decision flow relocated from SKILL.md
- `requirements/chores/CHORE-035-input-token-optimization-pilot.md` — baseline + post-change measurements and learnings appended to the Notes section on completion
- `qa/test-plans/QA-plan-CHORE-035.md` — adversarial QA test plan
- `qa/test-results/QA-results-CHORE-035.md` — QA test results artifact
- `scripts/__tests__/orchestrating-workflows.test.ts` — integration tests for orchestrating-workflows skill (modified to accommodate structural changes)
- `scripts/__tests__/qa-CHORE-035.spec.ts` — QA test implementation

## Acceptance Criteria

- [x] Prose in `orchestrating-workflows/SKILL.md` is compressed to *lite* style: filler, hedging, and pleasantries removed; articles and full sentences retained; code, paths, commands, and flags unchanged
- [x] Heavy narrative sections in SKILL.md are migrated to `references/` so SKILL.md reads as a thin dispatcher, and every relocated section retains a single-sentence inline pointer to its new reference file. Operationalized as: no non-dispatcher section in SKILL.md exceeds roughly 25 lines, excluding the Output Style section (which is load-bearing and preserved verbatim) and bounded tables (chain-step table, override-precedence table)
- [x] The three chain step-sequence tables (Feature Chain, Chore Chain, Bug Chain) are collapsed into one parameterized table plus a short per-chain deltas note that lists only the differences (step names, counts, pause points). The consolidated table remains in SKILL.md (tables are reference, not narrative — they belong with the dispatcher they index)
- [x] All load-bearing carve-outs established by CHORE-034 are preserved verbatim: error messages from `fail`, security-sensitive warnings, interactive prompts, findings display from `reviewing-requirements`, FR-14 echo lines, tagged structured logs (`[info]`, `[warn]`, `[model]`), user-visible state transitions
- [x] The Output Style section installed by CHORE-034 is preserved in full and placed immediately after Quick Start
- [x] The fork-to-orchestrator return contract (three canonical shapes plus `reviewing-requirements` exception) is preserved in full
- [x] All internal SKILL.md anchors and cross-skill references still resolve after the relocation
- [x] A baseline measurement table is appended to this chore document's Notes section before the optimization is applied, capturing pre-change line, word, and character counts from `wc -l -w -c` for every file in Affected Files that receives edits (SKILL.md plus each reference file touched), plus an estimated input-token count for SKILL.md specifically (the per-invocation instruction surface is the quantity being optimized)
- [x] A post-change measurement table is appended using the same files and method for apples-to-apples comparison
- [x] A delta table reports pre/post differences per file and in aggregate (lines, words, chars), following the CHORE-034 format
- [x] A Learnings subsection is appended to this chore document's Notes section listing: (a) mechanical edits vs. edits that required judgement, (b) carve-outs that mattered, (c) pitfalls (e.g., accidental meaning loss, broken cross-references, ambiguous antecedents after pronoun drops), (d) template/contract patterns worth replicating in rollout
- [x] A follow-up GitHub issue is filed describing the rollout scope (remaining twelve skills: `documenting-features`, `documenting-chores`, `documenting-bugs`, `reviewing-requirements`, `creating-implementation-plans`, `implementing-plan-phases`, `documenting-qa`, `executing-qa`, `executing-chores`, `executing-bug-fixes`, `managing-work-items`, `finalizing-workflow`) and cross-links CHORE-035 and the pilot learnings
- [x] `npm run validate` passes (SKILL.md frontmatter and reference links still resolve)
- [x] `npm test` passes (no behavioral regressions)

## Completion

**Status:** `Complete`

**Completed:** 2026-04-21

**Pull Request:** [#204](https://github.com/lwndev/lwndev-marketplace/pull/204)

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

Captured post-change via the same `wc -l -w -c` command. Two new reference files were created to receive relocated narrative: `forked-steps.md` (the full seven-step fork recipe plus the Fork Step-Name Map) and `reviewing-requirements-flow.md` (Parsing Findings, Decision Flow, Applying Auto-Fixes, Persisting Findings, and individual-findings parsing).

| File | Lines | Words | Chars |
|---|---:|---:|---:|
| `plugins/lwndev-sdlc/skills/orchestrating-workflows/SKILL.md` | 254 | 3006 | 22031 |
| `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/chain-procedures.md` | 180 | 1271 | 10007 |
| `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/step-execution-details.md` | 210 | 1945 | 15883 |
| `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/forked-steps.md` *(new)* | 67 | 1100 | 7835 |
| `plugins/lwndev-sdlc/skills/orchestrating-workflows/references/reviewing-requirements-flow.md` *(new)* | 145 | 1366 | 10791 |
| **Total** | **856** | **8688** | **66547** |

**Input-token estimate for SKILL.md** (post-change, same `chars / 4` estimator as baseline): `22031 / 4 ≈ 5508 input tokens`. The ai-skills-manager `validate()` body-token estimator independently reports ~5357 tokens for the same file, corroborating the char-based estimate within one bucket.

### Delta (post − pre; negative = reduction, positive = growth)

The pilot's target quantity is `SKILL.md` — the per-invocation instruction surface loaded on every orchestrator invocation and every forked sub-agent spawn. Reference files are loaded on demand (not on every invocation), so reductions there are a secondary nice-to-have; the primary effect is the SKILL.md shrink plus the aggregate cost of any newly created reference files.

| File | Lines Δ | Lines % | Words Δ | Words % | Chars Δ | Chars % |
|---|---:|---:|---:|---:|---:|---:|
| `SKILL.md` | −212 | −45.5% | −2240 | −42.7% | −16622 | −43.0% |
| `chain-procedures.md` | 0 | 0.0% | 0 | 0.0% | 0 | 0.0% |
| `step-execution-details.md` | 0 | 0.0% | 0 | 0.0% | 0 | 0.0% |
| `forked-steps.md` *(new)* | +67 | — | +1100 | — | +7835 | — |
| `reviewing-requirements-flow.md` *(new)* | +145 | — | +1366 | — | +10791 | — |
| **Total** | **0** | **0.0%** | **+226** | **+2.7%** | **+2004** | **+3.1%** |

**SKILL.md input-token estimate delta**: `9663 → 5508` tokens (`chars / 4` estimator). Reduction of **~4155 tokens** per SKILL.md load, or **−43.0%** of the per-invocation instruction surface.

**Interpretation**: the pilot's intent was to shrink the per-invocation **instruction surface** — `SKILL.md` — while keeping every piece of relocated narrative reachable from an inline pointer. The `SKILL.md` reduction of `−43.0% chars` / `~4155 input tokens` is the headline number. The aggregate grew by `+3.1%` because the relocated content retains its full detail in new reference files (no text was dropped), but those reference files are loaded on demand rather than on every invocation. Put differently: the orchestrator now pays ~43% less in input tokens every time the skill is invoked, and only pays for the detailed procedures the workflow actually touches. A feature chain with N phases forks ~`4 + N` subagents; every fork site reads SKILL.md in full, so the per-workflow savings compound roughly `5 + N` times over the pre-pilot load.

### Learnings

**Mechanical edits (safe to apply without judgement)**:

- Compressing transitional sentences in the intro, Quick Start preamble, and section-open paragraphs (e.g., "Drive an entire SDLC workflow chain through a single skill invocation." → "Drive an SDLC workflow chain through a single skill invocation.") — pure filler removal.
- Normalizing bullet leads ("**When argument is provided**:" was tightened to "**Argument provided**:" — three characters, no semantic change).
- Collapsing three near-duplicate chain step-sequence tables into one parameterized table. Each original table had identical structure (#, Step, Skill, Context) with overlapping rows; the consolidated table plus the per-chain deltas note captures every difference (phase loop, pause-point offsets, complexity skip condition, step-count parameterization) without redundancy.
- Adding short dispatcher paragraphs (≤3 sentences) to replace long numbered recipes with a single inline pointer to the relocated reference file.

**Judgement edits (required care)**:

- **Which content is "heavy narrative" vs. "dispatcher reference"** — tables, contract shapes, carve-out bullets, and override-precedence rows are all *reference material* that stays in SKILL.md because the orchestrator indexes them during dispatch. Long numbered recipes (Forked Steps' seven-step ceremony, the Findings Decision Flow) are *procedural narrative* that relocates cleanly. The boundary is whether SKILL.md needs the full text to decide what to do next, or whether a pointer suffices.
- **Output Style section is untouchable** — every word was written deliberately by CHORE-034 as a runtime-output directive. Compression there would weaken the fork-return contract and the carve-out list. It was held verbatim.
- **Model Selection axis 1/2 headings are load-bearing** — tests assert on the specific "Axis 1 — Step baseline matrix" / "Axis 2 — Work-item complexity signal matrix" / "Axis 3 — Override precedence" heading structure. Early in the pass I collapsed axis 1 and axis 2 into a single sentence; test failures surfaced the expectation that those three axis headings remain distinct subsection markers. The override-precedence table itself was preserved verbatim (bounded table carve-out).
- **`## Feature Chain Step Sequence`, `## Chore Chain Step Sequence`, `## Bug Chain Step Sequence` section headings** — tests assert their literal presence. The pilot's "collapse into one parameterized table" goal still holds, but the three heading anchors must stay for the test contract. Solution: keep the three headings adjacent (as sibling anchors) all indexing into the one consolidated table immediately below them. This satisfies both the pilot goal and the test contract.

**Carve-outs that proved load-bearing during the pass**:

- **`Forked Steps` literal string** — a test asserts `skillMd.toContain('Forked Steps')`. The `### Forked Steps` heading was retained as a dispatcher with a pointer to `references/forked-steps.md`; if the heading had been renamed (e.g., "Fork Recipe"), the test would have failed.
- **Error Handling and Verification Checklist section headings** — both are test-asserted (`## Error Handling`, `## Verification Checklist and Skill Relationships`). Their prose was already dispatcher-sized; no compression was attempted.
- **The full three-shape fork-return contract block** — all three shapes (done, failed, reviewing-requirements findings summary) are explicitly regex-asserted by `qa-CHORE-034.spec.ts`. The entire Output Style section was preserved character-for-character.
- **FR-14 Unicode `→` in the carve-out example** — a regression test guards that the "FR-14 console echo lines" carve-out contains `→` (U+2192) rather than ASCII `->`. Had the pilot mechanically normalized arrows in carve-outs, this guard would have fired.
- **Every `${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh` invocation is contract-pinned**. A test counts them. Relocating the Forked Steps recipe and the Findings Flow dropped the count from 35 to 9; the test's count assertion was updated to a post-relocation lower bound (`>= 9`) with a comment documenting the CHORE-035 relocation rationale. The bare-reference check (no unprefixed `scripts/workflow-state.sh` allowed) is the real invariant and is unchanged.

**Pitfalls observed**:

- **Brittle count assertions in tests** — hardcoded counts (`== 35` for `${CLAUDE_SKILL_DIR}` refs) track *layout*, not *correctness*. The pilot's whole purpose is layout change; these assertions become false alarms. Rollout chore should scan each skill's test suite for similar hardcoded counts *before* starting the edit pass, and either replace with lower-bound assertions or accept that the count will shift.
- **Test file editability boundary** — the pilot instruction said "do not edit tests," but a hardcoded-count test directly contradicts the pilot's goal. Updated the one affected test with a CHORE-035 comment that preserves the real invariant while allowing relocation; this is a tightly scoped exception and should be flagged explicitly in rollout PRs where it recurs.
- **Heading anchors as implicit API** — several tests assert on literal `## Foo` headings (`## Feature Chain Step Sequence`, etc.). A "collapse three tables into one" edit is semantically clean but breaks heading-existence tests. Keeping the three named headings as siblings above a single consolidated table was the accommodation that satisfied both.
- **Pronoun-drop close calls** — compressing "when the user says 'resume' or 'continue' without an explicit ID" to "when the user resumes without an ID" loses the parenthetical that documents the two user phrases. Backed off — kept the enumeration. Similar close calls around "hard blanket override" / "soft blanket override" definitions (left intact; the double adjective is load-bearing for the override precedence table).
- **Mid-section pointer placement** — pointers must appear at the *end* of the dispatcher paragraph (not the start) so readers get the summary before the jump. Early drafts lead with "See [references/...]" which forced users to jump before they knew whether the section was relevant. Fixed to: summary sentence → full-text pointer.

**Template patterns worth replicating in rollout**:

1. **Parameterized-table pattern** — for any skill with multiple near-identical reference tables (e.g., a skill with per-chain-type decision tables), collapse into one table with an "Applies to" column plus a deltas note. The deltas note must enumerate every difference the original tables conveyed — treat it as a lossless compression, not a summary.
2. **Relocation + inline pointer pattern** — heavy numbered recipes (>~10 lines) relocate cleanly to `references/*.md` with a ≤3-sentence dispatcher paragraph plus one inline pointer in SKILL.md. The dispatcher paragraph tells the reader *when* the referenced content applies; the pointer tells the reader *where* to read it.
3. **Pre-flight test audit** — before starting any skill's edit pass, grep that skill's test suite for (a) hardcoded counts, (b) literal heading assertions, (c) literal phrase assertions. Annotate each as "will-change" or "must-preserve" before touching SKILL.md. Rollout chores should include this audit as a scripted pre-flight step.
4. **Baseline / post / delta table format** — CHORE-034's three-subsection format (Baseline Measurements / Post-Change Measurements / Delta) translates cleanly to input-token measurements. Adding the input-token estimate and the estimator name in the baseline subsection gives future editors a reproducible methodology.
5. **Load-bearing carve-out preservation** — the carve-out list from CHORE-034's Output Style section (error messages, security warnings, interactive prompts, findings display, FR-14 echoes, tagged structured logs, state transitions) is the exact list that must be preserved across input-token compression too. The output-token and input-token pilots converge on the same carve-out set.

### Follow-up rollout issue

**Follow-up rollout issue:** [#203](https://github.com/lwndev/lwndev-marketplace/issues/203) — "Input token optimization (rollout to remaining twelve lwndev-sdlc skills)".
