# Changelog

## [1.1.0] - 2026-03-28

### Bug Fixes

- **core:** fix a bug (+2 more)
- **security:** bump brace-expansion to patch GHSA-f886-m6hf-6m8v
- **runtime-error:** address review suggestions for BUG-002 (+1 more)
- **logic-error:** prevent excessive echo permission prompts in documenting-qa
- **release:** remove uncategorized noise and trailing blank line from CHANGELOG (+1 more)
- **review:** address code review findings from PR #43
- **marketplace:** bump marketplace manifest version to 1.1.0
- **deps:** upgrade lodash to 4.17.23 for CVE-2025-13465
- **executing-chores:** enforce Closes #N in PR body when issue exists

### Features

- **init:** initial commit (+2 more)
- **review:** bump plugin version to 1.2.0 and complete Phase 3 verification (+2 more)
- **release:** add releasing-plugins skill and update plan status (Phase 4) (+3 more)
- **qa:** address PR review feedback (+3 more)
- add allowed-tools declarations to all 7 skills (FEAT-003) (#20)
- add executing-bug-fixes skill (#13)
- add documenting-bugs skill (#10)

### Other

- **test-plugin:** v1.0.1
- **lwndev-sdlc:** v1.3.0
- Add chore document for managing-git-worktrees skill review
- Add CI status badge to README
- Add npm audit to CI workflow
- Add tests and npm audit to pre-commit hook
- Add pre-commit hook with husky and lint-staged
- Add GitHub Actions CI workflow
- Fix project description to remove versioning claim
- Add project documentation, testing, and tooling
- Add CLI scripts for ai-skills-manager workflow
- Updating structure, adding asm dependency, adding gitignore
- Initial Commit

### Chores

- **refactoring:** add finalizing-workflow skill (#72) (+21 more)
- **documentation:** add PR link to CHORE-020 (+22 more)
- **cleanup:** commit package-lock.json from CHORE-019 (+2 more)
- **configuration:** add stop hook and release branch enforcement to releasing-plugins skill (CHORE-016)
- upgrade ai-skills-manager to 1.8.0 and update docs
- refine gitignore patterns
- update package-lock.json peer dependency markers

### Refactoring

- replace duplicated docs with shared ai-skills-docs submodule
- migrate scripts to ai-skills-manager v1.6.0 programmatic API

### Documentation

- fix skill count and check acceptance criteria
- add implementation notes to CHORE-007
- update CHORE-007 completion status
- update reference docs and remove date suffixes from filenames
- **implementation:** add implementation plan for documenting-bugs skill
- **requirements:** add automated test specs for documenting-bugs and executing-bug-fixes
- update README to reflect programmatic API usage
- improve implementing-plan-phases skill invocation triggers
- add filename convention to creating-implementation-plans skill
- fix ai-skills-manager repo URL in README
- update CLAUDE.md as reference implementation for ai-skills-manager
- update README as reference implementation for ai-skills-manager
- update Available Skills heading in README


