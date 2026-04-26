# Approval-Marker Grammar (BUG-014)

Every confirmation gate is enforced by a Claude Code hook that requires a fresh `.sdlc/approvals/.approval-<gate>-<ID>` marker. Markers are written by Hook A (`record-approval.sh`) only on real `UserPromptSubmit` events — auto-mode self-prompts produce no marker. To approve a gate, type one of the canonical shapes below verbatim. Case-insensitive on the keyword; the workflow ID is uppercase by convention.

## Canonical shapes

| Shape | Marker written | Use at |
|-------|----------------|--------|
| `approve plan-approval <ID>` | `.approval-plan-approval-<ID>` | feature-chain plan-approval pause (step 4) |
| `approve pr-review <ID>` | `.approval-pr-review-<ID>` | PR-review pause (any chain) |
| `approve findings-decision <ID>` | `.approval-findings-decision-<ID>` | reviewing-requirements findings-decision gate |
| `approve review-findings <ID>` | `.approval-review-findings-<ID>` | reviewing-requirements errors-present pause |
| `proceed <ID>` / `yes <ID>` | resolved against active gate, then pauseReason (see fallback below) | shorthand at any pause / gate |
| `merge <ID>` | `.approval-merge-approval-<ID>` | required for `gh pr merge` and the `finalizing-workflow` fork |
| `pause <ID>` | `.approval-pause-<ID>` | explicit decline (future use) |

## Examples — copy-paste verbatim

```
approve plan-approval BUG-014
approve pr-review FEAT-099
approve findings-decision CHORE-042
proceed BUG-014
merge BUG-014
```

## `proceed` / `yes` fallback caveat

`proceed <ID>` and `yes <ID>` resolve the marker name from the workflow's active gate (preferred) or `pauseReason`. When **no state file exists**, `record-approval.sh` writes `.approval-proceed-<ID>` as a generic audit record. Hook B looks for `.approval-<pauseReason>-<ID>` and Hook C looks for `.approval-merge-approval-<active-ID>` — the generic `.approval-proceed-<ID>` marker satisfies neither. When in doubt, type the explicit `approve <gate-type> <ID>` or `merge <ID>` shape so the marker name is unambiguous.

## Deny-message contract

Unknown shapes are silently ignored. If a hook denies a tool call, the deny message names the exact shape required (e.g. `User must type: approve plan-approval BUG-014`). Hook A is best-effort marker writing; Hooks B and C are the fail-secure guards.
