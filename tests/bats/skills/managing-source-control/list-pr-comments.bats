#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

# Strip inherited GIT_* env so fixture git calls cannot reach the real repo (#326).
load '../../helpers/git-env'
sanitize_git_env

# Bats fixture for managing-source-control/scripts/list-pr-comments.sh (FEAT-034
# Phase 3 / FR-5).
#
# Strategy: PATH-prepend a STUBDIR containing fake `git`, `gh`, and `az`
# binaries. The fake `git` pass-throughs to real git so backend-detect.sh can
# read the origin URL. The fake `gh` responds to `gh auth status` and to
# `gh api repos/<owner>/<repo>/issues/<pr>/comments`, returning preset JSON
# fixtures based on env vars. The fake `az` covers the repos-show /
# devops-invoke threads-list calls.
#
# Coverage (Phase 3 / FR-5 / FR-6 / Edge 8 / Edge 10 / Edge 13):
#   - GitHub empty PR → zero NDJSON lines + exit 0.
#   - GitHub single comment → one NDJSON record with the FR-5 schema and
#     sentinel ADO-only fields (thread_id=0, parent_comment_id=0,
#     thread_status="unknown", status="active", is_deleted=false).
#   - GitHub multi-comment → multiple NDJSON records in chronological order
#     (response order is preserved).
#   - ADO single thread with multiple comments → comments share the same
#     thread_id; FR-5 fields populated from response.
#   - ADO multi-thread interleave → thread linkage preserved across records.
#   - ADO deleted comment → is_deleted=true on the record (preserved, not
#     filtered).
#   - Null backend (gitlab origin) → zero records + [info] + exit 0.
#   - gh missing → zero records + [warn] + exit 0 (Edge 13).
#   - gh api 404 → zero records + [warn] + exit 0 (Edge 8).
#   - --json flag is a no-op (still NDJSON).
#   - Non-numeric PR number exits non-zero with [error].

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/../../../../plugins/lwndev-sdlc/skills/managing-source-control/scripts" && pwd)"
  LIST_PR_COMMENTS="${SCRIPT_DIR}/list-pr-comments.sh"
  REPO_DIR="$(mktemp -d "${BATS_TMPDIR:-/tmp}/msc-list-pr-comments.XXXXXX")"
  STUBDIR="${REPO_DIR}/bin"
  STATEDIR="${REPO_DIR}/state"
  mkdir -p "$STUBDIR" "$STATEDIR"

  # Capture original PATH + real rm so teardown can recover.
  ORIG_PATH="$PATH"
  REAL_RM="$(command -v rm)"

  cd "$REPO_DIR"
  REAL_GIT="$(command -v git)"
  "$REAL_GIT" init --quiet --initial-branch=main >/dev/null 2>&1 \
    || "$REAL_GIT" init --quiet >/dev/null 2>&1
  "$REAL_GIT" config user.email "test@example.com"
  "$REAL_GIT" config user.name "Test"
  "$REAL_GIT" config commit.gpgsign false

  # Fake `git`: pass through to real git.
  cat > "${STUBDIR}/git" <<STUBEOF
#!/usr/bin/env bash
exec "${REAL_GIT}" "\$@"
STUBEOF
  chmod +x "${STUBDIR}/git"

  # Fake `gh`: covers `gh auth status` and `gh api repos/.../issues/<pr>/comments`.
  cat > "${STUBDIR}/gh" <<STUBEOF
#!/usr/bin/env bash
echo "gh \$*" >> "${STATEDIR}/gh.log"
case "\$1" in
  auth)
    if [ -n "\${GH_NOT_AUTH:-}" ]; then
      echo "not authenticated" >&2
      exit 1
    fi
    exit 0
    ;;
  api)
    # \$2 looks like 'repos/<owner>/<repo>/issues/<pr>/comments'
    if [ -n "\${GH_API_FAIL:-}" ]; then
      echo "HTTP 404: Not Found" >&2
      exit 1
    fi
    case "\${GH_FIXTURE:-empty}" in
      empty)
        printf '[]'
        ;;
      single)
        cat <<'JSONEOF'
