#!/usr/bin/env bats
# Bats fixture for post-issue-comment.sh (FEAT-025 / FR-5).
#
# Stubs external commands (`gh`, `acli`, `rovo-mcp-invoke`) via PATH
# shadowing; uses the real sibling scripts (`backend-detect.sh`,
# `render-issue-comment.sh`) per the Phase 3 plan ("Do not stub
# backend-detect.sh or render-issue-comment.sh -- they are real
# script-to-script calls").
#
# Asserts every [warn]/[info] string verbatim (incl. backtick formatting and
# ASCII `--`) per NFR-1.

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  POST="${SCRIPT_DIR}/post-issue-comment.sh"

  FIXTURE_DIR="$(mktemp -d)"
  STUB_DIR="${FIXTURE_DIR}/stubs"
  TMP_REFS="${FIXTURE_DIR}/refs"
  TRACER="${FIXTURE_DIR}/tracer.log"
  mkdir -p "$STUB_DIR" "$TMP_REFS"
  : > "$TRACER"

  # Build minimal template files so the real render-issue-comment.sh
  # (invoked as a subprocess) can render without hitting the repo's real
  # references. It reads MWI_TEMPLATES_DIR when set.
  _write_default_templates
  export MWI_TEMPLATES_DIR="$TMP_REFS"

  # Put stubs first on PATH; keep rest intact so bash/awk/sed/mktemp/jq etc.
  # still resolve.
  export PATH="${STUB_DIR}:${PATH}"
  export TRACER
}

teardown() {
  if [ -n "${FIXTURE_DIR:-}" ] && [ -d "$FIXTURE_DIR" ]; then
    rm -rf "$FIXTURE_DIR"
  fi
}

_write_default_templates() {
  cat > "${TMP_REFS}/github-templates.md" <<'MD'
### phase-start

```
Starting Phase <PHASE>: <NAME>
```

### phase-completion

```
Completed Phase <PHASE>
```

### work-start

```
Starting work on <CHORE_ID>
```

### work-complete

```
Completed <CHORE_ID>
```

### bug-start

```
Starting work on <BUG_ID>
```

### bug-complete

```
Completed <BUG_ID>
```
MD

  cat > "${TMP_REFS}/jira-templates.md" <<'MD'
### phase-start

```json
{
  "version": 1,
  "type": "doc",
  "content": [
    { "type": "paragraph", "content": [ { "type": "text", "text": "Starting Phase {phase}: {name}" } ] }
  ]
}
```
MD
}

# ---------- stub writers ----------

# gh stub: honors GH_AUTH_RC (gh auth status rc), GH_COMMENT_RC (gh issue
# comment rc), GH_COMMENT_STDERR (stderr text on comment failure).
write_gh_stub() {
  cat > "${STUB_DIR}/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "TRACE:gh:$*" >> "${TRACER}"
case "$1" in
  auth)
    if [ "$2" = "status" ]; then
      exit "${GH_AUTH_RC:-0}"
    fi
    exit 0
    ;;
  issue)
    case "$2" in
      comment)
        if [ "${GH_COMMENT_RC:-0}" -ne 0 ]; then
          printf '%s\n' "${GH_COMMENT_STDERR:-boom}" >&2
        fi
        exit "${GH_COMMENT_RC:-0}"
        ;;
    esac
    exit 0
    ;;
esac
exit 0
EOF
  chmod +x "${STUB_DIR}/gh"
}

write_acli_stub() {
  cat > "${STUB_DIR}/acli" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "TRACE:acli:$*" >> "${TRACER}"
if [ "${ACLI_COMMENT_RC:-0}" -ne 0 ]; then
  printf '%s\n' "${ACLI_COMMENT_STDERR:-acli boom}" >&2
fi
exit "${ACLI_COMMENT_RC:-0}"
EOF
  chmod +x "${STUB_DIR}/acli"
}

write_rovo_stub() {
  cat > "${STUB_DIR}/rovo-mcp-invoke" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "TRACE:rovo:$*" >> "${TRACER}"
if [ "${ROVO_RC:-0}" -ne 0 ]; then
  printf '%s\n' "${ROVO_STDERR:-rovo boom}" >&2
fi
exit "${ROVO_RC:-0}"
EOF
  chmod +x "${STUB_DIR}/rovo-mcp-invoke"
}

# Block `gh` (or any binary) from PATH: write a "gh" that we then remove so
# `command -v gh` returns false. We simulate absence by simply not writing
# the stub; the test's STUB_DIR is first on PATH but the real `gh` on the
# host may resolve. Block via a directory-scoped empty PATH prefix instead.
empty_path_no_gh() {
  local dir="${FIXTURE_DIR}/nogh"
  mkdir -p "$dir"
  # Only link the bare minimum so bash/jq/mktemp/etc. still work.
  for bin in bash env awk sed grep tr cut wc mktemp head tail cat printf chmod rm mkdir ls true false test dirname basename sort jq uniq; do
    if [ -x "/bin/$bin" ]; then
      ln -s "/bin/$bin" "$dir/$bin" 2>/dev/null || true
    elif [ -x "/usr/bin/$bin" ]; then
      ln -s "/usr/bin/$bin" "$dir/$bin" 2>/dev/null || true
    elif [ -x "/opt/homebrew/bin/$bin" ]; then
      ln -s "/opt/homebrew/bin/$bin" "$dir/$bin" 2>/dev/null || true
    fi
  done
  printf '%s' "$dir"
}

# ---------- arg-validation tests ----------

@test "missing args (no issue-ref) -> exit 2" {
  run bash "$POST"
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage:"* ]]
}

@test "missing <type> -> exit 2" {
  run bash "$POST" "#42"
  [ "$status" -eq 2 ]
}

