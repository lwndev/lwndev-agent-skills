#!/usr/bin/env bash
# render-plan-scaffold.sh — Render an implementation-plan skeleton from one
# or more feature requirement docs (FEAT-029 / FR-1).
#
# Usage:
#   render-plan-scaffold.sh <FEAT-IDs> [--enforce-phase-budget]
#
#   <FEAT-IDs>  Comma-separated list of FEAT-NNN identifiers. Whitespace
#               around commas is tolerated. The first ID is the "primary"
#               feature; its name drives the plan title and its slug drives
#               the output filename.
#
#   --enforce-phase-budget
#               After rendering the scaffold, invoke
#               `validate-phase-sizes.sh <rendered-path>` (FR-5) and
#               propagate its exit code. A failing gate exits 1 with the
#               offender list on stderr; the rendered file is left in
#               place for inspection.
#
# Behavior:
#   1. Parse and validate the comma-separated FEAT-ID list.
#   2. Resolve every ID via `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-requirement-doc.sh`.
#      Surface upstream stderr verbatim and exit 1 on any unresolved ID.
#   3. For each resolved feature doc, extract: name (from `# Feature Requirements:`
#      heading), priority (first non-empty line after `## Priority`), and the
#      ordered list of `### FR-N:` headings.
#   4. Render the plan skeleton using the template at
#      `${CLAUDE_PLUGIN_ROOT}/skills/creating-implementation-plans/assets/implementation-plan.md`
#      as the source of section structure. One Features Summary row per ID.
#      One `### Phase N: <placeholder>` block per FR across all features in
#      document order.
#   5. Write the rendered plan to
#      `requirements/implementation/<primary-FEAT-ID>-<slug>.md`. Refuse to
#      overwrite — exit 2 if the target already exists.
#   6. Emit the absolute path to stdout. Exit 0.
#
# Exit codes:
#   0  Success (rendered plan path on stdout).
#   1  Upstream resolver failure or I/O error.
#   2  Missing args, malformed FEAT-IDs, or target file already exists.
#
# Bash 3.2-compatible (macOS ships /bin/bash 3.2). No associative arrays,
# no mapfile, no ${var,,}.

set -euo pipefail

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

if [ "$#" -lt 1 ]; then
  echo "error: usage: render-plan-scaffold.sh <FEAT-IDs> [--enforce-phase-budget]" >&2
  exit 2
fi

raw_ids=""
enforce_phase_budget="false"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --enforce-phase-budget)
      enforce_phase_budget="true"
      shift
      ;;
    --)
      shift
      ;;
    -*)
      echo "error: unknown flag: $1" >&2
      exit 2
      ;;
    *)
      if [ -z "$raw_ids" ]; then
        raw_ids="$1"
      else
        echo "error: unexpected positional argument: $1" >&2
        exit 2
      fi
      shift
      ;;
  esac
done

if [ -z "$raw_ids" ]; then
  echo "error: usage: render-plan-scaffold.sh <FEAT-IDs> [--enforce-phase-budget]" >&2
  exit 2
fi

# Split comma-separated list, tolerating whitespace around commas. Each
# element validated against ^FEAT-[0-9]+$.
ids=()
old_ifs="$IFS"
IFS=','
for raw in $raw_ids; do
  # Trim leading/trailing whitespace.
  trimmed="$(printf '%s' "$raw" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  if [ -z "$trimmed" ]; then
    IFS="$old_ifs"
    echo "error: malformed FEAT-IDs '$raw_ids': empty element" >&2
    exit 2
  fi
  if ! printf '%s' "$trimmed" | grep -Eq '^FEAT-[0-9]+$'; then
    IFS="$old_ifs"
    echo "error: malformed FEAT-IDs '$raw_ids': '$trimmed' does not match FEAT-NNN" >&2
    exit 2
  fi
  ids+=("$trimmed")
done
IFS="$old_ifs"

if [ "${#ids[@]}" -eq 0 ]; then
  echo "error: malformed FEAT-IDs '$raw_ids': empty list" >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# Plugin root + template resolution
# ---------------------------------------------------------------------------