[
  {"id":11,"user":{"login":"alice"},"created_at":"2026-05-17T10:14:22Z","body":"First review note"}
]
JSONEOF
        ;;
      multi)
        cat <<'JSONEOF'
[
  {"id":11,"user":{"login":"alice"},"created_at":"2026-05-17T10:14:22Z","body":"First review note"},
  {"id":12,"user":{"login":"bob"},"created_at":"2026-05-17T10:21:09Z","body":"Done in abc123."},
  {"id":13,"user":{"login":"carol"},"created_at":"2026-05-17T10:35:42Z","body":"LGTM"}
]
JSONEOF
        ;;
    esac
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
STUBEOF
  chmod +x "${STUBDIR}/gh"

  # Fake `az`: covers `repos show`, `repos pr -h`, `account show`,
  # `devops invoke` (probe + threads-list).
  cat > "${STUBDIR}/az" <<STUBEOF
#!/usr/bin/env bash
echo "az \$*" >> "${STATEDIR}/az.log"

# Help probe.
if [ "\$1" = "repos" ] && [ "\$2" = "pr" ] && [ "\$3" = "-h" ]; then
  if [ -n "\${AZ_EXT_MISSING:-}" ]; then
    echo "extension missing" >&2
    exit 1
  fi
  echo "az repos pr help"
  exit 0
fi

# Auth probe.
if [ "\$1" = "account" ] && [ "\$2" = "show" ]; then
  if [ -n "\${AZ_NOT_AUTH:-}" ]; then
    echo "not authenticated" >&2
    exit 1
  fi
  exit 0
fi

# Repo show: emit fixed UUID.
if [ "\$1" = "repos" ] && [ "\$2" = "show" ]; then
  if [ -n "\${AZ_REPO_SHOW_FAIL:-}" ]; then
    echo "az repos show failed" >&2
    exit 1
  fi
  echo "00000000-0000-0000-0000-00000000beef"
  exit 0
fi

