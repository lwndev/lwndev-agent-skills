#!/usr/bin/env bash
# parse-qa-return.sh — Parse the executing-qa return contract line (FR-12).
#
# Usage:
#   parse-qa-return.sh "<final-message-text>" [--artifact <path>]
#   parse-qa-return.sh --stdin [--artifact <path>]
#
# Applies the canonical contract regex against the supplied text:
#   ^Verdict: (PASS|ISSUES-FOUND|ERROR|EXPLORATORY-ONLY) \| Passed: ([0-9]+) \| Failed: ([0-9]+) \| Errored: ([0-9]+)$
#
# Positional-argument form: match the provided string directly.
# --stdin form: read full skill response from stdin; match the LAST line
#   that satisfies the regex (consistent with other parsers in this repo).
#
# On match: emit JSON {verdict, passed, failed, errored, summary} to stdout.
#   summary: derived from the first non-empty paragraph of the artifact's
#   "## Summary" section when --artifact is given; otherwise "see <artifact-path>"
#   placeholder if --artifact path is missing/unreadable, or empty string if
#   --artifact is not provided at all.
#
# On mismatch: stderr "error: contract mismatch: expected '<regex>'; got: '<actual>'"
#   exit 1.
#
# Exit codes:
#   0  parsed successfully
#   1  contract mismatch
#   2  missing/invalid args

set -euo pipefail

# The canonical contract regex (verbatim from qa-return-contract.md).
CONTRACT_REGEX='^Verdict: (PASS|ISSUES-FOUND|ERROR|EXPLORATORY-ONLY) \| Passed: ([0-9]+) \| Failed: ([0-9]+) \| Errored: ([0-9]+)$'
CONTRACT_REGEX_DISPLAY='^Verdict: (PASS|ISSUES-FOUND|ERROR|EXPLORATORY-ONLY) \| Passed: ([0-9]+) \| Failed: ([0-9]+) \| Errored: ([0-9]+)$'

# Parse args.
stdin_mode=false
artifact_path=""
message_text=""

if [[ $# -lt 1 ]]; then
  echo "error: parse-qa-return.sh requires at least one argument or --stdin." >&2
  exit 2
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stdin)
      stdin_mode=true
      shift
      ;;
    --artifact)
      [[ $# -ge 2 ]] || { echo "error: --artifact requires a path argument." >&2; exit 2; }
      artifact_path="$2"
      shift 2
      ;;
    --)
      shift
      # Remaining args treated as message text.
      message_text="${*}"
      break
      ;;
    --*)
      echo "error: unknown flag '${1}'." >&2
      exit 2
      ;;
    *)
      if [[ "$stdin_mode" == "true" ]]; then
        echo "error: unexpected positional argument '${1}' when --stdin is set." >&2
        exit 2
      fi
      message_text="$1"
      shift
      ;;
  esac
done

# Resolve the text to match against the regex.
match_text=""

if [[ "$stdin_mode" == "true" ]]; then
  # Read all of stdin; find the LAST line matching the contract regex.
  last_match=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ $CONTRACT_REGEX ]]; then
      last_match="$line"
    fi
  done
  match_text="$last_match"
  if [[ -z "$match_text" ]]; then
    # No line matched — report the empty input as the "got" value.
    echo "error: contract mismatch: expected '${CONTRACT_REGEX_DISPLAY}'; got: ''" >&2
    exit 1
  fi
else
  if [[ -z "$message_text" ]]; then
    echo "error: parse-qa-return.sh requires a message text argument or --stdin." >&2
    exit 2
  fi
  match_text="$message_text"
fi

# Apply the regex.
if ! [[ "$match_text" =~ $CONTRACT_REGEX ]]; then
  echo "error: contract mismatch: expected '${CONTRACT_REGEX_DISPLAY}'; got: '${match_text}'" >&2
  exit 1
fi

verdict="${BASH_REMATCH[1]}"
passed="${BASH_REMATCH[2]}"
failed="${BASH_REMATCH[3]}"
errored="${BASH_REMATCH[4]}"

# Derive summary from artifact's ## Summary section.
summary=""
if [[ -n "$artifact_path" ]]; then
  if [[ ! -f "$artifact_path" ]]; then
    # Graceful fallback: artifact missing.
    summary="see ${artifact_path}"
  else
    # Extract first non-empty paragraph under ## Summary.
    in_summary=false
    found_summary=false
    while IFS= read -r line || [[ -n "$line" ]]; do
      if [[ "$line" =~ ^##[[:space:]]+Summary([[:space:]]|$) ]]; then
        in_summary=true
        continue
      fi
      if [[ "$in_summary" == "true" ]]; then
        # Stop at next ## heading.
        if [[ "$line" =~ ^## ]]; then
          break
        fi
        # Skip empty lines until we find the first paragraph.
        if [[ -z "${line// }" ]]; then
          # If we already found content, a blank line ends the first paragraph.
          if [[ "$found_summary" == "true" ]]; then
            break
          fi
          continue
        fi
        # Accumulate first paragraph (single-line extraction: take the first non-empty line).
        summary="${line}"
        found_summary=true
        break
      fi
    done < "$artifact_path"

    if [[ -z "$summary" ]]; then
      summary="see ${artifact_path}"
    else
      summary="${summary} (artifact: ${artifact_path})"
    fi
  fi
fi

# Emit JSON.
if command -v jq >/dev/null 2>&1; then
  jq -n \
    --arg verdict "$verdict" \
    --argjson passed "$passed" \
    --argjson failed "$failed" \
    --argjson errored "$errored" \
    --arg summary "$summary" \
    '{verdict: $verdict, passed: $passed, failed: $failed, errored: $errored, summary: $summary}'
else
  # Pure-bash JSON fallback.
  _json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    printf '%s' "$s"
  }
  esc_verdict="$(_json_escape "$verdict")"
  esc_summary="$(_json_escape "$summary")"
  printf '{"verdict":"%s","passed":%s,"failed":%s,"errored":%s,"summary":"%s"}\n' \
    "$esc_verdict" "$passed" "$failed" "$errored" "$esc_summary"
fi

exit 0
