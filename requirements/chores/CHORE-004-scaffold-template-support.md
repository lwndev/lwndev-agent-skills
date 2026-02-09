# Chore: Add Scaffold Template Support

## Chore ID

`CHORE-004`

## Category

`refactoring`

## Description

Expose the `ai-skills-manager` v1.7.0 scaffold template options in the interactive `scaffold.ts` workflow. The current scaffold only collects `name`, `description`, and `allowedTools` — it should also offer template type selection, the `minimal` flag, and key template options like `memory`, `model`, and `argumentHint`.

## Affected Files

- `scripts/scaffold.ts`
- `tests/scaffold.test.ts`

## Acceptance Criteria

- [ ] Interactive prompt offers template type selection (`basic`, `forked`, `with-hooks`, `internal`, `agent`) with `basic` as default
- [ ] Interactive prompt offers a `minimal` toggle (default: no) to generate concise SKILL.md without guidance comments
- [ ] Interactive prompt offers memory scope selection (`user`, `project`, `local`) when relevant
- [ ] Interactive prompt offers model selection when the `agent` template type is chosen
- [ ] Interactive prompt offers `argumentHint` input (optional, max 100 chars)
- [ ] All new options are passed to the `scaffold()` API via the `template` parameter
- [ ] Existing tests continue to pass
- [ ] New tests cover template option passthrough
- [ ] `npm run build` and `npm run lint` pass

## Completion

**Status:** `Completed`

**Completed:** 2026-02-08

**Pull Request:** https://github.com/lwndev/lwndev-agent-skills/pull/6

## Notes

- The `ScaffoldTemplateOptions` interface supports additional fields (`context`, `agent`, `userInvocable`, `includeHooks`) that could be exposed conditionally based on template type selection.
- Consider grouping prompts so that basic scaffolds remain fast (name + description + template type) while advanced options only appear when a non-basic template is selected.
- The `forked` template sets `context: 'fork'` and `agent` template sets the `agent` field — these could be handled automatically by template selection rather than requiring separate prompts.
