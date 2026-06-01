---
id: BUG-024
version: 2
timestamp: 2026-06-01T03:19:15Z
persona: qa
---

## User Summary

When the finalize step's pre-flight check blocks a merge (e.g. on orphaned or un-adopted `qa-*` test files), the `finalizing-workflow` fork must no longer take destructive git action to unblock itself. Instead it surfaces the pre-flight error verbatim, reports `failed | preflight blocked: <reason>`, and makes no further git/gh mutations. A new Stop hook enforces the skill's write surface so the fork cannot delete, rename, content-edit, commit, or push any file other than the requirement document. The merge-approval gate alone is known to be insufficient; this guard must hold independently.

## Capability Report

- Mode: test-framework
- Framework: vitest
- Package manager: npm
- Test command: npm test
- Language: typescript

Note: the units under test are Bash scripts (`stop-hook.sh`, `finalize.sh`, `preflight-checks.sh`) and Markdown contract files; the project's shell-script harness is Bats (`npx bats tests/bats/...`). Scenarios marked `test-framework` are exercised at the script/hook-logic layer (a simulated `git status` / staged-index state), NOT by spawning a live finalize subagent. Agent-behavioral compliance (the fork returning the failure contract and abstaining from mutations) is enforced at runtime by the Stop hook and is marked `exploratory`.

## Scenarios (by dimension)

### Inputs

- [P0] Subagent stages a deletion (`git rm tests/unit/qa-BUG-018-advance-pause.test.ts`) of a `qa-*` file outside the write surface, then stops | mode: test-framework | expected: bats simulates the staged deletion in a temp repo; Stop hook exits 2 and the verbatim message names the offending path
- [P0] Subagent stages a rename (`git mv tests/unit/qa-X.test.ts tests/unit/X.qa.test.ts`) to dodge the `qa-*` prefix glob | mode: test-framework | expected: hook treats the rename (old-path or new-path outside surface) as a violation; exits 2; the FEAT-020 modality is caught, not only `git rm`
- [P0] Bulk out-of-surface rename of ~45 `qa-*.test.ts` files spanning unrelated tickets (FEAT-020 blast radius) | mode: test-framework | expected: hook blocks (exit 2) and enumerates every offending path; no "partial allow" where some out-of-surface files slip through
- [P1] Subagent makes an in-place content edit to an unrelated tracked file (not a delete/rename) | mode: test-framework | expected: hook also blocks content modifications outside the surface, not just rm/mv
- [P1] Allowed case — only the requirement doc is staged (`git add requirements/bugs/BUG-024-*.md` as part of the finalize bookkeeping commit) | mode: test-framework | expected: hook exits 0; legitimate BK-5 staging of `requirements/<type>/{ID}-*.md` is within the write surface and must not be blocked
- [P2] Out-of-surface path with an awkward name (leading dash, spaces, Unicode, nested dir) is staged | mode: test-framework | expected: hook still detects and blocks it; no misparse / no silent skip from word-splitting

### State transitions

- [P0] `preflight-checks.sh` exits non-zero (qa-* safety-net trips) | mode: test-framework | expected: `finalize.sh` exits 1, surfaces the pre-flight stderr verbatim, and performs zero recovery actions (no `git rm`/`git mv`/`git restore`/commit/push) — assert via bats that the merge dispatcher is never reached
- [P1] Forked fork hits a pre-flight block at runtime | mode: exploratory | expected: the subagent's final line is `failed | preflight blocked: <one-line reason>` and the index/work-tree is unchanged afterward
- [P1] Finalize re-invoked while the offending file is still present (repeat block) | mode: test-framework | expected: idempotent refusal — blocks again, never "fixes" the block, never violates NO-ROLLBACK
- [P2] Stop hook re-entry with `stop_hook_active: true` already set | mode: test-framework | expected: hook does not loop or double-block; clears its active marker and exits 0

### Environment

- [P1] Hook runs when the finalize active-marker is absent (skill not active) | mode: test-framework | expected: hook is a no-op (exit 0); it never blocks an unrelated session's Stop
- [P1] Hook runs outside a git repo / `git` returns an error | mode: test-framework | expected: hook fails safe with a clear error rather than allowing an unverified stop or crashing the session
- [P2] `jq` unavailable on PATH when the hook parses stdin JSON | mode: exploratory | expected: hook degrades gracefully (hand-parse fallback) or fails safe; it does not allow-stop by accident

### Dependency failure

- [P1] Diff guard must scope only the subagent's own changes, not pre-existing working-tree dirt that predates the run | mode: test-framework | expected: a baseline anchor is used (mirroring executing-qa's diff guard); pre-existing unrelated dirt does not trigger a false block, and run-introduced mutations do
- [P2] `managing-source-control` merge/view dispatcher unavailable during pre-flight | mode: exploratory | expected: pre-flight aborts cleanly and the fork returns `failed`; no destructive recovery is attempted to "work around" the missing dispatcher

### Cross-cutting (a11y, i18n, concurrency, permissions)

- [P0] The orchestrator finalize fork-prompt negative-constraint paragraph is present verbatim at all three fork sites in `step-execution-details.md` (feature step 5+N+4, chore step 7, bug step 7) | mode: test-framework | expected: a doc/grep assertion confirms the paragraph (forbidding `git rm`/`git mv`/`git restore --staged`/`rm` outside `requirements/<type>/{ID}-*.md` and instructing the `failed | preflight blocked:` return) appears at each site
- [P1] `finalizing-workflow/SKILL.md` gains a `## Write Surface` section AND a `hooks: Stop` frontmatter entry wiring `scripts/stop-hook.sh` | mode: test-framework | expected: assertion confirms both the section and the hook registration exist
- [P2] Permissions: hook respects the documented write surface as the single source of truth | mode: exploratory | expected: widening the surface requires an explicit SKILL.md edit; the hook does not silently honor an env-var or out-of-band override

## Non-applicable dimensions

- Accessibility (a11y): the change is SDLC tooling (Bash hooks, Markdown contracts) with no rendered UI surface, keyboard navigation, or screen-reader interaction to test.
- Internationalization (i18n): no user-facing localized strings, dates, numbers, or RTL layout; hook output is fixed-format diagnostic English consumed by the orchestrator.
- Injection (within Inputs): no SQL/XSS/network surface; the only "input" is git index/work-tree state, covered above by the awkward-filename scenario rather than classic injection vectors.
