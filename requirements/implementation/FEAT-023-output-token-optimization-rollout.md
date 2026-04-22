# Implementation Plan: Output Token Optimization Rollout

## Overview

Roll out the output-token optimization pattern piloted in CHORE-034 to the remaining twelve `lwndev-sdlc` skills. Each skill gains an `## Output Style` section (lite narration rules + load-bearing carve-outs + fork-to-orchestrator return contract), its `references/` directory is checked for fork-invocation specs that need a pointer, and its `assets/` artifact templates are reviewed for prose compression. Baseline and post-change `wc -l -w -c` measurements are captured per skill and aggregated in a final phase.

The pilot (`orchestrating-workflows`, CHORE-034) established the template. This rollout replicates that template mechanically across twelve skills ordered from lowest risk to highest, validating the pattern on small/simple skills before touching the most-invoked ones.

## Features Summary

| Feature ID | GitHub Issue | Feature Document | Priority | Complexity | Status |
|------------|--------------|------------------|----------|------------|--------|
| FEAT-023 | [#200](https://github.com/lwndev/lwndev-marketplace/issues/200) | [FEAT-023-output-token-optimization-rollout.md](../features/FEAT-023-output-token-optimization-rollout.md) | Medium | Low | Pending |

## Recommended Build Sequence

Phase ordering follows the risk-ordering suggestion from the skill guidance: smallest/simplest surface first, so the pattern is validated before touching large or heavily-invoked skills. Each phase covers exactly one skill (NFR-2). No grouping is applied — every skill has at least one non-trivial editorial decision (placement, role-specific contract wording, assets review), making independent review valuable for each.

---

### Phase 1: `finalizing-workflow` — smallest surface, SKILL.md only
**Feature:** [FEAT-023](../features/FEAT-023-output-token-optimization-rollout.md) | [#200](https://github.com/lwndev/lwndev-marketplace/issues/200)
**Status:** ✅ Complete

#### Rationale
- Smallest surface of all twelve skills: SKILL.md only (72 lines, no `references/`, no `assets/`).
- FR-3 and FR-4 do not apply; FR-5 scope is SKILL.md only.
- `finalizing-workflow` is a forked skill — it emits `done | artifact=... | <note>` on success and `failed | <reason>` on failure.
- Validating the pattern here at minimum risk before touching any skill with references or assets.

#### Implementation Steps
1. **Baseline measurement**: `wc -l -w -c plugins/lwndev-sdlc/skills/finalizing-workflow/SKILL.md` — record in Notes of FEAT-023 requirements doc.
2. **Identify placement**: locate `## Quick Start` in SKILL.md. If absent, use the first early-read section (`## When to Use This Skill`, `## Workflow Position`, etc.).
3. **Add `## Output Style` section** immediately after the identified placement anchor, containing the three subsections in order:
   - `### Lite narration rules` — seven bullets (no preamble, no end-of-turn summaries, no emoji, no restating user, no status echoes, ASCII punctuation/arrows in skill-authored prose, short sentences and bullets).
   - `### Load-bearing carve-outs (never strip)` — seven bullets matching the pilot's list (error messages, security warnings, interactive prompts, findings display, FR-14 echo lines, tagged structured logs, user-visible state transitions).
   - `### Fork-to-orchestrator return contract` — note that `finalizing-workflow` is invoked as a forked step by `orchestrating-workflows`; it emits `done | artifact=<path> | <note>` on success and `failed | <reason>` on failure. Include precedence clause.
4. **FR-3 check**: `finalizing-workflow` has no `references/` directory — FR-3 is a no-op. Record in FEAT-023 Notes.
5. **FR-4 check**: `finalizing-workflow` has no `assets/` directory — FR-4 is a no-op. Record in FEAT-023 Notes.
6. **Post-change measurement**: `wc -l -w -c plugins/lwndev-sdlc/skills/finalizing-workflow/SKILL.md` — record delta in FEAT-023 Notes.
7. **Validate**: `npm run validate`.
8. **Emit fork return**: `done | artifact=plugins/lwndev-sdlc/skills/finalizing-workflow/SKILL.md | Output Style section added`.

#### Deliverables
- [x] `plugins/lwndev-sdlc/skills/finalizing-workflow/SKILL.md` — `## Output Style` section added with three subsections
- [x] Baseline + post-change measurements recorded in FEAT-023 Notes
- [x] FR-3 and FR-4 no-ops recorded in FEAT-023 Notes
- [x] `npm run validate` passes

---

### Phase 2: `managing-work-items` — cross-cutting inline skill, no assets
**Feature:** [FEAT-023](../features/FEAT-023-output-token-optimization-rollout.md) | [#200](https://github.com/lwndev/lwndev-marketplace/issues/200)
**Status:** ✅ Complete

#### Rationale
- `managing-work-items` has no `assets/` directory — FR-4 is a no-op. It does have two `references/` files (`github-templates.md`, `jira-templates.md`) to check for FR-3.
- It is a cross-cutting inline skill (invoked directly from main context by the orchestrator, not as an Agent fork) — the return-contract subsection must note inline execution rather than the `done | ...` shape.
- Handling the inline-skill special case early validates the contract wording before the main forked-skill pattern is repeated ten more times.

#### Implementation Steps
1. **Baseline measurement**: `wc -l -w -c` on `SKILL.md`, `references/github-templates.md`, `references/jira-templates.md` — record in FEAT-023 Notes.
2. **Identify placement**: locate `## Quick Start` (or first early-read section if absent). `managing-work-items` has no `## Quick Start` — check current headers.
3. **Add `## Output Style` section** after the identified placement anchor:
   - `### Lite narration rules` — same seven bullets as Phase 1.
   - `### Load-bearing carve-outs (never strip)` — same seven bullets as Phase 1.
   - `### Fork-to-orchestrator return contract` — note that `managing-work-items` is a cross-cutting inline skill invoked from main context by the orchestrator (not as an Agent fork). The `done | ...` and `failed | ...` shapes do not apply to its return. Lite narration rules and carve-outs still govern its output.
4. **FR-3 check**: search `references/github-templates.md` and `references/jira-templates.md` for fork/Agent invocation specs. These files contain templates for GitHub and Jira API interactions — they document API call patterns but do not describe spawning subagents via the Agent tool. Record as no-op in FEAT-023 Notes.
5. **FR-4 check**: no `assets/` directory — FR-4 is a no-op. Record in FEAT-023 Notes.
6. **Post-change measurement**: `wc -l -w -c` on the same file set — record delta in FEAT-023 Notes.
7. **Validate**: `npm run validate`.
8. **Emit fork return**: `done | artifact=plugins/lwndev-sdlc/skills/managing-work-items/SKILL.md | Output Style section added`.

#### Deliverables
- [x] `plugins/lwndev-sdlc/skills/managing-work-items/SKILL.md` — `## Output Style` section added with inline-execution contract note
- [x] Baseline + post-change measurements recorded in FEAT-023 Notes
- [x] FR-3 no-ops for both reference files recorded in FEAT-023 Notes
- [x] FR-4 no-op recorded in FEAT-023 Notes
- [x] `npm run validate` passes

---

### Phase 3: `documenting-features` — main-context skill
**Feature:** [FEAT-023](../features/FEAT-023-output-token-optimization-rollout.md) | [#200](https://github.com/lwndev/lwndev-marketplace/issues/200)
**Status:** ✅ Complete

#### Rationale
- `documenting-features` is a main-context skill (runs directly in the orchestrator's conversation, not as an Agent fork). Its return-contract subsection notes it returns to the user, not a parent orchestrator.
- Has one `assets/` file (`feature-requirements.md`) and two `references/` files (example feature documents). Handling it next tests the main-context wording and the assets-review step on a representative skill.
- Sibling to `documenting-chores` and `documenting-bugs` — establishing the pattern here makes Phases 4 and 5 straightforward.

#### Implementation Steps
1. **Baseline measurement**: `wc -l -w -c` on `SKILL.md`, both `references/` files, and `assets/feature-requirements.md` — record in FEAT-023 Notes.
2. **Identify placement**: `documenting-features` has `## Quick Start` — add `## Output Style` immediately after it.
3. **Add `## Output Style` section**:
   - `### Lite narration rules` — seven bullets (standard).
   - `### Load-bearing carve-outs (never strip)` — seven bullets (standard).
   - `### Fork-to-orchestrator return contract` — note that `documenting-features` runs in main context (step 1 of the feature chain), not as a fork. It returns to the user, not to a parent orchestrator. The `done | ...` shape is not required.
4. **FR-3 check**: search `references/feature-requirements-example-episodes-command.md` and `references/feature-requirements-example-search-command.md` for fork/Agent invocation specs. These are example requirement documents, not invocation specs — no pointer needed. Record as no-op in FEAT-023 Notes.
5. **FR-4 review**: open `assets/feature-requirements.md`. This is a structural template (headers + placeholder sections). Assess whether any preamble or prose-heavy intro text can be compressed to meet the ~3% char floor. Apply tightening if prose-compressible; otherwise record as already-minimal in FEAT-023 Notes.
6. **Post-change measurement**: `wc -l -w -c` on the same file set — record delta in FEAT-023 Notes.
7. **Validate**: `npm run validate`.
8. **Emit fork return**: `done | artifact=plugins/lwndev-sdlc/skills/documenting-features/SKILL.md | Output Style section added`.

#### Deliverables
- [x] `plugins/lwndev-sdlc/skills/documenting-features/SKILL.md` — `## Output Style` section with main-context return-contract note
- [x] `assets/feature-requirements.md` — compressed or marked already-minimal in FEAT-023 Notes
- [x] Baseline + post-change measurements recorded in FEAT-023 Notes
- [x] FR-3 no-ops for both reference files recorded in FEAT-023 Notes
- [x] `npm run validate` passes

---

### Phase 4: `documenting-chores` — main-context skill, sibling to Phase 3
**Feature:** [FEAT-023](../features/FEAT-023-output-token-optimization-rollout.md) | [#200](https://github.com/lwndev/lwndev-marketplace/issues/200)
**Status:** Pending

#### Rationale
- Same shape as `documenting-features`: main-context, one `assets/` file, one `references/` file. Phase 3 establishes the pattern; this is a straight replication.
- Sibling to `documenting-bugs` (Phase 5) — handling them sequentially ensures consistency.

#### Implementation Steps
1. **Baseline measurement**: `wc -l -w -c` on `SKILL.md`, `references/categories.md`, and `assets/chore-document.md` — record in FEAT-023 Notes.
2. **Identify placement**: `documenting-chores` has `## Quick Start` — add `## Output Style` immediately after it.
3. **Add `## Output Style` section**:
   - `### Lite narration rules` — seven bullets (standard, matching Phase 3 wording exactly).
   - `### Load-bearing carve-outs (never strip)` — seven bullets (standard).
   - `### Fork-to-orchestrator return contract` — note that `documenting-chores` runs in main context (step 1 of the chore chain), not as a fork. Returns to the user, not a parent orchestrator. The `done | ...` shape is not required.
4. **FR-3 check**: search `references/categories.md` for fork/Agent invocation specs. This is a reference table of chore categories — no fork invocations. Record as no-op in FEAT-023 Notes.
5. **FR-4 review**: open `assets/chore-document.md`. Assess for preamble or compressible prose. Apply tightening or record as already-minimal.
6. **Post-change measurement**: `wc -l -w -c` on the same file set — record delta in FEAT-023 Notes.
7. **Validate**: `npm run validate`.
8. **Emit fork return**: `done | artifact=plugins/lwndev-sdlc/skills/documenting-chores/SKILL.md | Output Style section added`.

#### Deliverables
- [ ] `plugins/lwndev-sdlc/skills/documenting-chores/SKILL.md` — `## Output Style` section with main-context return-contract note
- [ ] `assets/chore-document.md` — compressed or marked already-minimal in FEAT-023 Notes
- [ ] Baseline + post-change measurements recorded in FEAT-023 Notes
- [ ] FR-3 no-op for `categories.md` recorded in FEAT-023 Notes
- [ ] `npm run validate` passes

---

### Phase 5: `documenting-bugs` — main-context skill, sibling to Phases 3–4
**Feature:** [FEAT-023](../features/FEAT-023-output-token-optimization-rollout.md) | [#200](https://github.com/lwndev/lwndev-marketplace/issues/200)
**Status:** Pending

#### Rationale
- Same shape as `documenting-chores`. Direct sibling; pattern is now well-validated from Phases 3–4.
- One `assets/` file (`bug-document.md`), one `references/` file (`categories.md` for bug categories).

#### Implementation Steps
1. **Baseline measurement**: `wc -l -w -c` on `SKILL.md`, `references/categories.md`, and `assets/bug-document.md` — record in FEAT-023 Notes.
2. **Identify placement**: `documenting-bugs` has `## Quick Start` — add `## Output Style` immediately after it.
3. **Add `## Output Style` section**:
   - `### Lite narration rules` — seven bullets (standard, consistent with Phases 3–4).
   - `### Load-bearing carve-outs (never strip)` — seven bullets (standard).
   - `### Fork-to-orchestrator return contract` — note that `documenting-bugs` runs in main context (step 1 of the bug chain), not as a fork. Returns to the user, not a parent orchestrator. The `done | ...` shape is not required.
4. **FR-3 check**: search `references/categories.md` for fork/Agent invocation specs. This is a bug-category reference table — no fork invocations. Record as no-op in FEAT-023 Notes.
5. **FR-4 review**: open `assets/bug-document.md`. Assess for preamble or compressible prose. Apply tightening or record as already-minimal.
6. **Post-change measurement**: `wc -l -w -c` on the same file set — record delta in FEAT-023 Notes.
7. **Validate**: `npm run validate`.
8. **Emit fork return**: `done | artifact=plugins/lwndev-sdlc/skills/documenting-bugs/SKILL.md | Output Style section added`.

#### Deliverables
- [ ] `plugins/lwndev-sdlc/skills/documenting-bugs/SKILL.md` — `## Output Style` section with main-context return-contract note
- [ ] `assets/bug-document.md` — compressed or marked already-minimal in FEAT-023 Notes
- [ ] Baseline + post-change measurements recorded in FEAT-023 Notes
- [ ] FR-3 no-op for `categories.md` recorded in FEAT-023 Notes
- [ ] `npm run validate` passes

---

### Phase 6: `reviewing-requirements` — forked skill, exception return shape
**Feature:** [FEAT-023](../features/FEAT-023-output-token-optimization-rollout.md) | [#200](https://github.com/lwndev/lwndev-marketplace/issues/200)
**Status:** Pending

#### Rationale
- `reviewing-requirements` is the one skill with a non-standard return shape: it emits `Found **N errors**, **N warnings**, **N info**` rather than `done | ...`. This exception must be documented carefully.
- Has the largest SKILL.md of the forked skills (393 lines). Handling it before `creating-implementation-plans` and `implementing-plan-phases` keeps complexity increasing monotonically.
- Has one `references/` file (`review-example.md`) and one `assets/` file (`review-findings-template.md`).

#### Implementation Steps
1. **Baseline measurement**: `wc -l -w -c` on `SKILL.md`, `references/review-example.md`, and `assets/review-findings-template.md` — record in FEAT-023 Notes.
2. **Identify placement**: `reviewing-requirements` has `## Quick Start` — add `## Output Style` immediately after it.
3. **Add `## Output Style` section**:
   - `### Lite narration rules` — seven bullets (standard).
   - `### Load-bearing carve-outs (never strip)` — seven bullets (standard), with explicit note that the full findings block (Step 8) must be emitted before the summary line even if it appears narration-heavy — this is the carve-out for findings display.
   - `### Fork-to-orchestrator return contract` — note that `reviewing-requirements` is forked by `orchestrating-workflows`. It emits a **non-standard** return shape: `Found **N errors**, **N warnings**, **N info**` as the final line of its response. It does NOT emit `done | ...`. The full findings block must precede the summary line. The precedence clause still applies — this summary line is the mandatory final line of the response.
4. **FR-3 check**: search `references/review-example.md` for fork/Agent invocation specs. This is an annotated example of a review findings document — no fork invocations described. Record as no-op in FEAT-023 Notes.
5. **FR-4 review**: open `assets/review-findings-template.md`. This is a structured template for the findings output. Assess whether any template prose is safely compressible without losing structural intent. Apply tightening or record as already-minimal.
6. **Post-change measurement**: `wc -l -w -c` on the same file set — record delta in FEAT-023 Notes.
7. **Validate**: `npm run validate`.
8. **Emit fork return**: `done | artifact=plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md | Output Style section added with exception return shape`.

#### Deliverables
- [ ] `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` — `## Output Style` section with `Found **N errors** ...` exception documented
- [ ] `assets/review-findings-template.md` — compressed or marked already-minimal in FEAT-023 Notes
- [ ] Baseline + post-change measurements recorded in FEAT-023 Notes
- [ ] FR-3 no-op for `review-example.md` recorded in FEAT-023 Notes
- [ ] `npm run validate` passes

---

### Phase 7: `creating-implementation-plans` — forked skill, meta (this very skill)
**Feature:** [FEAT-023](../features/FEAT-023-output-token-optimization-rollout.md) | [#200](https://github.com/lwndev/lwndev-marketplace/issues/200)
**Status:** Pending

#### Rationale
- `creating-implementation-plans` is the skill being used to produce this plan — updating it mid-rollout is intentionally deferred until Phase 7 so the plan-producing invocation runs on the pre-change version.
- Has one `references/` file (`implementation-plan-example.md`, 499 lines) and one `assets/` file (`implementation-plan.md`, 79 lines — the template skeleton used by this plan). Large reference file warrants careful FR-3 check.
- Standard `done | ...` return shape.

#### Implementation Steps
1. **Baseline measurement**: `wc -l -w -c` on `SKILL.md`, `references/implementation-plan-example.md`, and `assets/implementation-plan.md` — record in FEAT-023 Notes.
2. **Identify placement**: `creating-implementation-plans` has `## Quick Start` — add `## Output Style` immediately after it.
3. **Add `## Output Style` section**:
   - `### Lite narration rules` — seven bullets (standard).
   - `### Load-bearing carve-outs (never strip)` — seven bullets (standard).
   - `### Fork-to-orchestrator return contract` — note that `creating-implementation-plans` is forked by `orchestrating-workflows` (feature chain step 3). Emits `done | artifact=<path> | <note>` on success and `failed | <reason>` on failure. Include precedence clause.
4. **FR-3 check**: search `references/implementation-plan-example.md` for fork/Agent invocation specs. This is an example implementation plan document — it describes phases and steps but does not describe spawning subagents. Record as no-op in FEAT-023 Notes.
5. **FR-4 review**: open `assets/implementation-plan.md` (the structural skeleton). This template is headers + placeholder text with no preamble prose. Assess — likely already-minimal. Record finding in FEAT-023 Notes.
6. **Post-change measurement**: `wc -l -w -c` on the same file set — record delta in FEAT-023 Notes.
7. **Validate**: `npm run validate`.
8. **Emit fork return**: `done | artifact=plugins/lwndev-sdlc/skills/creating-implementation-plans/SKILL.md | Output Style section added`.

#### Deliverables
- [ ] `plugins/lwndev-sdlc/skills/creating-implementation-plans/SKILL.md` — `## Output Style` section added
- [ ] `assets/implementation-plan.md` — compressed or marked already-minimal in FEAT-023 Notes
- [ ] Baseline + post-change measurements recorded in FEAT-023 Notes
- [ ] FR-3 no-op for `implementation-plan-example.md` recorded in FEAT-023 Notes
- [ ] `npm run validate` passes

---

### Phase 8: `documenting-qa` — main-context skill, no references
**Feature:** [FEAT-023](../features/FEAT-023-output-token-optimization-rollout.md) | [#200](https://github.com/lwndev/lwndev-marketplace/issues/200)
**Status:** Pending

#### Rationale
- `documenting-qa` is a main-context skill (runs in the orchestrator's conversation). It has no `references/` directory — FR-3 is a no-op.
- Has two `assets/` files (`test-plan-template-v2.md` and `test-plan-template.md`). Sibling to `executing-qa` (Phase 9).
- Handling the QA pair (Phases 8–9) together in sequence ensures consistent wording before moving to the longer forked skills.

#### Implementation Steps
1. **Baseline measurement**: `wc -l -w -c` on `SKILL.md`, `assets/test-plan-template-v2.md`, and `assets/test-plan-template.md` — record in FEAT-023 Notes.
2. **Identify placement**: `documenting-qa` has `## Quick Start` — add `## Output Style` immediately after it.
3. **Add `## Output Style` section**:
   - `### Lite narration rules` — seven bullets (standard).
   - `### Load-bearing carve-outs (never strip)` — seven bullets (standard).
   - `### Fork-to-orchestrator return contract` — note that `documenting-qa` runs in main context (feature chain step 5, chore/bug chain step 3), not as a fork. Returns to the user, not a parent orchestrator. The `done | ...` shape is not required.
4. **FR-3 check**: `documenting-qa` has no `references/` directory — FR-3 is a no-op (Edge Case 1). Record in FEAT-023 Notes.
5. **FR-4 review**: open both `assets/test-plan-template-v2.md` and `assets/test-plan-template.md`. These are structured test-plan templates. Assess each for preamble or compressible prose. Apply tightening where safe or record as already-minimal. The v2 template is the active one — apply more scrutiny there.
6. **Post-change measurement**: `wc -l -w -c` on the same file set — record delta in FEAT-023 Notes.
7. **Validate**: `npm run validate`.
8. **Emit fork return**: `done | artifact=plugins/lwndev-sdlc/skills/documenting-qa/SKILL.md | Output Style section added`.

#### Deliverables
- [ ] `plugins/lwndev-sdlc/skills/documenting-qa/SKILL.md` — `## Output Style` section with main-context return-contract note
- [ ] Both `assets/` template files — compressed or marked already-minimal in FEAT-023 Notes
- [ ] Baseline + post-change measurements recorded in FEAT-023 Notes
- [ ] FR-3 no-op recorded in FEAT-023 Notes
- [ ] `npm run validate` passes

---

### Phase 9: `executing-qa` — main-context skill, no references
**Feature:** [FEAT-023](../features/FEAT-023-output-token-optimization-rollout.md) | [#200](https://github.com/lwndev/lwndev-marketplace/issues/200)
**Status:** Pending

#### Rationale
- `executing-qa` is a main-context skill (runs in the orchestrator's conversation). Like `documenting-qa`, it has no `references/` directory — FR-3 is a no-op.
- Has two `assets/` files (`test-results-template-v2.md` and `test-results-template.md`). Sibling pattern to Phase 8.
- Directly follows Phase 8 to maximize consistency while the QA template wording is fresh.

#### Implementation Steps
1. **Baseline measurement**: `wc -l -w -c` on `SKILL.md`, `assets/test-results-template-v2.md`, and `assets/test-results-template.md` — record in FEAT-023 Notes.
2. **Identify placement**: `executing-qa` has `## Quick Start` — add `## Output Style` immediately after it.
3. **Add `## Output Style` section**:
   - `### Lite narration rules` — seven bullets (standard).
   - `### Load-bearing carve-outs (never strip)` — seven bullets (standard).
   - `### Fork-to-orchestrator return contract` — note that `executing-qa` runs in main context (feature chain step 5+N+3, chore/bug chain step 6), not as a fork. Returns to the user, not a parent orchestrator. The `done | ...` shape is not required.
4. **FR-3 check**: `executing-qa` has no `references/` directory — FR-3 is a no-op (Edge Case 1). Record in FEAT-023 Notes.
5. **FR-4 review**: open both `assets/test-results-template-v2.md` and `assets/test-results-template.md`. These are structured results templates. Assess for preamble or compressible prose. Apply tightening where safe or record as already-minimal.
6. **Post-change measurement**: `wc -l -w -c` on the same file set — record delta in FEAT-023 Notes.
7. **Validate**: `npm run validate`.
8. **Emit fork return**: `done | artifact=plugins/lwndev-sdlc/skills/executing-qa/SKILL.md | Output Style section added`.

#### Deliverables
- [ ] `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` — `## Output Style` section with main-context return-contract note
- [ ] Both `assets/` template files — compressed or marked already-minimal in FEAT-023 Notes
- [ ] Baseline + post-change measurements recorded in FEAT-023 Notes
- [ ] FR-3 no-op recorded in FEAT-023 Notes
- [ ] `npm run validate` passes

---

### Phase 10: `implementing-plan-phases` — forked skill, longest SKILL.md
**Feature:** [FEAT-023](../features/FEAT-023-output-token-optimization-rollout.md) | [#200](https://github.com/lwndev/lwndev-marketplace/issues/200)
**Status:** Pending

#### Rationale
- `implementing-plan-phases` has the largest combined surface of the forked skills: 142-line SKILL.md, two `references/` files totaling 726 lines, and one `assets/` file (`pr-template.md`, 163 lines).
- It is a forked skill (feature chain steps 6…5+N) — standard `done | ...` return shape.
- Deferred to Phase 10 (after simpler forked skills) because the large reference surface increases the risk of accidentally compressing load-bearing procedural content.

#### Implementation Steps
1. **Baseline measurement**: `wc -l -w -c` on `SKILL.md`, `references/step-details.md`, `references/workflow-example.md`, and `assets/pr-template.md` — record in FEAT-023 Notes.
2. **Identify placement**: `implementing-plan-phases` has `## Quick Start` — add `## Output Style` immediately after it.
3. **Add `## Output Style` section**:
   - `### Lite narration rules` — seven bullets (standard).
   - `### Load-bearing carve-outs (never strip)` — seven bullets (standard).
   - `### Fork-to-orchestrator return contract` — note that `implementing-plan-phases` is forked by `orchestrating-workflows` (feature chain, one fork per phase). Emits `done | artifact=<path> | <note>` on success and `failed | <reason>` on failure. Include precedence clause.
4. **FR-3 check**: search `references/step-details.md` and `references/workflow-example.md` for fork/Agent invocation specs. `step-details.md` documents per-phase workflow steps; `workflow-example.md` is an annotated example. Neither is expected to describe spawning subagents. If any Agent-tool invocation pattern is found, add the one-line pointer immediately under it. Record outcome (pointer added or no-op) in FEAT-023 Notes.
5. **FR-4 review**: open `assets/pr-template.md`. This is a PR description template. Assess for preamble or compressible prose. Apply tightening where safe; do not remove load-bearing checklist items or structural sections. Record as compressed or already-minimal.
6. **Post-change measurement**: `wc -l -w -c` on the same file set — record delta in FEAT-023 Notes.
7. **Validate**: `npm run validate`.
8. **Emit fork return**: `done | artifact=plugins/lwndev-sdlc/skills/implementing-plan-phases/SKILL.md | Output Style section added`.

#### Deliverables
- [ ] `plugins/lwndev-sdlc/skills/implementing-plan-phases/SKILL.md` — `## Output Style` section added
- [ ] `assets/pr-template.md` — compressed or marked already-minimal in FEAT-023 Notes
- [ ] Baseline + post-change measurements recorded in FEAT-023 Notes
- [ ] FR-3 outcome for both reference files recorded in FEAT-023 Notes
- [ ] `npm run validate` passes

---

### Phase 11: `executing-chores` — forked skill, sibling to Phase 12
**Feature:** [FEAT-023](../features/FEAT-023-output-token-optimization-rollout.md) | [#200](https://github.com/lwndev/lwndev-marketplace/issues/200)
**Status:** Pending

#### Rationale
- `executing-chores` is a forked skill (chore chain step 4) — standard `done | ...` return shape. Has one `references/` file (`workflow-details.md`, 277 lines) and one `assets/` file (`pr-template.md`, 118 lines).
- Sibling to `executing-bug-fixes` (Phase 12) — handling them in sequence ensures consistent wording.
- Deferred until after `implementing-plan-phases` because the PR template compression pattern is now established.

#### Implementation Steps
1. **Baseline measurement**: `wc -l -w -c` on `SKILL.md`, `references/workflow-details.md`, and `assets/pr-template.md` — record in FEAT-023 Notes.
2. **Identify placement**: `executing-chores` has `## Quick Start` — add `## Output Style` immediately after it.
3. **Add `## Output Style` section**:
   - `### Lite narration rules` — seven bullets (standard).
   - `### Load-bearing carve-outs (never strip)` — seven bullets (standard).
   - `### Fork-to-orchestrator return contract` — note that `executing-chores` is forked by `orchestrating-workflows` (chore chain step 4). Emits `done | artifact=<path> | <note>` on success and `failed | <reason>` on failure. Include precedence clause.
4. **FR-3 check**: search `references/workflow-details.md` for fork/Agent invocation specs. This file documents the chore execution workflow steps. If any Agent-tool invocation pattern is found, add the one-line pointer. Record outcome in FEAT-023 Notes.
5. **FR-4 review**: open `assets/pr-template.md`. This is a chore PR description template. Assess for preamble or compressible prose. Apply tightening where safe. Record as compressed or already-minimal.
6. **Post-change measurement**: `wc -l -w -c` on the same file set — record delta in FEAT-023 Notes.
7. **Validate**: `npm run validate`.
8. **Emit fork return**: `done | artifact=plugins/lwndev-sdlc/skills/executing-chores/SKILL.md | Output Style section added`.

#### Deliverables
- [ ] `plugins/lwndev-sdlc/skills/executing-chores/SKILL.md` — `## Output Style` section added
- [ ] `assets/pr-template.md` — compressed or marked already-minimal in FEAT-023 Notes
- [ ] Baseline + post-change measurements recorded in FEAT-023 Notes
- [ ] FR-3 outcome for `workflow-details.md` recorded in FEAT-023 Notes
- [ ] `npm run validate` passes

---

### Phase 12: `executing-bug-fixes` — forked skill, sibling to Phase 11
**Feature:** [FEAT-023](../features/FEAT-023-output-token-optimization-rollout.md) | [#200](https://github.com/lwndev/lwndev-marketplace/issues/200)
**Status:** Pending

#### Rationale
- `executing-bug-fixes` is a forked skill (bug chain step 4) — standard `done | ...` return shape. Has one `references/` file (`workflow-details.md`, 338 lines) and one `assets/` file (`pr-template.md`, 180 lines). Largest `assets/` file of the sibling pair.
- Final per-skill phase before the grand-total aggregation. Completing this phase makes all twelve skills consistent.

#### Implementation Steps
1. **Baseline measurement**: `wc -l -w -c` on `SKILL.md`, `references/workflow-details.md`, and `assets/pr-template.md` — record in FEAT-023 Notes.
2. **Identify placement**: `executing-bug-fixes` has `## Quick Start` — add `## Output Style` immediately after it.
3. **Add `## Output Style` section**:
   - `### Lite narration rules` — seven bullets (standard).
   - `### Load-bearing carve-outs (never strip)` — seven bullets (standard).
   - `### Fork-to-orchestrator return contract` — note that `executing-bug-fixes` is forked by `orchestrating-workflows` (bug chain step 4). Emits `done | artifact=<path> | <note>` on success and `failed | <reason>` on failure. Include precedence clause.
4. **FR-3 check**: search `references/workflow-details.md` for fork/Agent invocation specs. This file documents the bug-fix execution workflow steps. If any Agent-tool invocation pattern is found, add the one-line pointer. Record outcome in FEAT-023 Notes.
5. **FR-4 review**: open `assets/pr-template.md`. This is the bug-fix PR description template (largest assets file: 180 lines). Assess carefully for preamble or compressible prose without losing load-bearing bug-specific checklist items. Apply tightening where safe. Record as compressed or already-minimal.
6. **Post-change measurement**: `wc -l -w -c` on the same file set — record delta in FEAT-023 Notes.
7. **Validate**: `npm run validate`.
8. **Emit fork return**: `done | artifact=plugins/lwndev-sdlc/skills/executing-bug-fixes/SKILL.md | Output Style section added`.

#### Deliverables
- [ ] `plugins/lwndev-sdlc/skills/executing-bug-fixes/SKILL.md` — `## Output Style` section added
- [ ] `assets/pr-template.md` — compressed or marked already-minimal in FEAT-023 Notes
- [ ] Baseline + post-change measurements recorded in FEAT-023 Notes
- [ ] FR-3 outcome for `workflow-details.md` recorded in FEAT-023 Notes
- [ ] `npm run validate` passes

---

### Phase 13: Grand-Total Aggregation and End-to-End Verification
**Feature:** [FEAT-023](../features/FEAT-023-output-token-optimization-rollout.md) | [#200](https://github.com/lwndev/lwndev-marketplace/issues/200)
**Status:** Pending

#### Rationale
- All twelve per-skill phases are complete. This phase aggregates the measurements, runs end-to-end verification, and closes out the acceptance criteria.
- No skill edits in this phase — it is purely measurement aggregation, validation, and documentation.

#### Implementation Steps
1. **Aggregate baseline measurements**: collect all per-skill baseline rows recorded in Phases 1–12. Compile the full baseline measurement table in FEAT-023 Notes (per-file rows, per-skill subtotals, grand total across all twelve skills). Use the CHORE-034 table format: columns `File | Lines | Words | Chars`.
2. **Aggregate post-change measurements**: compile the full post-change table in the same format.
3. **Compute and append the delta table**: emit the delta table in CHORE-034 format — columns `File | Lines Δ | Lines % | Words Δ | Words % | Chars Δ | Chars %` — with per-file rows, per-skill subtotals, and a grand-total row. Negative Δ = reduction; positive Δ = growth.
4. **Record FR-3 no-ops**: confirm that all twelve skills' `references/` directories (where they exist) were checked and no fork-invocation specs were found requiring a pointer. List each checked skill and its outcome. Skills with no `references/` directory are exempt and listed as such.
5. **Record FR-4 findings**: confirm per-skill assets review outcomes — either "compressed (applied)" or "already-minimal (no changes)" for each of the ten skills with `assets/`. List skills without assets as N/A.
6. **Record main-context vs forked deviations**: note that five skills (documenting-features, documenting-chores, documenting-bugs, documenting-qa, executing-qa) use the main-context return-contract note; one skill (managing-work-items) uses the inline-execution note; six skills (reviewing-requirements, creating-implementation-plans, implementing-plan-phases, executing-chores, executing-bug-fixes, finalizing-workflow) use the standard `done | ...` / `failed | ...` contract; `reviewing-requirements` has the additional exception return shape.
7. **Run `npm run validate`** — must pass.
8. **Run `npm test`** — must pass. If any test asserts on narration content trimmed by this rollout, update the test to match canonical narration and call it out explicitly in the Notes.
9. **Manual spot-check** (record outcome in Notes): render SKILL.md for one forked skill (`executing-chores`), one main-context skill (`documenting-qa`), and one cross-cutting skill (`managing-work-items`) in a markdown preview and confirm `## Output Style` reads cleanly.
10. **Emit fork return**: `done | artifact=requirements/features/FEAT-023-output-token-optimization-rollout.md | Grand-total measurements and verification complete`.

#### Deliverables
- [ ] Baseline measurement table appended to FEAT-023 Notes (per-file, per-skill subtotal, grand total)
- [ ] Post-change measurement table appended to FEAT-023 Notes
- [ ] Delta table appended to FEAT-023 Notes (lines Δ/%, words Δ/%, chars Δ/%)
- [ ] FR-3 no-op registry complete in FEAT-023 Notes (all nine skills with references checked, three exempt skills listed)
- [ ] FR-4 outcomes complete in FEAT-023 Notes (ten skills with assets reviewed, two without listed as N/A)
- [ ] Main-context vs forked deviation record complete in FEAT-023 Notes
- [ ] `npm run validate` passes
- [ ] `npm test` passes
- [ ] Manual spot-check outcome recorded in FEAT-023 Notes

---

## Shared Infrastructure

### `## Output Style` Template Text

Every per-skill phase adds a section with this three-subsection structure. The wording below is the canonical template — copy verbatim except for the return-contract subsection, which is adapted per skill role as noted.

```markdown
## Output Style

Follow the lite-narration rules below. Load-bearing carve-outs MUST be emitted as specified; they are not narration.

### Lite narration rules

- No preamble before tool calls. Do not announce "let me check" or "I'll run" -- issue the tool call.
- No end-of-turn summaries beyond one short sentence. Do not recap what the user can read from tool output.
- No emoji. ASCII punctuation only.
- No restating what the user just said.
- No status echoes that tools already show.
- Prefer ASCII arrows (`->`) and punctuation over Unicode alternatives in skill-authored prose. Existing Unicode em dashes in tables and reference docs are retained.
- Short sentences over paragraphs. Bullet lists over prose when listing more than two items.

### Load-bearing carve-outs (never strip)

The following MUST always be emitted even when they resemble narration:

- **Error messages from `fail` calls** -- users need the reason the skill halted.
- **Security-sensitive warnings** -- destructive-operation confirmations, credential prompts.
- **Interactive prompts** -- any prompt that blocks the workflow and requires user input.
- **Findings display from `reviewing-requirements`** -- the full findings list must be shown before any findings-decision prompt.
- **FR-14 console echo lines** -- audit-trail lines using the documented Unicode `->` emitter format; do not rewrite to ASCII.
- **Tagged structured logs** -- any line prefixed `[info]`, `[warn]`, or `[model]` is a structured log, not narration. Emit verbatim.
- **User-visible state transitions** -- pause, advance, and resume announcements (at most one line each).

### Fork-to-orchestrator return contract

[ADAPT PER SKILL ROLE -- see variants below]
```

**Return-contract subsection variants:**

- **Forked skill (standard)**: "This skill is forked by `orchestrating-workflows`. Emit `done | artifact=<path> | <note-of-at-most-10-words>` on success and `failed | <one-sentence reason>` on failure as the **final line** of the response. The return contract takes precedence over the lite rules when the two conflict."
- **`reviewing-requirements` exception**: "This skill is forked by `orchestrating-workflows`. It emits `Found **N errors**, **N warnings**, **N info**` as the **final line** of its response — not the `done | ...` shape. The full findings block must precede this summary line. The return contract takes precedence over the lite rules when the two conflict."
- **Main-context skill**: "This skill runs in main context (not as an Agent fork). It returns to the user, not to a parent orchestrator. The `done | ...` and `failed | ...` shapes are not required."
- **Inline cross-cutting skill**: "This skill is invoked inline from main context by the orchestrator (not as an Agent fork). The `done | ...` and `failed | ...` shapes do not apply to its return. Lite narration rules and carve-outs still govern its output."

### Baseline Measurements (pre-change)

Captured pre-change via `wc -l -w -c`. Recorded per-skill in each phase's Notes; aggregated in Phase 13.

| Skill | File | Lines | Words | Chars |
|-------|------|------:|------:|------:|
| `finalizing-workflow` | `SKILL.md` | 72 | 564 | 3982 |
| `managing-work-items` | `SKILL.md` | 358 | 2811 | 19210 |
| `managing-work-items` | `references/github-templates.md` | 740 | 2315 | 17196 |
| `managing-work-items` | `references/jira-templates.md` | 715 | 2079 | 19135 |
| `documenting-features` | `SKILL.md` | 122 | 746 | 5655 |
| `documenting-features` | `references/feature-requirements-example-episodes-command.md` | 274 | 1278 | 8512 |
| `documenting-features` | `references/feature-requirements-example-search-command.md` | 228 | 1021 | 6872 |
| `documenting-features` | `assets/feature-requirements.md` | 94 | 242 | 1715 |
| `documenting-chores` | `SKILL.md` | 117 | 607 | 4466 |
| `documenting-chores` | `references/categories.md` | 198 | 720 | 4785 |
| `documenting-chores` | `assets/chore-document.md` | 109 | 356 | 2456 |
| `documenting-bugs` | `SKILL.md` | 136 | 769 | 5432 |
| `documenting-bugs` | `references/categories.md` | 236 | 1134 | 7429 |
| `documenting-bugs` | `assets/bug-document.md` | 181 | 707 | 4759 |
| `reviewing-requirements` | `SKILL.md` | 393 | 3385 | 24386 |
| `reviewing-requirements` | `references/review-example.md` | 95 | 525 | 3897 |
| `reviewing-requirements` | `assets/review-findings-template.md` | 98 | 426 | 3178 |
| `creating-implementation-plans` | `SKILL.md` | 107 | 529 | 3981 |
| `creating-implementation-plans` | `references/implementation-plan-example.md` | 499 | 2766 | 20322 |
| `creating-implementation-plans` | `assets/implementation-plan.md` | 79 | 234 | 1771 |
| `implementing-plan-phases` | `SKILL.md` | 142 | 974 | 7118 |
| `implementing-plan-phases` | `references/step-details.md` | 399 | 1488 | 11039 |
| `implementing-plan-phases` | `references/workflow-example.md` | 327 | 977 | 8670 |
| `implementing-plan-phases` | `assets/pr-template.md` | 163 | 616 | 4088 |
| `documenting-qa` | `SKILL.md` | 168 | 1461 | 10257 |
| `documenting-qa` | `assets/test-plan-template-v2.md` | 65 | 334 | 2252 |
| `documenting-qa` | `assets/test-plan-template.md` | 65 | 422 | 2575 |
| `executing-qa` | `SKILL.md` | 238 | 1986 | 13831 |
| `executing-qa` | `assets/test-results-template-v2.md` | 81 | 380 | 2577 |
| `executing-qa` | `assets/test-results-template.md` | 89 | 466 | 2753 |
| `executing-chores` | `SKILL.md` | 143 | 935 | 7104 |
| `executing-chores` | `references/workflow-details.md` | 277 | 940 | 6249 |
| `executing-chores` | `assets/pr-template.md` | 118 | 420 | 2726 |
| `executing-bug-fixes` | `SKILL.md` | 176 | 1260 | 8958 |
| `executing-bug-fixes` | `references/workflow-details.md` | 338 | 1365 | 8649 |
| `executing-bug-fixes` | `assets/pr-template.md` | 180 | 878 | 5825 |
| **Grand Total** | | **6405** | **35390** | **262598** |

Post-change measurements and deltas will be appended to the FEAT-023 requirements doc Notes section in Phase 13.

## Testing Strategy

### Unit Tests

- `npm run validate` must pass after each per-skill phase (run once per phase as the final verification step before the fork return).
- Frontmatter fields (`name`, `description`, `allowed-tools`, `argument-hint`) must be unchanged for every skill after each phase.

### Integration Tests

- `npm test` runs end-to-end in Phase 13. If any test asserts on narration content that this rollout trims, update the test assertion to match the new canonical narration and call out the change explicitly in the Phase 13 deliverables notes and in the PR body (per NFR-3).

### Manual Testing

- Phase 13 spot-check: render SKILL.md for one forked sub-skill (`executing-chores`), one main-context sub-skill (`documenting-qa`), and one cross-cutting skill (`managing-work-items`) in markdown preview. Confirm `## Output Style` section reads cleanly, three subsections are in order, and role-specific wording is correct.
- After PR is merged, run one feature workflow chain end-to-end to confirm no fork-return regressions.
- Run one chore workflow chain end-to-end for the same purpose.

## Dependencies and Prerequisites

- **CHORE-034** — merged (confirmed; pilot is complete as of 2026-04-21). Its `requirements/chores/CHORE-034-output-token-optimization-pilot.md` Learnings section is the source of truth for the template pattern.
- **`orchestrating-workflows/SKILL.md`** — the canonical `## Output Style` example. The rollout replicates its three-subsection structure and wording.
- **No external tooling** beyond `wc` (available in every POSIX shell) and the existing `npm run validate` / `npm test` scripts.
- **No runtime changes** — this is a documentation/style change only. No script logic is modified.

## Risk Assessment

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Over-compression of load-bearing procedural content in `assets/` templates | High — loses structural intent from artifact output | Low — pilot established the floor (~3% char reduction); rollout treats structural skeletons as already-minimal | Apply FR-4 tightening only to prose sections; never touch numbered requirement blocks or checklist items |
| Incorrect return-contract wording for a skill role | Medium — subagent emits wrong shape; orchestrator parsing fails | Low — four canonical variants documented in Shared Infrastructure; phase reviewers can catch it | Canonical variant text in Shared Infrastructure section; spot-check in Phase 13 |
| `npm test` assertion on trimmed narration | Low — causes CI failure | Low — this rollout adds sections rather than removing existing narration | If a test fails, update assertion and call it out in PR body (NFR-3) |
| Placement collision — a skill already has `## Output Style` | Low — no known collisions; confirmed by header audit in pre-planning | Very Low | Per-phase check before editing; Edge Case 8 handling if found |
| `managing-work-items` FR-3 false positive — templates mistaken for fork invocations | Low — would add spurious pointer | Low — GitHub/Jira templates are API call patterns, not Agent-tool invocations | Search for "Agent" keyword specifically; record clearly in Notes |
| Inconsistent wording across the twelve skills | Medium — defeats NFR-4 consistency goal | Medium — twelve phases with potential for drift | Use the Shared Infrastructure template text verbatim; Phase 13 review confirms consistency |

## Success Criteria

- All twelve target skills have an `## Output Style` section in `SKILL.md` placed immediately after `## Quick Start` (or the first early-read section where no Quick Start exists).
- Each `## Output Style` section contains exactly three subsections in order: Lite narration rules -> Load-bearing carve-outs -> Fork-to-orchestrator return contract.
- Wording of the lite-narration rules and load-bearing carve-outs is consistent across all twelve target skills. Role-specific deviations (main-context, inline, exception return shape) are documented in FEAT-023 Notes.
- Each forked skill documents its canonical return shape(s). Main-context skills note they return to the user. `managing-work-items` notes inline execution.
- `reviewing-requirements` documents the `Found **N errors** ...` exception shape.
- All nine skills with `references/` directories have been checked for fork-invocation specs; outcomes (pointer added or no-op) are recorded in FEAT-023 Notes. Three exempt skills (no `references/`) are listed as such.
- All ten skills with `assets/` directories have been reviewed for FR-4; outcomes (compressed or already-minimal) are recorded in FEAT-023 Notes.
- Baseline and post-change `wc -l -w -c` measurements for all thirty-six files (SKILL.md + references + assets per skill) are appended to FEAT-023 Notes with per-file, per-skill subtotal, and grand-total rows.
- Delta table (lines Δ/%, words Δ/%, chars Δ/%) is appended to FEAT-023 Notes in CHORE-034 format.
- `npm run validate` passes.
- `npm test` passes.
- No frontmatter fields were changed except where strictly necessary.
- No Fork Step-Name Map entry or step-sequence table in `orchestrating-workflows` was modified.

## Code Organization

```
plugins/lwndev-sdlc/skills/
├── finalizing-workflow/
│   └── SKILL.md                          <- Phase 1: ## Output Style added
├── managing-work-items/
│   └── SKILL.md                          <- Phase 2: ## Output Style added (inline variant)
├── documenting-features/
│   ├── SKILL.md                          <- Phase 3: ## Output Style added (main-context variant)
│   └── assets/feature-requirements.md   <- Phase 3: FR-4 review
├── documenting-chores/
│   ├── SKILL.md                          <- Phase 4: ## Output Style added (main-context variant)
│   └── assets/chore-document.md         <- Phase 4: FR-4 review
├── documenting-bugs/
│   ├── SKILL.md                          <- Phase 5: ## Output Style added (main-context variant)
│   └── assets/bug-document.md           <- Phase 5: FR-4 review
├── reviewing-requirements/
│   ├── SKILL.md                          <- Phase 6: ## Output Style added (exception variant)
│   └── assets/review-findings-template.md <- Phase 6: FR-4 review
├── creating-implementation-plans/
│   ├── SKILL.md                          <- Phase 7: ## Output Style added (forked variant)
│   └── assets/implementation-plan.md    <- Phase 7: FR-4 review (likely already-minimal)
├── documenting-qa/
│   ├── SKILL.md                          <- Phase 8: ## Output Style added (main-context variant)
│   ├── assets/test-plan-template-v2.md  <- Phase 8: FR-4 review
│   └── assets/test-plan-template.md     <- Phase 8: FR-4 review
├── executing-qa/
│   ├── SKILL.md                          <- Phase 9: ## Output Style added (main-context variant)
│   ├── assets/test-results-template-v2.md <- Phase 9: FR-4 review
│   └── assets/test-results-template.md  <- Phase 9: FR-4 review
├── implementing-plan-phases/
│   ├── SKILL.md                          <- Phase 10: ## Output Style added (forked variant)
│   └── assets/pr-template.md            <- Phase 10: FR-4 review
├── executing-chores/
│   ├── SKILL.md                          <- Phase 11: ## Output Style added (forked variant)
│   └── assets/pr-template.md            <- Phase 11: FR-4 review
└── executing-bug-fixes/
    ├── SKILL.md                          <- Phase 12: ## Output Style added (forked variant)
    └── assets/pr-template.md            <- Phase 12: FR-4 review

requirements/
├── features/
│   └── FEAT-023-output-token-optimization-rollout.md  <- Notes section updated each phase
└── implementation/
    └── FEAT-023-output-token-optimization-rollout.md  <- this file
```
