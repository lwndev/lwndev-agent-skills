#!/usr/bin/env bash
# create-pr.sh — Dispatcher: push current branch and open a pull request.
#
# Usage: create-pr.sh <type> <ID> <summary> [--closes <issueRef>] [--issue-ref <ref>]
#
# Behavior (FEAT-033 / FR-3):
#   1. Validate args: <type> in {feat,chore,fix}; <ID> and <summary> non-empty.
#   2. Call `backend-detect.sh` (sibling); branch on `backend` field.
#   3. GitHub path:
#      - `command -v gh` → if missing, `[warn] GitHub CLI (gh) not found on PATH.` exit 0.
#      - `gh auth status` → if not authenticated, `[warn] GitHub CLI not authenticated -- run gh auth login.` exit 0.
#      - `git push -u origin <branch>`; on failure exit 1 (do NOT invoke gh).
#      - Read body template from `plugins/lwndev-sdlc/scripts/assets/pr-body.tmpl`
#        (still authoritative for GitHub; documented in references/pr-templates-github.md).
#      - Substitute placeholders ${TYPE}, ${ID}, ${SUMMARY}, ${CLOSES_LINE}, ${GENERATED_WITH}.
#      - `gh pr create --title <title> --body <body>` → URL on stdout, exit 0.
#   4. Azure DevOps path (FEAT-033 / Phase 4):
#      - NFR-1 skips: `az` missing, `az devops` extension missing, `az` not
#        authenticated, network/non-zero CLI exit → `[warn]` + exit 0.
#      - Resolve organization + project + repo from `backend-detect.sh`.
#      - Push current branch (always — parity with the gh path).
#      - Discover the default base branch via `git symbolic-ref`-style logic
#        (fall back to `main`).
#      - `az repos pr create --source-branch <branch> --target-branch <base>
#         --title <title> --description <body>
#         --organization https://dev.azure.com/<org>/ --project <project>
#         --repository <repo>`.
#      - Extract `_links.web.href` via `--query` for parity with `gh`'s URL
#        stdout.
#   5. Unrecognized / null backend: `[info] No recognized SCM backend detected from origin.` exit 0.
#
# `--closes <issueRef>` is the GitHub auto-close token (`Closes #N`). The token
# is rendered verbatim into the body via ${CLOSES_LINE}; empty/bare `#` is a
# usage error.
#
# `--issue-ref <ref>` is a backend-agnostic alias accepted for parity with the
# AzDO path documented in references/pr-templates-azdo.md. In Phase 3 the AzDO
# path is stubbed, so this flag is accepted but has no effect on output.
#
# Exit codes:
#   0 success (PR URL on stdout), graceful-degradation skip ([warn]/[info]),
#     or stubbed AzDO path
#   1 git push failed, gh pr create failed, or template missing
#   2 usage error (missing/invalid args, malformed --closes)

set -euo pipefail

# Bash 5.2+ enables patsub_replacement by default, which makes `&' in the
# replacement of `${var//pat/rep}` refer to the matched text. Disable so
# user-supplied summaries containing `&' stay literal.
shopt -u patsub_replacement 2>/dev/null || true

usage() {
  echo "error: usage: create-pr.sh <type> <ID> <summary> [--closes <issueRef>] [--issue-ref <ref>]" >&2
  exit 2
}

# Argument parsing — positional <type> <ID> <summary> plus optional flags.
positional=()
closes=""
closes_set=0
issue_ref=""
issue_ref_set=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --closes)
      if [ "$#" -lt 2 ]; then
        echo "error: --closes requires an argument" >&2
        exit 2
      fi
      closes="$2"
      closes_set=1
      shift 2
      ;;
    --closes=*)
      closes="${1#--closes=}"
      closes_set=1
      shift
      ;;
    --issue-ref)
      if [ "$#" -lt 2 ]; then
        echo "error: --issue-ref requires an argument" >&2
        exit 2
      fi
      issue_ref="$2"
      issue_ref_set=1
      shift 2
      ;;
    --issue-ref=*)
      issue_ref="${1#--issue-ref=}"
      issue_ref_set=1
      shift
      ;;
    --)
      shift
      while [ "$#" -gt 0 ]; do positional+=("$1"); shift; done
      ;;
    *)
      positional+=("$1")
      shift
      ;;
  esac
