# QA Loop Reference (FEAT-032 FR-7, FR-8)

The orchestrator's QA step is verdict-gated. After `executing-qa` returns, the orchestrator runs `qa-dispatch.sh` and branches on the dispatch token before calling `advance`.

## FR-7 Dispatch Table

| Row | Condition | Dispatch token | Action |
|-----|-----------|----------------|--------|
| 1 | Initial PASS (`qaFixAttempts == 0` AND verdict == `PASS`) | `advance` | Advance to next step. |
| 2 | EXPLORATORY-ONLY (only from initial run; re-QA cannot return this per FR-3) | `advance` | Advance to next step. No fixes needed. |
| 3 | ISSUES-FOUND AND `qaFixAttempts < qaLoopCap` | `fix-phase` | Increment counter; fork `addressing-qa-findings` (fix mode); re-invoke `executing-qa` (re-QA); loop. |
| 4 | ISSUES-FOUND AND `qaFixAttempts >= qaLoopCap` | `pause:qa-loop-exhausted` | Pause with resume options (see FR-8). |
| 5 | Post-fix PASS needing adoption (`qaFixAttempts > 0` AND `adoptedTests` empty) | `adopt-phase` | Fork `addressing-qa-findings` (adopt mode); on `done | phase=adopted` advance. |
| 6 | Post-adopt PASS (`qaFixAttempts > 0` AND `adoptedTests` non-empty) | `advance` | Advance to next step. |
| 7 | ERROR | `pause:qa-error` | Pause; surface error reason; user resolves manually. |

Note: `dispatch=re-qa` is not emitted by `qa-dispatch.sh`. The orchestrator emits it internally after a fix-phase returns `done | phase=fix-committed`.

## FR-8 Loop Semantics

One "attempt" = one full pass over all findings in the QA artifact + one re-QA execution:
1. `executing-qa` returns `ISSUES-FOUND`.
2. Orchestrator calls `workflow-state.sh inc-qa-fix-attempts {ID}` — appends a `{type:"qa-fix-attempt", attempt:<N>, at:<ISO>}` entry to `.stateEvents` per Edge Case 15.
3. Orchestrator forks `addressing-qa-findings` (fix mode).
4. `addressing-qa-findings` returns `done | phase=fix-committed`.
5. Orchestrator re-invokes `executing-qa` in re-QA mode (auto-detected per FR-3).
6. Loop back to `qa-dispatch.sh` with the new verdict.

Default cap: `qaLoopCap = 2` (set at `workflow-state.sh init`; overrideable per FR-8 resume).

## Pause Reasons and Resume Actions

| Pause reason | Trigger | Resume action |
|---|---|---|
| `qa-loop-exhausted` | `ISSUES-FOUND` AND `qaFixAttempts >= qaLoopCap` | `--approve-advance`: advance with counter preserved. `--qa-loop-cap <N>`: reset counter to 0, set cap to N, retry loop. Neither: stay paused. |
| `qa-error` | `executing-qa` returns `ERROR` verdict | User resolves environment/test issue manually, then re-invokes. No flag needed. |
| `fix-suite-failed` | `addressing-qa-findings` fix phase returns suite-gate failure | User reverts or fixes the full-suite failure manually, then re-invokes. No flag needed. v1 has no auto-revert (Edge Case 13). |
| `adoption-failed` | `addressing-qa-findings` adopt phase returns partial-success failure | User fixes the failing QA test's import structure manually, then re-invokes. `adoptedTests` is preserved across the pause per FR-4 step 2.3. |

### `qa-loop-exhausted` resume prompt (load-bearing carve-out)

```
QA loop exhausted after {qaFixAttempts} fix attempt(s). Issues remain unresolved.
Resume options:
  --approve-advance   advance past QA with issues unresolved (counter preserved)
  --qa-loop-cap <N>   raise the cap to N and retry (resets counter to 0)
To abandon: close this workflow and address the issues manually.
```

### Mutual-exclusion guard (FR-8)

`--approve-advance` and `--qa-loop-cap` are mutually exclusive. `parse-model-flags.sh` exits 2 with the verbatim message:

```
Error: --approve-advance and --qa-loop-cap are mutually exclusive
```

## State Fields

| Field | Type | Default | Written by |
|---|---|---|---|
| `qaFixAttempts` | integer | 0 | `inc-qa-fix-attempts`, `reset-qa-fix-attempts` |
| `qaLastVerdict` | string\|null | null | `set-qa-verdict` (after each `executing-qa` run) |
| `adoptedTests` | string[] | [] | `record-adopted-test` |
| `qaLoopCap` | integer | 2 | `set-qa-loop-cap` (via `--qa-loop-cap <N>` resume) |
| `stateEvents` | object[] | [] | `inc-qa-fix-attempts` (appends `{type,attempt,at}`) |

## Edge Case Cross-References

- **Edge Case 5**: re-QA PASS on first attempt — `qaFixAttempts = 1`, verdict `PASS`, `adoptedTests` empty → dispatch `adopt-phase`.
- **Edge Case 8**: re-QA mode entered but QA files manually deleted — `executing-qa` emits `ERROR` with verbatim NFR-2 reason; orchestrator pauses with `qa-error`.
- **Edge Case 13**: full-suite gate failed after fix — no auto-revert in v1; user resolves manually. The `fix-suite-failed` pause reason surfaces the FR-4 step-4 failure reason verbatim.
- **Edge Case 14**: `adoption-failed` with partial progress — `adoptedTests` records already-adopted paths across the pause; on re-invoke the adopt phase skips already-adopted files.
- **Edge Case 15**: loop history traceability — each `inc-qa-fix-attempts` appends a `{type:"qa-fix-attempt", attempt:<N>, at:<ISO>}` entry to `.stateEvents`; the history survives pause/resume cycles.
- **Edge Case 16**: user abandons at `qa-loop-exhausted` — no flag provided → workflow stays paused; user may re-open the issue and start a new workflow or manually fix and re-invoke.
