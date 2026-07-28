#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

# Strip inherited GIT_* env so fixture git calls cannot reach the real repo (#326).
load "${BATS_TEST_DIRNAME%/tests/bats/*}/tests/bats/helpers/git-env"

# Bats fixture for managing-source-control/scripts/pr-comment.sh (FEAT-034 Phase 2 ADO branch).
#
# Strategy: PATH-prepend a STUBDIR containing fake `git`, `az`, and `curl`
# binaries. The fake `git` passes through to real git so backend-detect.sh
# can read the origin URL. The fake `az` covers `repos show`, `account show`,
# `repos pr -h`, `devops invoke` (GET probe + GET thread + POST thread + POST
# reply), responding deterministically based on $AZ_PROBE_MODE, $AZ_THREAD_*,
# and other env vars. The fake `curl` responds to the raw-HTTP fallback.
#
# Coverage (Phase 2 / FR-2 / FR-3 / FR-4 / NFR-3 / Edge 4 / Edge 6):
#   - Top-level thread create returns the formatted discussion URL.
#   - Reply resolves parentCommentId from listed comments (max id).
#   - Reply on empty thread uses parentCommentId 0.
#   - --reply-to on missing thread emits [warn] + exits 0.
#   - Probe hits PullRequestThreads first try (cache populated).
#   - Probe hits pullrequestthreads on second try.
#   - Probe hits threads on third try.
#   - Probe-failure writes probe-failed sentinel + [warn] + exits 0.
#   - Cache-hit short-circuits the probe within 24h.
#   - Cache invalidates past 24h TTL (probe runs again).
#   - Missing AZURE_DEVOPS_PAT on forced-curl path emits [warn] + exits 0.
#   - az devops invoke POST failure auto-falls-back to curl when PAT set.
#   - NFR-1 graceful skips: az missing, az devops ext missing, az not logged in.

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/../../../../plugins/lwndev-sdlc/skills/managing-source-control/scripts" && pwd)"
  PR_COMMENT="${SCRIPT_DIR}/pr-comment.sh"
  REPO_DIR="$(mktemp -d "${BATS_TMPDIR:-/tmp}/msc-pr-comment-azdo.XXXXXX")"
  STUBDIR="${REPO_DIR}/bin"
  STATEDIR="${REPO_DIR}/state"
  mkdir -p "$STUBDIR" "$STATEDIR"

  # Capture the original PATH + real binary paths BEFORE we restrict PATH so
  # teardown can restore the host PATH for bats' internal cleanup (which uses
  # `rm` etc. via the in-process PATH the test leaves behind).
  ORIG_PATH="$PATH"
  REAL_RM="$(command -v rm)"

  cd "$REPO_DIR"
  REAL_GIT="$(command -v git)"
  "$REAL_GIT" init --quiet --initial-branch=main >/dev/null 2>&1 \
    || "$REAL_GIT" init --quiet >/dev/null 2>&1
  "$REAL_GIT" config user.email "test@example.com"
  "$REAL_GIT" config user.name "Test"
  "$REAL_GIT" config commit.gpgsign false

  # Fake `git`: pass-through to real git (script doesn't push, only reads remote URL).
  cat > "${STUBDIR}/git" <<STUBEOF
#!/usr/bin/env bash
exec "${REAL_GIT}" "\$@"
STUBEOF
  chmod +x "${STUBDIR}/git"

  # Fake `az`: cover the four invocation shapes used by pr-comment.sh.
  cat > "${STUBDIR}/az" <<STUBEOF
#!/usr/bin/env bash
# Trace each invocation for assertions.
echo "az \$*" >> "${STATEDIR}/az.log"

# 1. \`az repos pr -h\` — extension probe.
if [ "\$1" = "repos" ] && [ "\$2" = "pr" ] && [ "\$3" = "-h" ]; then
  if [ -n "\${AZ_EXT_MISSING:-}" ]; then
    echo "extension missing" >&2
    exit 1
  fi
  echo "az repos pr help"
  exit 0
fi

# 2. \`az account show\` — auth probe.
if [ "\$1" = "account" ] && [ "\$2" = "show" ]; then
  if [ -n "\${AZ_NOT_AUTH:-}" ]; then
    echo "not authenticated" >&2
    exit 1
  fi
  exit 0
fi

# 3. \`az repos show ... --query id -o tsv\` — repositoryId resolver.
if [ "\$1" = "repos" ] && [ "\$2" = "show" ]; then
  if [ -n "\${AZ_REPO_SHOW_FAIL:-}" ]; then
    echo "az repos show failed (stub)" >&2
    exit 1
  fi
  echo "00000000-0000-0000-0000-000000000fff"
  exit 0