@test "missing <context-json> -> exit 2" {
  run bash "$POST" "#42" "phase-start"
  [ "$status" -eq 2 ]
}

@test "invalid type -> exit 2" {
  run bash "$POST" "#42" "bogus-type" '{}'
  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid type"* ]]
}

@test "malformed context JSON -> exit 2" {
  run bash "$POST" "#42" "phase-start" "not-json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"malformed context JSON"* ]]
}

# ---------- no-reference path ----------

@test "empty issue-ref -> [info] skip, exit 0" {
  run bash "$POST" "" "phase-start" '{"phase":1,"name":"N"}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"[info] No issue reference provided, skipping issue operations."* ]]
}

@test "unrecognized issue-ref 'foo' -> [info] skip, exit 0" {
  run bash "$POST" "foo" "phase-start" '{"phase":1,"name":"N"}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"[info] No issue reference provided, skipping issue operations."* ]]
}

# ---------- GitHub pre-flight ----------

@test "gh not on PATH -> verbatim [warn], exit 0" {
  # Rebuild PATH without gh.
  nogh="$(empty_path_no_gh)"
  PATH="$nogh" run bash "$POST" "#42" "phase-start" '{"phase":1,"name":"N"}'
  [ "$status" -eq 0 ]
  [[ "$output" == *'[warn] GitHub CLI (`gh`) not found on PATH. Skipping GitHub issue operations.'* ]]
}

@test "gh not authenticated -> verbatim [warn], exit 0" {
  write_gh_stub
  GH_AUTH_RC=1 run bash "$POST" "#42" "phase-start" '{"phase":1,"name":"N"}'
  [ "$status" -eq 0 ]
  [[ "$output" == *'[warn] GitHub CLI not authenticated -- run `gh auth login` to enable issue tracking.'* ]]
}

# ---------- GitHub render failure ----------

@test "render failure (missing required var) -> [warn] Failed to render, exit 0" {
  write_gh_stub
  # Context missing required <PHASE> and <NAME>.
  run bash "$POST" "#42" "phase-start" '{}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"[warn] Failed to render phase-start comment for #42:"* ]]
  [[ "$output" == *"Skipping."* ]]
}

# ---------- GitHub post failure ----------

@test "gh issue comment fails -> [warn] gh: gh issue comment failed, exit 0" {
  write_gh_stub
  GH_COMMENT_RC=1 GH_COMMENT_STDERR="permission denied" \
    run bash "$POST" "#42" "phase-start" '{"phase":1,"name":"N"}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"[warn] gh: gh issue comment failed: permission denied"* ]]
}

# ---------- GitHub happy path ----------

@test "github happy path: gh auth + comment succeed -> exit 0, empty stdout, gh invoked" {
  write_gh_stub
  run bash "$POST" "#42" "phase-start" '{"phase":1,"name":"N"}'
  [ "$status" -eq 0 ]
  # stdout should be empty (success is silent).
  [ -z "$output" ]
  grep -F "TRACE:gh:issue comment 42 --body" "$TRACER"
}

# ---------- Jira Tier 3 (no backend) ----------

@test "jira ref, Rovo unavailable + acli unavailable -> Tier 3 skip [warn], exit 0" {
  # No rovo-mcp-invoke stub, no acli stub. Use no-gh PATH so host gh
  # doesn't satisfy unrelated command-v checks.
  nogh="$(empty_path_no_gh)"
  PATH="$nogh" run bash "$POST" "PROJ-123" "phase-start" '{"phase":1,"name":"N"}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"[warn] No Jira backend available (Rovo MCP not registered, acli not found). Skipping Jira operations."* ]]
}

# ---------- Jira Tier 2 (acli) happy path ----------

@test "jira ref, acli available -> acli invoked, exit 0" {
  write_acli_stub
  run bash "$POST" "PROJ-123" "phase-start" '{"phase":1,"name":"N"}'
  [ "$status" -eq 0 ]
  grep -F "TRACE:acli:jira workitem comment-create --key PROJ-123 --body" "$TRACER"
}

# ---------- Jira Tier 1 -> Tier 2 fall-through ----------

@test "jira ref, Rovo fails + acli present -> falls through to acli, exit 0" {
  write_rovo_stub
  write_acli_stub
  ROVO_RC=1 ROVO_STDERR="rovo unavailable" \
    run bash "$POST" "PROJ-123" "phase-start" '{"phase":1,"name":"N"}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Rovo MCP tool \`addCommentToJiraIssue\` returned unexpected response"* ]]
  [[ "$output" == *"Falling through to acli."* ]]
  grep -F "TRACE:rovo:addCommentToJiraIssue" "$TRACER"
  grep -F "TRACE:acli:jira workitem comment-create --key PROJ-123 --body" "$TRACER"
}

# ---------- Jira acli failure ----------

@test "jira acli command fails -> [warn] acli: acli command failed, exit 0" {
  write_acli_stub
  ACLI_COMMENT_RC=1 ACLI_COMMENT_STDERR="network error" \
    run bash "$POST" "PROJ-123" "phase-start" '{"phase":1,"name":"N"}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"[warn] acli: acli command failed: network error"* ]]
}

# ---------- Idempotency ----------

@test "idempotency: duplicate invocation is safe (both succeed)" {
  write_gh_stub
  run bash "$POST" "#99" "phase-start" '{"phase":1,"name":"N"}'
  [ "$status" -eq 0 ]
  run bash "$POST" "#99" "phase-start" '{"phase":1,"name":"N"}'
  [ "$status" -eq 0 ]
  # Two gh invocations should have landed in the tracer.
  count="$(grep -c "TRACE:gh:issue comment 99" "$TRACER" || true)"
  [ "$count" = "2" ]
}
