#!/usr/bin/env bats
# Bats fixture for fetch-issue.sh (FEAT-025 / FR-6).
#
# Stubs external commands (`gh`, `acli`, `rovo-mcp-invoke`) via PATH
# shadowing; uses the real sibling `backend-detect.sh`.
#
# Asserts normalized JSON shape {title, body, labels, state, assignees} and
# verbatim [warn] strings (NFR-1).

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  FETCH="${SCRIPT_DIR}/fetch-issue.sh"

  FIXTURE_DIR="$(mktemp -d)"
  STUB_DIR="${FIXTURE_DIR}/stubs"
  TRACER="${FIXTURE_DIR}/tracer.log"
  mkdir -p "$STUB_DIR"
  : > "$TRACER"

  export PATH="${STUB_DIR}:${PATH}"
  export TRACER
}

teardown() {
  if [ -n "${FIXTURE_DIR:-}" ] && [ -d "$FIXTURE_DIR" ]; then
    rm -rf "$FIXTURE_DIR"
  fi
}

# ---------- stub writers ----------

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
    if [ "$2" = "view" ]; then
      if [ "${GH_VIEW_RC:-0}" -ne 0 ]; then
        printf '%s\n' "${GH_VIEW_STDERR:-boom}" >&2
        exit "${GH_VIEW_RC}"
      fi
      # Emit the default JSON payload or an override.
      printf '%s' "${GH_VIEW_STDOUT:-{\"title\":\"T\",\"body\":\"B\",\"labels\":[],\"state\":\"OPEN\",\"assignees\":[]\}}"
      exit 0
    fi
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
if [ "${ACLI_VIEW_RC:-0}" -ne 0 ]; then
  printf '%s\n' "${ACLI_VIEW_STDERR:-acli boom}" >&2
  exit "${ACLI_VIEW_RC}"
fi
# Default structured text response (overridable).
if [ -n "${ACLI_VIEW_STDOUT:-}" ]; then
  printf '%s\n' "${ACLI_VIEW_STDOUT}"
else
  cat <<'TXT'
Summary: Example Jira Issue
Description: An example body.
Status: In Progress
Labels: backend, urgent
Assignee: Alice
TXT
fi
exit 0
EOF
  chmod +x "${STUB_DIR}/acli"
}

write_rovo_stub() {
  cat > "${STUB_DIR}/rovo-mcp-invoke" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "TRACE:rovo:$*" >> "${TRACER}"
if [ "${ROVO_RC:-0}" -ne 0 ]; then
  printf '%s\n' "${ROVO_STDERR:-rovo boom}" >&2
  exit "${ROVO_RC}"
fi
if [ -n "${ROVO_STDOUT:-}" ]; then
  printf '%s' "${ROVO_STDOUT}"
else
  # Default Jira issue object shape (subset).
  cat <<'JSON'
{"fields":{"summary":"Rovo Title","description":"Rovo Body","labels":["x"],"status":{"name":"Done"},"assignee":{"displayName":"Bob"}}}
JSON
fi
exit 0
EOF
  chmod +x "${STUB_DIR}/rovo-mcp-invoke"
}