# devops invoke.
if [ "\$1" = "devops" ] && [ "\$2" = "invoke" ]; then
  resource=""
  method=""
  while [ "\$#" -gt 0 ]; do
    case "\$1" in
      --resource)     resource="\$2"; shift 2 ;;
      --http-method)  method="\$2"; shift 2 ;;
      *)              shift ;;
    esac
  done

  # Probe path: GET with no payload. Trace mode + emit empty value list
  # so the probe accepts the resource token.
  if [ "\$method" = "GET" ]; then
    # If a probe-only fixture wants to force a particular candidate to "win",
    # gate on AZ_PROBE_MODE=first|second|third. By default (empty), all
    # candidates succeed.
    case "\${AZ_PROBE_MODE:-any}" in
      first)
        [ "\$resource" = "PullRequestThreads" ] || exit 1
        ;;
      second)
        [ "\$resource" = "PullRequestThreads" ] && exit 1
        [ "\$resource" = "pullrequestthreads" ] || exit 1
        ;;
      third)
        [ "\$resource" = "threads" ] || exit 1
        ;;
      any|*) ;;
    esac

    # Now we are EITHER in the probe round OR in the real threads-list call.
    # We disambiguate by counting: pr-comment.sh's probe discards stdout, so
    # the value of stdout is only consumed on the real call. It is safe to
    # always emit the AZ_THREADS_FIXTURE body since the probe ignores it.
    case "\${AZ_THREADS_FIXTURE:-empty}" in
      empty)
        echo '{"value":[],"count":0}'
        ;;
      single-thread)
        cat <<'JSONEOF'
{
  "value": [
    {
      "id": 9,
      "status": "active",
      "comments": [
        {"id":17,"parentCommentId":0,"commentType":1,"author":{"displayName":"Alice","uniqueName":"alice@example.com"},"publishedDate":"2026-05-17T10:14:22Z","content":"Please rename foo to bar.","isDeleted":false},
        {"id":18,"parentCommentId":17,"commentType":1,"author":{"displayName":"Bob","uniqueName":"bob@example.com"},"publishedDate":"2026-05-17T10:21:09Z","content":"Done in abc123.","isDeleted":false}
      ]
    }
  ],
  "count": 1
}
JSONEOF
        ;;
      multi-thread)
        cat <<'JSONEOF'
{
  "value": [
    {
      "id": 9,
      "status": "active",
      "comments": [
        {"id":17,"parentCommentId":0,"commentType":1,"author":{"displayName":"Alice","uniqueName":"alice@example.com"},"publishedDate":"2026-05-17T10:14:22Z","content":"Thread-9 first","isDeleted":false},
        {"id":18,"parentCommentId":17,"commentType":1,"author":{"displayName":"Bob","uniqueName":"bob@example.com"},"publishedDate":"2026-05-17T10:21:09Z","content":"Thread-9 second","isDeleted":false}
      ]
    },
    {
      "id": 10,
      "status": "fixed",
      "comments": [
        {"id":19,"parentCommentId":0,"commentType":1,"author":{"displayName":"Carol","uniqueName":"carol@example.com"},"publishedDate":"2026-05-17T11:00:00Z","content":"Thread-10 first","isDeleted":false}
      ]
    }
  ],
  "count": 2
}
JSONEOF
        ;;
      deleted)
        cat <<'JSONEOF'
{
  "value": [
    {
      "id": 9,
      "status": "active",
      "comments": [
        {"id":17,"parentCommentId":0,"commentType":1,"author":{"displayName":"Alice","uniqueName":"alice@example.com"},"publishedDate":"2026-05-17T10:14:22Z","content":"Live comment","isDeleted":false},
        {"id":18,"parentCommentId":17,"commentType":1,"author":{"displayName":"Bob","uniqueName":"bob@example.com"},"publishedDate":"2026-05-17T10:21:09Z","content":"Deleted comment","isDeleted":true}
      ]
    }
  ],
  "count": 1
}
JSONEOF
        ;;
    esac
    exit 0
  fi

  exit 0
fi

exit 0
STUBEOF
  chmod +x "${STUBDIR}/az"

  # Symlink core utilities the script + backend-detect need.
  for _tool in bash dirname jq date base64 head sed tr cat mktemp cp mv rm chmod grep awk touch ls printf env id sleep; do
    _real="$(command -v "$_tool" 2>/dev/null || true)"
    if [ -n "$_real" ]; then
      ln -sf "$_real" "${STUBDIR}/${_tool}"
    fi
  done

  PATH="${STUBDIR}"
  export PATH
  unset GH_NOT_AUTH GH_API_FAIL GH_FIXTURE
  unset AZ_EXT_MISSING AZ_NOT_AUTH AZ_REPO_SHOW_FAIL
  unset AZ_PROBE_MODE AZ_THREADS_FIXTURE SDLC_SCM_BACKEND

  # Use a distinct org/repo from pr-comment-azdo.bats to avoid cache-file races
  # under bats --jobs parallelism. The cache file path is keyed off
  # <org>.<repo> by the script, so a unique org gives us an isolated cache.
  AZDO_TEST_ORG="contoso-listpr"
  AZDO_TEST_REPO="plugin-repo"
  CACHE_FILE="/tmp/sdlc-azdo-pr-thread-resource.${AZDO_TEST_ORG}.${AZDO_TEST_REPO}"

  # Pre-populate the probe cache so the ADO branch skips the probe round and
  # the GET-shape stub only gets exercised for the real threads-list call.
  printf '%s\n%s\n' "$(date +%s)" "PullRequestThreads" > "$CACHE_FILE"
}

teardown() {
  cd /
  "$REAL_RM" -rf "$REPO_DIR"
  "$REAL_RM" -f "$CACHE_FILE"
  PATH="$ORIG_PATH"
  export PATH
}

