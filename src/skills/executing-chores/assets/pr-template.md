# Pull Request Template for Chores

Copy and customize this template when creating a chore PR.

---

## Template

```markdown
## Chore
[CHORE-XXX](requirements/chores/CHORE-XXX-description.md)

## Summary
[Brief description of what this chore accomplishes - 1-2 sentences]

## Changes
- [Change 1]
- [Change 2]
- [Change 3]

## Testing
- [ ] Tests pass
- [ ] Build succeeds
- [ ] Linting passes (if applicable)

## Related
- Closes #N <!-- REQUIRED if chore document has a GitHub Issue link - enables auto-close on merge -->

---
🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

**Important:** If the chore document links to a GitHub issue, you MUST include `Closes #N` in the Related section. This auto-closes the issue when the PR is merged. Without it, the issue must be closed manually.

---

## Filled Example

```markdown
## Chore
[CHORE-003](requirements/chores/CHORE-003-cleanup-unused-imports.md)

## Summary
Removes unused imports across the src/ directory to reduce bundle size and improve code clarity.

## Changes
- Removed 15 unused imports from src/commands/
- Removed 8 unused imports from src/utils/
- Fixed import ordering per eslint rules

## Testing
- [x] Tests pass
- [x] Build succeeds
- [x] Linting passes

## Related
- Closes #18

---
🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

---

## Usage with gh CLI

```bash
gh pr create --title "chore(cleanup): remove unused imports" --body "## Chore
[CHORE-003](requirements/chores/CHORE-003-cleanup-unused-imports.md)

## Summary
Removes unused imports across the src/ directory to reduce bundle size and improve code clarity.

## Changes
- Removed 15 unused imports from src/commands/
- Removed 8 unused imports from src/utils/
- Fixed import ordering per eslint rules

## Testing
- [x] Tests pass
- [x] Build succeeds
- [x] Linting passes

## Related
- Closes #18

---
🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

---

## Section Guidelines

### Chore Link
- Always link to the chore document
- Use relative path from repository root

### Summary
- Keep to 1-2 sentences
- Focus on the outcome, not the process
- Be specific about what improved

### Changes
- List concrete changes made
- Group related changes
- Use consistent formatting (bullets)
- Include numbers when relevant ("Removed 15 unused imports")

### Testing
- Check off items that pass
- Leave unchecked with explanation if something doesn't apply
- Add custom checks if the chore requires specific verification

### Related
- **Use "Closes #N" to auto-close linked issue on merge** - REQUIRED if chore document has a GitHub Issue link
- Use "Refs #N" to link without closing
- List any other related PRs or issues
