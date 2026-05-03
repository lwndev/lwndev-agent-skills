---
id: CHORE-037
version: 2
timestamp: 2026-05-03T13:14:30Z
persona: qa
---

## User Summary

Move the heavyweight test gate (`npm test`, `npm audit`, `npm run validate`) from `.husky/pre-commit` into a new `.husky/pre-push` hook. The `pre-commit` hook is reduced to fast checks (`npx lint-staged`, `npm run lint`, `npm run format:check`) so doc-only commits, marker commits, and WIP commits no longer pay the multi-minute test tax. CI remains the authoritative gate; the README contributor docs are updated to document the new tier split.

## Capability Report

```json
{
  "id": "CHORE-037",
  "mode": "test-framework",
  "framework": "vitest",
  "packageManager": "npm",
  "testCommand": "npm test",
  "language": "typescript"
}
```

(Note: hook-script behavior is naturally exercised under Bats — the project's `tests/bats/` runner is part of `npm test` via `npm run test:bats`. Scenarios that probe the hook contents themselves are tagged `mode: test-framework` against Bats; scenarios that depend on a real `git commit` / `git push` round-trip with side effects are tagged `mode: exploratory`.)

## Scenarios (by dimension)

### Inputs

- [P0] `.husky/pre-commit` does NOT contain any of `npm test`, `npm audit`, `npm run validate` after the change | mode: test-framework | expected: Bats test that greps the file for forbidden tokens; assertion fails if any heavy command appears
- [P0] `.husky/pre-push` exists, is executable, and contains all three of `npm test`, `npm audit --audit-level=high`, `npm run validate` | mode: test-framework | expected: Bats test that asserts file presence, `[ -x .husky/pre-push ]`, and greps for each command; fails if any is missing
- [P0] `.husky/pre-commit` retains `npx lint-staged`, `npm run lint`, and `npm run format:check` invocations | mode: test-framework | expected: Bats test greps for each command; fails if any was dropped during the rewrite
- [P1] `.husky/pre-push` runs the three heavy commands in a deterministic order, with each failure short-circuiting later commands | mode: test-framework | expected: Bats test sources the script under a stub `PATH` and asserts execution order via call log; if `npm test` fails, neither `npm audit` nor `npm run validate` runs
- [P1] A staged change with a deliberate Prettier violation triggers a pre-commit failure (regression check on the surviving fast-path) | mode: exploratory | expected: manual `git commit` against a tweaked file fails on `format:check`; commit aborted
- [P1] A push of a branch carrying a deliberately failing Vitest test is blocked by pre-push (AC #4) | mode: exploratory | expected: manual `git push` exits non-zero; remote ref unchanged on `origin`
- [P1] A push of a branch carrying a deliberately failing Bats test is blocked by pre-push (Bats is part of `npm test`) | mode: exploratory | expected: manual `git push` exits non-zero; tests/bats failure surfaces in hook output
- [P1] A doc-only commit touching only `requirements/**/*.md` completes in under 5 seconds locally (AC #3) | mode: exploratory | expected: `time git commit -m "docs: …"` reports total wall time well below 5s on the maintainer's machine; record reading and attach to PR
- [P1] `git commit --no-verify` still bypasses pre-commit (escape hatch preserved) | mode: exploratory | expected: amend or commit with `--no-verify` succeeds without running lint-staged
- [P2] `git push --no-verify` bypasses pre-push (escape hatch preserved and documented) | mode: exploratory | expected: `git push --no-verify` skips the hook; remote ref updates without running tests
- [P2] Pushing a tag (`git push origin <tag>`) — does pre-push fire and gate? Husky's default behavior runs the hook for tag refs too; this can surprise on release tagging | mode: exploratory | expected: confirm whether `git push origin v1.2.3` triggers pre-push; document outcome in README if the hook gates tag pushes
- [P2] `git push --delete origin <branch>` — does pre-push fire on a deletion? | mode: exploratory | expected: confirm whether the hook runs on a delete; document the answer

### State transitions

- [P0] A pre-push hook killed mid-run (`Ctrl-C` during `npm test`) leaves the remote ref unchanged | mode: exploratory | expected: kill during long test; verify `git ls-remote origin <branch>` matches pre-push state and the local `git push` reports the abort
- [P1] Two simultaneous `git commit` invocations from separate terminals do not corrupt the lint-staged stash or leave residue under `.git/index.lock` | mode: exploratory | expected: race two commits; both either succeed or fail cleanly with the standard `index.lock` busy message — no partial application
- [P1] `git commit --amend` re-fires pre-commit and runs the fast checks against the amended snapshot | mode: exploratory | expected: amend with a Prettier violation introduced; pre-commit fails, amend aborted
- [P1] `git rebase --autostash --interactive` with multiple `pick` commits fires pre-commit per resulting commit (no skip) | mode: exploratory | expected: rebase a 3-commit branch; pre-commit runs three times; any one failure halts rebase
- [P2] A failed pre-push leaves no half-pushed state on remote AND does not advance the local tracking ref | mode: exploratory | expected: introduce a guaranteed pre-push failure; `git rev-parse @{u}` is unchanged; `gh pr view` shows no new commits
- [P2] After a pre-push failure, fixing the issue and re-pushing succeeds without a stale lock or cache state | mode: exploratory | expected: fix-then-push round-trip works without `git gc` or `rm .git/*.lock`

### Environment

- [P0] Fresh clone + `npm install` correctly installs husky and registers both hooks (`prepare` script wired) | mode: exploratory | expected: clone into a temp dir, run `npm install`, verify `.husky/pre-commit` and `.husky/pre-push` are present, executable, and `git config core.hooksPath` points at `.husky`
- [P1] On a machine without GNU parallel installed, `npm test` (and therefore pre-push) still completes — the bats command must not silently skip | mode: exploratory | expected: temporarily remove `parallel` from PATH and run `npm test`; either Bats falls back to serial OR the script fails loudly with a clear "GNU parallel required" message; silent skipping is a bug
- [P1] Pre-commit hook works on a Linux contributor machine (CI-like environment) — bash shebang + executable bit are honored | mode: exploratory | expected: run inside the CI image (or a Linux VM) and verify `git commit` invokes the hook
- [P2] Pre-push hook works under Git for Windows / WSL — line-ending and shebang differences do not break execution | mode: exploratory | expected: confirm on a Windows or WSL host that `.husky/pre-push` runs via `bash`; document the outcome
- [P2] Pre-commit hook runs even when invoked from an IDE Git integration (VS Code, JetBrains) rather than the terminal | mode: exploratory | expected: commit via the IDE; verify the same fast-path runs and the IDE surfaces failure
- [P2] Running in a worktree (`git worktree`) — hooks fire correctly because `core.hooksPath` is repo-local | mode: exploratory | expected: create a worktree, commit, verify the same fast-path runs

### Dependency failure

- [P0] `npm audit` against an offline registry does not silently pass — pre-push must fail loudly when the registry is unreachable | mode: exploratory | expected: disconnect network, run `npm audit --audit-level=high`; expect non-zero exit OR a clear message; silent zero-exit is a bug
- [P0] `npm audit --audit-level=high` and CI's bare `npm audit` disagree on moderate-severity advisories: a moderate vuln passes pre-push but fails CI (W2 from requirements review) — does the team accept this delta or align? | mode: exploratory | expected: introduce a synthetic moderate-severity dep (or use a known advisory in a fixture); confirm pre-push passes while CI fails; record decision in README or in a follow-up
- [P1] `npm test` failure surfaces a useful error in the pre-push output (not buffered until end) so the contributor can iterate | mode: exploratory | expected: observe streaming output during a real failure; expect failing test name to be visible before the run ends
- [P1] `npm run validate` failure (e.g., a malformed plugin manifest) blocks pre-push with a clear plugin-validation error | mode: exploratory | expected: introduce a malformed `plugins/*/.claude-plugin/plugin.json`; pre-push exits with the validator's stderr surfaced
- [P2] Slow network during `npm audit` — pre-push completes but takes notably longer; no false-positive timeout failure | mode: exploratory | expected: throttle network; confirm `npm audit` completes; pre-push exits 0 with a slow run

### Cross-cutting (a11y, i18n, concurrency, permissions)

- [P0] Marker-commit polling-spiral regression check: a commit that updates only `requirements/implementation/CHORE-037-*.md` (or any single doc file) does NOT trigger the orchestrator stop-hook polling spiral the issue cites | mode: exploratory | expected: stage and commit a marker-only change while an orchestrated workflow is in-progress; observe stop-hook does not loop because the commit completes in < 5s; record stop-hook firing count
- [P1] README "Development" section is updated and accurately describes the new tier split (pre-commit scope, pre-push scope, CI authoritative) | mode: exploratory | expected: read the updated README; verify the prose names the right files and commands; verify it warns contributors that local commits can be locally broken between pushes (the documented tradeoff)
- [P1] Permissions: `.husky/pre-push` is committed with executable bit set so a fresh clone receives it correctly | mode: test-framework | expected: Bats test invokes `git ls-files --stage .husky/pre-push` and asserts mode bits include `100755`; or invokes `[ -x .husky/pre-push ]` after clone-equivalent setup
- [P2] Concurrency: a contributor running a long-running pre-push in one shell while attempting another `git commit` (fast pre-commit) in a second shell does not deadlock or corrupt state | mode: exploratory | expected: race the two; both complete; no `index.lock` residue
- [P2] Determinism: re-running `npm install` does not regenerate or overwrite `.husky/pre-commit` / `.husky/pre-push` with stale husky-template defaults | mode: exploratory | expected: after the change, run `npm install` again; `git status` shows no modifications under `.husky/`

## Non-applicable dimensions

- accessibility (a11y): the change touches only command-line git hooks and a README section; there is no UI surface, no rendered control, and no user-input control flow that screen readers or keyboard navigation interact with
- internationalization (i18n): hook scripts emit short ASCII status text from `npm` / `git` / lint-staged, all of which are already English-only tooling output; the chore introduces no new locale-sensitive strings, dates, numbers, or RTL text and the README addition is in the same English contributor-doc style as the rest of the file
