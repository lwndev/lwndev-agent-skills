#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

# Strip inherited GIT_* env so fixture git calls cannot reach the real repo (#326).
load "${BATS_TEST_DIRNAME%/tests/bats/*}/tests/bats/helpers/git-env"

# Round-trip integration test: pr-comment.sh + list-pr-comments.sh against a
# real Azure DevOps PR (FEAT-034 Phase 5).
#
# IMPORTANT: This test posts real comments to a real ADO PR and does NOT clean
# them up. Use a sacrificial / scratch PR on a project you control. Comment
# bodies are generated GUIDs so they are easy to identify as test noise.
#
# Required env vars (absent = skipped):
#   SDLC_INTEGRATION_AZDO_PR_URL — full URL of an open ADO PR you have write
#     access to, e.g.:
#     https://dev.azure.com/myorg/myproject/_git/myrepo/pullrequest/42
#   AZURE_DEVOPS_PAT — Personal Access Token with at minimum the
#     vso.code_write scope (also needed for the raw-HTTP curl path).
#
# The az CLI must already be authenticated (az login) or az devops login
# must have been run with this PAT. The ADO extension must be installed
# (az extension add --name azure-devops).
#
# Run a single file (no GNU parallel needed):
#   SDLC_INTEGRATION_AZDO_PR_URL=... AZURE_DEVOPS_PAT=... \
#   npx bats tests/bats/skills/managing-source-control/pr-comment-roundtrip-azdo.bats

setup_file() {
  if [ -z "${SDLC_INTEGRATION_AZDO_PR_URL:-}" ]; then
    skip "set SDLC_INTEGRATION_AZDO_PR_URL to run the ADO round-trip integration test"
  fi
  if [ -z "${AZURE_DEVOPS_PAT:-}" ]; then
    skip "set AZURE_DEVOPS_PAT (scope: vso.code_write) to run the ADO round-trip integration test"
  fi
}

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/../../../../plugins/lwndev-sdlc/skills/managing-source-control/scripts" && pwd)"
  PR_COMMENT="${SCRIPT_DIR}/pr-comment.sh"
  LIST_PR_COMMENTS="${SCRIPT_DIR}/list-pr-comments.sh"

  # Parse PR number from the URL.
  # ADO URLs end with /pullrequest/<n>
  PR_URL="${SDLC_INTEGRATION_AZDO_PR_URL}"
  PR_NUMBER="$(printf '%s' "$PR_URL" | grep -oE '/pullrequest/[0-9]+' | grep -oE '[0-9]+' | head -1)"
  if [ -z "$PR_NUMBER" ]; then
    skip "could not parse a PR number from SDLC_INTEGRATION_AZDO_PR_URL=${PR_URL}"
  fi

  # Derive the clone URL from the PR URL.
  # https://dev.azure.com/<org>/<project>/_git/<repo>/pullrequest/<n>
  #   -> https://dev.azure.com/<org>/<project>/_git/<repo>
  CLONE_URL="$(printf '%s' "$PR_URL" | sed 's|/pullrequest/[0-9]*||')"

  WORK_DIR="$(mktemp -d "${BATS_TMPDIR:-/tmp}/msc-rt-azdo.XXXXXX")"

  # Clone using the PAT for authentication (inline credential in URL).
  PAT_CLONE_URL="$(printf '%s' "$CLONE_URL" | sed "s|https://|https://anything:${AZURE_DEVOPS_PAT}@|")"
  git clone --quiet --depth=1 "$PAT_CLONE_URL" "${WORK_DIR}/repo" 2>/dev/null \
    || { skip "could not clone ${CLONE_URL} — verify AZURE_DEVOPS_PAT and SDLC_INTEGRATION_AZDO_PR_URL"; }

  REPO_DIR="${WORK_DIR}/repo"
  cd "$REPO_DIR"

  # Generate two unique GUIDs: one for the top-level comment, one for the reply.
  if command -v uuidgen >/dev/null 2>&1; then
    GUID_TOP="sdlc-rt-azdo-top-$(uuidgen | tr '[:upper:]' '[:lower:]')"
    GUID_REPLY="sdlc-rt-azdo-reply-$(uuidgen | tr '[:upper:]' '[:lower:]')"
  elif [ -r /proc/sys/kernel/random/uuid ]; then
    GUID_TOP="sdlc-rt-azdo-top-$(cat /proc/sys/kernel/random/uuid)"
    GUID_REPLY="sdlc-rt-azdo-reply-$(cat /proc/sys/kernel/random/uuid)"
  else
    GUID_TOP="sdlc-rt-azdo-top-$(date +%s)-$$"
    GUID_REPLY="sdlc-rt-azdo-reply-$(date +%s)-$(($$+1))"
  fi
}

