# Pull Request Template for Feature Implementations

Copy and customize this template when creating a PR after all implementation plan phases are complete.

---

## Template

```markdown
## Feature
[FEAT-XXX](requirements/features/FEAT-XXX-description.md)

## Implementation Plan
[FEAT-XXX Implementation Plan](requirements/implementation/FEAT-XXX-description.md)

## Summary
[Brief description of the feature - 1-2 sentences]

## Phases Completed

| Phase | Name | Status |
|-------|------|--------|
| 1 | [Phase 1 name] | ✅ Complete |
| 2 | [Phase 2 name] | ✅ Complete |

## Changes
- [Change 1]
- [Change 2]
- [Change 3]

## Testing
- [ ] All phase deliverables verified
- [ ] Tests pass
- [ ] Build succeeds
- [ ] Linting passes (if applicable)

## Related
- Closes #N <!-- REQUIRED if implementation plan has a GitHub Issue link - enables auto-close on merge -->

---
🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

**Important:** If the implementation plan links to a GitHub issue, you MUST include `Closes #N` in the Related section. This auto-closes the issue when the PR is merged. Without it, the issue must be closed manually.

---

## Filled Example

```markdown
## Feature
[FEAT-002](requirements/features/FEAT-002-validate-skill-command.md)

## Implementation Plan
[FEAT-002 Implementation Plan](requirements/implementation/FEAT-002-validate-skill-command.md)

## Summary
Adds a validation engine for skills with file-exists and required-fields validators, orchestrated through a validate command.

## Phases Completed

| Phase | Name | Status |
|-------|------|--------|
| 1 | YAML Parsing Infrastructure | ✅ Complete |
| 2 | Validation Engine | ✅ Complete |
| 3 | Enhanced Validation Rules | ✅ Complete |
| 4 | Command Integration & Output | ✅ Complete |

## Changes
- Added file-exists and required-fields validators
- Created validation orchestrator
- Integrated validate command with CLI
- Added comprehensive test suite with 95% coverage

## Testing
- [x] All phase deliverables verified
- [x] Tests pass
- [x] Build succeeds
- [x] Linting passes

## Related
- Closes #2

---
🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

---

## Usage with gh CLI

```bash
gh pr create --title "feat(FEAT-XXX): feature summary" --body "## Feature
[FEAT-XXX](requirements/features/FEAT-XXX-description.md)

## Implementation Plan
[FEAT-XXX Implementation Plan](requirements/implementation/FEAT-XXX-description.md)

## Summary
Brief description of the feature.

## Phases Completed

| Phase | Name | Status |
|-------|------|--------|
| 1 | Phase 1 name | ✅ Complete |
| 2 | Phase 2 name | ✅ Complete |

## Changes
- Change 1
- Change 2

## Testing
- [x] All phase deliverables verified
- [x] Tests pass
- [x] Build succeeds
- [x] Linting passes

## Related
- Closes #N

---
🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

---

## Section Guidelines

### Feature Link
- Always link to the feature requirements document
- Use relative path from repository root

### Implementation Plan Link
- Always link to the implementation plan document
- Provides reviewers with full phase-by-phase context

### Summary
- Keep to 1-2 sentences
- Focus on the outcome, not the process
- Be specific about what the feature does

### Phases Completed
- List all phases from the implementation plan
- All phases should show ✅ Complete (PR is only created after all phases are done)
- Use phase names from the plan document

### Changes
- List concrete changes made across all phases
- Group related changes
- Use consistent formatting (bullets)
- Include numbers when relevant ("Added 12 validators")

### Testing
- Include phase deliverable verification
- Include standard checks: tests pass, build succeeds
- Check off items that pass
- Add custom checks if the feature requires specific verification

### Related
- **Use `Closes #N` to auto-close linked issue on merge** — REQUIRED if implementation plan has a GitHub Issue link
- Use "Refs #N" to link without closing
- List any other related PRs or issues