fi

# 4. \`az devops invoke --area git --resource <token> --route-parameters ...\`
if [ "\$1" = "devops" ] && [ "\$2" = "invoke" ]; then
  resource=""
  method=""
  in_file=""
  has_thread_route=0
  while [ "\$#" -gt 0 ]; do
    case "\$1" in
      --resource)          resource="\$2"; shift 2 ;;
      --http-method)       method="\$2"; shift 2 ;;
      --in-file)           in_file="\$2"; shift 2 ;;
      --route-parameters)
        shift
        while [ "\$#" -gt 0 ] && [ "\${1#--}" = "\$1" ]; do
          case "\$1" in
            threadId=*) has_thread_route=1 ;;
          esac
          shift
        done
        ;;
      *) shift ;;
    esac
  done

  # ---- Probe phase (GET, no threadId) ------------------------------------
  if [ "\$method" = "GET" ] && [ "\$has_thread_route" -eq 0 ]; then
    case "\${AZ_PROBE_MODE:-first}" in
      first)
        # Only PullRequestThreads succeeds.
        [ "\$resource" = "PullRequestThreads" ] || exit 1
        echo '{"value":[],"count":0}'
        exit 0
        ;;
      second)
        # PullRequestThreads fails; pullrequestthreads succeeds.
        [ "\$resource" = "PullRequestThreads" ] && exit 1
        [ "\$resource" = "pullrequestthreads" ] || exit 1
        echo '{"value":[],"count":0}'
        exit 0
        ;;
      third)
        # Only threads succeeds.
        [ "\$resource" = "threads" ] || exit 1
        echo '{"value":[],"count":0}'
        exit 0
        ;;
      none)
        # All fail.
        exit 1
        ;;
      *)
        echo '{"value":[],"count":0}'; exit 0 ;;
    esac
  fi

  # ---- Thread GET (reply path) -------------------------------------------
  if [ "\$method" = "GET" ] && [ "\$has_thread_route" -eq 1 ]; then
    case "\${AZ_THREAD_MODE:-populated}" in
      populated)
        cat <<'JSONEOF'
{"id":42,"comments":[{"id":1,"content":"first","commentType":1},{"id":3,"content":"third","commentType":1},{"id":2,"content":"second","commentType":1}]}
JSONEOF
        exit 0
        ;;
      empty)
        cat <<'JSONEOF'
{"id":42,"comments":[]}
JSONEOF
        exit 0
        ;;
      missing)
        echo "TF401174: pull request thread not found" >&2
        exit 1
        ;;
      *)
        exit 0 ;;
    esac
  fi

  # ---- POST (top-level or reply) -----------------------------------------
  if [ "\$method" = "POST" ]; then
    # Record the in-file payload for assertions.
    if [ -n "\$in_file" ] && [ -f "\$in_file" ]; then
      cp "\$in_file" "${STATEDIR}/last-post-payload.json"
    fi
    if [ "\$has_thread_route" -eq 1 ]; then
      touch "${STATEDIR}/az.post-reply.invoked"
    else
      touch "${STATEDIR}/az.post-thread.invoked"
    fi

    if [ -n "\${AZ_POST_FAIL:-}" ]; then
      echo "az devops invoke POST failure (stub)" >&2
      exit 1
    fi

    if [ "\$has_thread_route" -eq 1 ]; then
      echo '{"id":42}'
    else
      echo '{"id":777}'
    fi
    exit 0
  fi

  exit 0
fi

exit 0
STUBEOF
  chmod +x "${STUBDIR}/az"

  # Fake `curl`: capture invocations + emit synthetic JSON responses.
  cat > "${STUBDIR}/curl" <<STUBEOF
#!/usr/bin/env bash
echo "curl \$*" >> "${STATEDIR}/curl.log"
touch "${STATEDIR}/curl.invoked"
url=""
data_file=""
while [ "\$#" -gt 0 ]; do
  case "\$1" in
    --data-binary)
      arg="\$2"
      if [ "\${arg:0:1}" = "@" ]; then
        data_file="\${arg:1}"
        if [ -f "\$data_file" ]; then
          cp "\$data_file" "${STATEDIR}/last-curl-payload.json"
        fi
      fi
      shift 2
      ;;
    -X|-H) shift 2 ;;
    -sS)   shift ;;
    *)
      case "\$1" in
        http*) url="\$1" ;;
      esac
      shift
      ;;
  esac