set_origin() {
  "$REAL_GIT" -C "$REPO_DIR" remote remove origin >/dev/null 2>&1 || true
  "$REAL_GIT" -C "$REPO_DIR" remote add origin "$1"
}

# ---------- usage ----------

@test "missing pr-number → usage error, exit 2" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  run --separate-stderr bash "$LIST_PR_COMMENTS"
  [ "$status" -eq 2 ]
}

@test "non-numeric pr-number → [error] + exit 2" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  run --separate-stderr bash "$LIST_PR_COMMENTS" "abc"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"[error] pr-number must be a numeric PR identifier"* ]]
}

@test "--json flag is a no-op (still NDJSON output)" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  GH_FIXTURE=single run bash "$LIST_PR_COMMENTS" 127 --json
  [ "$status" -eq 0 ]
  # Exactly one record.
  [ "$(printf '%s\n' "$output" | grep -c '^{')" -eq 1 ]
}

# ---------- GitHub branch ----------

@test "github empty PR → zero NDJSON lines, exit 0" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  GH_FIXTURE=empty run bash "$LIST_PR_COMMENTS" 127
  [ "$status" -eq 0 ]
  # No records on stdout. (Empty output OR empty after trim.)
  [ -z "$(printf '%s' "$output" | tr -d '[:space:]')" ]
}

@test "github single comment → one FR-5 NDJSON record with sentinels" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  GH_FIXTURE=single run bash "$LIST_PR_COMMENTS" 127
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '^{')" -eq 1 ]
  line="$(printf '%s\n' "$output" | head -n 1)"
  # FR-5 schema check (sentinels for thread-aware fields).
  echo "$line" | jq -e '
    .thread_id == 0
    and .comment_id == 11
    and .parent_comment_id == 0
    and .author == "alice"
    and .author_unique_name == "alice"
    and .published == "2026-05-17T10:14:22Z"
    and .content == "First review note"
    and .status == "active"
    and .is_deleted == false
    and .thread_status == "unknown"
  ' >/dev/null
}

@test "github multi-comment → multiple NDJSON records in chronological order" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  GH_FIXTURE=multi run bash "$LIST_PR_COMMENTS" 127
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '^{')" -eq 3 ]
  # Order preserved from gh api response (chronological).
  first_id="$(printf '%s\n' "$output"  | head -n 1 | jq -r '.comment_id')"
  second_id="$(printf '%s\n' "$output" | sed -n '2p' | jq -r '.comment_id')"
  third_id="$(printf '%s\n' "$output"  | sed -n '3p' | jq -r '.comment_id')"
  [ "$first_id" = "11" ]
  [ "$second_id" = "12" ]
  [ "$third_id" = "13" ]
}

# ---------- Edge 13 / 8: GitHub graceful skips ----------

@test "gh absent (github origin) → zero records + [warn] + exit 0" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  rm -f "${STUBDIR}/gh"
  run --separate-stderr env PATH="${STUBDIR}" bash "$LIST_PR_COMMENTS" 127
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] GitHub CLI (gh) not found on PATH."* ]]
  [ -z "$(printf '%s' "$output" | tr -d '[:space:]')" ]
}

@test "gh auth failing → zero records + [warn] + exit 0" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  GH_NOT_AUTH=1 run --separate-stderr bash "$LIST_PR_COMMENTS" 127
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] GitHub CLI not authenticated"* ]]
  [ -z "$(printf '%s' "$output" | tr -d '[:space:]')" ]
}

@test "gh api 404 → zero records + [warn] + exit 0" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  GH_API_FAIL=1 run --separate-stderr bash "$LIST_PR_COMMENTS" 9999
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] PR 9999 not found on github; skipping comment."* ]]
  [ -z "$(printf '%s' "$output" | tr -d '[:space:]')" ]
}

# ---------- ADO branch ----------

