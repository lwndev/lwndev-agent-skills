# GitHub PR Body Template

Reference for the PR body template used by `scripts/create-pr.sh` on the GitHub path.

## Template Location

The authoritative template lives at:

```
plugins/lwndev-sdlc/scripts/assets/pr-body.tmpl
```

The skill's `create-pr.sh` reads this file verbatim, performs placeholder substitution in bash (not `envsubst`), and passes the result to `gh pr create --body`.

## Template Contents

```
## Summary

${TYPE} ${ID}: ${SUMMARY}

${CLOSES_LINE}

## Test plan

- [ ] Tests updated or added as appropriate
- [ ] `npm run validate` passes
- [ ] `npm test` passes

${GENERATED_WITH}
```

## Placeholder Semantics

Substitution is done in-process via bash parameter expansion (`${body//\$\{VAR\}/$value}`). No external dependency. `&` in `$value` stays literal because the script disables Bash 5.2's `patsub_replacement` shopt at entry.

| Placeholder | Value source | Example |
|-------------|--------------|---------|
| `${TYPE}` | First positional arg | `feat`, `chore`, `fix` |
| `${ID}` | Second positional arg | `FEAT-033` |
| `${SUMMARY}` | Third positional arg | `Add managing-source-control skill` |
| `${CLOSES_LINE}` | `Closes ${closes}` when `--closes` set; empty string otherwise | `Closes #120` or `` |
| `${GENERATED_WITH}` | Constant trailer | `🤖 Generated with [Claude Code](https://claude.com/claude-code)` |

When `--closes` is omitted, `${CLOSES_LINE}` collapses to an empty string and the surrounding blank line in the template renders as a stray blank — this is intentional and visually negligible in rendered Markdown.

## `Closes #N` Auto-Close Syntax

GitHub recognizes the following keywords in a PR body and automatically closes the linked issue when the PR is merged into the default branch:

- `close`, `closes`, `closed`
- `fix`, `fixes`, `fixed`
- `resolve`, `resolves`, `resolved`

Followed by `#<number>` (same-repo) or `owner/repo#<number>` (cross-repo).

`create-pr.sh --closes "#120"` renders as `Closes #120` in the body, which triggers GitHub's auto-close on merge.

**Important**: the keyword must appear in the PR **body** (not just the title) to trigger auto-close. Putting `Closes #N` only in the title is a no-op for closure semantics.

## Multi-Issue Closure

The current `--closes` flag accepts a single ref. To close multiple issues, edit the PR body after creation and add additional `Closes #M` lines manually, or extend `create-pr.sh` to accept comma-separated refs (out of scope for FEAT-033).

## Re-rendering After Edit

`gh pr edit --body-file <path>` re-applies a body verbatim. To re-render from the template, dump the body to a file, edit placeholders, then `gh pr edit --body-file`.

## See Also

- [pr-templates-azdo.md](pr-templates-azdo.md) — Azure DevOps flavor with `AB#<id>` work-item linkage.
- [commit-conventions.md](commit-conventions.md) — Title format (`feat(<ID>): <summary>`) used by `${TYPE}(${ID}): ${SUMMARY}` in the body.
