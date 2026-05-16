#!/usr/bin/env bash
# backend-detect.sh — Detect the SCM backend from `git remote get-url origin`
# and honor the `SDLC_SCM_BACKEND=github|azdo` env override (FEAT-033 / FR-1).
#
# Usage: backend-detect.sh
#
# Takes no arguments. Reads `origin` URL via `git remote get-url origin`.
#
# Emits JSON on stdout describing the backend identity:
#   GitHub  → {"backend":"github","owner":"<owner>","repo":"<repo>"}
#   AzDO    → {"backend":"azdo","organization":"<org>","project":"<project>","repo":"<repo>"}
#   Unknown → literal `null`
#
# Recognized origin URL forms:
#   GitHub HTTPS : https://github.com/<owner>/<repo>(.git)?
#   GitHub SSH   : git@github.com:<owner>/<repo>(.git)?
#   AzDO HTTPS   : https://dev.azure.com/<org>/<project>/_git/<repo>
#   AzDO legacy  : https://<org>.visualstudio.com/<project>/_git/<repo>
#                  https://<org>.visualstudio.com/DefaultCollection/<project>/_git/<repo>
#   AzDO SSH     : git@ssh.dev.azure.com:v3/<org>/<project>/<repo>
#
# `SDLC_SCM_BACKEND` env override: when set to `github` or `azdo`, the override
# flips the BACKEND LABEL ONLY. The script still parses the origin URL against
# the overridden backend's pattern to populate identity fields. If the URL does
# not match, emit literal `null` and log a `[warn]` on stderr.
#
# AzDO `organization` is emitted as the bare name (e.g. `contoso`). Dispatchers
# downstream construct the `--organization https://dev.azure.com/<org>/` URL
# form when invoking `az`.
#
# Exit codes:
#   0 any detection outcome (including `null`)
#   2 internal parse error

set -euo pipefail

emit_null() {
  printf 'null\n'
  exit 0
}

# Match origin against the GitHub URL forms. On match, sets OWNER and REPO,
# echoes JSON, returns 0. On no-match, returns 1.
parse_github() {
  local origin="$1"
  local owner repo

  if [[ "$origin" =~ ^https?://github\.com/([^/]+)/([^/]+)$ ]]; then
    owner="${BASH_REMATCH[1]}"
    repo="${BASH_REMATCH[2]%.git}"
  elif [[ "$origin" =~ ^git@github\.com:([^/]+)/([^/]+)$ ]]; then
    owner="${BASH_REMATCH[1]}"
    repo="${BASH_REMATCH[2]%.git}"
  else
    return 1
  fi

  if [ -z "$owner" ] || [ -z "$repo" ]; then
    return 1
  fi

  printf '{"backend":"github","owner":"%s","repo":"%s"}\n' "$owner" "$repo"
  return 0
}

# Match origin against the Azure DevOps URL forms. On match, sets ORG, PROJECT,
# REPO, echoes JSON, returns 0. On no-match, returns 1.
parse_azdo() {
  local origin="$1"
  local org project repo

  if [[ "$origin" =~ ^https?://dev\.azure\.com/([^/]+)/([^/]+)/_git/([^/]+)$ ]]; then
    org="${BASH_REMATCH[1]}"
    project="${BASH_REMATCH[2]}"
    repo="${BASH_REMATCH[3]%.git}"
  elif [[ "$origin" =~ ^https?://([^./]+)\.visualstudio\.com/(DefaultCollection/)?([^/]+)/_git/([^/]+)$ ]]; then
    org="${BASH_REMATCH[1]}"
    project="${BASH_REMATCH[3]}"
    repo="${BASH_REMATCH[4]%.git}"
  elif [[ "$origin" =~ ^git@ssh\.dev\.azure\.com:v3/([^/]+)/([^/]+)/([^/]+)$ ]]; then
    org="${BASH_REMATCH[1]}"
    project="${BASH_REMATCH[2]}"
    repo="${BASH_REMATCH[3]%.git}"
  else
    return 1
  fi

  if [ -z "$org" ] || [ -z "$project" ] || [ -z "$repo" ]; then
    return 1
  fi

  printf '{"backend":"azdo","organization":"%s","project":"%s","repo":"%s"}\n' "$org" "$project" "$repo"
  return 0
}

# Read origin URL. If `git remote get-url origin` fails (no remote, not in a
# git repo, etc.), treat as no-origin and emit null.
origin=""
if origin_raw=$(git remote get-url origin 2>/dev/null); then
  # Trim trailing whitespace (including any newline left by `git`).
  origin="${origin_raw%$'\n'}"
  # Trim trailing spaces too.
  while [[ "$origin" =~ [[:space:]]$ ]]; do
    origin="${origin%[[:space:]]}"
  done
fi

if [ -z "$origin" ]; then
  emit_null
fi

override="${SDLC_SCM_BACKEND:-}"

case "$override" in
  github)
    if parse_github "$origin"; then
      exit 0
    fi
    echo "[warn] SDLC_SCM_BACKEND=github set but origin does not match github URL pattern." >&2
    emit_null
    ;;
  azdo)
    if parse_azdo "$origin"; then
      exit 0
    fi
    echo "[warn] SDLC_SCM_BACKEND=azdo set but origin does not match azdo URL pattern." >&2
    emit_null
    ;;
  "")
    # No override — auto-detect.
    if parse_github "$origin"; then
      exit 0
    fi
    if parse_azdo "$origin"; then
      exit 0
    fi
    emit_null
    ;;
  *)
    echo "[warn] SDLC_SCM_BACKEND=${override} not recognized; expected 'github' or 'azdo'." >&2
    emit_null
    ;;
esac