@test "azdo single-thread multi-comment → comments share thread_id" {
  set_origin "https://dev.azure.com/${AZDO_TEST_ORG}/sdlc-tools/_git/${AZDO_TEST_REPO}"
  AZ_THREADS_FIXTURE=single-thread run bash "$LIST_PR_COMMENTS" 42
  [ "$status" -eq 0 ] || { >&3 echo "OUT=$output"; false; }
  [ "$(printf '%s\n' "$output" | grep -c '^{')" -eq 2 ]
  first="$(printf '%s\n' "$output" | head -n 1)"
  second="$(printf '%s\n' "$output" | sed -n '2p')"
  echo "$first" | jq -e '
    .thread_id == 9
    and .comment_id == 17
    and .parent_comment_id == 0
    and .author == "Alice"
    and .author_unique_name == "alice@example.com"
    and .published == "2026-05-17T10:14:22Z"
    and .status == "active"
    and .is_deleted == false
    and .thread_status == "active"
  ' >/dev/null
  echo "$second" | jq -e '
    .thread_id == 9
    and .comment_id == 18
    and .parent_comment_id == 17
    and .author == "Bob"
    and .is_deleted == false
  ' >/dev/null
}

@test "azdo multi-thread interleave → thread linkage preserved" {
  set_origin "https://dev.azure.com/${AZDO_TEST_ORG}/sdlc-tools/_git/${AZDO_TEST_REPO}"
  AZ_THREADS_FIXTURE=multi-thread run bash "$LIST_PR_COMMENTS" 42
  [ "$status" -eq 0 ] || { >&3 echo "OUT=$output"; false; }
  [ "$(printf '%s\n' "$output" | grep -c '^{')" -eq 3 ]
  # Records 1,2 share thread_id=9; record 3 has thread_id=10 with thread_status "fixed".
  t1="$(printf '%s\n' "$output" | head -n 1 | jq -r '.thread_id')"
  t2="$(printf '%s\n' "$output" | sed -n '2p' | jq -r '.thread_id')"
  t3="$(printf '%s\n' "$output" | sed -n '3p' | jq -r '.thread_id')"
  ts3="$(printf '%s\n' "$output" | sed -n '3p' | jq -r '.thread_status')"
  [ "$t1" = "9" ]
  [ "$t2" = "9" ]
  [ "$t3" = "10" ]
  [ "$ts3" = "fixed" ]
}

@test "azdo deleted-comment row carries is_deleted: true" {
  set_origin "https://dev.azure.com/${AZDO_TEST_ORG}/sdlc-tools/_git/${AZDO_TEST_REPO}"
  AZ_THREADS_FIXTURE=deleted run bash "$LIST_PR_COMMENTS" 42
  [ "$status" -eq 0 ] || { >&3 echo "OUT=$output"; false; }
  [ "$(printf '%s\n' "$output" | grep -c '^{')" -eq 2 ]
  live="$(printf '%s\n' "$output" | head -n 1)"
  deleted="$(printf '%s\n' "$output" | sed -n '2p')"
  echo "$live" | jq -e '.is_deleted == false' >/dev/null
  echo "$deleted" | jq -e '.is_deleted == true and .comment_id == 18' >/dev/null
}

@test "azdo empty threads list → zero NDJSON lines, exit 0" {
  set_origin "https://dev.azure.com/${AZDO_TEST_ORG}/sdlc-tools/_git/${AZDO_TEST_REPO}"
  AZ_THREADS_FIXTURE=empty run bash "$LIST_PR_COMMENTS" 42
  [ "$status" -eq 0 ]
  [ -z "$(printf '%s' "$output" | tr -d '[:space:]')" ]
}

