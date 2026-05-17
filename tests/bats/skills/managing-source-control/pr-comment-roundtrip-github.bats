#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# Round-trip integration test: pr-comment.sh + list-pr-comments.sh against a
# real GitHub PR (FEAT-034 Phase 5).
#
# IMPORTANT: This test posts a real comment to a real GitHub PR and does NOT
# clean it up. Use a sacrificial / scratch PR on a repo you control. The
# comment body is a generated GUID so it is easy to identify test noise.
#
# Required env vars (set to run; absent = skipped):
#   SDLC_INTEGRATION_GITHUB_PR_URL — full URL of an open GitHub PR on a repo
#     you have write access to, e.g.:
#     https://github.com/example/my-repo/pull/42
#   gh auth login must already be complete in the shell that runs the test.
#
# Run a single file (no GNU parallel needed):
#   npx bats tests/bats/skills/managing-source-control/pr-comment-roundtrip-github.bats

setup_file() {
  if [ -z "${SDLC_INTEGRATION_GITHUB_PR_URL:-}" ]; then
    skip "set SDLC_INTEGRATION_GITHUB_PR_URL to run the GitHub round-trip integration test"
  fi
}

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/../../../../plugins/lwndev-sdlc/skills/managing-source-control/scripts" && pwd)"
  PR_COMMENT="${SCRIPT_DIR}/pr-comment.sh"
  LIST_PR_COMMENTS="${SCRIPT_DIR}/list-pr-comments.sh"

  # Parse PR number from the URL.
  # Handles both .../pull/<n> and .../pullrequest/<n> patterns.
  PR_URL="${SDLC_INTEGRATION_GITHUB_PR_URL}"
  PR_NUMBER="$(printf '%s' "$PR_URL" | grep -oE '/pull/[0-9]+' | grep -oE '[0-9]+' | head -1)"
  if [ -z "$PR_NUMBER" ]; then
    skip "could not parse a PR number from SDLC_INTEGRATION_GITHUB_PR_URL=${PR_URL}"
  fi

  # We need the test to run from within a clone of the target repo so that
  # backend-detect.sh reads the correct origin. The URL itself tells us the
  # repo: strip the /pull/<n> suffix to get the repo web URL, then convert to
  # a .git clone URL.
  REPO_URL="$(printf '%s' "$PR_URL" | sed 's|/pull/[0-9]*||')"
  WORK_DIR="$(mktemp -d "${BATS_TMPDIR:-/tmp}/msc-rt-github.XXXXXX")"

  git clone --quiet --depth=1 "${REPO_URL}.git" "${WORK_DIR}/repo" 2>/dev/null \
    || { skip "could not clone ${REPO_URL}.git — ensure gh auth is valid and SDLC_INTEGRATION_GITHUB_PR_URL points to an accessible repo"; }

  REPO_DIR="${WORK_DIR}/repo"
  cd "$REPO_DIR"

  # Generate a GUID body to uniquely identify this test's comment.
  if command -v uuidgen >/dev/null 2>&1; then
    GUID="sdlc-rt-github-$(uuidgen | tr '[:upper:]' '[:lower:]')"
  elif [ -r /proc/sys/kernel/random/uuid ]; then
    GUID="sdlc-rt-github-$(cat /proc/sys/kernel/random/uuid)"
  else
    GUID="sdlc-rt-github-$(date +%s)-$$"
  fi
}

teardown() {
  cd /
  rm -rf "$WORK_DIR"
  # NOTE: comments posted to the PR are intentionally NOT cleaned up.
  # Use a sacrificial / scratch PR only.
}

# ---------- Round-trip: post a comment, list it, assert presence ----------

@test "GitHub round-trip: post comment, list, assert GUID present in NDJSON" {
  # Post the comment; capture the returned URL.
  run bash "$PR_COMMENT" "$PR_NUMBER" "$GUID"
  if [ "$status" -ne 0 ]; then
    >&3 echo "pr-comment.sh exit=${status} output=${output}"
    false
  fi
  # Output should be a GitHub comment URL.
  [[ "$output" == *"github.com"* ]] || { >&3 echo "Unexpected output: ${output}"; false; }

  # Allow a short moment for GitHub to index the comment.
  sleep 2

  # List comments; grep for the GUID.
  run bash "$LIST_PR_COMMENTS" "$PR_NUMBER"
  if [ "$status" -ne 0 ]; then
    >&3 echo "list-pr-comments.sh exit=${status} output=${output}"
    false
  fi
  # Each line is an NDJSON record; the GUID must appear in at least one.
  if ! printf '%s\n' "$output" | grep -qF "$GUID"; then
    >&3 echo "GUID not found in list output:"
    >&3 printf '%s\n' "$output"
    false
  fi
  # Validate FR-5 schema on the matching record.
  matching_record="$(printf '%s\n' "$output" | grep -F "$GUID" | head -1)"
  printf '%s' "$matching_record" | jq -e '
    has("thread_id") and has("comment_id") and has("author") and
    has("published") and has("content") and has("status") and
    has("is_deleted") and has("thread_status")
  ' >/dev/null || { >&3 echo "FR-5 schema check failed on: ${matching_record}"; false; }
}