if [ -z "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  # Fall back to the script's enclosing plugin root by walking up from
  # skills/<name>/scripts/ → plugin root.
  script_dir="$(cd "$(dirname "$0")" && pwd)"
  CLAUDE_PLUGIN_ROOT="$(cd "${script_dir}/../../.." && pwd)"
fi

resolver="${CLAUDE_PLUGIN_ROOT}/scripts/resolve-requirement-doc.sh"
if [ ! -x "$resolver" ] && [ ! -f "$resolver" ]; then
  echo "error: resolve-requirement-doc.sh not found at $resolver" >&2
  exit 1
fi

template="${CLAUDE_PLUGIN_ROOT}/skills/creating-implementation-plans/assets/implementation-plan.md"
if [ ! -f "$template" ]; then
  echo "error: implementation-plan.md template not found at $template" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Per-feature extraction helpers
# ---------------------------------------------------------------------------

# Extract the name following `# Feature Requirements:` from a feature doc.
# Strips leading/trailing whitespace.
extract_name() {
  local doc="$1"
  local line
  line="$(grep -m1 -E '^# Feature Requirements:' "$doc" || true)"
  if [ -z "$line" ]; then
    return 1
  fi
  printf '%s' "$line" | sed -e 's/^# Feature Requirements:[[:space:]]*//' -e 's/[[:space:]]*$//'
}

# Extract the first non-empty line after `## Priority`.
extract_priority() {
  local doc="$1"
  awk '
    /^## Priority[[:space:]]*$/ { in_section=1; next }
    in_section && /^##[[:space:]]/ { exit }
    in_section && NF { print; exit }
  ' "$doc"
}

# Extract `### FR-N: <title>` headings in document order. One heading per
# line on stdout.
extract_fr_headings() {
  local doc="$1"
  grep -E '^### FR-[0-9]+' "$doc" || true
}

# Slug derived from the feature doc filename: strip directory + the
# `FEAT-NNN-` prefix + `.md` suffix.
extract_slug() {
  local doc_path="$1"
  local base
  base="$(basename "$doc_path" .md)"
  printf '%s' "$base" | sed -E 's/^FEAT-[0-9]+-//'
}

# ---------------------------------------------------------------------------
# Resolve every feature doc up-front. Build parallel arrays: ids, docs,
# names, priorities. Build a single concatenated FR list with origin marks.
# ---------------------------------------------------------------------------

resolved_docs=()
resolved_names=()
resolved_priorities=()

for id in "${ids[@]}"; do
  # Forward resolver stderr verbatim by NOT redirecting it.
  if ! doc_path="$(bash "$resolver" "$id")"; then
    # Resolver already wrote a meaningful error to stderr.
    exit 1
  fi
  if [ ! -f "$doc_path" ]; then
    echo "error: resolver returned non-existent path '$doc_path' for $id" >&2
    exit 1
  fi
  name="$(extract_name "$doc_path" || true)"
  if [ -z "$name" ]; then
    echo "error: $doc_path missing '# Feature Requirements:' heading" >&2
    exit 1
  fi
  priority="$(extract_priority "$doc_path" || true)"
  if [ -z "$priority" ]; then
    priority="TBD"
  fi
  resolved_docs+=("$doc_path")
  resolved_names+=("$name")
  resolved_priorities+=("$priority")
done

# Primary = first ID.
primary_id="${ids[0]}"
primary_name="${resolved_names[0]}"
primary_doc="${resolved_docs[0]}"
primary_slug="$(extract_slug "$primary_doc")"
if [ -z "$primary_slug" ]; then
  echo "error: could not derive slug from $primary_doc" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Output path + overwrite guard
# ---------------------------------------------------------------------------

target_rel="requirements/implementation/${primary_id}-${primary_slug}.md"
target_dir="$(dirname "$target_rel")"

if [ ! -d "$target_dir" ]; then
  if ! mkdir -p "$target_dir"; then
    echo "error: failed to create $target_dir" >&2
    exit 1
  fi
fi

if [ -e "$target_rel" ]; then
  echo "error: target file already exists: $target_rel" >&2
  exit 2
fi

# Resolve to an absolute path for stdout. Use the parent directory because
# the file does not yet exist.
target_abs_dir="$(cd "$target_dir" && pwd)"
target_abs="${target_abs_dir}/$(basename "$target_rel")"

# ---------------------------------------------------------------------------
# Render the plan
# ---------------------------------------------------------------------------

# Build Features Summary rows. Each row: ID | issue link placeholder |
# linked feature doc | priority | TBD | Pending.
build_summary_rows() {
  local i
  for i in $(seq 0 $((${#ids[@]} - 1))); do
    local id="${ids[$i]}"
    local doc="${resolved_docs[$i]}"
    local name="${resolved_names[$i]}"
    local priority="${resolved_priorities[$i]}"
    local doc_basename
    doc_basename="$(basename "$doc")"
    printf '| %s | TBD | [%s](../features/%s) | %s | TBD | Pending |\n' \
      "$id" "$doc_basename" "$doc_basename" "$priority"
  done
}

# Build phase blocks. One per FR across all features in document order.
build_phase_blocks() {
  local phase_n=0
  local i
  for i in $(seq 0 $((${#ids[@]} - 1))); do
    local id="${ids[$i]}"
    local doc="${resolved_docs[$i]}"
    local doc_basename
    doc_basename="$(basename "$doc")"
    local fr_lines
    fr_lines="$(extract_fr_headings "$doc")"
    if [ -z "$fr_lines" ]; then
      continue
    fi
    # Iterate FR headings line-by-line.
    while IFS= read -r fr_line; do
      [ -z "$fr_line" ] && continue
      phase_n=$((phase_n + 1))
      # Strip leading `### ` to get the FR title (e.g., "FR-1: Foo").
      local fr_title
      fr_title="$(printf '%s' "$fr_line" | sed -e 's/^###[[:space:]]*//')"
      if [ "$phase_n" -gt 1 ]; then
        printf '\n---\n\n'
      fi
      printf '### Phase %d: [%s placeholder]\n' "$phase_n" "$fr_title"
      printf '**Feature:** [%s](../features/%s) | [#TBD](TBD)\n' "$id" "$doc_basename"
      printf '**Status:** Pending\n'
      printf '**Depends on:** [TBD]\n'
      printf '\n#### Rationale\n- [TBD]\n'
      printf '\n#### Implementation Steps\n1. [TBD]\n'
      printf '\n#### Deliverables\n- [ ] [TBD]\n'
    done <<EOF
$fr_lines
EOF
  done
}

{
  printf '# Implementation Plan: %s\n' "$primary_name"
  printf '\n## Overview\n[1-2 paragraph summary of what is being built and why]\n'
  printf '\n## Features Summary\n\n'
  printf '| Feature ID | GitHub Issue | Feature Document | Priority | Complexity | Status |\n'
  printf '|------------|--------------|------------------|----------|------------|--------|\n'
  build_summary_rows
  printf '\n## Recommended Build Sequence\n\n'
  build_phase_blocks
  printf '\n\n## Shared Infrastructure\n[Common utilities, patterns, or components needed across features]\n'
  printf '\n## Testing Strategy\n[Unit, integration, and E2E testing approach]\n'
  printf '\n## Dependencies and Prerequisites\n[External deps, existing code requirements]\n'
  printf '\n## Risk Assessment\n\n'
  printf '| Risk | Impact | Probability | Mitigation |\n'
  printf '|------|--------|-------------|------------|\n'
  printf '| [Risk description] | High/Med/Low | High/Med/Low | [Mitigation strategy] |\n'
  printf '\n## Success Criteria\n[Per-feature and overall project success metrics]\n'
} > "$target_abs"

printf '%s\n' "$target_abs"

# ---------------------------------------------------------------------------
# --enforce-phase-budget gate (FR-5). Invoke validate-phase-sizes.sh on the
# rendered file and propagate its exit code. The rendered file remains on
# disk regardless of the gate outcome so the user can inspect or amend it.
# ---------------------------------------------------------------------------
if [ "$enforce_phase_budget" = "true" ]; then
  script_dir="$(cd "$(dirname "$0")" && pwd)"
  validator="${script_dir}/validate-phase-sizes.sh"
  if [ ! -f "$validator" ]; then
    echo "error: validate-phase-sizes.sh not found at ${validator}" >&2
    exit 1
  fi
  if ! bash "$validator" "$target_abs"; then
    exit 1
  fi
fi

exit 0
