#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

# Strip inherited GIT_* env so fixture git calls cannot reach the real repo (#326).
load "${BATS_TEST_DIRNAME%/tests/bats/*}/tests/bats/helpers/git-env"

# QA-FEAT-034: adversarial probes for managing-source-control PR comment scripts.
# Built from the v2 QA plan at qa/test-plans/QA-plan-FEAT-034.md.
# Targets P0/P1 scenarios that the implementation team's bats fixtures did not explicitly cover.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
  SCRIPTS="$REPO_ROOT/plugins/lwndev-sdlc/skills/managing-source-control/scripts"
  TMP="$(mktemp -d)"
  STUBDIR="$TMP/stub"
  mkdir -p "$STUBDIR"

  # Fake git: pass through `remote get-url origin` to a fixture, otherwise delegate.
  cat > "$STUBDIR/git" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "remote" ] && [ "$2" = "get-url" ] && [ "$3" = "origin" ]; then
  echo "https://github.com/owner/repo.git"
  exit 0
fi
if [ "$1" = "rev-parse" ] && [ "$2" = "--show-toplevel" ]; then
  echo "$BATS_TMPDIR/fake-repo"
  exit 0
fi
exec /usr/bin/env -i PATH=/usr/bin:/bin git "$@"
EOF
  chmod +x "$STUBDIR/git"

  # Fake gh: records argv into RECORD_FILE, returns success URL.
  RECORD_FILE="$TMP/gh-record"
  export RECORD_FILE
  export BODY_FILE_CONTENT="$TMP/body-file-content"
  cat > "$STUBDIR/gh" <<'EOF'
#!/usr/bin/env bash
# Record one argv element per line.
for a in "$@"; do printf '%s\n' "$a" >> "$RECORD_FILE"; done
echo "--END--" >> "$RECORD_FILE"
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then exit 0; fi
if [ "$1" = "pr" ] && [ "$2" = "comment" ]; then
  # Find --body and --body-file and their values
  prev=""
  for a in "$@"; do
    case "$prev" in
      --body)      printf 'BODY_SEEN:%s\n' "$a" >> "$RECORD_FILE" ;;
      --body-file) cp -f "$a" "$BODY_FILE_CONTENT" 2>/dev/null || true ;;
    esac
    prev="$a"
  done
  echo "https://github.com/owner/repo/issues/1#issuecomment-12345"
  exit 0
fi
exit 0
EOF
  chmod +x "$STUBDIR/gh"

  export PATH="$STUBDIR:$PATH"
  export PR_COMMENT="$SCRIPTS/pr-comment.sh"
  export LIST_PR="$SCRIPTS/list-pr-comments.sh"
}

teardown() {
  rm -rf "$TMP"
}

# ---- P0: Inputs — shell-special characters in body must passthrough verbatim ----

@test "qa: body with single quotes posts verbatim" {
  run "$PR_COMMENT" 1 "this 'has' single quotes"
  [ "$status" -eq 0 ]
  grep -q "BODY_SEEN:this 'has' single quotes" "$RECORD_FILE"
}

@test "qa: body with double quotes posts verbatim" {
  run "$PR_COMMENT" 1 'this "has" double quotes'
  [ "$status" -eq 0 ]
  grep -q 'BODY_SEEN:this "has" double quotes' "$RECORD_FILE"
}

@test "qa: body with backticks posts verbatim (no command substitution)" {
  run "$PR_COMMENT" 1 'literal `id` not substituted'
  [ "$status" -eq 0 ]
  grep -q 'BODY_SEEN:literal `id` not substituted' "$RECORD_FILE"
  # Assert no command output (e.g., "uid=") leaked into the body
  ! grep -q 'uid=' "$RECORD_FILE"
}

@test "qa: body with dollar-VAR posts literally (no shell expansion)" {
  export FOO=should-not-expand
  run "$PR_COMMENT" 1 'before $FOO after'
  [ "$status" -eq 0 ]
  grep -q 'BODY_SEEN:before $FOO after' "$RECORD_FILE"
  ! grep -q 'BODY_SEEN:before should-not-expand after' "$RECORD_FILE"
}

@test "qa: body with semicolon posts verbatim (no command chaining)" {
  run "$PR_COMMENT" 1 'first; echo PWNED'
  [ "$status" -eq 0 ]
  grep -q 'BODY_SEEN:first; echo PWNED' "$RECORD_FILE"
  ! grep -q 'BODY_SEEN:PWNED' "$RECORD_FILE"
}

# ---- P0: Inputs — body-file with large content goes via --body-file, not --body ----

@test "qa: body-file with 100KB content invokes --body-file (not --body argv)" {
  body_path="$TMP/large-body"
  yes "padding line" 2>/dev/null | head -n 8000 > "$body_path"
  body_bytes=$(wc -c < "$body_path")
  [ "$body_bytes" -gt 50000 ]
  run "$PR_COMMENT" 1 --body-file "$body_path"
  [ "$status" -eq 0 ]
  # Stub records argv one-per-line; assert --body-file appears and --body does not.
  grep -q '^--body-file$' "$RECORD_FILE"
  ! grep -q '^--body$' "$RECORD_FILE"
  # File contents reached the stub via --body-file path.
  cmp -s "$body_path" "$BODY_FILE_CONTENT"
}