@test "azdo probe cache is hit (no GET probe re-issued) after Phase 2 populated it" {
  set_origin "https://dev.azure.com/${AZDO_TEST_ORG}/sdlc-tools/_git/${AZDO_TEST_REPO}"
  # The cache file is pre-populated by setup(). Use AZ_PROBE_MODE=first so that
  # if the probe DID run, only PullRequestThreads would succeed — we just want
  # to assert the threads-list call ran without re-probing the other tokens.
  AZ_THREADS_FIXTURE=single-thread AZ_PROBE_MODE=first \
    run bash "$LIST_PR_COMMENTS" 42
  [ "$status" -eq 0 ]
  # With fresh cache there should be exactly one GET (the real threads-list
  # call) — assert by checking the az.log GET count.
  get_count="$(grep -c -- '--http-method GET' "${STATEDIR}/az.log" || true)"
  [ "$get_count" = "1" ] || { >&3 echo "az.log:"; >&3 cat "${STATEDIR}/az.log"; false; }
}

@test "azdo probe-cache write is atomic (no .tmp residue after success)" {
  set_origin "https://dev.azure.com/${AZDO_TEST_ORG}/sdlc-tools/_git/${AZDO_TEST_REPO}"
  # Clear the cache pre-populated by setup() so the probe path actually runs.
  rm -f "$CACHE_FILE" "${CACHE_FILE}.tmp"
  AZ_THREADS_FIXTURE=single-thread AZ_PROBE_MODE=first \
    run bash "$LIST_PR_COMMENTS" 42
  [ "$status" -eq 0 ] || { >&3 echo "OUT=$output"; false; }
  [ -f "$CACHE_FILE" ]
  payload="$(sed -n '2p' "$CACHE_FILE")"
  [ "$payload" = "PullRequestThreads" ]
  # The `.tmp` staging file must be renamed away on success.
  [ ! -f "${CACHE_FILE}.tmp" ]
}

# ---------- ADO NFR-1 graceful skips ----------

@test "azdo: az absent → zero records + [warn] + exit 0" {
  set_origin "https://dev.azure.com/${AZDO_TEST_ORG}/sdlc-tools/_git/${AZDO_TEST_REPO}"
  rm -f "${STUBDIR}/az"
  run --separate-stderr bash "$LIST_PR_COMMENTS" 42
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] Azure CLI (az) not found on PATH."* ]]
  [ -z "$(printf '%s' "$output" | tr -d '[:space:]')" ]
}

@test "azdo: az devops extension missing → [warn] + exit 0" {
  set_origin "https://dev.azure.com/${AZDO_TEST_ORG}/sdlc-tools/_git/${AZDO_TEST_REPO}"
  AZ_EXT_MISSING=1 run --separate-stderr bash "$LIST_PR_COMMENTS" 42
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] az devops extension not available"* ]]
}

@test "azdo: az not authenticated → [warn] + exit 0" {
  set_origin "https://dev.azure.com/${AZDO_TEST_ORG}/sdlc-tools/_git/${AZDO_TEST_REPO}"
  AZ_NOT_AUTH=1 run --separate-stderr bash "$LIST_PR_COMMENTS" 42
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] Azure CLI not authenticated"* ]]
}

@test "azdo: cached probe-failed sentinel → [warn] + zero records + exit 0" {
  set_origin "https://dev.azure.com/${AZDO_TEST_ORG}/sdlc-tools/_git/${AZDO_TEST_REPO}"
  cache="$CACHE_FILE"
  now="$(date +%s)"
  printf '%s\n%s\n' "$now" "probe-failed" > "$cache"
  run --separate-stderr bash "$LIST_PR_COMMENTS" 42
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] ADO PR-thread resource probe failed across [PullRequestThreads, pullrequestthreads, threads]. Skipping comment."* ]]
  [ -z "$(printf '%s' "$output" | tr -d '[:space:]')" ]
}

# ---------- Edge 13: null backend ----------

@test "null backend (gitlab origin) → zero records + [info] + exit 0" {
  set_origin "https://gitlab.com/foo/bar.git"
  run --separate-stderr bash "$LIST_PR_COMMENTS" 42
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[info] No recognized SCM backend detected from origin. Skipping PR comment."* ]]
  [ -z "$(printf '%s' "$output" | tr -d '[:space:]')" ]
}
