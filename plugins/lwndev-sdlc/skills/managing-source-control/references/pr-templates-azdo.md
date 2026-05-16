# Azure DevOps PR Body Template

Reference for the PR body template used by `scripts/create-pr.sh` on the Azure DevOps path.

> **Phase 3 status**: the AzDO path of `create-pr.sh` is a stub that emits `[warn] Azure DevOps PR creation not yet implemented.` and exits 0. Phase 4 implements the full `az repos pr create` invocation against this template.

## Template Structure

The AzDO body mirrors the GitHub template structure for visual consistency, with placeholder substitution rules identical to the GitHub flavor:

```
## Summary

${TYPE} ${ID}: ${SUMMARY}

${WORK_ITEM_LINE}

## Test plan

- [ ] Tests updated or added as appropriate
- [ ] `npm run validate` passes
- [ ] `npm test` passes

${GENERATED_WITH}
```

The only semantic difference is `${WORK_ITEM_LINE}` (replaces GitHub's `${CLOSES_LINE}`), which carries the AzDO work-item linkage token.

## Work-Item Linkage Tokens

Azure DevOps supports two distinct token forms depending on the issue tracker backing the project:

### `AB#<id>` — Azure Boards work items

`AB#<id>` (where `<id>` is the numeric Azure Boards work-item ID) links the PR to a work item. Azure DevOps auto-transitions the work item to **Resolved** when the PR is completed (merged), subject to the project's process template configuration.

Example: `AB#1234` in the PR body links Work Item #1234.

### Jira issue keys — when the project is linked to Jira

If the AzDO project is integrated with Jira via the **Azure DevOps for Jira** marketplace app, mention the Jira issue key (`PROJ-123`) in the PR body or commit messages. The integration smart-commits the linkage; closure semantics depend on the Jira workflow's smart-commit rules (typically `#close` or `#resolve` as a separate token).

## `--issue-ref` Flag Behavior

`create-pr.sh` accepts a backend-agnostic `--issue-ref <ref>` flag. The dispatcher selects the auto-close token format based on the **backend detected from `origin`**, not the ref string:

| `--issue-ref` value | Detected backend | Rendered as |
|---------------------|------------------|-------------|
| `#120` | `github` | `Closes #120` |
| `AB#1234` | `azdo` | `AB#1234` (no auto-close keyword — AzDO links via `AB#` token alone) |
| `PROJ-123` | `azdo` (with Jira link) | `PROJ-123` (Jira smart-commit recognition) |

`--closes <ref>` is preserved for GitHub backward compatibility and is treated as an alias for `--issue-ref <ref>` when the backend is GitHub. On the AzDO path, `--closes` is accepted but `--issue-ref` is the preferred flag.

## Merge-Strategy Asymmetry

Azure DevOps PR completion (`az repos pr update --status completed`) honors the **branch policy's default merge strategy** (squash / no-FF / rebase) configured on the target branch. The `gh pr merge --merge` GitHub equivalent forces a merge commit unconditionally.

In Phase 4 the AzDO dispatcher passes `--squash false` to opt out of squash for partial parity, but the final merge type is governed by the branch policy. Operators who need byte-identical merge behavior across backends must configure the AzDO branch policy to match GitHub's behavior — this is out of scope for the dispatcher.

## See Also

- [pr-templates-github.md](pr-templates-github.md) — GitHub flavor with `Closes #N` auto-close.
- [commit-conventions.md](commit-conventions.md) — Title format (`feat(<ID>): <summary>`).
- MS docs: [Link work items to GitHub/AzDO PRs](https://learn.microsoft.com/en-us/azure/devops/boards/github/link-to-from-github)
