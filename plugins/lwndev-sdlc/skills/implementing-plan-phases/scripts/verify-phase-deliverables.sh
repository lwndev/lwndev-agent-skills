#!/usr/bin/env bash
# verify-phase-deliverables.sh — Verify phase deliverables exist and project checks pass (FEAT-027 / FR-4).
#
# Usage: verify-phase-deliverables.sh <plan-file> <phase-N>
#
# Parses the `#### Deliverables` subsection inside the `### Phase <phase-N>:`
# block, extracts leading backticked file paths from each `- [ ]` / `- [x]`
# entry, and runs:
#   1. File existence check per extracted path.
#   2. `npm run lint`         — when `lint` is defined in package.json.
#   3. `npm run format:check` — when `format:check` is defined in package.json.
#   4. `npm test`             — captures exit code + last 50 lines on failure.
#   5. `npm run build`        — captures exit code + last 50 lines on failure.
#   6. `npm run test:coverage` — run only when a coverage token is detected
#      in the phase block or the `## Testing Requirements` section.
#
# Fail-fast: a failing stage leaves downstream stages reported `skipped`.
#
# Graceful degradation:
#   If `npm` is not on PATH, emits a `[warn]` line to stderr and marks
#   lint/format/test/build/coverage all as `"skipped"`. Exits 0 when files.missing
#   is empty in that case.
#
# Fence-aware: deliverable lines inside ``` / ~~~ fenced blocks are ignored.
#
# Stdout: one JSON object with the shape:
#   {
#     "files":   {"ok":[...], "missing":[...]},
#     "lint":    "pass" | "fail" | "skipped",
#     "format":  "pass" | "fail" | "skipped",
#     "test":    "pass" | "fail" | "skipped",
#     "build":   "pass" | "fail" | "skipped",
#     "coverage":"pass" | "fail" | "skipped",
#     "output":  { "lint":"...", "format":"...", "test":"...", "build":"...", "coverage":"..." }   // keys present only for failing checks
#   }
#
# Exit codes:
#   0  files.missing empty AND all of lint/format/test/build/coverage ∈ {pass, skipped}.
#   1  missing files, a failing check, plan missing, or no matching phase block.
#   2  missing / malformed args.
#
# Dependencies:
#   Optional `jq` for JSON assembly; pure-bash `printf` fallback otherwise.
#   Optional `npm` — absent-on-PATH triggers graceful degradation per NFR-1.

set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "error: usage: verify-phase-deliverables.sh <plan-file> <phase-N>" >&2
  exit 2
fi

plan="$1"
phase_n="$2"

if [[ ! "$phase_n" =~ ^[1-9][0-9]*$ ]]; then
  echo "error: <phase-N> must be a positive integer, got: ${phase_n}" >&2
  exit 2
fi

if [ ! -f "$plan" ] || [ ! -r "$plan" ]; then
  echo "error: plan file not found or unreadable: ${plan}" >&2
  exit 1
fi

