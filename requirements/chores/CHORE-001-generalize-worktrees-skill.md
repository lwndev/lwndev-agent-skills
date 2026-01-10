# Chore: Review and Update Git Worktrees Skill

## Chore ID

`CHORE-001`

## Category

`refactoring`

## GitHub Issue

[#1](https://github.com/lwndev/lwndev-agent-skills/issues/1)

## Description

Review and update the `managing-git-worktrees` skill to:
1. Remove project-specific references (pullapod-cli) and make the skill reusable
2. Align with Agent Skills specification and best practices documentation

## Reference Documentation

Compare against these documents in `docs/`:
- `docs/agent-skills/agent-skills-specification.md` - Format specification
- `docs/anthropic/agent-skills-best-practices-20251229.md` - Authoring best practices
- `docs/anthropic/agent-skills-overview-20251229.md` - Architecture overview

## Affected Files

- `src/skills/managing-git-worktrees/SKILL.md`
- `src/skills/managing-git-worktrees/REFERENCE.md`
- `src/skills/managing-git-worktrees/SCENARIOS.md`
- `src/skills/managing-git-worktrees/SCRIPTS.md`

## Steps

### Step 1: Generalize Project References

- [ ] Replace all "pullapod-cli" and "pullapod" references with generic placeholders (e.g., `my-project`, `{project}`)
- [ ] Remove the "Project-Specific Notes (pullapod-cli)" section from SKILL.md or generalize it
- [ ] Update example paths to use generic project names
- [ ] Ensure all scenarios use consistent placeholder naming

### Step 2: Align with Specification

Per `agent-skills-specification.md`:
- [ ] Verify `name` field follows conventions (lowercase, hyphens, max 64 chars)
- [ ] Verify `description` field is under 1024 chars and includes what/when
- [ ] Consider reorganizing files into `references/` subdirectory per spec recommendation
- [ ] Ensure file references are one level deep from SKILL.md

### Step 3: Apply Best Practices

Per `agent-skills-best-practices-20251229.md`:
- [ ] Verify SKILL.md body is under 500 lines (current: ~236 lines - OK)
- [ ] Ensure description is written in third person
- [ ] Review for conciseness - remove explanations Claude doesn't need
- [ ] Add table of contents to longer reference files (>100 lines)
- [ ] Verify progressive disclosure pattern is used appropriately
- [ ] Consider if reference files are too long and should be split:
  - REFERENCE.md: ~425 lines
  - SCENARIOS.md: ~540 lines
  - SCRIPTS.md: ~573 lines

### Step 4: Validate and Test

- [ ] Verify the skill still reads coherently after changes
- [ ] Run `npm run build` to validate skill packaging
- [ ] Test skill invocation works correctly

## Acceptance Criteria

- [ ] No project-specific references remain (pullapod-cli/pullapod)
- [ ] Skill structure aligns with Agent Skills specification
- [ ] Best practices are applied where applicable
- [ ] Build passes successfully
- [ ] Skill remains functional and coherent

## Notes

### Current Issues

**Project-specific references:**
- SKILL.md lines 69-82, 94-113, 143-163, 213-226 contain pullapod-specific examples
- REFERENCE.md uses pullapod examples in commands throughout
- SCENARIOS.md has extensive pullapod-specific workflow examples
- SCRIPTS.md uses pullapod in script examples

**Structure considerations:**
- Current structure uses root-level .md files (REFERENCE.md, SCENARIOS.md, SCRIPTS.md)
- Spec recommends `references/` and `scripts/` subdirectories
- Evaluate whether restructuring adds value or introduces unnecessary churn

**Conciseness opportunities:**
- Best practices emphasize "Claude is already very smart" - only add context Claude doesn't have
- Some explanatory content may be redundant
- Consider which sections justify their token cost

### Placeholder Naming

Use consistent placeholder naming throughout:
- Project name: `my-project` or `acme-cli`
- Worktree paths: `../my-project-feature-x`, `../my-project-bugfix`
- Branch names: `feature/search`, `fix/metadata` (generic)
