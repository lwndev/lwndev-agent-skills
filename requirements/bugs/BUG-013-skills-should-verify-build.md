# Bug: Phase-Completion Skills Skip Build Health Checks

## Bug ID

`BUG-013`

## GitHub Issue

[#212](https://github.com/lwndev/lwndev-marketplace/issues/212)

## Category

`logic-error`

## Severity

`high`

## Description

Phase-completion skills declare success without running the repository's build health commands (`npm run lint`, `npm run format:check`, `npm test`), so lint/format violations reach release branches and `main`. The infrastructure exists in `package.json` but no skill invokes the linter or formatter before reporting a phase complete.

## Steps to Reproduce

1. From a clean working tree, run a chore, bug-fix, or feature workflow that introduces a prettier-only violation in a `.ts` file (for example, an over-long string literal or wrong indentation).
2. Let the executing skill (`executing-chores`, `executing-bug-fixes`, or `implementing-plan-phases`) complete its phase and open a PR.
3. Push the branch (or let the workflow's PR push automatically).
4. Observe CI: the `build / Lint` job fails on prettier/eslint errors that `npm run lint` would have caught locally in seconds.

Live evidence:

- [run 24781710973](https://github.com/lwndev/lwndev-marketplace/actions/runs/24781710973) — `release(lwndev-sdlc): v1.17.0` on `release/lwndev-sdlc-v1.17.0`
- [run 24781373957](https://github.com/lwndev/lwndev-marketplace/actions/runs/24781373957) — `feat/FEAT-023-output-token-optimization`
- [run 24781373952](https://github.com/lwndev/lwndev-marketplace/actions/runs/24781373952) — post-merge CI on `main`

## Expected Behavior

Before any of the affected skills emit a `done | artifact=...` line, open a PR, or tag a release, they should:

1. Detect available build-health commands from `package.json` scripts (`lint`, `format:check`, `test`, `build`, `validate`).
2. Run them and halt the phase if any fail, surfacing the first failure to the user.
3. Offer the auto-fix path when one exists (`lint:fix`, `format`) before re-running.

A phase that introduces a prettier-only violation must not open a PR or finalize until the violation is resolved.

## Actual Behavior

Skills declare success and open PRs (or tag releases) while lint/format violations remain. CI then fails on locally detectable issues, and the violations occasionally reach `main` post-merge. `npm run lint:fix` would have resolved 24 of the 25 errors in the most recent failure automatically.

## Root Cause(s)

1. `plugins/lwndev-sdlc/skills/executing-chores/SKILL.md:63` documents Step 7 as the prose instruction "Run tests/build verification" with no enforcement script. The verification checklist (`SKILL.md:159-161`) lists "Tests pass" and "Build succeeds" but neither item is wired to a deterministic check, so the skill relies on Claude's narration rather than a script outcome.
2. `plugins/lwndev-sdlc/skills/executing-bug-fixes/SKILL.md:65` carries the identical gap: Step 9 also reads "Run tests/build verification" with no enforcement script (`SKILL.md:192-193` for the matching checklist).
3. `plugins/lwndev-sdlc/skills/implementing-plan-phases/scripts/verify-phase-deliverables.sh:217-252` is the only enforcement script in the chain, and it runs `npm test` and `npm run build` but never invokes `npm run lint` or `npm run format:check`. Lint and format violations therefore pass the gate.
4. `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md:145` runs the project's `capability.testCommand` (e.g. `npm test`, `npx vitest run`) but does not invoke `npm run lint` or `npm run format:check`, so the QA step does not catch code-quality violations either.
5. `plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/preflight-checks.sh:98-219` performs structural checks only (clean tree, branch ≠ main, PR open and mergeable) and runs no build-health commands before merging. It assumes upstream skills verified, which (per RCs 1–4) they did not.
6. `.claude/skills/releasing-plugins/SKILL.md:23-162` has no `npm run validate` / `npm run lint` / `npm run format:check` step between changelog preparation (Phase 1) and tag-and-push (Phase 2), so a release tag can be cut against a tree that fails CI.

## Affected Files

- `plugins/lwndev-sdlc/skills/executing-chores/SKILL.md`
- `plugins/lwndev-sdlc/skills/executing-bug-fixes/SKILL.md`
- `plugins/lwndev-sdlc/skills/executing-qa/SKILL.md`
- `plugins/lwndev-sdlc/skills/implementing-plan-phases/SKILL.md`
- `plugins/lwndev-sdlc/skills/implementing-plan-phases/scripts/verify-phase-deliverables.sh`
- `plugins/lwndev-sdlc/skills/finalizing-workflow/SKILL.md`
- `plugins/lwndev-sdlc/skills/finalizing-workflow/scripts/preflight-checks.sh`
- `.claude/skills/releasing-plugins/SKILL.md`
- New file (to be created during implementation): `plugins/lwndev-sdlc/scripts/verify-build-health.sh` — shared verification script so the six skills above do not duplicate the detect-and-run logic. Path is illustrative; the implementation plan may finalize the exact location and name.
- New file (to be created during implementation): `plugins/lwndev-sdlc/scripts/verify-build-health.bats` — bats coverage for the new shared script. Same naming caveat as above.

## Acceptance Criteria

- [x] A shared build-health script exists, detects the available `package.json` scripts (`lint`, `format:check`, `test`, `build`), runs each that exists, and exits non-zero on the first failure with the first error surfaced to stdout/stderr (RC-1, RC-2, RC-3, RC-4, RC-5, RC-6).
- [x] `npm run validate` is detected only when an explicit opt-in flag (e.g. `--include-validate`) is passed; the default detection list excludes it because `validate` is project-specific (in this repo it runs the plugin/skill validator, which is heavier than the other commands and may mean something different in consumer repos) (RC-1, RC-2, RC-3, RC-4, RC-5, RC-6).
- [x] When invoked without a TTY (or with `--no-interactive`), the shared script reports the failure and exits non-zero without offering the auto-fix prompt — orchestrator-forked subagents have no direct user channel, so they always fail-fast (RC-1, RC-2, RC-3, RC-4, RC-5, RC-6).
- [x] When invoked in a project without a recognized `package.json` (or with no matching scripts), the shared script exits zero with an `[info]` skip-message, mirroring `verify-phase-deliverables.sh`'s graceful skip when `npm` is absent (RC-3).
- [x] The shared script offers an auto-fix path (`lint:fix`, `format`) when the corresponding script exists and the call site is interactive, and only re-runs the original check after the user opts in to the fix. The auto-fix branch is reachable only from the four wiring sites that prepare the tree for downstream gates: `executing-chores`, `executing-bug-fixes`, `implementing-plan-phases`, and `releasing-plugins`. `executing-qa` and `finalizing-workflow` invoke the script with `--no-interactive` so the auto-fix branch is suppressed — at those sites a failure must halt the verdict, not be silently corrected (RC-1, RC-2, RC-3, RC-6).
- [x] `executing-chores` Step 7 invokes the shared build-health script and halts with `failed | <reason>` if it exits non-zero, instead of relying on prose narration (RC-1).
- [x] `executing-bug-fixes` Step 9 invokes the shared build-health script and halts with `failed | <reason>` if it exits non-zero (RC-2).
- [x] `implementing-plan-phases`' `verify-phase-deliverables.sh` either invokes the shared build-health script or adds `npm run lint` and `npm run format:check` to its enforced checks, with JSON output reflecting their pass/fail status (RC-3).
- [x] `executing-qa` invokes the shared build-health script before declaring its run complete, so lint/format regressions surfaced during QA fail the QA verdict rather than passing through (RC-4).
- [x] `finalizing-workflow`'s `preflight-checks.sh` invokes the shared build-health script (or rejects the merge if upstream skills did not record a passing run), preventing merges of branches that fail lint/format/test locally (RC-5).
- [x] `releasing-plugins` invokes the shared build-health script between Phase 1 (changelog) and Phase 2 (tag + push), and aborts the release when it exits non-zero (RC-6).
- [x] Bats coverage exists for the shared build-health script: pass case, fail-fast case, missing-script graceful skip, and auto-fix opt-in path (RC-1, RC-2, RC-3, RC-4, RC-5, RC-6).
- [x] A regression test (or recorded manual repro) demonstrates that introducing a prettier-only violation in a chore, bug-fix, and feature phase now blocks PR creation rather than reaching CI (RC-1, RC-2, RC-3).

## Completion

**Status:** `In Progress`

**Completed:** YYYY-MM-DD

**Pull Request:** [#237](https://github.com/lwndev/lwndev-marketplace/pull/237)

## Notes

- `package.json` already defines `lint`, `format:check`, `test`, `build`, and `validate` — the fix is wiring, not infrastructure.
- The exact wiring (one shared sub-skill vs. inline checks repeated across the six skills) is open. The acceptance criteria above bias toward a single shared script to avoid duplication, consistent with the repo's "Prefer Scripts Over Prose" authoring principle, but the implementation plan may revisit this trade-off.
- `executing-qa` is intentionally a code-quality gate as well as a feature gate per this fix; if the team prefers to keep its scope strictly feature-correctness, RC-4's acceptance criterion can be moved to a chained verification step instead.
- **Husky / pre-commit hook integration is out of scope for BUG-013.** `package.json` declares `"prepare": "husky"`, so a husky-managed git hook surface exists, but this bug is scoped to the phase-completion gates listed in RC-1 through RC-6. Whether the same shared script should also run from `.husky/pre-commit` (and how it should compose with any existing hooks) is a separate decision; track it as a follow-up if the implementation reveals overlap or conflict.