done
# Reply path embeds /threads/<id>/comments.
if [[ "\$url" == */threads/*/comments* ]]; then
  echo '{"id":888}'
else
  echo '{"id":999}'
fi
exit 0
STUBEOF
  chmod +x "${STUBDIR}/curl"

  # Symlink the rest of the tools backend-detect / pr-comment need.
  for _tool in bash dirname jq date base64 head sed tr cat mktemp cp mv rm mkdir chmod grep awk touch ls printf env id sleep; do
    _real="$(command -v "$_tool" 2>/dev/null || true)"
    if [ -n "$_real" ]; then
      ln -sf "$_real" "${STUBDIR}/${_tool}"
    fi
  done

  # Restrict PATH to STUBDIR so the real az/curl on the host cannot leak in.
  PATH="${STUBDIR}"
  export PATH
  unset AZ_EXT_MISSING AZ_NOT_AUTH AZ_REPO_SHOW_FAIL
  unset AZ_PROBE_MODE AZ_THREAD_MODE AZ_POST_FAIL
  unset SDLC_AZDO_HTTP AZURE_DEVOPS_PAT SDLC_SCM_BACKEND

  set_origin "https://dev.azure.com/contoso/sdlc-tools/_git/plugin-repo"
}

teardown() {
  cd /
  "$REAL_RM" -rf "$REPO_DIR"
  # Wipe any cache files this fixture might have written.
  "$REAL_RM" -f /tmp/sdlc-azdo-pr-thread-resource.contoso.plugin-repo
  # Restore PATH so bats' own post-test cleanup can still find core utils.
  PATH="$ORIG_PATH"
  export PATH
}

set_origin() {
  "$REAL_GIT" -C "$REPO_DIR" remote remove origin >/dev/null 2>&1 || true
  "$REAL_GIT" -C "$REPO_DIR" remote add origin "$1"
}

# ---------- NFR-1: ADO graceful-degradation skips ----------

@test "az absent → [warn] skip, exit 0" {
  rm -f "${STUBDIR}/az"
  run --separate-stderr bash "$PR_COMMENT" 1761 "body"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] Azure CLI (az) not found on PATH."* ]] || { >&3 echo "STDERR=$stderr"; false; }
}

@test "az devops extension missing → [warn] skip, exit 0" {
  AZ_EXT_MISSING=1 run --separate-stderr bash "$PR_COMMENT" 1761 "body"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] az devops extension not available"* ]] || { >&3 echo "STDERR=$stderr"; false; }
}

@test "az not authenticated → [warn] skip, exit 0" {
  AZ_NOT_AUTH=1 run --separate-stderr bash "$PR_COMMENT" 1761 "body"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] Azure CLI not authenticated"* ]] || { >&3 echo "STDERR=$stderr"; false; }
}

# ---------- FR-2: top-level thread create ----------

@test "top-level thread create → discussion URL on stdout, az POST invoked" {
  run --separate-stderr bash "$PR_COMMENT" 1761 "LGTM body"
  [ "$status" -eq 0 ] || { >&3 echo "STATUS=$status OUT=$output STDERR=$stderr"; false; }
  [[ "$output" == *"https://dev.azure.com/contoso/sdlc-tools/_git/plugin-repo/pullrequest/1761?discussionId=777"* ]] \
    || { >&3 echo "OUT=$output"; false; }
  [ -f "${STATEDIR}/az.post-thread.invoked" ] \
    || { >&3 echo "=== az.log ==="; >&3 cat "${STATEDIR}/az.log" 2>/dev/null; false; }
  jq -e '.comments[0].parentCommentId == 0 and .comments[0].content == "LGTM body" and .comments[0].commentType == 1 and .status == 1' \
    "${STATEDIR}/last-post-payload.json" >/dev/null
}

# ---------- FR-3: reply path ----------

@test "reply to populated thread resolves parentCommentId from max comment id" {
  AZ_THREAD_MODE=populated run bash "$PR_COMMENT" 1761 --body "reply text" --reply-to 42
  [ "$status" -eq 0 ] || { >&3 echo "OUT=$output"; false; }
  [[ "$output" == *"?discussionId=42"* ]]
  [ -f "${STATEDIR}/az.post-reply.invoked" ]
  jq -e '.parentCommentId == 3 and .content == "reply text" and .commentType == 1' \
    "${STATEDIR}/last-post-payload.json" >/dev/null
}

@test "reply to empty thread uses parentCommentId 0" {
  AZ_THREAD_MODE=empty run bash "$PR_COMMENT" 1761 --body "first reply" --reply-to 42
  [ "$status" -eq 0 ] || { >&3 echo "OUT=$output"; false; }
  jq -e '.parentCommentId == 0' "${STATEDIR}/last-post-payload.json" >/dev/null
}

# ---------- Edge 6: missing thread on reply ----------

@test "reply to missing thread → [warn] skip, exit 0" {
  AZ_THREAD_MODE=missing run --separate-stderr bash "$PR_COMMENT" 1761 --body "body" --reply-to 9999
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] ADO thread 9999 not found; skipping reply."* ]] || { >&3 echo "STDERR=$stderr"; false; }
  [ ! -f "${STATEDIR}/az.post-reply.invoked" ]
}

# ---------- NFR-3: resource-name probe + cache ----------

@test "probe succeeds on first candidate (PullRequestThreads), cache populated" {
  rm -f /tmp/sdlc-azdo-pr-thread-resource.contoso.plugin-repo
  rm -f /tmp/sdlc-azdo-pr-thread-resource.contoso.plugin-repo.tmp
  AZ_PROBE_MODE=first run bash "$PR_COMMENT" 1761 "body"
  [ "$status" -eq 0 ]
  [ -f /tmp/sdlc-azdo-pr-thread-resource.contoso.plugin-repo ]
  payload="$(sed -n '2p' /tmp/sdlc-azdo-pr-thread-resource.contoso.plugin-repo)"
  [ "$payload" = "PullRequestThreads" ]
  # Atomic-write: the `.tmp` staging file must be renamed away on success.
  [ ! -f /tmp/sdlc-azdo-pr-thread-resource.contoso.plugin-repo.tmp ]
}

@test "probe falls through to second candidate (pullrequestthreads)" {
  rm -f /tmp/sdlc-azdo-pr-thread-resource.contoso.plugin-repo
  AZ_PROBE_MODE=second run bash "$PR_COMMENT" 1761 "body"
  [ "$status" -eq 0 ]
  payload="$(sed -n '2p' /tmp/sdlc-azdo-pr-thread-resource.contoso.plugin-repo)"
  [ "$payload" = "pullrequestthreads" ]
}

@test "probe falls through to third candidate (threads)" {
  rm -f /tmp/sdlc-azdo-pr-thread-resource.contoso.plugin-repo
  AZ_PROBE_MODE=third run bash "$PR_COMMENT" 1761 "body"
  [ "$status" -eq 0 ]
  payload="$(sed -n '2p' /tmp/sdlc-azdo-pr-thread-resource.contoso.plugin-repo)"
  [ "$payload" = "threads" ]
}

# ---------- Edge 4: probe exhaustion ----------

@test "probe exhaustion writes probe-failed sentinel + [warn] + exits 0" {
  rm -f /tmp/sdlc-azdo-pr-thread-resource.contoso.plugin-repo
  AZ_PROBE_MODE=none run --separate-stderr bash "$PR_COMMENT" 1761 "body"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] ADO PR-thread resource probe failed across [PullRequestThreads, pullrequestthreads, threads]. Skipping comment."* ]] \
    || { >&3 echo "STDERR=$stderr"; false; }
  payload="$(sed -n '2p' /tmp/sdlc-azdo-pr-thread-resource.contoso.plugin-repo)"
  [ "$payload" = "probe-failed" ]
}

@test "probe-failed sentinel within TTL short-circuits + [warn] + exits 0" {
  cache=/tmp/sdlc-azdo-pr-thread-resource.contoso.plugin-repo
  now=$(date +%s)
  printf '%s\n%s\n' "$now" "probe-failed" > "$cache"
  run --separate-stderr bash "$PR_COMMENT" 1761 "body"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] ADO PR-thread resource probe failed across [PullRequestThreads, pullrequestthreads, threads]. Skipping comment."* ]] \
    || { >&3 echo "STDERR=$stderr"; false; }
  # No POST should have happened.
  [ ! -f "${STATEDIR}/az.post-thread.invoked" ]
}

@test "fresh cache short-circuits probe (single GET probe is NOT re-invoked)" {
  cache=/tmp/sdlc-azdo-pr-thread-resource.contoso.plugin-repo
  now=$(date +%s)
  printf '%s\n%s\n' "$now" "PullRequestThreads" > "$cache"
  # Force any probe attempt to fail so a re-probe would error visibly.
  AZ_PROBE_MODE=none run bash "$PR_COMMENT" 1761 "body"
  [ "$status" -eq 0 ] || { >&3 echo "OUT=$output"; false; }
  [[ "$output" == *"?discussionId=777"* ]]
  # az.log should have NO GET probe invocations (only repos show + POST).
  if [ -f "${STATEDIR}/az.log" ]; then
    ! grep -E -- "--http-method GET" "${STATEDIR}/az.log" >/dev/null \
      || grep -E -- "threadId=" "${STATEDIR}/az.log" >/dev/null
    # ^ allow GET only if it's the thread read on the reply path; here there is no reply.
    ! grep -E -- "--http-method GET" "${STATEDIR}/az.log" >/dev/null
  fi
}

@test "expired cache (>24h) triggers re-probe + cache rewrite" {
  cache=/tmp/sdlc-azdo-pr-thread-resource.contoso.plugin-repo
  # Stamp the cache 25h in the past.
  old=$(( $(date +%s) - 25*3600 ))
  printf '%s\n%s\n' "$old" "PullRequestThreads" > "$cache"
  AZ_PROBE_MODE=third run bash "$PR_COMMENT" 1761 "body"
  [ "$status" -eq 0 ] || { >&3 echo "OUT=$output"; false; }
  payload="$(sed -n '2p' "$cache")"
  [ "$payload" = "threads" ]
}

# ---------- FR-4: curl fallback ----------

@test "SDLC_AZDO_HTTP=curl without PAT → [warn] skip, exit 0" {
  SDLC_AZDO_HTTP=curl run --separate-stderr bash "$PR_COMMENT" 1761 "body"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] AZURE_DEVOPS_PAT not set; cannot post PR comment via raw HTTP. Skipping."* ]] \
    || { >&3 echo "STDERR=$stderr"; false; }
  [ ! -f "${STATEDIR}/curl.invoked" ]
}

@test "SDLC_AZDO_HTTP=curl with PAT → curl invoked, URL emitted" {
  SDLC_AZDO_HTTP=curl AZURE_DEVOPS_PAT=pat-secret run bash "$PR_COMMENT" 1761 "body"
  [ "$status" -eq 0 ] || { >&3 echo "OUT=$output"; false; }
  [[ "$output" == *"?discussionId=999"* ]]
  [ -f "${STATEDIR}/curl.invoked" ]
  # No az devops invoke POST should have been made on the top-level path.
  [ ! -f "${STATEDIR}/az.post-thread.invoked" ]
}

@test "az devops invoke POST failure with PAT set → auto-fallback to curl" {
  AZ_POST_FAIL=1 AZURE_DEVOPS_PAT=pat-secret run --separate-stderr bash "$PR_COMMENT" 1761 "body"
  [ "$status" -eq 0 ] || { >&3 echo "STDERR=$stderr"; false; }
  [[ "$stderr" == *"[warn] az devops invoke failed; falling back to raw HTTP via curl."* ]] \
    || { >&3 echo "STDERR=$stderr"; false; }
  [ -f "${STATEDIR}/curl.invoked" ]
}

# ---------- Tmpfile leak guard (top-level + reply curl paths) ----------

@test "forced-curl top-level: payload tmpfile is removed before exit (no leak)" {
  payload_tmp="${REPO_DIR}/payload-tmp"
  mkdir -p "$payload_tmp"
  run env TMPDIR="$payload_tmp" SDLC_AZDO_HTTP=curl AZURE_DEVOPS_PAT=pat-secret \
    bash "$PR_COMMENT" 1761 "body"
  [ "$status" -eq 0 ] || { >&3 echo "OUT=$output"; false; }
  [ -f "${STATEDIR}/curl.invoked" ]
  remaining="$(ls -A "$payload_tmp" 2>/dev/null || true)"
  [ -z "$remaining" ] || { >&3 echo "leaked tmpfiles: $remaining"; false; }
}

@test "forced-curl reply: payload tmpfile is removed before exit (no leak)" {
  payload_tmp="${REPO_DIR}/payload-tmp"
  mkdir -p "$payload_tmp"
  AZ_THREAD_MODE=populated run env TMPDIR="$payload_tmp" \
    SDLC_AZDO_HTTP=curl AZURE_DEVOPS_PAT=pat-secret \
    bash "$PR_COMMENT" 1761 --body "reply text" --reply-to 42
  [ "$status" -eq 0 ] || { >&3 echo "OUT=$output"; false; }
  [ -f "${STATEDIR}/curl.invoked" ]
  remaining="$(ls -A "$payload_tmp" 2>/dev/null || true)"
  [ -z "$remaining" ] || { >&3 echo "leaked tmpfiles: $remaining"; false; }
}

@test "az devops invoke POST failure without PAT → [warn] skip, exit 0" {
  AZ_POST_FAIL=1 run --separate-stderr bash "$PR_COMMENT" 1761 "body"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] az devops invoke (thread POST) failed"* ]] \
    || { >&3 echo "STDERR=$stderr"; false; }
  [ ! -f "${STATEDIR}/curl.invoked" ]
}
