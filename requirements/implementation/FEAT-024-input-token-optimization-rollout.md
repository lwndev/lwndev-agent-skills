# Implementation Plan: Input Token Optimization Rollout

## Overview

Roll out the input-token optimization pattern piloted in CHORE-035 to the remaining twelve `lwndev-sdlc` skills. Each target skill's `SKILL.md` is compressed using the three-axis template: (1) lite-style prose compression, (2) heavy-narrative relocation to `references/`, and (3) natural collapse of repeated tables. The pilot showed these axes reduce the per-invocation instruction surface by ~43% without behavioral change.

The approach orders skills from smallest/simplest to largest/most complex. Each phase covers exactly one skill (NFR-2 per-skill atomicity), performs a pre-flight test audit (FR-7) before touching any file, captures baseline and post-change `wc` measurements, and verifies correctness with `npm run validate` and targeted tests. The final phase aggregates measurements and closes acceptance criteria.

## Features Summary

| Feature ID | GitHub Issue | Feature Document | Priority | Complexity | Status |
|------------|--------------|------------------|----------|------------|--------|
| FEAT-024 | [#203](https://github.com/lwndev/lwndev-marketplace/issues/203) | [FEAT-024-input-token-optimization-rollout.md](../features/FEAT-024-input-token-optimization-rollout.md) | Medium | Low | Pending |

## Recommended Build Sequence

Phase ordering follows the same risk-sequencing logic used in FEAT-023: smallest surface first, so the three-axis template is validated on low-complexity skills before touching the largest and most-invoked ones. Within that ordering, the three sibling documenting-* skills are grouped consecutively (Phases 2–4) since they share shape, and the three sibling executing-* skills are grouped consecutively (Phases 8–10) for the same reason. Each phase covers exactly one skill. No multi-skill grouping is applied — per NFR-2, every skill warrants independent review given the editorial judgment required per axis.

**Phase ordering summary:**

| Phase | Skill | SKILL.md (lines) | Key characteristic |
|-------|-------|------------------|--------------------|
| 0 | Pre-flight (no edits) | — | Branch + baseline measurements across all 12 skills |
| 1 | `finalizing-workflow` | 104 | Smallest surface; no `references/`, no `assets/` |
| 2 | `documenting-features` | 154 | Main-context, one asset, two references |
| 3 | `documenting-chores` | 149 | Main-context sibling; one asset, one reference |
| 4 | `documenting-bugs` | 168 | Main-context sibling; one asset, one reference |
| 5 | `managing-work-items` | 390 | Inline cross-cutting; two large references, no assets |
| 6 | `creating-implementation-plans` | 139 | Forked; one asset, one large reference |
| 7 | `reviewing-requirements` | 434 | Forked; largest SKILL.md; exception return shape; three modes |
| 8 | `executing-chores` | 179 | Forked; one reference, one asset; "Unicode `->`" carve-out fix |
| 9 | `executing-bug-fixes` | 212 | Forked sibling; one reference, one asset; "Unicode `->`" carve-out fix |
| 10 | `documenting-qa` | 200 | Main-context; no `references/`; two assets |
| 11 | `executing-qa` | 270 | Main-context; no `references/`; two assets |
| 12 | `implementing-plan-phases` | 178 | Forked; largest combined reference surface; "Unicode `->`" carve-out fix |
| 13 | Aggregation | — | Grand-total measurements, Summary, AC verification, e2e tests |

---

### Phase 0: Pre-flight — Branch Creation and Baseline Measurements
**Feature:** [FEAT-024](../features/FEAT-024-input-token-optimization-rollout.md) | [#203](https://github.com/lwndev/lwndev-marketplace/issues/203)
**Status:** ✅ Complete

#### Rationale
- Captures an immutable pre-change baseline across all twelve skills before any edits land.
- Creates the feature branch so all subsequent phase commits land in one PR.
- Records the top-level test audit inventory — which test files exist and whether any already exhibit hardcoded-count or literal-heading assertions that will need attention.
- No SKILL.md is edited in this phase; it is purely setup and measurement.

#### Implementation Steps
1. **Create feature branch**: `git checkout -b feat/FEAT-024-input-token-optimization-rollout` from `main`.
2. **Baseline measurement sweep**: for each of the twelve target skills, run `wc -l -w -c` on:
   - `SKILL.md`
   - All files under `references/` (if the directory exists)
   - All files under `assets/` (if the directory exists)
   Record every row in the FEAT-024 Notes → Baseline Measurements subsection. Format: `| Skill | File | Lines | Words | Chars |`. Add a per-skill subtotal and a grand-total row.
3. **Input-token estimate for each SKILL.md**: compute `chars / 4` for each SKILL.md's char count. Record alongside the `wc` measurements. If `ANTHROPIC_API_KEY` is available, run the `/v1/messages/count_tokens` endpoint as a corroborating figure.
4. **Top-level test audit**: open `scripts/__tests__/<skill-name>.test.ts` for each of the twelve skills. For each test file, scan for:
   - Hardcoded numeric counts (e.g., `.toHaveLength(35)`, `count == N`) — these may shift when sections are added or removed
   - Literal `##` heading assertions (e.g., `toContain('## Feature Chain Step Sequence')`)
   - Literal phrase assertions (e.g., `toContain('Forked Steps')`)
   Record each finding in the FEAT-024 Notes → Per-skill FR-7 pre-flight audit findings subsection as "will-change" or "must-preserve". This top-level audit seeds the per-phase pre-flight step with already-identified candidates.
5. **Run `npm test`** to establish a green-baseline before any edits. Record pass/fail.
6. **Run `npm run validate`** to confirm all twelve skills are valid before the rollout starts.

#### Deliverables
- [x] Feature branch `feat/FEAT-024-input-token-optimization-rollout` created
- [x] Baseline `wc -l -w -c` measurements for all twelve skills (per-file, per-skill subtotal, grand total) recorded in FEAT-024 Notes → Baseline Measurements
- [x] `chars / 4` input-token estimates for all twelve SKILL.md files recorded alongside baseline measurements
- [x] Top-level FR-7 audit findings (all twelve test files scanned) recorded in FEAT-024 Notes → Per-skill FR-7 pre-flight audit findings
- [x] `npm test` green baseline confirmed
- [x] `npm run validate` passes

---

### Phase 1: `finalizing-workflow` — smallest surface, no references, no assets
**Feature:** [FEAT-024](../features/FEAT-024-input-token-optimization-rollout.md) | [#203](https://github.com/lwndev/lwndev-marketplace/issues/203)
**Status:** ✅ Complete

#### Rationale
- Smallest SKILL.md of the twelve (104 lines). No `references/`, no `assets/` — FR-2 can only produce a no-op or create a new `references/` directory if narrative relocation is warranted; FR-3 is a guaranteed no-op (no repeated tables possible).
- Edge Case 1 applies: if heavy narrative is identified for relocation, create `references/` as part of this phase.
- Validating the three-axis template at minimum risk before any skill with references or assets.
- `finalizing-workflow` is a forked skill — standard `done | ...` return shape; its `## Output Style` section (from FEAT-023) is a FR-4 preservation target.

#### Implementation Steps
1. **FR-7 pre-flight test audit**: open `scripts/__tests__/finalizing-workflow.test.ts`. Confirm or refine the Phase 0 audit findings. Classify each assertion as "will-change" or "must-preserve". Record any new findings in the FEAT-024 Notes → Per-skill FR-7 pre-flight audit findings subsection.
2. **Baseline measurement** (from Phase 0): confirm the row for `finalizing-workflow/SKILL.md` is present in the Notes.
3. **FR-1 — lite-style prose compression**: read `SKILL.md` in full. Apply compression: remove filler and hedging phrases; keep full sentences where pronoun antecedents would be lost by truncation; leave code blocks, command lines, flags, paths, anchor IDs, and table headers untouched. Preserve all FR-4 carve-outs verbatim (error messages, security warnings, interactive prompts, FR-14 echo lines, tagged structured logs, state transitions, `## Output Style` section). Do NOT compress the `## Output Style` section.
4. **FR-2 — heavy-narrative relocation**: identify any non-dispatcher sections exceeding ~25 lines of procedural narrative. If found, relocate to a new `references/` file with a single-sentence inline pointer at the relocation site (pointer at end of dispatcher paragraph). If no such sections exist, record FR-2 as a no-op in Notes.
5. **FR-3 — natural collapse**: scan for near-duplicate or repeated tables. `finalizing-workflow` is unlikely to have any; record as no-op with brief justification in Notes.
6. **FR-4 — carve-out verification**: confirm all carve-out items are present and verbatim. Confirm `## Output Style` section is intact.
7. **Post-change measurement**: `wc -l -w -c plugins/lwndev-sdlc/skills/finalizing-workflow/SKILL.md`. Compute `chars / 4` token estimate. Record in FEAT-024 Notes → Post-Change Measurements.
8. **Delta computation**: record lines Δ, lines %, words Δ, words %, chars Δ, chars % in FEAT-024 Notes → Delta subsection.
9. **Update any affected test assertions** identified in step 1 in the same commit. Add a comment referencing FEAT-024 explaining the change reason.
10. **Run `npm run validate`** — must pass.
11. **Run `npm test -- --testPathPatterns=finalizing-workflow`** — must pass.
12. **Commit**: `feat(FEAT-024): apply input-token optimization to finalizing-workflow` on feature branch.

#### Deliverables
- [x] `plugins/lwndev-sdlc/skills/finalizing-workflow/SKILL.md` — FR-1 prose compression applied
- [x] `plugins/lwndev-sdlc/skills/finalizing-workflow/references/` — created with relocated content OR FR-2 recorded as no-op
- [x] FR-3 no-op recorded in FEAT-024 Notes with justification
- [x] Post-change measurements and delta recorded in FEAT-024 Notes
- [x] Any affected test assertions updated in same commit
- [x] `npm run validate` passes
- [x] `npm test -- --testPathPatterns=finalizing-workflow` passes

---

### Phase 2: `documenting-features` — main-context, two references, one asset
**Feature:** [FEAT-024](../features/FEAT-024-input-token-optimization-rollout.md) | [#203](https://github.com/lwndev/lwndev-marketplace/issues/203)
**Status:** ✅ Complete

#### Rationale
- First of the three main-context documenting-* skills. At 154 lines, it is lightweight enough to establish the pattern cleanly.
- Has two reference files (example requirement documents) and one asset (`feature-requirements.md` template). The reference files are examples, not procedural narrative — FR-2 relocation is unlikely to apply to them, but they must be checked.
- Establishing the three-axis pattern on `documenting-features` makes Phases 3–4 straightforward sibling replications.

#### Implementation Steps
1. **FR-7 pre-flight test audit**: open `scripts/__tests__/documenting-features.test.ts`. Confirm or refine Phase 0 audit findings. Classify each assertion as "will-change" or "must-preserve". Record in FEAT-024 Notes.
2. **Baseline measurement** (from Phase 0): confirm per-file rows for `SKILL.md`, both references, and `assets/feature-requirements.md` are present.
3. **FR-1 — lite-style prose compression**: read `SKILL.md` in full. Apply compression: remove filler and hedging; keep full sentences where antecedents or enumerations would be lost; preserve all FR-4 carve-outs and the `## Output Style` section verbatim.
4. **FR-2 — heavy-narrative relocation**: identify non-dispatcher sections exceeding ~25 lines. Candidate sections: any long numbered recipe or multi-step procedure. Relocate to `references/` with inline pointer if warranted. The two existing reference files are example requirement documents — they are reference material, not new relocation targets. If no relocation is warranted for SKILL.md sections, record FR-2 as a no-op in Notes.
5. **FR-3 — natural collapse**: scan for near-duplicate tables. `documenting-features` is unlikely to have repeated tables (it documents a single workflow); record as no-op with justification if so.
6. **FR-4 — carve-out verification**: confirm all carve-out items intact; confirm `## Output Style` verbatim.
7. **Post-change measurement**: `wc -l -w -c` on `SKILL.md`, both reference files (unchanged; record same values), and `assets/feature-requirements.md` (unchanged if not edited). Compute `chars / 4` for SKILL.md. Record in FEAT-024 Notes.
8. **Delta computation**: record per-file and per-skill subtotal deltas. Only SKILL.md (and any new/modified files) will show non-zero delta.
9. **Update any affected test assertions** in the same commit with FEAT-024 comment.
10. **Run `npm run validate`** — must pass.
11. **Run `npm test -- --testPathPatterns=documenting-features`** — must pass.
12. **Commit**: `feat(FEAT-024): apply input-token optimization to documenting-features`.

#### Deliverables
- [x] `plugins/lwndev-sdlc/skills/documenting-features/SKILL.md` — FR-1 compression applied
- [x] `plugins/lwndev-sdlc/skills/documenting-features/references/` — new file added for relocated narrative OR FR-2 recorded as no-op
- [x] FR-3 outcome recorded in FEAT-024 Notes
- [x] Post-change measurements and delta recorded in FEAT-024 Notes
- [x] Any affected test assertions updated in same commit
- [x] `npm run validate` passes
- [x] `npm test -- --testPathPatterns=documenting-features` passes

---

### Phase 3: `documenting-chores` — main-context sibling, one reference, one asset
**Feature:** [FEAT-024](../features/FEAT-024-input-token-optimization-rollout.md) | [#203](https://github.com/lwndev/lwndev-marketplace/issues/203)
**Status:** ✅ Complete

#### Rationale
- Direct sibling to `documenting-features` (Phase 2). Same main-context shape. One reference (`categories.md` — a reference table) and one asset (`chore-document.md` — structural template). Phase 2 establishes the pattern; this is a straight replication on a slightly smaller surface.
- `documenting-chores` is the step-1 entry point for the chore chain — any relocation here must not disturb the dispatcher's ability to identify the right chain and kick off the sequence.

#### Implementation Steps
1. **FR-7 pre-flight test audit**: open `scripts/__tests__/documenting-chores.test.ts`. Confirm or refine Phase 0 findings. Record in FEAT-024 Notes.
2. **Baseline measurement** (from Phase 0): confirm per-file rows present.
3. **FR-1 — lite-style prose compression**: apply to `SKILL.md`. Preserve carve-outs and `## Output Style` verbatim.
4. **FR-2 — heavy-narrative relocation**: scan for sections exceeding ~25 lines. `references/categories.md` is a chore-category reference table — it is already in `references/`; no relocation needed for it. If SKILL.md sections qualify for relocation, move them. Record outcome.
5. **FR-3 — natural collapse**: scan for repeated tables. Record as no-op with justification if none found.
6. **FR-4 — carve-out verification**: confirm all carve-outs and `## Output Style` intact.
7. **Post-change measurement + delta**: `wc -l -w -c` on all files in scope. Compute SKILL.md `chars / 4`. Record in FEAT-024 Notes.
8. **Update any affected test assertions** in same commit with FEAT-024 comment.
9. **Run `npm run validate`** — must pass.
10. **Run `npm test -- --testPathPatterns=documenting-chores`** — must pass.
11. **Commit**: `feat(FEAT-024): apply input-token optimization to documenting-chores`.

#### Deliverables
- [x] `plugins/lwndev-sdlc/skills/documenting-chores/SKILL.md` — FR-1 compression applied
- [x] FR-2 outcome (relocation or no-op) recorded in FEAT-024 Notes
- [x] FR-3 outcome recorded in FEAT-024 Notes
- [x] Post-change measurements and delta recorded in FEAT-024 Notes
- [x] Any affected test assertions updated in same commit
- [x] `npm run validate` passes
- [x] `npm test -- --testPathPatterns=documenting-chores` passes

---

### Phase 4: `documenting-bugs` — main-context sibling, one reference, one asset
**Feature:** [FEAT-024](../features/FEAT-024-input-token-optimization-rollout.md) | [#203](https://github.com/lwndev/lwndev-marketplace/issues/203)
**Status:** ✅ Complete

#### Rationale
- Direct sibling to `documenting-chores` (Phase 3). Same main-context shape. One reference (`categories.md` — a bug-category reference table) and one asset (`bug-document.md`). The three-axis pattern is now fully validated on two sibling skills; Phase 4 is a straight replication.
- At 168 lines, SKILL.md is the largest of the three documenting-* siblings — slightly more editorial judgment needed but no structural differences.

#### Implementation Steps
1. **FR-7 pre-flight test audit**: open `scripts/__tests__/documenting-bugs.test.ts`. Confirm or refine Phase 0 findings. Record in FEAT-024 Notes.
2. **Baseline measurement** (from Phase 0): confirm per-file rows present.
3. **FR-1 — lite-style prose compression**: apply to `SKILL.md`. Preserve carve-outs and `## Output Style` verbatim.
4. **FR-2 — heavy-narrative relocation**: scan for sections exceeding ~25 lines. `references/categories.md` is already a reference file. Identify any SKILL.md sections that qualify. Record outcome.
5. **FR-3 — natural collapse**: scan for repeated tables. Record as no-op with justification if none found.
6. **FR-4 — carve-out verification**: confirm all carve-outs and `## Output Style` intact.
7. **Post-change measurement + delta**: `wc -l -w -c` on all files in scope. Compute SKILL.md `chars / 4`. Record in FEAT-024 Notes.
8. **Update any affected test assertions** in same commit with FEAT-024 comment.
9. **Run `npm run validate`** — must pass.
10. **Run `npm test -- --testPathPatterns=documenting-bugs`** — must pass.
11. **Commit**: `feat(FEAT-024): apply input-token optimization to documenting-bugs`.

#### Deliverables
- [x] `plugins/lwndev-sdlc/skills/documenting-bugs/SKILL.md` — FR-1 compression applied
- [x] FR-2 outcome recorded in FEAT-024 Notes
- [x] FR-3 outcome recorded in FEAT-024 Notes
- [x] Post-change measurements and delta recorded in FEAT-024 Notes
- [x] Any affected test assertions updated in same commit
- [x] `npm run validate` passes
- [x] `npm test -- --testPathPatterns=documenting-bugs` passes

---

### Phase 5: `managing-work-items` — inline cross-cutting skill, two large references, no assets
**Feature:** [FEAT-024](../features/FEAT-024-input-token-optimization-rollout.md) | [#203](https://github.com/lwndev/lwndev-marketplace/issues/203)
**Status:** ✅ Complete

#### Rationale
- `managing-work-items` is the largest SKILL.md so far in the sequence (390 lines) but has no `assets/`. It has two large reference files: `github-templates.md` (740 lines) and `jira-templates.md` (715 lines). These reference files are API call patterns and template collections — they are reference material that stays in `references/` by definition; FR-2 is a no-op for them. The SKILL.md itself may contain procedural narrative that can be relocated.
- It is a cross-cutting inline skill (invoked from main context by the orchestrator, not as an Agent fork) — its return-contract shape is distinct from forked skills. Its `## Output Style` section documents this already (from FEAT-023).
- Handling this skill before the forked skills keeps the main-context/inline group together and surfaces any issues with the large reference surface before moving to skills with their own reference relocation needs.

#### Implementation Steps
1. **FR-7 pre-flight test audit**: open `scripts/__tests__/managing-work-items.test.ts`. Confirm or refine Phase 0 findings. Record in FEAT-024 Notes.
2. **Baseline measurement** (from Phase 0): confirm per-file rows for `SKILL.md`, `references/github-templates.md`, and `references/jira-templates.md` are present.
3. **FR-1 — lite-style prose compression**: read `SKILL.md` in full. Apply compression. Preserve all FR-4 carve-outs and `## Output Style` verbatim.
4. **FR-2 — heavy-narrative relocation**: scan SKILL.md for sections exceeding ~25 lines of procedural narrative. The two existing reference files are already reference material — they are not relocation sources, but any long procedural blocks in SKILL.md that do not need to be read in full at dispatch time may be relocated as new files or appended to an existing reference file. Leave inline pointers at relocation sites (at end of dispatcher paragraphs). Record outcome.
5. **FR-3 — natural collapse**: scan for repeated or near-duplicate tables. `managing-work-items` may have per-backend (GitHub/Jira) operation tables with shared structure — if so, consolidate into one parameterized table plus a lossless deltas note. Record as no-op if no repetition exists.
6. **FR-4 — carve-out verification**: confirm all carve-outs and `## Output Style` intact.
7. **Post-change measurement + delta**: `wc -l -w -c` on all files in scope. Compute SKILL.md `chars / 4`. Record in FEAT-024 Notes.
8. **Update any affected test assertions** in same commit with FEAT-024 comment.
9. **Run `npm run validate`** — must pass.
10. **Run `npm test -- --testPathPatterns=managing-work-items`** — must pass.
11. **Commit**: `feat(FEAT-024): apply input-token optimization to managing-work-items`.

#### Deliverables
- [x] `plugins/lwndev-sdlc/skills/managing-work-items/SKILL.md` — FR-1 compression applied
- [x] FR-2 outcome recorded in FEAT-024 Notes (relocation or no-op, with justification)
- [x] FR-3 outcome recorded in FEAT-024 Notes (collapse or no-op, with justification)
- [x] Post-change measurements and delta recorded in FEAT-024 Notes
- [x] Any affected test assertions updated in same commit
- [x] `npm run validate` passes
- [x] `npm test -- --testPathPatterns=managing-work-items` passes

---

### Phase 6: `creating-implementation-plans` — forked skill, one reference, one asset
**Feature:** [FEAT-024](../features/FEAT-024-input-token-optimization-rollout.md) | [#203](https://github.com/lwndev/lwndev-marketplace/issues/203)
**Status:** Pending

#### Rationale
- First of the forked skills in this sequence. At 139 lines, it is the smallest SKILL.md among the forked skills. It has one large reference file (`implementation-plan-example.md`, 499 lines — an annotated example plan) and one asset (`implementation-plan.md`, 79 lines — the structural skeleton used for plans like this document).
- This skill is being used to produce this plan — the pre-change version runs the planning invocation, so it is safe to optimize it immediately. (FEAT-023 deferred it to Phase 7 for the same reason; this rollout has no such constraint since we are not re-invoking `creating-implementation-plans` during the rollout itself.)
- Establishing the forked-skill pattern here before `reviewing-requirements` (the most complex forked skill) keeps risk increasing monotonically.

#### Implementation Steps
1. **FR-7 pre-flight test audit**: open `scripts/__tests__/creating-implementation-plans.test.ts`. Confirm or refine Phase 0 findings. Record in FEAT-024 Notes.
2. **Baseline measurement** (from Phase 0): confirm per-file rows for `SKILL.md`, `references/implementation-plan-example.md`, and `assets/implementation-plan.md`.
3. **FR-1 — lite-style prose compression**: read `SKILL.md` in full. Apply compression. Preserve all FR-4 carve-outs and `## Output Style` verbatim.
4. **FR-2 — heavy-narrative relocation**: scan SKILL.md for sections exceeding ~25 lines. `references/implementation-plan-example.md` is already a reference file (example, not procedural narrative). If SKILL.md contains long numbered procedures or decision flows, relocate them with inline pointers. Record outcome.
5. **FR-3 — natural collapse**: scan for repeated tables. Record as no-op with justification if none found.
6. **FR-4 — carve-out verification**: confirm all carve-outs and `## Output Style` intact.
7. **Post-change measurement + delta**: `wc -l -w -c` on all files in scope. Compute SKILL.md `chars / 4`. Record in FEAT-024 Notes.
8. **Update any affected test assertions** in same commit with FEAT-024 comment.
9. **Run `npm run validate`** — must pass.
10. **Run `npm test -- --testPathPatterns=creating-implementation-plans`** — must pass.
11. **Commit**: `feat(FEAT-024): apply input-token optimization to creating-implementation-plans`.

#### Deliverables
- [ ] `plugins/lwndev-sdlc/skills/creating-implementation-plans/SKILL.md` — FR-1 compression applied
- [ ] FR-2 outcome recorded in FEAT-024 Notes
- [ ] FR-3 outcome recorded in FEAT-024 Notes
- [ ] Post-change measurements and delta recorded in FEAT-024 Notes
- [ ] Any affected test assertions updated in same commit
- [ ] `npm run validate` passes
- [ ] `npm test -- --testPathPatterns=creating-implementation-plans` passes

---

### Phase 7: `reviewing-requirements` — forked skill, largest SKILL.md, three-mode dispatcher
**Feature:** [FEAT-024](../features/FEAT-024-input-token-optimization-rollout.md) | [#203](https://github.com/lwndev/lwndev-marketplace/issues/203)
**Status:** Pending

#### Rationale
- Largest SKILL.md of the twelve (434 lines, 27 945 chars). `reviewing-requirements` operates in three distinct modes (standard review, test-plan reconciliation, code-review reconciliation) selected automatically from context — the SKILL.md must preserve all mode-selection logic and the per-mode findings display exactly.
- The FR-2 relocation threshold (~25 lines) may apply to per-mode procedural flows — these are the primary candidates for relocation to `references/`. An existing `references/review-example.md` (95 lines) is reference material, not a relocation target.
- This skill has a non-standard return shape (`Found **N errors**, **N warnings**, **N info**`) and interactive findings-decision prompts — both are load-bearing FR-4 carve-outs. Extra care required.
- Deferring to Phase 7 (after simpler forked skills) ensures the template is well-calibrated before editing the highest-complexity SKILL.md.

#### Implementation Steps
1. **FR-7 pre-flight test audit**: open `scripts/__tests__/reviewing-requirements.test.ts`. Confirm or refine Phase 0 findings. Pay particular attention to any assertions on the three-mode dispatch logic, findings display format, or the `Found **N errors** ...` return line. Record in FEAT-024 Notes.
2. **Baseline measurement** (from Phase 0): confirm per-file rows for `SKILL.md`, `references/review-example.md`, and `assets/review-findings-template.md`.
3. **FR-1 — lite-style prose compression**: read `SKILL.md` in full. Apply compression. The three-mode dispatch table, all findings display blocks, all carve-out bullets, the interactive prompts, and the `## Output Style` section must be preserved verbatim.
4. **FR-2 — heavy-narrative relocation**: identify sections exceeding ~25 lines. The per-mode step sequences and any verbose decision-flow prose are primary candidates. Relocate to a new file (e.g., `references/mode-procedures.md`) with inline pointers. The `## Output Style` section is explicitly excluded from the ~25-line threshold. Record outcome.
5. **FR-3 — natural collapse**: scan for repeated tables. `reviewing-requirements` may have near-duplicate tables across its three modes (e.g., per-mode findings format tables). If found, consolidate into one parameterized table plus a lossless deltas note enumerating every mode-specific difference. Record outcome.
6. **FR-4 — carve-out verification**: confirm findings display, interactive prompts, `Found **N errors** ...` return line, FR-14 echo lines, tagged structured logs, state transitions, and `## Output Style` all intact.
7. **Post-change measurement + delta**: `wc -l -w -c` on all files in scope. Compute SKILL.md `chars / 4`. Record in FEAT-024 Notes. Per-skill subtotal must include `review-example.md` and `review-findings-template.md` even if unchanged.
8. **Update any affected test assertions** in same commit with FEAT-024 comment.
9. **Run `npm run validate`** — must pass.
10. **Run `npm test -- --testPathPatterns=reviewing-requirements`** — must pass.
11. **Commit**: `feat(FEAT-024): apply input-token optimization to reviewing-requirements`.

#### Deliverables
- [ ] `plugins/lwndev-sdlc/skills/reviewing-requirements/SKILL.md` — FR-1 compression applied; all three-mode logic, findings display, and interactive prompts preserved verbatim
- [ ] New `references/` file(s) for relocated mode-procedure narrative OR FR-2 recorded as no-op
- [ ] FR-3 outcome recorded in FEAT-024 Notes
- [ ] Post-change measurements and delta recorded in FEAT-024 Notes
- [ ] Any affected test assertions updated in same commit
- [ ] `npm run validate` passes
- [ ] `npm test -- --testPathPatterns=reviewing-requirements` passes

---

### Phase 8: `executing-chores` — forked skill, one reference, one asset, carve-out fix
**Feature:** [FEAT-024](../features/FEAT-024-input-token-optimization-rollout.md) | [#203](https://github.com/lwndev/lwndev-marketplace/issues/203)
**Status:** Pending

#### Rationale
- `executing-chores` is a forked skill (chore chain step 4). It has one reference file (`workflow-details.md`, 277 lines — a detailed workflow procedure) and one asset (`pr-template.md` — PR description template).
- Edge Case 10 applies: `executing-chores` currently contains the self-contradictory form "Unicode `->` " in its FR-14 carve-out block. The rollout pass must correct this to "Unicode `→`" per FR-4's Correction note. This correction is classified as a carve-out fidelity fix, not a behavioral change. Call it out explicitly in the commit message and PR body.
- The `references/workflow-details.md` file may itself be a candidate for further relocation (if SKILL.md has long sections pointing into it without adequate coverage from the existing reference pointer). However, since it is already in `references/`, the primary FR-2 question is whether SKILL.md still retains verbose sections that should point to it instead.

#### Implementation Steps
1. **FR-7 pre-flight test audit**: open `scripts/__tests__/executing-chores.test.ts`. Confirm or refine Phase 0 findings. Note any assertion that pins the "Unicode `->` " string — this will become "will-change". Record in FEAT-024 Notes.
2. **Baseline measurement** (from Phase 0): confirm per-file rows for `SKILL.md`, `references/workflow-details.md`, and `assets/pr-template.md`.
3. **Carve-out fidelity fix**: locate the FR-14 carve-out block in `SKILL.md`. Replace any occurrence of "Unicode `->` " (ASCII arrow, self-contradictory) with "Unicode `→`" (the canonical form used in `orchestrating-workflows/SKILL.md` after CHORE-035). Record the line(s) changed.
4. **FR-1 — lite-style prose compression**: apply to `SKILL.md` (including the already-fixed carve-out line). Preserve all FR-4 carve-outs and `## Output Style` verbatim.
5. **FR-2 — heavy-narrative relocation**: scan SKILL.md for sections exceeding ~25 lines. `workflow-details.md` already holds the detailed workflow; verify that SKILL.md correctly dispatches to it with inline pointers and does not redundantly repeat the full detail. Relocate any remaining long SKILL.md sections. Record outcome.
6. **FR-3 — natural collapse**: scan for repeated tables. Record as no-op with justification if none found.
7. **FR-4 — carve-out verification**: confirm all carve-outs intact; confirm the corrected "Unicode `→`" form is present; confirm `## Output Style` verbatim.
8. **Post-change measurement + delta**: `wc -l -w -c` on all files in scope. Compute SKILL.md `chars / 4`. Record in FEAT-024 Notes.
9. **Update any affected test assertions** (including any that asserted on the old "Unicode `->`" string) in same commit with FEAT-024 comment.
10. **Run `npm run validate`** — must pass.
11. **Run `npm test -- --testPathPatterns=executing-chores`** — must pass.
12. **Commit**: `feat(FEAT-024): apply input-token optimization to executing-chores; fix FR-14 carve-out Unicode arrow`.

#### Deliverables
- [ ] `plugins/lwndev-sdlc/skills/executing-chores/SKILL.md` — FR-1 compression applied; "Unicode `→`" carve-out fidelity fix applied and called out in commit
- [ ] FR-2 outcome recorded in FEAT-024 Notes
- [ ] FR-3 outcome recorded in FEAT-024 Notes
- [ ] Post-change measurements and delta recorded in FEAT-024 Notes
- [ ] Any affected test assertions updated in same commit (including Unicode arrow assertion if present)
- [ ] `npm run validate` passes
- [ ] `npm test -- --testPathPatterns=executing-chores` passes

---

### Phase 9: `executing-bug-fixes` — forked skill, one reference, one asset, carve-out fix
**Feature:** [FEAT-024](../features/FEAT-024-input-token-optimization-rollout.md) | [#203](https://github.com/lwndev/lwndev-marketplace/issues/203)
**Status:** Pending

#### Rationale
- Direct sibling to `executing-chores` (Phase 8). Same forked-skill shape: one reference (`workflow-details.md`, 338 lines — slightly larger than the chores equivalent) and one asset (`pr-template.md`).
- Edge Case 10 applies: `executing-bug-fixes` also contains the self-contradictory "Unicode `->`" form in its FR-14 carve-out. Correct to "Unicode `→`" in this phase, same as Phase 8. Call out in commit and PR body.
- Sequenced immediately after Phase 8 so the carve-out fix pattern is fresh and consistent.

#### Implementation Steps
1. **FR-7 pre-flight test audit**: open `scripts/__tests__/executing-bug-fixes.test.ts`. Confirm or refine Phase 0 findings. Note any assertion pinning the old carve-out string. Record in FEAT-024 Notes.
2. **Baseline measurement** (from Phase 0): confirm per-file rows present.
3. **Carve-out fidelity fix**: locate and correct "Unicode `->`" to "Unicode `→`" in the FR-14 carve-out block. Record the line(s) changed.
4. **FR-1 — lite-style prose compression**: apply to `SKILL.md` (post-fix). Preserve all FR-4 carve-outs and `## Output Style` verbatim.
5. **FR-2 — heavy-narrative relocation**: scan SKILL.md for sections exceeding ~25 lines. `workflow-details.md` holds the detailed bug-fix workflow; verify SKILL.md correctly dispatches with inline pointers. Relocate any remaining verbose SKILL.md sections. Record outcome.
6. **FR-3 — natural collapse**: scan for repeated tables. Record as no-op with justification if none found.
7. **FR-4 — carve-out verification**: confirm corrected "Unicode `→`" form and all other carve-outs; confirm `## Output Style` verbatim.
8. **Post-change measurement + delta**: `wc -l -w -c` on all files in scope. Compute SKILL.md `chars / 4`. Record in FEAT-024 Notes.
9. **Update any affected test assertions** in same commit with FEAT-024 comment.
10. **Run `npm run validate`** — must pass.
11. **Run `npm test -- --testPathPatterns=executing-bug-fixes`** — must pass.
12. **Commit**: `feat(FEAT-024): apply input-token optimization to executing-bug-fixes; fix FR-14 carve-out Unicode arrow`.

#### Deliverables
- [ ] `plugins/lwndev-sdlc/skills/executing-bug-fixes/SKILL.md` — FR-1 compression applied; "Unicode `→`" carve-out fidelity fix applied and called out in commit
- [ ] FR-2 outcome recorded in FEAT-024 Notes
- [ ] FR-3 outcome recorded in FEAT-024 Notes
- [ ] Post-change measurements and delta recorded in FEAT-024 Notes
- [ ] Any affected test assertions updated in same commit
- [ ] `npm run validate` passes
- [ ] `npm test -- --testPathPatterns=executing-bug-fixes` passes

---

### Phase 10: `documenting-qa` — main-context, no references, two assets
**Feature:** [FEAT-024](../features/FEAT-024-input-token-optimization-rollout.md) | [#203](https://github.com/lwndev/lwndev-marketplace/issues/203)
**Status:** Pending

#### Rationale
- `documenting-qa` is a main-context skill (run in the orchestrator's conversation). At 200 lines, it is the second-largest of the main-context skills. It has no `references/` directory (Edge Cases 1 and 9 apply) and two assets (`test-plan-template-v2.md` and `test-plan-template.md`).
- If FR-2 identifies heavy narrative for relocation, a new `references/` directory must be created. The asset files are structural templates — they are measurement targets (FR-5) but the FR-1 compression target is SKILL.md.
- Sequenced after the executing-* pair to keep all forked skills together; the QA skills (10–11) wrap up the main-context group.

#### Implementation Steps
1. **FR-7 pre-flight test audit**: open `scripts/__tests__/documenting-qa.test.ts`. Confirm or refine Phase 0 findings. Record in FEAT-024 Notes.
2. **Baseline measurement** (from Phase 0): confirm per-file rows for `SKILL.md`, `assets/test-plan-template-v2.md`, and `assets/test-plan-template.md`. No `references/` row exists yet (Edge Case 9).
3. **FR-1 — lite-style prose compression**: apply to `SKILL.md`. Preserve all FR-4 carve-outs and `## Output Style` verbatim.
4. **FR-2 — heavy-narrative relocation**: scan SKILL.md for sections exceeding ~25 lines. If any qualify, create `references/` directory and relocate with inline pointers. If no sections qualify, record FR-2 as a no-op and note that no `references/` directory is needed. Record outcome explicitly (Edge Case 1 resolution).
5. **FR-3 — natural collapse**: scan for repeated tables. The adversarial dimension table is a candidate if it appears more than once. Record as no-op with justification if none found.
6. **FR-4 — carve-out verification**: confirm all carve-outs and `## Output Style` intact.
7. **Post-change measurement + delta**: `wc -l -w -c` on all files in scope (new `references/` files if created). Compute SKILL.md `chars / 4`. Record in FEAT-024 Notes. Per Edge Case 9, explicitly note the `references/`-absent state before and after in the measurement notes.
8. **Update any affected test assertions** in same commit with FEAT-024 comment.
9. **Run `npm run validate`** — must pass.
10. **Run `npm test -- --testPathPatterns=documenting-qa`** — must pass.
11. **Commit**: `feat(FEAT-024): apply input-token optimization to documenting-qa`.

#### Deliverables
- [ ] `plugins/lwndev-sdlc/skills/documenting-qa/SKILL.md` — FR-1 compression applied
- [ ] `plugins/lwndev-sdlc/skills/documenting-qa/references/` — created with relocated content OR FR-2 recorded as no-op
- [ ] FR-3 outcome recorded in FEAT-024 Notes
- [ ] Post-change measurements and delta recorded in FEAT-024 Notes (Edge Case 9 noted)
- [ ] Any affected test assertions updated in same commit
- [ ] `npm run validate` passes
- [ ] `npm test -- --testPathPatterns=documenting-qa` passes

---

### Phase 11: `executing-qa` — main-context, no references, two assets
**Feature:** [FEAT-024](../features/FEAT-024-input-token-optimization-rollout.md) | [#203](https://github.com/lwndev/lwndev-marketplace/issues/203)
**Status:** Pending

#### Rationale
- Direct sibling to `documenting-qa` (Phase 10). Same main-context, no-references shape. Two assets (`test-results-template-v2.md`, `test-results-template.md`). At 270 lines, it is the second-largest SKILL.md of the twelve — the additional lines are primarily the QA execution procedure and the results artifact schema.
- Edge Cases 1 and 9 apply (same as Phase 10). If heavy narrative is identified, create `references/` directory.
- Sequenced directly after Phase 10 to keep the QA pair together.

#### Implementation Steps
1. **FR-7 pre-flight test audit**: open `scripts/__tests__/executing-qa.test.ts`. Confirm or refine Phase 0 findings. Record in FEAT-024 Notes.
2. **Baseline measurement** (from Phase 0): confirm per-file rows for `SKILL.md`, `assets/test-results-template-v2.md`, and `assets/test-results-template.md`. No `references/` row.
3. **FR-1 — lite-style prose compression**: apply to `SKILL.md`. Preserve all FR-4 carve-outs (especially the verdict-decision prompts and results display blocks) and `## Output Style` verbatim.
4. **FR-2 — heavy-narrative relocation**: scan SKILL.md for sections exceeding ~25 lines. Primary candidates: long numbered test-execution recipes, verbose verdict decision flows. Relocate to a new `references/` file with inline pointers if warranted. Record outcome explicitly (Edge Case 1 resolution).
5. **FR-3 — natural collapse**: scan for repeated tables. If the per-chain step sequence or per-dimension test table appears more than once, consolidate. Record as no-op with justification if none found.
6. **FR-4 — carve-out verification**: confirm all carve-outs (verdict prompts, results display, FR-14 echo lines, tagged structured logs, state transitions) and `## Output Style` intact.
7. **Post-change measurement + delta**: `wc -l -w -c` on all files in scope. Compute SKILL.md `chars / 4`. Record in FEAT-024 Notes. Note Edge Case 9 resolution.
8. **Update any affected test assertions** in same commit with FEAT-024 comment.
9. **Run `npm run validate`** — must pass.
10. **Run `npm test -- --testPathPatterns=executing-qa`** — must pass.
11. **Commit**: `feat(FEAT-024): apply input-token optimization to executing-qa`.

#### Deliverables
- [ ] `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md` — FR-1 compression applied
- [ ] `plugins/lwndev-sdlc/skills/executing-qa/references/` — created with relocated content OR FR-2 recorded as no-op
- [ ] FR-3 outcome recorded in FEAT-024 Notes
- [ ] Post-change measurements and delta recorded in FEAT-024 Notes (Edge Case 9 noted)
- [ ] Any affected test assertions updated in same commit
- [ ] `npm run validate` passes
- [ ] `npm test -- --testPathPatterns=executing-qa` passes

---

### Phase 12: `implementing-plan-phases` — forked skill, largest combined surface, carve-out fix
**Feature:** [FEAT-024](../features/FEAT-024-input-token-optimization-rollout.md) | [#203](https://github.com/lwndev/lwndev-marketplace/issues/203)
**Status:** Pending

#### Rationale
- `implementing-plan-phases` has the largest combined file surface of all twelve skills: 178-line SKILL.md, two reference files totaling 726 lines (`step-details.md` 399 lines + `workflow-example.md` 327 lines), and one asset (`pr-template.md`). Deferring it to last among the forked skills ensures the three-axis template is well-calibrated before the highest-risk edit.
- Edge Case 10 applies: this skill also contains the self-contradictory "Unicode `->`" form. Correct to "Unicode `→`" in this phase. Call out in commit and PR body.
- The two large reference files are already reference material (step details + workflow example). The primary FR-2 question is whether SKILL.md still holds verbose sections that should be dispatching to those references via pointers rather than repeating content.
- This is the last per-skill phase. Completing it makes all twelve skills consistent and triggers Phase 13.

#### Implementation Steps
1. **FR-7 pre-flight test audit**: open `scripts/__tests__/implementing-plan-phases.test.ts`. Confirm or refine Phase 0 findings. Pay attention to any assertions on section headings that index the per-phase status workflow or the step-details pointer. Record in FEAT-024 Notes.
2. **Baseline measurement** (from Phase 0): confirm per-file rows for `SKILL.md`, `references/step-details.md`, `references/workflow-example.md`, and `assets/pr-template.md`.
3. **Carve-out fidelity fix**: locate and correct "Unicode `->`" to "Unicode `→`" in the FR-14 carve-out block. Record the line(s) changed.
4. **FR-1 — lite-style prose compression**: apply to `SKILL.md` (post-fix). Preserve all FR-4 carve-outs, the plan-approval pause prompt, status transition markers, and `## Output Style` verbatim.
5. **FR-2 — heavy-narrative relocation**: scan SKILL.md for sections exceeding ~25 lines. The two existing reference files hold most procedural detail. Verify SKILL.md dispatches to them with inline pointers and does not redundantly repeat the full detail. If any SKILL.md sections still qualify for relocation, add to an existing reference or create a new file. Record outcome.
6. **FR-3 — natural collapse**: scan for repeated tables. `implementing-plan-phases` is invoked per phase — if it has per-phase variant tables (e.g., per-chain phase sequence tables), apply parameterized collapse plus lossless deltas note. Record outcome.
7. **FR-4 — carve-out verification**: confirm corrected "Unicode `→`" and all other carve-outs; confirm `## Output Style` verbatim.
8. **Post-change measurement + delta**: `wc -l -w -c` on all files in scope. Compute SKILL.md `chars / 4`. Record in FEAT-024 Notes.
9. **Update any affected test assertions** in same commit with FEAT-024 comment.
10. **Run `npm run validate`** — must pass.
11. **Run `npm test -- --testPathPatterns=implementing-plan-phases`** — must pass.
12. **Commit**: `feat(FEAT-024): apply input-token optimization to implementing-plan-phases; fix FR-14 carve-out Unicode arrow`.

#### Deliverables
- [ ] `plugins/lwndev-sdlc/skills/implementing-plan-phases/SKILL.md` — FR-1 compression applied; "Unicode `→`" carve-out fidelity fix applied and called out in commit
- [ ] FR-2 outcome recorded in FEAT-024 Notes (SKILL.md-to-references pointer verification or additional relocation)
- [ ] FR-3 outcome recorded in FEAT-024 Notes
- [ ] Post-change measurements and delta recorded in FEAT-024 Notes
- [ ] Any affected test assertions updated in same commit
- [ ] `npm run validate` passes
- [ ] `npm test -- --testPathPatterns=implementing-plan-phases` passes

---

### Phase 13: Grand-Total Aggregation, Summary, and Acceptance Criteria Verification
**Feature:** [FEAT-024](../features/FEAT-024-input-token-optimization-rollout.md) | [#203](https://github.com/lwndev/lwndev-marketplace/issues/203)
**Status:** Pending

#### Rationale
- All twelve per-skill phases are complete. This phase aggregates measurements, computes the Summary subsection against the CHORE-035 prediction, runs full end-to-end verification, and closes the acceptance criteria.
- No SKILL.md is edited in this phase — purely measurement aggregation, documentation, and verification.

#### Implementation Steps
1. **Aggregate baseline measurements**: collect per-file baseline rows recorded across Phases 0–12. Compile the full baseline table in FEAT-024 Notes → Baseline Measurements: per-file rows, per-skill subtotals, grand total. Columns: `Skill | File | Lines | Words | Chars | Input-token est (chars/4)`.
2. **Aggregate post-change measurements**: compile the full post-change table in the same format in FEAT-024 Notes → Post-Change Measurements.
3. **Compute and append the delta table**: emit the delta table in FEAT-024 Notes → Delta: columns `Skill | File | Lines Δ | Lines % | Words Δ | Words % | Chars Δ | Chars %`. Add per-skill subtotals and a grand-total row. Call out the SKILL.md input-token delta per skill separately — it is the primary target quantity (per FR-5).
4. **Compile FR-2 relocation registry**: for each of the twelve skills, record the FR-2 outcome (relocated file(s) created, relocation site pointers added, or no-op with justification). Skills with no pre-existing `references/` directory and no new relocation (Edge Case 1 no-op) are listed explicitly.
5. **Compile FR-3 collapse registry**: for each skill, record the FR-3 outcome (collapse applied with description of consolidated tables, or no-op with justification).
6. **Compile FR-4 carve-out fidelity log**: list the three skills where "Unicode `->`" was corrected to "Unicode `→`" (`executing-chores`, `executing-bug-fixes`, `implementing-plan-phases`). Confirm correction is in place for each.
7. **Compile FR-7 audit closure**: for each of the twelve skills, record the audit finding disposition — "will-change" assertions updated, "must-preserve" assertions verified passing.
8. **Append Summary subsection** to FEAT-024 Notes → Summary: aggregate total SKILL.md chars saved across all twelve skills; total estimated input-token reduction; per-workflow savings derivation (a feature chain with N phases dispatches ~4 + N skills as forks; each fork reads one SKILL.md in full, so savings compound ~4 + N times per workflow). Compare against the CHORE-035 pilot prediction (~5 + N compounded per workflow).
9. **Run `npm run validate`** — must pass.
10. **Run `npm test`** (full suite, not scoped) — must pass. If any test fails, diagnose and fix in this phase's commit.
11. **Manual spot-check** (record outcome in FEAT-024 Notes): render `SKILL.md` for one forked skill (`implementing-plan-phases`), one main-context skill (`executing-qa`), and one cross-cutting skill (`managing-work-items`) in markdown preview. Confirm dispatcher paragraphs read cleanly and reference pointers resolve.
12. **Run one full feature workflow chain** (resume or new) to confirm no dispatch regressions from heavy-narrative relocation. Record outcome in FEAT-024 Notes.
13. **Run one full chore workflow chain** to confirm no dispatch regressions for non-feature chain types. Record outcome in FEAT-024 Notes.
14. **Verify all acceptance criteria** in FEAT-024 requirements doc — check each checkbox as complete.
15. **Commit**: `feat(FEAT-024): aggregate measurements, Summary subsection, and full AC verification`.

#### Deliverables
- [ ] Baseline measurement table (per-file, per-skill subtotal, grand total) appended to FEAT-024 Notes → Baseline Measurements
- [ ] Post-change measurement table appended to FEAT-024 Notes → Post-Change Measurements
- [ ] Delta table appended to FEAT-024 Notes → Delta (SKILL.md input-token delta called out per skill)
- [ ] FR-2 relocation registry complete in FEAT-024 Notes
- [ ] FR-3 collapse registry complete in FEAT-024 Notes
- [ ] FR-4 carve-out fidelity log complete in FEAT-024 Notes (three Unicode-arrow corrections documented)
- [ ] FR-7 audit closure complete in FEAT-024 Notes
- [ ] Summary subsection appended to FEAT-024 Notes (total savings + per-workflow compounding + CHORE-035 comparison)
- [ ] `npm run validate` passes
- [ ] `npm test` (full suite) passes
- [ ] Manual spot-check outcome recorded in FEAT-024 Notes
- [ ] Feature workflow chain end-to-end outcome recorded in FEAT-024 Notes
- [ ] Chore workflow chain end-to-end outcome recorded in FEAT-024 Notes
- [ ] All acceptance criteria checkboxes verified in FEAT-024 requirements doc

---

## Shared Infrastructure

### Three-Axis Template

Every per-skill phase applies the same three-axis template mechanically:

**Axis 1 — FR-1: Lite-style prose compression**
Remove filler, hedging, and pleasantries. Keep articles and full sentences (no pronoun-drop that loses the antecedent). Preserve Edge Case 7 constructs (parenthetical enumerations of user-facing phrases). Leave code blocks, command lines, flags, file paths, anchor identifiers, and table headers untouched. Never compress the `## Output Style` section.

**Axis 2 — FR-2: Heavy-narrative relocation**
Test: does SKILL.md need the full text to decide what to do next, or does a pointer suffice? Threshold: no non-dispatcher section should exceed ~25 lines, excluding `## Output Style` and bounded tables. Tables, contract shapes, carve-out bullets, and override-precedence rows stay in SKILL.md (indexed at dispatch time). Long numbered recipes and verbose procedural narratives relocate to `references/`. Inline pointer at end of dispatcher paragraph, not the start (Edge Case 8).

**Axis 3 — FR-3: Natural collapse**
Consolidate near-duplicate tables (e.g., per-chain step-sequence tables) into one parameterized table plus a lossless deltas note. The deltas note must enumerate every difference the original tables conveyed (not a summary). Skills without repeated tables record FR-3 as a no-op.

### Load-Bearing Carve-Outs (FR-4)

The following must NEVER be stripped by FR-1 and must be preserved verbatim in every target SKILL.md:

- Error messages from `fail` calls
- Security-sensitive warnings (destructive-operation confirmations, baseline-bypass warnings)
- Interactive prompts (plan-approval pause, findings-decision prompts, review-findings prompts)
- Findings display from `reviewing-requirements` (full findings list must precede any decision prompt)
- FR-14 console echo lines — canonical form is "Unicode `→`" (not "Unicode `->`"); correct the self-contradictory form where found
- Tagged structured logs (`[info]`, `[warn]`, `[model]`)
- User-visible state transitions (pause, advance, resume — at most one line each)
- Code blocks, command lines, flags, file paths, anchor identifiers, table headers
- The entire `## Output Style` section installed by FEAT-023 (preserved character-for-character)

### Measurement Methodology

Measurements use `wc -l -w -c` (POSIX static word count), matching the CHORE-035 pilot methodology. Input-token estimate for each `SKILL.md` is `chars / 4` (rule-of-thumb fallback estimator). If `ANTHROPIC_API_KEY` is available, the `/v1/messages/count_tokens` endpoint result is recorded as a corroborating figure alongside the `chars / 4` number. The `ai-skills-manager` `validate()` body-token estimator may also be recorded if available. All three estimators are distinguished in the Notes table columns. Runtime telemetry is out of scope.

### Pre-flight Test Audit Taxonomy (FR-7)

Findings are classified as:
- **will-change**: test asserts on content that this rollout will modify (e.g., hardcoded line counts, narration phrases being compressed, headings being renamed). Update the test in the same phase commit. For hardcoded-count assertions, convert to a lower-bound assertion and add a comment referencing FEAT-024.
- **must-preserve**: test asserts on content that must remain unchanged (e.g., carve-out exact text, frontmatter fields, script invocations, fork-return contract shape). Verify the assertion still passes after edits.

---

## Testing Strategy

### Unit Tests

- `npm run validate` runs after each per-skill phase commit (phases 1–12). Frontmatter fields (`name`, `description`, `allowed-tools`, `argument-hint`) must be unchanged after every phase.
- Per-skill test file (`npm test -- --testPathPatterns=<skill-name>`) runs after each phase. If a test assertion needs updating due to FR-1 compression (per FR-7 pre-flight audit), the update lands in the same phase commit, not deferred.

### Integration Tests

- Full `npm test` runs in Phase 13 after all twelve skills are complete. Any test that was not caught by the per-phase targeted run must be fixed in Phase 13.
- No failing tests should persist across phase boundaries (NFR-3).

### Manual Testing

- Phase 13 spot-check: render SKILL.md for one forked skill (`implementing-plan-phases`), one main-context skill (`executing-qa`), and one cross-cutting skill (`managing-work-items`) in markdown preview. Confirm dispatcher paragraphs read cleanly and reference pointers resolve.
- Phase 13: run one full feature workflow chain to confirm no dispatch regressions from heavy-narrative relocation.
- Phase 13: run one full chore workflow chain for the same purpose.

---

## Dependencies and Prerequisites

- **CHORE-035** (merged) — pilot; `requirements/chores/CHORE-035-input-token-optimization-pilot.md` Learnings section is the source of truth for the three-axis template and FR-7 pattern.
- **CHORE-034** (merged) — established the FR-4 carve-out list.
- **FEAT-023** (merged) — installed `## Output Style` in every target skill; that section is a FR-4 preservation target for this rollout.
- **FEAT-014** (merged) — defined the FR-14 console echo line format (Unicode `→`); canonical for the FR-4 carve-out correction.
- **`orchestrating-workflows/SKILL.md`** — the canonical post-pilot example of the three-axis template; the rollout replicates its structural pattern.
- **No external tooling** beyond `wc`, the `chars / 4` estimator, and the existing `npm run validate` / `npm test` scripts.

---

## Risk Assessment

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Over-compression strips a load-bearing carve-out | High — alters skill runtime behavior | Low — FR-4 carve-out list is explicit and long; phase reviewer can verify | Use FR-4 checklist step in every phase; spot-check in Phase 13 manual testing |
| Pronoun-drop loses an antecedent (Edge Case 7) | Medium — skill loses a required user-facing phrase | Low — pilot Learnings flag this explicitly as a template item | Keep full sentences where antecedent or enumeration would be lost; FR-7 pre-flight flags these |
| FR-2 inline pointer placed at start of paragraph (Edge Case 8) | Low — pointer before the summary defeats readability intent | Low — explicit rule: pointer at end of dispatcher paragraph | Apply the rule mechanically; Phase 13 spot-check confirms placement |
| `reviewing-requirements` three-mode logic damaged by compression | High — orchestrator mode-dispatch breaks | Medium — large SKILL.md with complex dispatch table | Defer to Phase 7; extra scrutiny on mode-selection table and per-mode findings block |
| Hardcoded-count test fails silently across phase boundary (NFR-3) | Medium — CI red on later commit | Low — FR-7 pre-flight audit identifies these; per-phase targeted test run catches them | FR-7 in Phase 0 seeds the per-phase audit; targeted `npm test` per phase |
| Unicode `→` correction applied inconsistently across three skills | Low — carve-out text remains partially incorrect | Low — Edge Case 10 is called out explicitly for all three skills | Phases 8, 9, 12 each include the correction step; Phase 13 verifies all three |
| `references/` directory creation for `documenting-qa`, `executing-qa`, `finalizing-workflow` introduces a broken anchor | Medium — `npm run validate` fails | Low — anchor resolution is tested by `npm run validate` | Run `npm run validate` immediately after creating any new reference file |
| Measurement methodology inconsistency (NFR-1) | Low — post-change numbers are not comparable to baseline | Low — `chars / 4` is a single formula; `wc` is deterministic | Document methodology explicitly in Phase 0; use it mechanically per phase |

---

## Success Criteria

- All twelve target skills have had their `SKILL.md` prose compressed to lite style (FR-1), with load-bearing carve-outs preserved verbatim and `## Output Style` character-for-character intact.
- Each target skill has had heavy-narrative sections relocated to `references/` with inline pointers, or the skill is recorded as an FR-2 no-op (FR-2).
- Each target skill has had natural collapse applied, or the skill is recorded as an FR-3 no-op (FR-3).
- The three skills with self-contradictory "Unicode `->`" carve-out text (`executing-chores`, `executing-bug-fixes`, `implementing-plan-phases`) have been corrected to "Unicode `→`" (FR-4 correction note).
- Baseline and post-change `wc -l -w -c` measurements and `chars / 4` SKILL.md input-token estimates have been captured per skill and aggregated in FEAT-024 Notes (FR-5/NFR-1).
- A Summary subsection in FEAT-024 Notes aggregates total SKILL.md chars/input-tokens saved and compares against the CHORE-035 pilot prediction (NFR-5).
- A pre-flight test audit (FR-7) has been recorded per skill before that skill's edit pass; all "will-change" assertions have been updated in the relevant phase commit.
- Each skill's optimization was committed as an independent phase commit (NFR-2). No multi-skill grouping was applied; the PR body calls this out.
- The same three-axis template, carve-out list, and measurement format were applied consistently to every skill (NFR-4).
- No frontmatter fields, script invocations, file paths, artifact paths, verification checklist semantics, Fork Step-Name Map entries, step-sequence table semantics, or fork-return contracts have changed (FR-6).
- All internal SKILL.md anchors and cross-skill references still resolve.
- `npm run validate` passes.
- `npm test` (full suite) passes.

---

## Code Organization

```
plugins/lwndev-sdlc/skills/
├── finalizing-workflow/
│   ├── SKILL.md                                   <- Phase 1: FR-1/FR-2/FR-3 applied
│   └── references/                                <- Phase 1: created if FR-2 relocation needed
├── documenting-features/
│   ├── SKILL.md                                   <- Phase 2: FR-1/FR-2/FR-3 applied
│   ├── references/                                <- Phase 2: new files if FR-2 relocation needed
│   │   ├── feature-requirements-example-episodes-command.md  (unchanged)
│   │   └── feature-requirements-example-search-command.md    (unchanged)
│   └── assets/feature-requirements.md            (unchanged; FR-5 measurement only)
├── documenting-chores/
│   ├── SKILL.md                                   <- Phase 3: FR-1/FR-2/FR-3 applied
│   ├── references/categories.md                  (unchanged; FR-5 measurement only)
│   └── assets/chore-document.md                 (unchanged; FR-5 measurement only)
├── documenting-bugs/
│   ├── SKILL.md                                   <- Phase 4: FR-1/FR-2/FR-3 applied
│   ├── references/categories.md                  (unchanged; FR-5 measurement only)
│   └── assets/bug-document.md                   (unchanged; FR-5 measurement only)
├── managing-work-items/
│   ├── SKILL.md                                   <- Phase 5: FR-1/FR-2/FR-3 applied
│   └── references/
│       ├── github-templates.md                   (unchanged; FR-5 measurement only)
│       └── jira-templates.md                     (unchanged; FR-5 measurement only)
├── creating-implementation-plans/
│   ├── SKILL.md                                   <- Phase 6: FR-1/FR-2/FR-3 applied
│   ├── references/implementation-plan-example.md (unchanged; FR-5 measurement only)
│   └── assets/implementation-plan.md            (unchanged; FR-5 measurement only)
├── reviewing-requirements/
│   ├── SKILL.md                                   <- Phase 7: FR-1/FR-2/FR-3 applied
│   ├── references/
│   │   ├── review-example.md                     (unchanged; FR-5 measurement only)
│   │   └── mode-procedures.md                    <- Phase 7: new file if FR-2 relocation
│   └── assets/review-findings-template.md       (unchanged; FR-5 measurement only)
├── executing-chores/
│   ├── SKILL.md                                   <- Phase 8: FR-1/FR-2/FR-3 applied; "Unicode →" fix
│   ├── references/workflow-details.md            (unchanged; FR-5 measurement only)
│   └── assets/pr-template.md                    (unchanged; FR-5 measurement only)
├── executing-bug-fixes/
│   ├── SKILL.md                                   <- Phase 9: FR-1/FR-2/FR-3 applied; "Unicode →" fix
│   ├── references/workflow-details.md            (unchanged; FR-5 measurement only)
│   └── assets/pr-template.md                    (unchanged; FR-5 measurement only)
├── documenting-qa/
│   ├── SKILL.md                                   <- Phase 10: FR-1/FR-2/FR-3 applied
│   ├── references/                                <- Phase 10: created if FR-2 relocation needed
│   ├── assets/test-plan-template-v2.md          (unchanged; FR-5 measurement only)
│   └── assets/test-plan-template.md             (unchanged; FR-5 measurement only)
├── executing-qa/
│   ├── SKILL.md                                   <- Phase 11: FR-1/FR-2/FR-3 applied
│   ├── references/                                <- Phase 11: created if FR-2 relocation needed
│   ├── assets/test-results-template-v2.md       (unchanged; FR-5 measurement only)
│   └── assets/test-results-template.md          (unchanged; FR-5 measurement only)
└── implementing-plan-phases/
    ├── SKILL.md                                   <- Phase 12: FR-1/FR-2/FR-3 applied; "Unicode →" fix
    ├── references/
    │   ├── step-details.md                        (unchanged; FR-5 measurement only)
    │   └── workflow-example.md                   (unchanged; FR-5 measurement only)
    └── assets/pr-template.md                    (unchanged; FR-5 measurement only)

requirements/
├── features/
│   └── FEAT-024-input-token-optimization-rollout.md  <- Notes section updated each phase
└── implementation/
    └── FEAT-024-input-token-optimization-rollout.md  <- this file
```