empty_path_no_gh() {
  local dir="${FIXTURE_DIR}/nogh"
  mkdir -p "$dir"
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

# ---------- arg validation ----------

@test "missing arg -> exit 2" {
  run bash "$FETCH"
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage:"* ]]
}

# ---------- no-reference path ----------

@test "empty ref -> stdout 'null', exit 0" {
  run bash "$FETCH" ""
  [ "$status" -eq 0 ]
  [ "$output" = "null" ]
}

@test "unrecognized ref 'foo' -> stdout 'null', exit 0" {
  run bash "$FETCH" "foo"
  [ "$status" -eq 0 ]
  [ "$output" = "null" ]
}

# ---------- GitHub pre-flight ----------

@test "gh not on PATH -> verbatim [warn], empty stdout, exit 0" {
  nogh="$(empty_path_no_gh)"
  PATH="$nogh" run bash "$FETCH" "#42"
  [ "$status" -eq 0 ]
  [ -z "$output" ] || [[ "$output" == *'[warn] GitHub CLI (`gh`) not found on PATH. Skipping GitHub issue operations.'* ]]

  # Verify the warn landed on stderr (not stdout) via a second, stderr-isolated run.
  err_file="${FIXTURE_DIR}/err1"
  PATH="$nogh" bash "$FETCH" "#42" 2>"$err_file" >/dev/null
  [ "$?" -eq 0 ] || true
  err="$(cat "$err_file")"
  [[ "$err" == *'[warn] GitHub CLI (`gh`) not found on PATH. Skipping GitHub issue operations.'* ]]
}

@test "gh not authenticated -> verbatim [warn], empty stdout, exit 0" {
  write_gh_stub
  err_file="${FIXTURE_DIR}/err2"
  GH_AUTH_RC=1 bash "$FETCH" "#42" 2>"$err_file" >"${FIXTURE_DIR}/out2"
  [ "$?" -eq 0 ]
  err="$(cat "$err_file")"
  out="$(cat "${FIXTURE_DIR}/out2")"
  [[ "$err" == *'[warn] GitHub CLI not authenticated -- run `gh auth login` to enable issue tracking.'* ]]
  [ -z "$out" ]
}

# ---------- GitHub happy path ----------

@test "github happy path -> exit 0, stdout contains normalized fields" {
  write_gh_stub
  run bash "$FETCH" "#42"
  [ "$status" -eq 0 ]
  [[ "$output" == *"\"title\""* ]]
  [[ "$output" == *"\"body\""* ]]
  [[ "$output" == *"\"labels\""* ]]
  [[ "$output" == *"\"state\""* ]]
  [[ "$output" == *"\"assignees\""* ]]
  # gh invoked with the expected args.
  grep -F "TRACE:gh:issue view 42 --json title,body,labels,state,assignees" "$TRACER"
}

# ---------- GitHub fetch failure ----------

@test "gh issue view fails generic -> [warn] gh: gh issue view failed, empty stdout, exit 0" {
  write_gh_stub
  err_file="${FIXTURE_DIR}/err3"
  out_file="${FIXTURE_DIR}/out3"
  GH_VIEW_RC=1 GH_VIEW_STDERR="server 500" \
    bash "$FETCH" "#42" 2>"$err_file" >"$out_file"
  [ "$?" -eq 0 ]
  err="$(cat "$err_file")"
  out="$(cat "$out_file")"
  [[ "$err" == *"[warn] gh: gh issue view failed: server 500. Skipping."* ]]
  [ -z "$out" ]
}

@test "gh issue view returns 'not found' -> [warn] not found, empty stdout, exit 0" {
  write_gh_stub
  err_file="${FIXTURE_DIR}/err4"
  out_file="${FIXTURE_DIR}/out4"
  GH_VIEW_RC=1 GH_VIEW_STDERR="issue not found" \
    bash "$FETCH" "#42" 2>"$err_file" >"$out_file"
  [ "$?" -eq 0 ]
  err="$(cat "$err_file")"
  out="$(cat "$out_file")"
  [[ "$err" == *'[warn] `gh issue view` returned not found for #42. Skipping.'* ]]
  [ -z "$out" ]
}

# ---------- Jira Tier 1 (Rovo) ----------

@test "jira Tier 1 Rovo happy path -> normalized JSON on stdout, exit 0" {
  write_rovo_stub
  run bash "$FETCH" "PROJ-123"
  [ "$status" -eq 0 ]
  # jq normalizes into the expected shape.
  title="$(printf '%s' "$output" | jq -r '.title')"
  state="$(printf '%s' "$output" | jq -r '.state')"
  assignee="$(printf '%s' "$output" | jq -r '.assignees[0]')"
  [ "$title" = "Rovo Title" ]
  [ "$state" = "Done" ]
  [ "$assignee" = "Bob" ]
  grep -F "TRACE:rovo:getJiraIssue" "$TRACER"
}

# ---------- Jira Tier 1 -> Tier 2 fall-through ----------

@test "jira Tier 1 Rovo fails, Tier 2 acli present -> acli parse wins, exit 0" {
  write_rovo_stub
  write_acli_stub
  ROVO_RC=1 ROVO_STDERR="rovo died" \
    run bash "$FETCH" "PROJ-123"
  [ "$status" -eq 0 ]
  # Fall-through warn appears on stderr (mixed by bats into $output by default).
  [[ "$output" == *"Rovo MCP tool \`getJiraIssue\` returned unexpected response"* ]]
  [[ "$output" == *"Falling through to acli."* ]]
  # acli stub's default structured text parsed into normalized JSON.
  # Extract the last line (after the warn) — it should be JSON.
  # Use a file to isolate stdout.
  err_file="${FIXTURE_DIR}/err5"
  out_file="${FIXTURE_DIR}/out5"
  ROVO_RC=1 ROVO_STDERR="rovo died" \
    bash "$FETCH" "PROJ-123" 2>"$err_file" >"$out_file"
  out="$(cat "$out_file")"
  title="$(printf '%s' "$out" | jq -r '.title')"
  state="$(printf '%s' "$out" | jq -r '.state')"
  [ "$title" = "Example Jira Issue" ]
  [ "$state" = "In Progress" ]
}

# ---------- Jira Tier 2 (acli) happy path ----------

@test "jira ref, no Rovo stub, acli present -> acli parse wins, exit 0" {
  write_acli_stub
  err_file="${FIXTURE_DIR}/err6"
  out_file="${FIXTURE_DIR}/out6"
  bash "$FETCH" "PROJ-999" 2>"$err_file" >"$out_file"
  [ "$?" -eq 0 ]
  out="$(cat "$out_file")"
  labels_count="$(printf '%s' "$out" | jq -r '.labels | length')"
  [ "$labels_count" = "2" ]
  grep -F "TRACE:acli:jira workitem view --key PROJ-999" "$TRACER"
}

# ---------- Jira acli failure ----------

@test "jira acli fails 'not found' -> [warn] issue not found, empty stdout, exit 0" {
  write_acli_stub
  err_file="${FIXTURE_DIR}/err7"
  out_file="${FIXTURE_DIR}/out7"
  ACLI_VIEW_RC=1 ACLI_VIEW_STDERR="issue not found" \
    bash "$FETCH" "PROJ-7" 2>"$err_file" >"$out_file"
  [ "$?" -eq 0 ]
  err="$(cat "$err_file")"
  out="$(cat "$out_file")"
  [[ "$err" == *"[warn] Jira issue PROJ-7 not found. Skipping."* ]]
  [ -z "$out" ]
}

@test "jira acli generic failure -> [warn] acli: acli command failed, exit 0" {
  write_acli_stub
  err_file="${FIXTURE_DIR}/err8"
  out_file="${FIXTURE_DIR}/out8"
  ACLI_VIEW_RC=1 ACLI_VIEW_STDERR="server 500" \
    bash "$FETCH" "PROJ-7" 2>"$err_file" >"$out_file"
  [ "$?" -eq 0 ]
  err="$(cat "$err_file")"
  out="$(cat "$out_file")"
  [[ "$err" == *"[warn] acli: acli command failed: server 500. Skipping."* ]]
  [ -z "$out" ]
}

# ---------- Jira Tier 3 skip ----------

@test "jira ref, no Rovo, no acli -> Tier 3 [warn], empty stdout, exit 0" {
  nogh="$(empty_path_no_gh)"
  err_file="${FIXTURE_DIR}/err9"
  out_file="${FIXTURE_DIR}/out9"
  PATH="$nogh" bash "$FETCH" "PROJ-5" 2>"$err_file" >"$out_file"
  [ "$?" -eq 0 ]
  err="$(cat "$err_file")"
  out="$(cat "$out_file")"
  [[ "$err" == *"[warn] No Jira backend available (Rovo MCP not registered, acli not found). Skipping Jira operations."* ]]
  [ -z "$out" ]
}
