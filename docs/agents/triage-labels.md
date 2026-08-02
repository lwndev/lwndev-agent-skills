# Triage Labels

The skills speak in terms of five canonical triage roles. This file maps those roles to the actual label strings used in this repo's issue tracker.

| Label in mattpocock/skills | Label in our tracker | Meaning                                  |
| -------------------------- | -------------------- | ---------------------------------------- |
| `needs-triage`             | `needs-triage`       | Maintainer needs to evaluate this issue  |
| `needs-info`               | `needs-info`         | Waiting on reporter for more information |
| `ready-for-agent`          | `ready-for-agent`    | Fully specified, ready for an AFK agent  |
| `ready-for-human`          | `ready-for-human`    | Requires human implementation            |
| `wontfix`                  | `wontfix`            | Will not be actioned                     |

When a skill mentions a role (e.g. "apply the AFK-ready triage label"), use the corresponding label string from this table.

Edit the right-hand column to match whatever vocabulary you actually use.

## Repo state

All five labels exist. `wontfix` ships with GitHub's default set; the other four were created on 2026-08-01 with the commands below, kept for reference:

```bash
gh label create needs-triage    --color "d876e3" --description "Maintainer needs to evaluate this issue"
gh label create needs-info      --color "fbca04" --description "Waiting on reporter for more information"
gh label create ready-for-agent --color "0e8a16" --description "Fully specified, ready for an AFK agent"
gh label create ready-for-human --color "1d76db" --description "Requires human implementation"
```

Re-running `gh label create` on an existing label fails. Use `gh label edit <name>` to change a colour or description.

These are distinct from the repo's existing workflow labels (`bug`, `enhancement`, `qa-loop-lifecycle`, `wayfinder:*`) — no collision.