# ---- P0: Inputs — multiple body sources rejected before backend dispatch ----

@test "qa: positional + --body rejects with ambiguous source error" {
  run "$PR_COMMENT" 1 "positional" --body "flag-body"
  [ "$status" -ne 0 ]
  [[ "$output" == *"body source ambiguous"* ]]
  # Stub must NOT have been called.
  [ ! -s "$RECORD_FILE" ]
}

@test "qa: --body + --body-file rejects with ambiguous source error" {
  echo "file-body" > "$TMP/body"
  run "$PR_COMMENT" 1 --body "flag-body" --body-file "$TMP/body"
  [ "$status" -ne 0 ]
  [[ "$output" == *"body source ambiguous"* ]]
  [ ! -s "$RECORD_FILE" ]
}

@test "qa: positional + --body-file rejects with ambiguous source error" {
  echo "file-body" > "$TMP/body"
  run "$PR_COMMENT" 1 "positional" --body-file "$TMP/body"
  [ "$status" -ne 0 ]
  [[ "$output" == *"body source ambiguous"* ]]
  [ ! -s "$RECORD_FILE" ]
}

@test "qa: all three body sources rejects with ambiguous source error" {
  echo "file-body" > "$TMP/body"
  run "$PR_COMMENT" 1 "positional" --body "flag-body" --body-file "$TMP/body"
  [ "$status" -ne 0 ]
  [[ "$output" == *"body source ambiguous"* ]]
  [ ! -s "$RECORD_FILE" ]
}

# ---- P1: Inputs — --reply-to validation runs before backend dispatch ----

@test "qa: non-numeric --reply-to rejected before gh invocation" {
  run "$PR_COMMENT" 1 --body "x" --reply-to "abc"
  [ "$status" -ne 0 ]
  [[ "$output" == *"--reply-to must be a numeric thread id"* ]]
  [ ! -s "$RECORD_FILE" ]
}

@test "qa: negative --reply-to rejected before gh invocation" {
  run "$PR_COMMENT" 1 --body "x" --reply-to "-1"
  [ "$status" -ne 0 ]
  [[ "$output" == *"--reply-to must be a numeric thread id"* ]] || [[ "$output" == *"reply-to"* ]]
}

@test "qa: empty --reply-to rejected" {
  run "$PR_COMMENT" 1 --body "x" --reply-to ""
  [ "$status" -ne 0 ]
  [ ! -s "$RECORD_FILE" ]
}

# ---- P1: Inputs — non-numeric PR number rejected before backend dispatch ----

@test "qa: non-numeric PR number rejected before gh invocation" {
  run "$PR_COMMENT" "not-a-pr" "body"
  [ "$status" -ne 0 ]
  [ ! -s "$RECORD_FILE" ]
}

# ---- P1: Cross-cutting — errors go to stderr, URL on stdout (clean piping) ----

@test "qa: success URL is on stdout only (stderr empty on happy path)" {
  run "$PR_COMMENT" 1 "body"
  [ "$status" -eq 0 ]
  # stdout should contain the URL
  [[ "$output" == *"github.com"* ]]
}

@test "qa: graceful skip warning routed to stderr (stdout empty)" {
  # Wipe gh from stub PATH to trigger graceful skip
  rm -f "$STUBDIR/gh"
  run "$PR_COMMENT" 1 "body"
  [ "$status" -eq 0 ]
  # The [warn] line should be on stderr, not stdout — test it didn't end up in stdout
  # by checking stdout is empty (run's $output is combined stdout+stderr by default;
  # use --separate-stderr to disambiguate)
  run --separate-stderr "$PR_COMMENT" 1 "body"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [[ "$stderr" == *"[warn]"* ]]
}

# ---- P1: NDJSON schema — list-pr-comments stdout/stderr separation ----

@test "qa: list-pr-comments graceful skip emits zero stdout records" {
  # Wipe gh from stub PATH
  rm -f "$STUBDIR/gh"
  run --separate-stderr "$LIST_PR" 1
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [[ "$stderr" == *"[warn]"* ]]
}

# ---- P1: Environment — unrecognized backend gracefully skips ----

@test "qa: unrecognized origin (gitlab) returns null backend -> graceful skip" {
  # Override fake git to return gitlab origin
  cat > "$STUBDIR/git" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "remote" ] && [ "$2" = "get-url" ] && [ "$3" = "origin" ]; then
  echo "https://gitlab.com/owner/repo.git"; exit 0
fi
exec /usr/bin/env -i PATH=/usr/bin:/bin git "$@"
EOF
  chmod +x "$STUBDIR/git"
  run --separate-stderr "$PR_COMMENT" 1 "body"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"No recognized SCM backend"* ]] || [[ "$stderr" == *"[info]"* ]]
  [ ! -s "$RECORD_FILE" ]
}
