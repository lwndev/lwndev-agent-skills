#!/usr/bin/env bats
# Bats fixture for render-issue-comment.sh (FEAT-025 / FR-4).
#
# Exercises the template renderer end-to-end:
#   * GitHub backend, all six comment types (happy path)
#   * Jira backend, `acli` tier (markdown source), happy path
#   * Jira backend, `rovo` tier (ADF JSON), happy path + list expansion
#   * Unknown context key → stderr warn, exit 0
#   * Missing required variable → exit 1, `unresolved placeholder`
#   * Malformed context JSON → exit 2
#   * Invalid backend / invalid type / missing backend arg → exit 2
#   * Template missing for a (valid) type → exit 1
#   * Idempotency: identical context → identical stdout
#   * ADF JSON escaping: unescaped-quote-in-context still yields valid JSON
#     (defensive invariant; the renderer escapes via jq -Rsc so the
#     validator passes — documents the no-injection contract).
#
# The fixture builds its own minimal template files under a temp directory
# and points the script at them via MWI_TEMPLATES_DIR, isolating tests from
# the real `references/` content (whose evolution is tracked in Phase 4).

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  RENDER="${SCRIPT_DIR}/render-issue-comment.sh"
  TMP_REFS="$(mktemp -d)"
  export MWI_TEMPLATES_DIR="$TMP_REFS"
  _write_default_templates
}

teardown() {
  if [ -n "${TMP_REFS:-}" ] && [ -d "${TMP_REFS}" ]; then
    rm -rf "$TMP_REFS"
  fi
}

_write_default_templates() {
  cat > "${TMP_REFS}/github-templates.md" <<'MD'
# Test fixtures — GitHub / Jira-acli markdown templates

### phase-start

```
Starting Phase <PHASE>: <NAME>

**Work Item:** <WORK_ITEM_ID>

**Implementation Steps:**
<STEPS>

**Expected Deliverables:**
<DELIVERABLES>

**Status:** In Progress
```

### phase-completion

```
Completed Phase <PHASE>: <NAME>

**Work Item:** <WORK_ITEM_ID>

**Deliverables Verified:**
<DELIVERABLES>

**Commit:** <COMMIT_SHA>
```

### work-start

```
Starting work on <CHORE_ID>

**Branch:** <BRANCH>

**Acceptance Criteria:**
<CRITERIA>
```

### work-complete

```
Completed <CHORE_ID>

**Pull Request:** #<PR_NUM>

**Acceptance Criteria Verified:**
<CRITERIA>
```

### bug-start

```
Starting work on <BUG_ID>

**Severity:** <SEVERITY>

**Root Causes to Address:**
<ROOT_CAUSES>

**Acceptance Criteria:**
<CRITERIA>

**Branch:** <BRANCH>
```

### bug-complete

```
Completed <BUG_ID>

**Pull Request:** #<PR_NUM>

**Root Cause Resolution:**
<ROOT_CAUSE_RESOLUTIONS>

**Verification:**
<VERIFICATION_RESULTS>
```
MD

  cat > "${TMP_REFS}/jira-templates.md" <<'MD'
# Test fixtures — Jira rovo ADF templates

### phase-start

```json
{
  "version": 1,
  "type": "doc",
  "content": [
    {
      "type": "heading",
      "attrs": { "level": 3 },
      "content": [
        { "type": "text", "text": "Starting Phase {phase}: {name}" }
      ]
    },
    {
      "type": "bulletList",
      "content": [
        {
          "type": "listItem",
          "content": [
            { "type": "paragraph", "content": [ { "type": "text", "text": "{steps[0]}" } ] }
          ]
        },
        {
          "type": "listItem",
          "content": [
            { "type": "paragraph", "content": [ { "type": "text", "text": "{steps[1]}" } ] }
          ]
        }
      ]
    }
  ]
}
```

### phase-completion

```json
{
  "version": 1,
  "type": "doc",
  "content": [
    { "type": "paragraph", "content": [ { "type": "text", "text": "Completed Phase {phase}" } ] }
  ]
}
```
MD
}

# ---------- GitHub happy paths (all six comment types) ----------

@test "github backend, phase-start, valid context -> non-empty markdown, exit 0" {
  run bash "$RENDER" github phase-start \
    '{"phase":2,"name":"Renderer","workItemId":"FEAT-025","steps":["Write script","Write tests"],"deliverables":["a","b"]}'
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  [[ "$output" == *"Starting Phase 2: Renderer"* ]]
  [[ "$output" == *"- Write script"* ]]
  [[ "$output" == *"- Write tests"* ]]
  [[ "$output" == *"- a"* ]]
  [[ "$output" == *"- b"* ]]
}

