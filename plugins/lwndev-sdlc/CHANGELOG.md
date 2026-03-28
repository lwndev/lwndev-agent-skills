# Changelog

## [1.4.0] - 2026-03-28

### Features

- **FEAT-008:** add argument-hint support to skills (#86)
- **reviewing-requirements:** add code-review reconciliation mode (#82)

### Bug Fixes

- **QA verification:** rewrite from coverage auditor to direct entry verification, restore Errors count in output format
- **documenting-qa:** prevent excessive echo permission prompts; add retry and resilience guidance
- **security:** bump brace-expansion to patch GHSA-f886-m6hf-6m8v

### Chores

- Add finalizing-workflow skill for end-of-chain wrap-up
- Migrate test runner from Jest to Vitest
- Update workflow chains across all skills with reconciliation step labels
- Align QA templates with execution lifecycle
- Add acceptance criteria checkoff to execution skills
- Add commit-and-push step to implementing-plan-phases
- Add PR creation to implementing-plan-phases
- Automate release branch creation in release script
- Add stop hook and release branch enforcement to releasing-plugins
- Add changelog noise filtering and scope collapsing
- Remove unneeded .gitkeep files

[1.4.0]: https://github.com/lwndev/lwndev-marketplace/compare/lwndev-sdlc@1.3.0...lwndev-sdlc@1.4.0

## [1.3.0] - 2026-03-21

### Chores

- **documentation:** address review feedback for PR #47
- **documentation:** mark CHORE-015 as completed
- **documentation:** correct QA skill placement in workflow chains (CHORE-015)
- **documentation:** add reviewing-requirements to plugin README
- **documentation:** mark CHORE-014 as completed
- **documentation:** update README.md and CLAUDE.md for new skills (CHORE-014)
- **documentation:** update CHORE-013 status to Completed
- **refactoring:** relocate QA output paths from test/ to qa/
- **refactoring:** address PR review feedback
- **refactoring:** update CHORE-012 status to completed
- **refactoring:** flatten plugin structure, eliminate src/ and dist/
- **refactoring:** address PR review feedback
- **refactoring:** update CHORE-011 status to completed
- **refactoring:** restructure repo for multi-plugin marketplace
- **refactoring:** update repo references to lwndev-marketplace
- **refactoring:** address code review feedback
- **refactoring:** update CHORE-010 status to completed
- **refactoring:** refactor skills into Claude Code plugin structure
- **documentation:** update CHORE-009 status to completed
- **documentation:** add extend-claude-with-skills reference doc
- upgrade ai-skills-manager to 1.8.0 and update docs
- **cleanup:** remove managing-git-worktrees skill
- **refactoring:** use detailed validation in build script (#7)
- **refactoring:** expose scaffold template options (#6)
- **documentation:** add completion tracking to chore workflow (#4)
- refine gitignore patterns
- update package-lock.json peer dependency markers
- **refactoring:** align skill directory structure with spec (#3)
- **refactoring:** generalize managing-git-worktrees skill (#2)

### Bug Fixes

- **review:** address code review findings from PR #43
- **release:** address code review findings from PR #40
- **marketplace:** bump marketplace manifest version to 1.1.0
- **deps:** upgrade lodash to 4.17.23 for CVE-2025-13465
- **executing-chores:** enforce Closes #N in PR body when issue exists

### Features

- **review:** bump plugin version to 1.2.0 and complete Phase 3 verification
- **review:** add review recommendation to documenting skills (Phase 2)
- **review:** add reviewing-requirements skill and requirements (Phase 1)
- **release:** add releasing-plugins skill and update plan status (Phase 4)
- **release:** add post-merge tagging script (Phase 3)
- **release:** add release script for plugin version bumping (Phase 2)
- **release:** add shared infrastructure for plugin release workflow (Phase 1)
- **qa:** address PR review feedback
- **qa:** add executing-qa skill with multi-phase stop hook (FEAT-004 Phase 3)
- **qa:** add documenting-qa skill with stop hook and test plan template (FEAT-004 Phase 2)
- **qa:** add qa-verifier subagent and plugin infrastructure (FEAT-004 Phase 1)
- add allowed-tools declarations to all 7 skills (FEAT-003) (#20)
- add executing-bug-fixes skill (#13)
- add documenting-bugs skill (#10)

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