# Scan the plan:
#   - Extract the phase block bounded by `### Phase <phase-N>:` → next
#     `### Phase` heading or EOF.
#   - Inside that block, within the `#### Deliverables` subsection (bounded by
#     the next `####` heading or phase-block end), collect `- [ ]` / `- [x]`
#     lines that begin with a backticked path.
#   - Detect coverage token (`coverage` or `[0-9]+%`) anywhere in the phase
#     block OR in the `## Testing Requirements` section.
#
# Emits tab-separated records for deliverables:
#   DELIV\t<path>
# And a single marker:
#   MARKER\t<phase-found|no-phase>
# And optionally:
#   COVERAGE\t1
scan_output=$(
  tr -d '\r' < "$plan" \
    | awk -v phase_n="$phase_n" '
        BEGIN {
          in_fence = 0
          in_target_phase = 0
          in_deliverables = 0
          in_testing_req = 0
          phase_seen = 0
          coverage_flag = 0
        }
        function maybe_detect_coverage(text) {
          # Detect literal `coverage` (case-insensitive) or a `[0-9]+%` pattern.
          low = tolower(text)
          if (index(low, "coverage") > 0) { coverage_flag = 1; return }
          if (match(text, /[0-9]+%/)) { coverage_flag = 1; return }
        }
        {
          line = $0
          stripped = line
          sub(/^[ \t]+/, "", stripped)

          if (stripped ~ /^(```|~~~)/) {
            in_fence = !in_fence
            next
          }
          if (in_fence) next

          # Testing Requirements section detection (scope for coverage probe).
          if (match(line, /^##[ ]+Testing[ ]+Requirements/)) {
            in_testing_req = 1
            in_target_phase = 0
            in_deliverables = 0
            next
          }
          if (in_testing_req && match(line, /^##[ ]+/)) {
            # Any other H2 ends Testing Requirements.
            if (!match(line, /^##[ ]+Testing[ ]+Requirements/)) {
              in_testing_req = 0
            }
          }

          # Phase heading detection.
          if (match(line, /^###[ ]+Phase[ ]+[0-9]+:/)) {
            num = line
            sub(/^###[ ]+Phase[ ]+/, "", num)
            sub(/:.*$/, "", num)
            in_testing_req = 0
            if (num == phase_n) {
              in_target_phase = 1
              in_deliverables = 0
              phase_seen = 1
            } else {
              in_target_phase = 0
              in_deliverables = 0
            }
            next
          }

          # Within target phase: track Deliverables subsection boundary.
          if (in_target_phase) {
            # An H4 heading inside the phase block.
            if (match(line, /^####[ ]+/)) {
              heading = line
              sub(/^####[ ]+/, "", heading)
              sub(/[ \t]+$/, "", heading)
              if (tolower(heading) == "deliverables") {
                in_deliverables = 1
              } else {
                in_deliverables = 0
              }
              next
            }
            # Coverage probe within phase.
            maybe_detect_coverage(line)

            # Deliverable line inside `#### Deliverables`.
            if (in_deliverables && match(line, /^[ \t]*-[ ]\[[ xX]\][ ]/)) {
              rest = line
              sub(/^[ \t]*-[ ]\[[ xX]\][ ]+/, "", rest)
              # Leading backticked path: `<path>`
              if (match(rest, /^`[^`]+`/)) {
                pathtok = substr(rest, RSTART + 1, RLENGTH - 2)
                printf "DELIV\t%s\n", pathtok
              }
              # Lines without a leading backtick are skipped (non-file deliverables).
              next
            }
          }

          # Coverage probe within Testing Requirements section.
          if (in_testing_req) {
            maybe_detect_coverage(line)
          }
        }
        END {
          if (coverage_flag) printf "COVERAGE\t1\n"
          printf "MARKER\t%s\n", (phase_seen ? "phase-found" : "no-phase")
        }
      '
)

marker=$(printf '%s\n' "$scan_output" | awk -F'\t' '/^MARKER\t/ { m=$2 } END { print m }')
if [ "$marker" = "no-phase" ]; then
  echo "error: phase ${phase_n} not found in plan" >&2
  exit 1
fi

coverage_requested=0
if printf '%s\n' "$scan_output" | grep -q '^COVERAGE	1$'; then
  coverage_requested=1
fi

# Collect deliverable paths.
paths=()
while IFS=$'\t' read -r tag path; do
  [ "$tag" = "DELIV" ] || continue
  [ -z "$path" ] && continue
  paths+=("$path")
done <<< "$scan_output"

# Run plan checks.
ok_paths=()
missing_paths=()
for p in "${paths[@]}"; do
  if [ -e "$p" ]; then
    ok_paths+=("$p")
  else
    missing_paths+=("$p")
  fi
done

lint_status="skipped"
format_status="skipped"
test_status="skipped"
build_status="skipped"
coverage_status="skipped"
lint_output=""
format_output=""
test_output=""
build_output=""
coverage_output=""

# package.json script existence helper. Scopes the no-jq fallback to the
# `scripts` block via awk so that top-level keys like `"name": "lint"` or a
# dependency named `lint` do not produce a false positive.
have_pkg_script() {
  local name="$1"
  local pkg
  pkg="$(pwd)"
  while [ "$pkg" != "/" ] && [ -n "$pkg" ]; do
    if [ -f "$pkg/package.json" ]; then
      if command -v jq >/dev/null 2>&1; then
        jq -e --arg n "$name" '.scripts[$n] // empty' "$pkg/package.json" >/dev/null 2>&1
        return $?
      fi
      awk '
        /"scripts"[[:space:]]*:[[:space:]]*\{/ { in_block = 1; depth = 1; next }
        in_block {
          for (i = 1; i <= length($0); i++) {
            c = substr($0, i, 1)
            if (c == "{") depth++
            else if (c == "}") { depth--; if (depth == 0) { in_block = 0; exit } }
          }
          print
        }
      ' "$pkg/package.json" | grep -Eq "^[[:space:]]*\"${name}\"[[:space:]]*:"
      return $?
    fi
    pkg="$(dirname "$pkg")"
  done
  return 1
}

if ! command -v npm >/dev/null 2>&1; then
  echo "[warn] verify-phase-deliverables: npm not found; skipping lint/format/test/build/coverage checks." >&2
else
  # npm run lint — only when defined in package.json.
  if have_pkg_script lint; then
    tmp_lint_out=$(mktemp)
    if npm run lint >"$tmp_lint_out" 2>&1; then
      lint_status="pass"
    else
      lint_status="fail"
      lint_output=$(tail -n 50 "$tmp_lint_out")
    fi
    rm -f "$tmp_lint_out"
  fi

  # npm run format:check — only when defined and prior stages passed.
  if [ "$lint_status" != "fail" ] && have_pkg_script format:check; then
    tmp_format_out=$(mktemp)
    if npm run format:check >"$tmp_format_out" 2>&1; then
      format_status="pass"
    else
      format_status="fail"
      format_output=$(tail -n 50 "$tmp_format_out")
    fi
    rm -f "$tmp_format_out"
  fi

  # npm test — fail-fast if prior stages failed.
  if [ "$lint_status" != "fail" ] && [ "$format_status" != "fail" ]; then
    tmp_test_out=$(mktemp)
    if npm test >"$tmp_test_out" 2>&1; then
      test_status="pass"
    else
      test_status="fail"
      test_output=$(tail -n 50 "$tmp_test_out")
    fi
    rm -f "$tmp_test_out"
  fi

  # npm run build — skip further checks if prior stage failed (fail fast).
  if [ "$lint_status" != "fail" ] && [ "$format_status" != "fail" ] && [ "$test_status" = "pass" ]; then
    tmp_build_out=$(mktemp)
    if npm run build >"$tmp_build_out" 2>&1; then
      build_status="pass"
    else
      build_status="fail"
      build_output=$(tail -n 50 "$tmp_build_out")
    fi
    rm -f "$tmp_build_out"
  fi

  # npm run test:coverage when coverage was requested, and prior stages succeeded.
  if [ "$coverage_requested" -eq 1 ]; then
    if [ "$test_status" = "pass" ] && [ "$build_status" = "pass" ]; then
      tmp_cov_out=$(mktemp)
      if npm run test:coverage >"$tmp_cov_out" 2>&1; then
        coverage_status="pass"
      else
        coverage_status="fail"
        coverage_output=$(tail -n 50 "$tmp_cov_out")
      fi
      rm -f "$tmp_cov_out"
    fi
    # If prior stages failed, coverage stays "skipped".
  fi
fi

# Assemble JSON.
have_jq=0
if command -v jq >/dev/null 2>&1; then
  have_jq=1
fi

json_array() {
  # Emit JSON array of strings from positional args.
  if [ "$#" -eq 0 ]; then
    printf '[]'
    return
  fi
  if [ "$have_jq" -eq 1 ]; then
    printf '%s\n' "$@" | jq -Rc -s 'split("\n") | map(select(length > 0))'
    return
  fi
  # Pure-bash: escape each string for JSON.
  local out="[" first=1 s esc
  for s in "$@"; do
    esc="${s//\\/\\\\}"
    esc="${esc//\"/\\\"}"
    if [ "$first" -eq 1 ]; then
      out+="\"${esc}\""
      first=0
    else
      out+=",\"${esc}\""
    fi
  done
  out+="]"
  printf '%s' "$out"
}

json_string() {
  local s="$1"
  if [ "$have_jq" -eq 1 ]; then
    printf '%s' "$s" | jq -Rs .
    return
  fi
  local esc="${s//\\/\\\\}"
  esc="${esc//\"/\\\"}"
  # Escape newlines, tabs, carriage returns for JSON string literal.
  esc="${esc//$'\n'/\\n}"
  esc="${esc//$'\r'/\\r}"
  esc="${esc//$'\t'/\\t}"
  printf '"%s"' "$esc"
}

files_ok_json=$(json_array "${ok_paths[@]+"${ok_paths[@]}"}")
files_missing_json=$(json_array "${missing_paths[@]+"${missing_paths[@]}"}")

# Build "output" object: include keys only for failing checks.
output_parts=""
if [ "$lint_status" = "fail" ]; then
  val=$(json_string "$lint_output")
  output_parts="\"lint\":${val}"
fi
if [ "$format_status" = "fail" ]; then
  val=$(json_string "$format_output")
  if [ -n "$output_parts" ]; then output_parts="${output_parts},"; fi
  output_parts+="\"format\":${val}"
fi
if [ "$test_status" = "fail" ]; then
  val=$(json_string "$test_output")
  if [ -n "$output_parts" ]; then output_parts="${output_parts},"; fi
  output_parts+="\"test\":${val}"
fi
if [ "$build_status" = "fail" ]; then
  val=$(json_string "$build_output")
  if [ -n "$output_parts" ]; then output_parts="${output_parts},"; fi
  output_parts+="\"build\":${val}"
fi
if [ "$coverage_status" = "fail" ]; then
  val=$(json_string "$coverage_output")
  if [ -n "$output_parts" ]; then output_parts="${output_parts},"; fi
  output_parts+="\"coverage\":${val}"
fi
output_json="{${output_parts}}"

printf '{"files":{"ok":%s,"missing":%s},"lint":"%s","format":"%s","test":"%s","build":"%s","coverage":"%s","output":%s}\n' \
  "$files_ok_json" "$files_missing_json" \
  "$lint_status" "$format_status" "$test_status" "$build_status" "$coverage_status" \
  "$output_json"

# Aggregate exit code.
rc=0
if [ "${#missing_paths[@]}" -gt 0 ]; then
  rc=1
fi
for s in "$lint_status" "$format_status" "$test_status" "$build_status" "$coverage_status"; do
  case "$s" in
    pass|skipped) : ;;
    *) rc=1 ;;
  esac
done
exit "$rc"