done

if [ "${#positional[@]}" -ne 3 ]; then
  usage
fi

type="${positional[0]}"
id="${positional[1]}"
summary="${positional[2]}"

case "$type" in
  feat|chore|fix) ;;
  *)
    echo "error: invalid type '${type}' (expected feat, chore, or fix)" >&2
    exit 2
    ;;
esac

if [ "$closes_set" -eq 1 ]; then
  if [ -z "$closes" ] || [ "$closes" = "#" ]; then
    echo "error: --closes value is malformed" >&2
    exit 2
  fi
fi

# Ensure issue_ref / issue_ref_set are always defined for `set -u` safety
# (the GitHub path does not consume them; the AzDO path optionally does).
: "${issue_ref:=}"
: "${issue_ref_set:=0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECT="${SCRIPT_DIR}/backend-detect.sh"

# Detect backend.
detect_out="$(bash "$DETECT" 2>/dev/null || true)"

backend=""
az_org=""
az_project=""
az_repo=""
if [ -n "$detect_out" ] && [ "$detect_out" != "null" ]; then
  if command -v jq >/dev/null 2>&1; then
    backend="$(printf '%s' "$detect_out" | jq -r '.backend // ""' 2>/dev/null || true)"
    az_org="$(printf '%s' "$detect_out" | jq -r '.organization // ""' 2>/dev/null || true)"
    az_project="$(printf '%s' "$detect_out" | jq -r '.project // ""' 2>/dev/null || true)"
    az_repo="$(printf '%s' "$detect_out" | jq -r '.repo // ""' 2>/dev/null || true)"
  else
    if [[ "$detect_out" =~ \"backend\":\"([^\"]+)\" ]]; then
      backend="${BASH_REMATCH[1]}"
    fi
    if [[ "$detect_out" =~ \"organization\":\"([^\"]+)\" ]]; then
      az_org="${BASH_REMATCH[1]}"
    fi
    if [[ "$detect_out" =~ \"project\":\"([^\"]+)\" ]]; then
      az_project="${BASH_REMATCH[1]}"
    fi
    if [[ "$detect_out" =~ \"repo\":\"([^\"]+)\" ]]; then
      az_repo="${BASH_REMATCH[1]}"
    fi
  fi
fi

case "$backend" in
  github)
    # NFR-1: graceful skip paths.
    if ! command -v gh >/dev/null 2>&1; then
      echo "[warn] GitHub CLI (gh) not found on PATH." >&2
      exit 0
    fi
    if ! gh auth status >/dev/null 2>&1; then
      echo "[warn] GitHub CLI not authenticated -- run gh auth login." >&2
      exit 0
    fi

    # Push current branch.
    branch="$(git rev-parse --abbrev-ref HEAD)"
    if ! git push -u origin "$branch"; then
      exit 1
    fi

    # Assemble title.
    title="${type}(${id}): ${summary}"

    # Resolve template path. The template lives under the legacy plugin scripts
    # dir (still authoritative for GitHub) until a later phase migrates it.
    # Discover it by walking up from this script: skills/managing-source-control/scripts/
    # → skills/managing-source-control/ → skills/ → lwndev-sdlc/ → scripts/assets/pr-body.tmpl.
    plugin_root="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
    tmpl_path="${plugin_root}/scripts/assets/pr-body.tmpl"
    if [ ! -f "$tmpl_path" ]; then
      echo "error: template not found: ${tmpl_path}" >&2
      exit 1
    fi

    tmpl_body="$(cat "$tmpl_path")"

    if [ "$closes_set" -eq 1 ]; then
      closes_line="Closes ${closes}"
    else
      closes_line=""
    fi

    generated_with='🤖 Generated with [Claude Code](https://claude.com/claude-code)'

    body="$tmpl_body"
    body="${body//\$\{TYPE\}/$type}"
    body="${body//\$\{ID\}/$id}"
    body="${body//\$\{SUMMARY\}/$summary}"
    body="${body//\$\{CLOSES_LINE\}/$closes_line}"
    body="${body//\$\{GENERATED_WITH\}/$generated_with}"

    if ! gh pr create --title "$title" --body "$body"; then
      exit 1
    fi
    exit 0
    ;;
  azdo)
    # NFR-1: graceful skip paths.
    if ! command -v az >/dev/null 2>&1; then
      echo "[warn] Azure CLI (az) not found on PATH." >&2
      exit 0
    fi
    if ! az repos pr -h >/dev/null 2>&1; then
      echo "[warn] az devops extension not available -- run az extension add --name azure-devops." >&2
      exit 0
    fi
    if ! az account show >/dev/null 2>&1; then
      echo "[warn] Azure CLI not authenticated -- run az login (Azure AD) or az devops login --pat <token>." >&2
      exit 0
    fi

    branch="$(git rev-parse --abbrev-ref HEAD)"
    if ! git push -u origin "$branch"; then
      exit 1
    fi

    # Discover base branch. Prefer origin/HEAD; fall back to "main".
    base_branch="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' || true)"
    if [ -z "$base_branch" ]; then
      base_branch="main"
    fi

    title="${type}(${id}): ${summary}"

    # Build the AzDO body — preserve Summary / Test Plan / Changes section
    # structure documented in references/pr-templates-azdo.md.
    if [ "$issue_ref_set" -eq 1 ] && [ -n "$issue_ref" ]; then
      issue_token="${issue_ref}"
    elif [ "$closes_set" -eq 1 ]; then
      issue_token="${closes}"
    else
      issue_token=""
    fi

    body="## Summary"
    body="${body}"$'\n\n'"${summary}"
    if [ -n "$issue_token" ]; then
      body="${body}"$'\n\n'"Related: ${issue_token}"
    fi
    body="${body}"$'\n\n'"## Test Plan"$'\n\n'"- Verify ${type}(${id}) behaves as documented."
    body="${body}"$'\n\n'"## Changes"$'\n\n'"See diff."
    body="${body}"$'\n\n'"🤖 Generated with [Claude Code](https://claude.com/claude-code)"

    az_org_url=""
    if [ -n "$az_org" ]; then
      az_org_url="https://dev.azure.com/${az_org}/"
    fi

    az_stderr_file="$(mktemp)"
    set +e
    az_out="$(az repos pr create \
      --source-branch "$branch" \
      --target-branch "$base_branch" \
      --title "$title" \
      --description "$body" \
      --query '_links.web.href' \
      -o tsv \
      ${az_org_url:+--organization "$az_org_url"} \
      ${az_project:+--project "$az_project"} \
      ${az_repo:+--repository "$az_repo"} \
      2>"$az_stderr_file")"
    rc=$?
    set -e
    if [ "$rc" -ne 0 ]; then
      az_err="$(head -n 1 "$az_stderr_file" 2>/dev/null || true)"
      rm -f "$az_stderr_file"
      echo "[warn] az repos pr create failed: ${az_err}" >&2
      exit 0
    fi
    rm -f "$az_stderr_file"

    # Emit the URL on stdout for parity with the gh path.
    printf '%s\n' "$az_out"
    exit 0
    ;;
  "")
    echo "[info] No recognized SCM backend detected from origin." >&2
    exit 0
    ;;
  *)
    echo "[info] No recognized SCM backend detected from origin." >&2
    exit 0
    ;;
esac