@test "github backend, phase-completion -> exit 0" {
  run bash "$RENDER" github phase-completion \
    '{"phase":2,"name":"Renderer","workItemId":"FEAT-025","deliverables":["a"],"commitSha":"abc1234"}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Completed Phase 2: Renderer"* ]]
  [[ "$output" == *"abc1234"* ]]
}

@test "github backend, work-start -> exit 0" {
  run bash "$RENDER" github work-start \
    '{"choreId":"CHORE-003","branch":"chore/CHORE-003-x","criteria":["c1","c2"]}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Starting work on CHORE-003"* ]]
  [[ "$output" == *"- c1"* ]]
  [[ "$output" == *"- c2"* ]]
}

@test "github backend, work-complete -> exit 0" {
  run bash "$RENDER" github work-complete \
    '{"choreId":"CHORE-003","prNum":42,"criteria":["c1"]}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Completed CHORE-003"* ]]
  [[ "$output" == *"#42"* ]]
}

@test "github backend, bug-start -> exit 0" {
  run bash "$RENDER" github bug-start \
    '{"bugId":"BUG-001","severity":"High","rootCauses":["r1","r2"],"criteria":["c1"],"branch":"fix/BUG-001-x"}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"BUG-001"* ]]
  [[ "$output" == *"High"* ]]
  [[ "$output" == *"- r1"* ]]
}

@test "github backend, bug-complete -> exit 0" {
  run bash "$RENDER" github bug-complete \
    '{"bugId":"BUG-001","prNum":58,"rootCauseResolutions":["RC-1 fixed"],"verificationResults":["tests pass"]}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"BUG-001"* ]]
  [[ "$output" == *"#58"* ]]
  [[ "$output" == *"- RC-1 fixed"* ]]
  [[ "$output" == *"- tests pass"* ]]
}

# ---------- Jira acli (markdown) happy path ----------

@test "jira backend, acli tier, phase-start -> markdown output (no ADF)" {
  run bash "$RENDER" jira phase-start \
    '{"phase":1,"name":"Backend","workItemId":"FEAT-025","steps":["s1"],"deliverables":["d1"]}' \
    acli
  [ "$status" -eq 0 ]
  [[ "$output" == *"Starting Phase 1: Backend"* ]]
  # Must not be JSON-shaped (ADF output starts with `{`).
  [[ "${output:0:1}" != "{" ]]
}

@test "jira backend, default tier (no 4th arg) -> acli/markdown" {
  run bash "$RENDER" jira phase-start \
    '{"phase":3,"name":"Defaults","workItemId":"FEAT-025","steps":["s"],"deliverables":["d"]}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Starting Phase 3: Defaults"* ]]
}

# ---------- Jira rovo (ADF) happy path + list expansion ----------

@test "jira backend, rovo tier, phase-start -> ADF JSON output" {
  run bash "$RENDER" jira phase-start \
    '{"phase":2,"name":"Renderer","steps":["a","b"]}' \
    rovo
  [ "$status" -eq 0 ]
  [[ "$output" == *'"version": 1'* ]]
  [[ "$output" == *'"type": "doc"'* ]]
  [[ "$output" == *"Starting Phase 2: Renderer"* ]]
  # Valid JSON.
  echo "$output" | jq -e . >/dev/null
}

@test "ADF list expansion: 3 items render 3 listItem nodes" {
  run bash "$RENDER" jira phase-start \
    '{"phase":1,"name":"X","steps":["a","b","c"]}' \
    rovo
  [ "$status" -eq 0 ]
  # Count listItem occurrences — should be 3.
  count="$(echo "$output" | jq '[.. | objects | select(.type == "listItem")] | length')"
  [ "$count" = "3" ]
}

@test "ADF list expansion: structure contains bulletList wrapper" {
  run bash "$RENDER" jira phase-start \
    '{"phase":1,"name":"X","steps":["only"]}' \
    rovo
  [ "$status" -eq 0 ]
  [[ "$output" == *'"bulletList"'* ]]
  [[ "$output" == *'"listItem"'* ]]
}

# ---------- Markdown list expansion ----------

@test "markdown list expansion: steps=[a,b,c] -> three '- X' bullets" {
  run bash "$RENDER" github phase-start \
    '{"phase":1,"name":"X","workItemId":"FEAT-X","steps":["a","b","c"],"deliverables":["d"]}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"- a"* ]]
  [[ "$output" == *"- b"* ]]
  [[ "$output" == *"- c"* ]]
}

# ---------- Warnings + errors ----------