teardown() {
  cd /
  rm -rf "$WORK_DIR"
  # NOTE: comments posted to the PR are intentionally NOT cleaned up.
  # Use a sacrificial / scratch PR only.
}

# ---------- Round-trip: top-level + reply, then list and assert ----------

@test "ADO round-trip: post top-level comment, post reply, list, assert GUIDs + thread linkage" {
  # 1. Post a top-level comment.
  run bash "$PR_COMMENT" "$PR_NUMBER" "$GUID_TOP"
  if [ "$status" -ne 0 ]; then
    >&3 echo "top-level pr-comment.sh exit=${status} output=${output}"
    false
  fi
  # Output is the PR URL with ?discussionId=<threadId>
  [[ "$output" == *"?discussionId="* ]] || { >&3 echo "Unexpected top-level output: ${output}"; false; }

  # Parse the discussionId (= thread id) from the URL.
  DISCUSSION_ID="$(printf '%s' "$output" | grep -oE 'discussionId=[0-9]+' | grep -oE '[0-9]+')"
  if [ -z "$DISCUSSION_ID" ]; then
    >&3 echo "Could not parse discussionId from: ${output}"
    false
  fi

  # 2. Post a reply to the newly created thread.
  run bash "$PR_COMMENT" "$PR_NUMBER" --body "$GUID_REPLY" --reply-to "$DISCUSSION_ID"
  if [ "$status" -ne 0 ]; then
    >&3 echo "reply pr-comment.sh exit=${status} output=${output}"
    false
  fi
  [[ "$output" == *"?discussionId=${DISCUSSION_ID}"* ]] \
    || { >&3 echo "Unexpected reply output: ${output}"; false; }

  # Allow ADO a moment to settle.
  sleep 2

  # 3. List all comments on the PR.
  run bash "$LIST_PR_COMMENTS" "$PR_NUMBER"
  if [ "$status" -ne 0 ]; then
    >&3 echo "list-pr-comments.sh exit=${status} output=${output}"
    false
  fi

  # 4. Assert both GUIDs appear in the NDJSON output.
  if ! printf '%s\n' "$output" | grep -qF "$GUID_TOP"; then
    >&3 echo "Top-level GUID not found. List output:"
    >&3 printf '%s\n' "$output"
    false
  fi
  if ! printf '%s\n' "$output" | grep -qF "$GUID_REPLY"; then
    >&3 echo "Reply GUID not found. List output:"
    >&3 printf '%s\n' "$output"
    false
  fi

  # 5. Extract the two matching records.
  top_record="$(printf '%s\n' "$output" | grep -F "$GUID_TOP" | head -1)"
  reply_record="$(printf '%s\n' "$output" | grep -F "$GUID_REPLY" | head -1)"

  # 6. Both must share the same thread_id.
  top_thread_id="$(printf '%s' "$top_record" | jq -r '.thread_id')"
  reply_thread_id="$(printf '%s' "$reply_record" | jq -r '.thread_id')"
  if [ "$top_thread_id" != "$DISCUSSION_ID" ]; then
    >&3 echo "Top record thread_id=${top_thread_id} does not match discussionId=${DISCUSSION_ID}"
    >&3 echo "top_record=${top_record}"
    false
  fi
  if [ "$reply_thread_id" != "$DISCUSSION_ID" ]; then
    >&3 echo "Reply record thread_id=${reply_thread_id} does not match discussionId=${DISCUSSION_ID}"
    >&3 echo "reply_record=${reply_record}"
    false
  fi

  # 7. The reply's parent_comment_id must be > 0 (the id of the original comment
  #    in the thread, resolved by pr-comment.sh's reply path).
  reply_parent="$(printf '%s' "$reply_record" | jq -r '.parent_comment_id')"
  top_comment_id="$(printf '%s' "$top_record" | jq -r '.comment_id')"
  if [ "${reply_parent:-0}" -le 0 ] 2>/dev/null; then
    >&3 echo "Reply parent_comment_id=${reply_parent} should be > 0 (should reference the original comment)"
    >&3 echo "top_record=${top_record}"
    >&3 echo "reply_record=${reply_record}"
    false
  fi
  # reply's parent_comment_id should equal the top comment's comment_id.
  if [ "$reply_parent" != "$top_comment_id" ]; then
    >&3 echo "reply parent_comment_id=${reply_parent} != top comment_id=${top_comment_id}"
    >&3 echo "top_record=${top_record}"
    >&3 echo "reply_record=${reply_record}"
    false
  fi

  # 8. FR-5 schema check on both records.
  for rec in "$top_record" "$reply_record"; do
    printf '%s' "$rec" | jq -e '
      has("thread_id") and has("comment_id") and has("parent_comment_id") and
      has("author") and has("published") and has("content") and
      has("status") and has("is_deleted") and has("thread_status")
    ' >/dev/null || { >&3 echo "FR-5 schema check failed on: ${rec}"; false; }
  done
}
