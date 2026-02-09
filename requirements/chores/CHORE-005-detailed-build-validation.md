# Chore: Use Detailed Validation in Build

## Chore ID

`CHORE-005`

## Category

`refactoring`

## Description

Switch the build script from simple `validate()` to `validate(path, { detailed: true })` to surface per-check results during builds. This gives skill authors clear feedback on which specific validation checks passed or failed, especially useful now that v1.7.0 validates new frontmatter fields (memory, model, hooks, agent, etc.).

## Affected Files

- `scripts/build.ts`
- `tests/build.test.ts`

## Acceptance Criteria

- [ ] Build uses `validate(path, { detailed: true })` instead of `validate(path)`
- [ ] Successful builds display a summary of passed checks (e.g., `22/22 checks passed`)
- [ ] Failed builds display which specific checks failed with their error messages
- [ ] Warnings from validation are displayed as warnings (non-blocking)
- [ ] Existing tests continue to pass
- [ ] New tests cover detailed validation output formatting
- [ ] `npm run build` and `npm run lint` pass

## Completion

**Status:** `Pending`

**Completed:** YYYY-MM-DD

**Pull Request:** N/A

## Notes

- The `DetailedValidateResult` returns a `checks` record keyed by `ValidationCheckName` (23 check types). Each entry has `{ passed: boolean, error?: string }`.
- Consider a verbose/quiet mode: default output could show just the summary count, with a `--verbose` flag to list every individual check result.
- The `warnings` field in `DetailedValidateResult` is optional — handle the case where it's undefined.