@test "unknown context variable -> stderr [warn], exit 0" {
  run bash "$RENDER" github phase-start \
    '{"phase":1,"name":"N","workItemId":"FEAT-X","steps":["s"],"deliverables":["d"],"extraKey":"ignored"}'
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] render-issue-comment: unused context variable:"* ]] || [[ "$output" == *"[warn] render-issue-comment: unused context variable:"* ]]
}

@test "missing required variable -> exit 1, unresolved placeholder" {
  run bash "$RENDER" github phase-start \
    '{"name":"N","workItemId":"FEAT-X","steps":["s"],"deliverables":["d"]}'
  [ "$status" -eq 1 ]
  [[ "$output" == *"unresolved placeholder"* ]] || [[ "$stderr" == *"unresolved placeholder"* ]]
}

@test "malformed context JSON -> exit 2" {
  run bash "$RENDER" github phase-start 'not-json-at-all'
  [ "$status" -eq 2 ]
}

@test "invalid backend -> exit 2, invalid backend message" {
  run bash "$RENDER" gitlab phase-start '{}'
  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid backend"* ]]
}

@test "invalid type -> exit 2, invalid type message" {
  run bash "$RENDER" github bogus-type '{}'
  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid type"* ]]
}

@test "missing backend arg -> exit 2, usage message" {
  run bash "$RENDER"
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage:"* ]]
}

@test "invalid tier -> exit 2" {
  run bash "$RENDER" github phase-start '{"phase":1,"name":"N","workItemId":"X","steps":["s"],"deliverables":["d"]}' weirdtier
  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid tier"* ]]
}

@test "template missing for (valid) type -> exit 1" {
  # Replace the default templates with a file that has no work-start block.
  cat > "${TMP_REFS}/github-templates.md" <<'MD'
### phase-start
```
Phase <PHASE>
```
MD
  run bash "$RENDER" github work-start '{"choreId":"CHORE-1","branch":"b","criteria":["c"]}'
  [ "$status" -eq 1 ]
  [[ "$output" == *"template not found for type"* ]]
}

@test "template file missing entirely -> exit 1" {
  # Remove the jira template file and call rovo path.
  rm -f "${TMP_REFS}/jira-templates.md"
  run bash "$RENDER" jira phase-start '{"phase":1,"name":"N","steps":["s"]}' rovo
  [ "$status" -eq 1 ]
  [[ "$output" == *"template file not found"* ]] || [[ "$output" == *"template not found"* ]]
}

# ---------- Idempotency ----------

@test "idempotency: same context produces identical stdout" {
  ctx='{"phase":1,"name":"X","workItemId":"FEAT-X","steps":["a","b"],"deliverables":["d"]}'
  run bash "$RENDER" github phase-start "$ctx"
  [ "$status" -eq 0 ]
  first="$output"
  run bash "$RENDER" github phase-start "$ctx"
  [ "$status" -eq 0 ]
  [ "$output" = "$first" ]
}

@test "idempotency (ADF): same context produces identical stdout" {
  ctx='{"phase":1,"name":"X","steps":["a","b"]}'
  run bash "$RENDER" jira phase-start "$ctx" rovo
  [ "$status" -eq 0 ]
  first="$output"
  run bash "$RENDER" jira phase-start "$ctx" rovo
  [ "$status" -eq 0 ]
  [ "$output" = "$first" ]
}

# ---------- ADF JSON escaping invariant ----------

@test "ADF: context value with embedded quote is JSON-escaped -> valid JSON output" {
  # The renderer must JSON-escape scalar substitutions so malformed input
  # values do not break the emitted ADF. This verifies the defensive
  # invariant: rendering must not emit invalid JSON even when context
  # contains characters that would otherwise break the structure.
  run bash "$RENDER" jira phase-completion \
    '{"phase":"2 \"bad\" value"}' rovo
  [ "$status" -eq 0 ]
  # Output must still parse as JSON.
  echo "$output" | jq -e . >/dev/null
  [[ "$output" == *"2 \\\"bad\\\" value"* ]] || [[ "$output" == *'2 "bad" value'* ]]
}

@test "ADF template body is invalid JSON -> exit 1" {
  # Corrupt the jira templates file so the template block is not parseable.
  cat > "${TMP_REFS}/jira-templates.md" <<'MD'
### phase-start

```json
{ this is: not valid json at all }
```
MD
  run bash "$RENDER" jira phase-start '{"phase":1,"name":"N","steps":["s"]}' rovo
  [ "$status" -eq 1 ]
  [[ "$output" == *"ADF template is not valid JSON"* ]] || [[ "$output" == *"unresolved placeholder"* ]]
}
