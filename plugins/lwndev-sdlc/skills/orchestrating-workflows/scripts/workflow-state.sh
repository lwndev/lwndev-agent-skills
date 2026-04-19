#!/usr/bin/env bash
set -euo pipefail

# workflow-state.sh — State management for orchestrating-workflows skill
# Manages .sdlc/workflows/{ID}.json state files for SDLC workflow chains.
# Requires: jq, bash-compatible shell

# Check jq availability
if ! command -v jq &>/dev/null; then
  echo "Error: jq is required but not installed." >&2
  echo "Install via: brew install jq (macOS), apt-get install jq (Debian/Ubuntu), or see https://jqlang.github.io/jq/download/" >&2
  exit 1
fi

WORKFLOWS_DIR=".sdlc/workflows"

usage() {
  echo "Usage: workflow-state.sh <command> <args...>" >&2
  echo "" >&2
  echo "Commands:" >&2
  echo "  init <ID> <type>              Create state file for a new workflow" >&2
  echo "  status <ID>                   Return current state as JSON" >&2
  echo "  advance <ID> [artifact-path]  Mark current step complete, advance to next" >&2
  echo "  pause <ID> <reason>           Set status to paused" >&2
  echo "  resume <ID>                   Set status to in-progress" >&2
  echo "  fail <ID> <message>           Set status to failed with error" >&2
  echo "  complete <ID>                 Mark workflow as complete" >&2
  echo "  set-pr <ID> <pr-num> <branch> Record PR metadata" >&2
  echo "  populate-phases <ID> <count>  Insert phase steps and post-phase steps" >&2
  echo "  phase-count <ID>              Return number of implementation phases" >&2
  echo "  phase-status <ID>             Return per-phase completion status" >&2
  echo "  set-complexity <ID> <tier>    Set work-item complexity tier (low|medium|high)" >&2
  echo "  get-model <ID> <step-name>    Resolve model tier for a step (baseline + complexity + modelOverride)" >&2
  echo "  record-model-selection <ID> <stepIndex> <skill> <mode> <phase> <tier> <complexityStage> <startedAt>" >&2
  echo "                                Append an entry to the modelSelections audit trail" >&2
  echo "  classify-init <ID> [doc-path]" >&2
  echo "                                Compute init-stage work-item complexity (low|medium|high) from the" >&2
  echo "                                requirement document. Dispatches by chain type read from state." >&2
  echo "                                doc-path is optional; if omitted the default location for the chain" >&2
  echo "                                type is used (requirements/features/{ID}-*.md, etc.)." >&2
  echo "  classify-post-plan <ID> [plan-path]" >&2
  echo "                                Feature-only. Re-compute complexity including phase count from the" >&2
  echo "                                implementation plan and apply upgrade-only max(persisted, new)." >&2
  echo "  resolve-tier <ID> <step-name> [flags...]" >&2
  echo "                                Debug helper. Walk the FR-3 precedence chain and echo the resolved" >&2
  echo "                                tier. Flags: --cli-model <tier>, --cli-complexity <tier>," >&2
  echo "                                --cli-model-for <step>:<tier>, --state-override <tier>." >&2
  echo "                                In real orchestrator runs, CLI flags are parsed in the orchestrator" >&2
  echo "                                layer and passed through; this subcommand exists so the resolver can" >&2
  echo "                                be exercised from unit tests and by humans running dry-run checks." >&2
  echo "  resume-recompute <ID> [--doc <path>] [--plan <path>]" >&2
  echo "                                FEAT-014 FR-12. Stage-aware, upgrade-only re-computation on resume." >&2
  echo "                                Reads complexityStage, re-runs classify-init (and classify-post-plan" >&2
  echo "                                when stage is post-plan), applies max(persisted, new). Persists when" >&2
  echo "                                upgraded, logs a one-line info message, and echoes the resolved tier." >&2
  echo "  next-tier-up <tier>           FEAT-014 FR-11. Pure helper. Echoes the next tier up in the" >&2
  echo "                                haiku → sonnet → opus → fail progression. Exits 2 when already" >&2
  echo "                                at opus (retry exhausted)." >&2
  echo "  check-claude-version [required]" >&2
  echo "                                FEAT-014 NFR-6. Compare 'claude --version' against required minimum" >&2
  echo "                                (default 2.1.72). Exits 0 if current >= required or if version" >&2
  echo "                                cannot be determined (graceful). Exits 1 if current < required" >&2
  echo "                                and emits the documented warning line to stderr." >&2
  echo "  set-gate <ID> <gate-type>     Signal that the orchestrator is waiting for user input within an" >&2
  echo "                                in-progress step. Valid gate types: findings-decision." >&2
  echo "  clear-gate <ID>               Remove the active gate (sets gate to null)." >&2
  echo "  record-findings <ID> <stepIndex> <errors> <warnings> <info> <decision> <summary> [--rerun] [--details-file <path>]" >&2
  echo "                                Persist reviewing-requirements findings on a step entry." >&2
  echo "                                decision must be one of: advanced, auto-advanced, user-advanced, auto-fixed, paused." >&2
  echo "                                --rerun writes to rerunFindings instead of findings." >&2
  echo "                                --details-file is only used when decision is auto-advanced." >&2
  exit 1
}

state_file() {
  echo "${WORKFLOWS_DIR}/${1}.json"
}

ensure_dir() {
  mkdir -p "$WORKFLOWS_DIR"
}

validate_id() {
  local id="$1"
  if [[ ! "$id" =~ ^(FEAT|CHORE|BUG)-[0-9]+$ ]]; then
    echo "Error: Invalid ID format '${id}'. Expected FEAT-NNN, CHORE-NNN, or BUG-NNN." >&2
    exit 1
  fi
}

validate_state_file() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "Error: State file not found: ${file}" >&2
    exit 1
  fi
  if ! jq -e '.id and .type and .status and .steps and (.currentStep != null)' "$file" &>/dev/null; then
    echo "Error: State file is malformed or missing required fields (id, type, status, steps, currentStep)." >&2
    echo "Consider deleting ${file} and restarting the workflow." >&2
    exit 1
  fi
  # Defensive migration (FR-13): silently add FEAT-014 fields if missing.
  _migrate_state_file "$file"
}

now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# --- Model selection helpers (FEAT-014) ---

# Map a tier name to a numeric rank for comparison: haiku=1 < sonnet=2 < opus=3.
# Emits empty string for unknown tiers.
_tier_rank() {
  case "$1" in
    haiku) echo 1 ;;
    sonnet) echo 2 ;;
    opus) echo 3 ;;
    *) echo "" ;;
  esac
}

# Compare two tier strings and echo the higher one. If either side is unknown,
# the other is returned. If both are unknown, echoes the first argument.
_max_tier() {
  local a="$1"
  local b="$2"
  local ra rb
  ra=$(_tier_rank "$a")
  rb=$(_tier_rank "$b")
  if [[ -z "$ra" && -z "$rb" ]]; then
    echo "$a"
    return
  fi
  if [[ -z "$ra" ]]; then
    echo "$b"
    return
  fi
  if [[ -z "$rb" ]]; then
    echo "$a"
    return
  fi
  if (( ra >= rb )); then
    echo "$a"
  else
    echo "$b"
  fi
}

# Map a work-item complexity label (low|medium|high) to its associated model tier.
# low → haiku, medium → sonnet, high → opus. Returns empty string for unknown / null.
_complexity_to_tier() {
  case "$1" in
    low) echo "haiku" ;;
    medium) echo "sonnet" ;;
    high) echo "opus" ;;
    *) echo "" ;;
  esac
}

# Step baseline lookup (FEAT-014 Axis 1). Echoes baseline tier for a given step name.
# Unknown step names default to "sonnet" (safe floor).
_step_baseline() {
  case "$1" in
    reviewing-requirements|creating-implementation-plans|implementing-plan-phases|executing-chores|executing-bug-fixes)
      echo "sonnet"
      ;;
    finalizing-workflow|pr-creation)
      echo "haiku"
      ;;
    *)
      echo "sonnet"
      ;;
  esac
}

# Step baseline-lock lookup. Baseline-locked steps ignore work-item complexity upgrades
# and soft overrides. Echoes "true" if locked, "false" otherwise.
_step_baseline_locked() {
  case "$1" in
    finalizing-workflow|pr-creation) echo "true" ;;
    *) echo "false" ;;
  esac
}

# Defensive migration for pre-existing state files missing required fields.
# Adds complexity, complexityStage, modelOverride, modelSelections (FEAT-014 FR-13),
# and gate (BUG-011) with their init defaults when any are missing. Silent except for
# a single stderr debug line the first time a file is actually rewritten.
_migrate_state_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0

  # Quick check: does the file need migration at all?
  local needs_migration
  needs_migration=$(jq '
    (has("complexity") | not) or
    (has("complexityStage") | not) or
    (has("modelOverride") | not) or
    (has("modelSelections") | not) or
    (has("gate") | not)
  ' "$file" 2>/dev/null || echo "false")

  if [[ "$needs_migration" != "true" ]]; then
    return 0
  fi

  echo "[workflow-state] debug: migrating ${file} to add missing state fields (model-selection and gate)" >&2

  jq '
    (if has("complexity") | not then .complexity = null else . end)
    | (if has("complexityStage") | not then .complexityStage = "init" else . end)
    | (if has("modelOverride") | not then .modelOverride = null else . end)
    | (if has("modelSelections") | not then .modelSelections = [] else . end)
    | (if has("gate") | not then .gate = null else . end)
  ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
}

# --- Classifier signal extractors (FEAT-014 Phase 2) ---
#
# These helpers parse synthetic and real requirement documents to drive the
# FR-2a / FR-2b two-stage classifier. Each extractor is deliberately pure
# (reads one file, echoes one value) so the unit tests can exercise them in
# isolation against synthetic fixtures. All extractors return an empty string
# when the signal cannot be computed — the caller is responsible for applying
# the FR-10 fallback (`sonnet` work-item complexity, never `opus`).

# Count unchecked/checked acceptance-criteria list items under the
# `## Acceptance Criteria` heading. The heading terminator is either the next
# top-level `## ` heading or end-of-file. Returns the count (possibly 0) or
# empty string if the heading is absent altogether.
_count_acceptance_criteria() {
  local doc="$1"
  [[ -f "$doc" ]] || { echo ""; return; }

  awk '
    BEGIN { in_ac = 0; count = 0; found = 0 }
    /^## Acceptance Criteria[[:space:]]*$/ { in_ac = 1; found = 1; next }
    in_ac && /^## / { in_ac = 0 }
    in_ac && /^[[:space:]]*-[[:space:]]*\[[ xX]\]/ { count++ }
    END { if (found) print count; else print "" }
  ' "$doc"
}

# Count the distinct root-cause references (RC-N). Prefer the ordered list
# under `## Root Cause(s)` — this maps 1:1 with the RC-N convention used by
# bug docs authored from the `documenting-bugs` template. Falls back to
# scraping `RC-N` mentions across the whole file if the heading is absent.
_count_root_causes() {
  local doc="$1"
  [[ -f "$doc" ]] || { echo ""; return; }

  # Preferred path: count the numbered list items under ## Root Cause(s).
  local list_count
  list_count=$(awk '
    BEGIN { in_rc = 0; count = 0 }
    /^## Root Cause\(s\)[[:space:]]*$/ { in_rc = 1; next }
    in_rc && /^## / { in_rc = 0 }
    in_rc && /^[[:space:]]*[0-9]+\.[[:space:]]/ { count++ }
    END { print count }
  ' "$doc")

  if [[ -n "$list_count" && "$list_count" != "0" ]]; then
    echo "$list_count"
    return
  fi

  # Fallback: count distinct RC-N references anywhere in the doc.
  local rc_count
  rc_count=$(grep -oE 'RC-[0-9]+' "$doc" 2>/dev/null | sort -u | wc -l | tr -d ' ')
  if [[ "$rc_count" -gt 0 ]]; then
    echo "$rc_count"
  else
    echo ""
  fi
}

# Count the functional-requirement headings under the
# `## Functional Requirements` section. Headings matching the form
# `### FR-N:` are counted except when the heading line contains the literal
# token `removed` (case-insensitive) — see the FEAT-014 self-classification
# sanity check which excludes removed requirements from the count.
# Returns empty string if the section is absent.
_count_functional_requirements() {
  local doc="$1"
  [[ -f "$doc" ]] || { echo ""; return; }

  awk '
    BEGIN { in_fr = 0; count = 0; found = 0 }
    /^## Functional Requirements[[:space:]]*$/ { in_fr = 1; found = 1; next }
    in_fr && /^## / { in_fr = 0 }
    in_fr && /^### FR-[0-9]+/ {
      line = tolower($0)
      if (index(line, "removed") == 0) count++
    }
    END { if (found) print count; else print "" }
  ' "$doc"
}

# Extract the severity field from a bug document. Looks for `## Severity`
# followed by a value line (either inline backticks or plain text on the
# first non-empty body line). Returns the lowercased value, or empty string
# when absent. Recognised values: low, medium, high, critical.
_extract_severity() {
  local doc="$1"
  [[ -f "$doc" ]] || { echo ""; return; }

  local raw
  raw=$(awk '
    BEGIN { in_sev = 0 }
    /^## Severity[[:space:]]*$/ { in_sev = 1; next }
    in_sev && /^## / { exit }
    in_sev && NF > 0 { print; exit }
  ' "$doc")

  # Strip surrounding backticks and whitespace.
  raw=$(echo "$raw" | tr -d '`' | tr '[:upper:]' '[:lower:]' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  echo "$raw"
}

# Extract the category field from a bug document. Same shape as severity.
_extract_category() {
  local doc="$1"
  [[ -f "$doc" ]] || { echo ""; return; }

  local raw
  raw=$(awk '
    BEGIN { in_cat = 0 }
    /^## Category[[:space:]]*$/ { in_cat = 1; next }
    in_cat && /^## / { exit }
    in_cat && NF > 0 { print; exit }
  ' "$doc")

  raw=$(echo "$raw" | tr -d '`' | tr '[:upper:]' '[:lower:]' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  echo "$raw"
}

# Count implementation-plan phases. Plan files use `### Phase N:` headings.
# Returns empty string if the plan file is absent or has zero phases.
_count_phases() {
  local plan="$1"
  [[ -f "$plan" ]] || { echo ""; return; }

  local count
  count=$(grep -cE '^### Phase [0-9]+' "$plan" 2>/dev/null || true)
  if [[ "$count" -gt 0 ]]; then
    echo "$count"
  else
    echo ""
  fi
}

# Check whether the Non-Functional Requirements section mentions any
# security / authentication / performance concern. Uses word-boundary
# matching (delimited by non-letter characters) rather than substring
# matching so "author metadata", "performer", and similar false positives
# do NOT trigger a bump. Also skips lines inside fenced code blocks
# (```...```) so example YAML/JSON inside NFR prose cannot distort counts.
#
# Matched keywords (case-insensitive, whole-word):
#   security, secure
#   authentication, authorization
#   performance, latency, throughput
#
# Echoes "true" if any whole-word keyword is found in NFR prose outside
# fenced blocks, "false" if the section exists but has no match, and
# empty string if the section is absent entirely.
_check_security_auth_perf() {
  local doc="$1"
  [[ -f "$doc" ]] || { echo ""; return; }

  awk '
    BEGIN {
      in_nfr = 0
      found = 0
      matched = 0
      in_fence = 0
      # Whole-word keyword pattern. Anchored with (^|[^a-z]) / ([^a-z]|$)
      # to prevent substring matches ("author" ⊄ "authored", "perf" ⊄
      # "performer"). Expand by adding new keywords here; keep the set
      # aligned with the NFR bump spec in FR-2a.
      pattern = "(^|[^a-z])(security|secure|authentication|authorization|performance|latency|throughput)([^a-z]|$)"
    }
    # Track fence state before any NFR-section logic so fenced code inside
    # the NFR section is excluded from matching.
    /^```/ { in_fence = !in_fence; next }
    /^## Non-Functional Requirements[[:space:]]*$/ { in_nfr = 1; found = 1; next }
    in_nfr && /^## / { in_nfr = 0 }
    in_nfr && !in_fence {
      line = tolower($0)
      if (match(line, pattern)) {
        matched = 1
      }
    }
    END {
      if (!found) { print ""; exit }
      if (matched) print "true"; else print "false"
    }
  ' "$doc"
}

# Bucket a numeric count into a complexity tier using the supplied edges.
# Usage: _bucket_count <n> <low-max> <medium-max>
# Returns "low" if n <= low-max, "medium" if n <= medium-max, else "high".
# Returns empty string if n is empty.
_bucket_count() {
  local n="$1"
  local low_max="$2"
  local medium_max="$3"
  [[ -n "$n" ]] || { echo ""; return; }
  if (( n <= low_max )); then
    echo "low"
  elif (( n <= medium_max )); then
    echo "medium"
  else
    echo "high"
  fi
}

# Bump a complexity label by one tier. low → medium, medium → high, high → high.
# Empty / unknown values pass through unchanged.
_bump_complexity() {
  case "$1" in
    low) echo "medium" ;;
    medium) echo "high" ;;
    high) echo "high" ;;
    *) echo "$1" ;;
  esac
}

# Max of two complexity labels under the low < medium < high ordering.
# Returns whichever of the two labels is higher. Unknown values are
# treated as rank 0, so the known value always wins against them.
_max_complexity() {
  local a="$1"
  local b="$2"
  local ra=0 rb=0
  case "$a" in low) ra=1 ;; medium) ra=2 ;; high) ra=3 ;; esac
  case "$b" in low) rb=1 ;; medium) rb=2 ;; high) rb=3 ;; esac
  if (( ra == 0 && rb == 0 )); then
    echo ""
    return
  fi
  if (( ra >= rb )); then
    echo "$a"
  else
    echo "$b"
  fi
}

# Resolve the default requirement-doc path for a given ID and chain type.
_default_doc_path() {
  local id="$1"
  local type="$2"
  local dir
  case "$type" in
    feature) dir="requirements/features" ;;
    chore)   dir="requirements/chores" ;;
    bug)     dir="requirements/bugs" ;;
    *) echo ""; return ;;
  esac

  [[ -d "$dir" ]] || { echo ""; return; }
  local found
  found=$(ls ${dir}/${id}-*.md 2>/dev/null | sort | head -1 || true)
  if [[ -z "$found" ]]; then
    # Also accept the bare {ID}.md form used in a handful of older docs.
    [[ -f "${dir}/${id}.md" ]] && found="${dir}/${id}.md"
  fi
  echo "$found"
}

# Resolve the default implementation-plan path for a given feature ID.
_default_plan_path() {
  local id="$1"
  [[ -d "requirements/implementation" ]] || { echo ""; return; }
  ls requirements/implementation/${id}-*.md 2>/dev/null | sort | head -1 || true
}

# --- Signal classifiers per chain type (FEAT-014 FR-2a) ---
#
# Each classifier parses the signals relevant to its chain and returns a
# work-item complexity label (low|medium|high). On unparseable input (no
# signals extracted at all) they fall back to "medium" so the caller's
# final mapping produces `sonnet` — honouring FR-10 which mandates sonnet
# as the unparseable-signal floor, never opus.

_classify_chore() {
  local doc="$1"
  local ac_count
  ac_count=$(_count_acceptance_criteria "$doc")
  if [[ -z "$ac_count" ]]; then
    echo "medium"  # FR-10 fallback → sonnet
    return
  fi
  # Chore thresholds: ≤3 low, 4–8 medium, 9+ high.
  _bucket_count "$ac_count" 3 8
}

_classify_bug() {
  local doc="$1"
  local severity category rc_count
  severity=$(_extract_severity "$doc")
  category=$(_extract_category "$doc")
  rc_count=$(_count_root_causes "$doc")

  local sev_tier=""
  case "$severity" in
    low) sev_tier="low" ;;
    medium) sev_tier="medium" ;;
    high|critical) sev_tier="high" ;;
  esac

  local rc_tier=""
  if [[ -n "$rc_count" ]]; then
    # RC thresholds: 1 low, 2–3 medium, 4+ high.
    rc_tier=$(_bucket_count "$rc_count" 1 3)
  fi

  # If both signals are missing, fall back to medium (FR-10).
  if [[ -z "$sev_tier" && -z "$rc_tier" ]]; then
    echo "medium"
    return
  fi

  local base
  base=$(_max_complexity "$sev_tier" "$rc_tier")
  if [[ -z "$base" ]]; then
    base="medium"
  fi

  # Category bump (security or performance → bump one tier).
  local cat_bump=false
  case "$category" in
    security|performance)
      base=$(_bump_complexity "$base")
      cat_bump=true
      ;;
  esac

  # CHORE-031 / T1: neither severity alone nor RC count alone can promote
  # to high. Require severity ≥ medium AND at least one escalation signal
  # (rc_count ≥ 4 → rc_tier=high, or security/performance category bump).
  if [[ "$base" == "high" ]]; then
    local sev_rank=0
    case "$sev_tier" in medium) sev_rank=2 ;; high) sev_rank=3 ;; esac
    if (( sev_rank < 2 )) || { [[ "$rc_tier" != "high" ]] && [[ "$cat_bump" != "true" ]]; }; then
      base="medium"
    fi
  fi

  echo "$base"
}

_classify_feature_init() {
  local doc="$1"
  local fr_count sec
  fr_count=$(_count_functional_requirements "$doc")
  sec=$(_check_security_auth_perf "$doc")

  if [[ -z "$fr_count" && -z "$sec" ]]; then
    echo "medium"  # FR-10 fallback → sonnet
    return
  fi

  local base=""
  if [[ -n "$fr_count" ]]; then
    # Feature thresholds: ≤5 low, 6–12 medium, 13+ high.
    base=$(_bucket_count "$fr_count" 5 12)
  fi
  if [[ -z "$base" ]]; then
    base="medium"
  fi

  if [[ "$sec" == "true" ]]; then
    base=$(_bump_complexity "$base")
  fi

  echo "$base"
}

_classify_feature_post_plan() {
  local plan="$1"
  local phases
  phases=$(_count_phases "$plan")
  if [[ -z "$phases" ]]; then
    echo ""  # caller preserves persisted tier (NFR-5)
    return
  fi
  # Feature phase thresholds: 1 low, 2–3 medium, 4+ high.
  _bucket_count "$phases" 1 3
}

cmd_classify_init() {
  local id="$1"
  local doc="${2:-}"
  local file
  file=$(state_file "$id")
  validate_state_file "$file"

  local chain_type
  chain_type=$(jq -r '.type' "$file")

  if [[ -z "$doc" ]]; then
    doc=$(_default_doc_path "$id" "$chain_type")
  fi

  if [[ -z "$doc" || ! -f "$doc" ]]; then
    # No doc to parse — FR-10 fallback to medium → sonnet.
    echo "medium"
    return
  fi

  case "$chain_type" in
    chore)   _classify_chore "$doc" ;;
    bug)     _classify_bug "$doc" ;;
    feature) _classify_feature_init "$doc" ;;
    *)
      echo "Error: Unsupported chain type '${chain_type}' for classify-init." >&2
      exit 1
      ;;
  esac
}

cmd_classify_post_plan() {
  local id="$1"
  local plan="${2:-}"
  local file
  file=$(state_file "$id")
  validate_state_file "$file"

  local chain_type
  chain_type=$(jq -r '.type' "$file")
  if [[ "$chain_type" != "feature" ]]; then
    echo "Error: classify-post-plan is only valid for feature chains (got '${chain_type}')." >&2
    exit 1
  fi

  if [[ -z "$plan" ]]; then
    plan=$(_default_plan_path "$id")
  fi

  local persisted
  persisted=$(jq -r '.complexity // ""' "$file")

  local new_tier=""
  if [[ -n "$plan" && -f "$plan" ]]; then
    new_tier=$(_classify_feature_post_plan "$plan")
  fi

  if [[ -z "$new_tier" ]]; then
    # NFR-5: no plan / unparseable → retain persisted tier, no upgrade.
    echo "${persisted:-medium}"
    return
  fi

  # Upgrade-only max(persisted, new_tier). If persisted is unset, use new.
  local resolved
  if [[ -z "$persisted" ]]; then
    resolved="$new_tier"
  else
    resolved=$(_max_complexity "$persisted" "$new_tier")
    if [[ -z "$resolved" ]]; then
      resolved="$new_tier"
    fi
  fi

  # FEAT-014 FR-2b: persist the result and flip complexityStage to "post-plan"
  # when an actual upgrade occurred (the whole point of the post-plan stage is
  # to mark the transition for audit-trail purposes). When nothing changed we
  # leave the state file alone so the caller can grep for "no-op" semantics.
  if [[ "$resolved" != "$persisted" ]]; then
    jq --arg tier "$resolved" \
      '.complexity = $tier | .complexityStage = "post-plan"' \
      "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
  fi

  echo "$resolved"
}

# Resolve the final tier per the FR-3 precedence chain. This is a debug
# helper — the canonical walker lives in the orchestrator SKILL.md as
# markdown prose (Phase 2 deliverable). The shell implementation here
# mirrors that prose verbatim so unit tests can exercise every precedence
# level, the baseline-lock interaction, and the hard-vs-soft distinction.
cmd_resolve_tier() {
  local id="$1"
  shift || true
  local step_name="$1"
  shift || true

  local cli_model=""
  local cli_complexity=""
  local cli_model_for=""
  local state_override_flag=""
  local state_override_value=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --cli-model)
        cli_model="${2:-}"; shift 2 ;;
      --cli-complexity)
        cli_complexity="${2:-}"; shift 2 ;;
      --cli-model-for)
        cli_model_for="${2:-}"; shift 2 ;;
      --state-override)
        state_override_flag="set"
        state_override_value="${2:-}"; shift 2 ;;
      *)
        echo "Error: Unknown resolve-tier flag '$1'." >&2
        exit 1
        ;;
    esac
  done

  local file
  file=$(state_file "$id")
  validate_state_file "$file"

  local baseline locked complexity_label
  baseline=$(_step_baseline "$step_name")
  locked=$(_step_baseline_locked "$step_name")
  complexity_label=$(jq -r '.complexity // ""' "$file")

  # Step 1: start at baseline.
  local tier="$baseline"

  # Step 2: apply work-item complexity unless baseline-locked.
  if [[ "$locked" != "true" ]]; then
    local wi_tier
    wi_tier=$(_complexity_to_tier "$complexity_label")
    if [[ -n "$wi_tier" ]]; then
      tier=$(_max_tier "$tier" "$wi_tier")
    fi
  fi

  # Step 3: walk the override chain in FR-5 precedence order. The first
  # non-null entry wins; hard overrides replace, soft overrides upgrade-only.
  # The `--state-override` flag lets unit tests inject a state.modelOverride
  # value without having to round-trip through `set-complexity`; when not
  # supplied, the flag falls back to the persisted value.
  local effective_state_override
  if [[ "$state_override_flag" == "set" ]]; then
    effective_state_override="$state_override_value"
  else
    effective_state_override=$(jq -r '.modelOverride // ""' "$file")
  fi

  # Resolve the per-step value for --cli-model-for. Format: step:tier.
  local per_step_value=""
  if [[ -n "$cli_model_for" ]]; then
    local mf_step="${cli_model_for%%:*}"
    local mf_tier="${cli_model_for##*:}"
    if [[ "$mf_step" == "$step_name" ]]; then
      per_step_value="$mf_tier"
    fi
  fi

  # Chain entries: (value, kind). Walk in order; first non-empty wins.
  # Both arrays MUST stay the same length — the walker below uses
  # ${#chain_values[@]} as the loop bound so adding a new precedence level
  # only requires appending to both arrays (no loop-bound bump needed).
  local chain_values=("$per_step_value" "$cli_model" "$cli_complexity" "$effective_state_override")
  local chain_kinds=("hard" "hard" "soft" "soft")
  local i=0
  while (( i < ${#chain_values[@]} )); do
    local value="${chain_values[$i]}"
    local kind="${chain_kinds[$i]}"
    if [[ -n "$value" ]]; then
      if [[ "$kind" == "hard" ]]; then
        # Hard override: replace tier entirely (can go below baseline).
        tier="$value"
      else
        # Soft override: upgrade-only, respects baseline lock.
        if [[ "$locked" == "true" ]]; then
          : # baseline-locked steps reject soft overrides
        else
          # For --cli-complexity, translate low/medium/high → tier first.
          local soft_tier="$value"
          local translated
          translated=$(_complexity_to_tier "$value")
          if [[ -n "$translated" ]]; then
            soft_tier="$translated"
          fi
          tier=$(_max_tier "$tier" "$soft_tier")
        fi
      fi
      break
    fi
    i=$((i + 1))
  done

  echo "$tier"
}

# Generate the feature chain step sequence (FR-1)
# Steps 1-5 are fixed, then phase steps are added dynamically later
generate_feature_steps() {
  cat <<'STEPS'
[
  {"name":"Document feature requirements","skill":"documenting-features","context":"main","status":"pending","artifact":null,"completedAt":null},
  {"name":"Review requirements (standard)","skill":"reviewing-requirements","context":"fork","status":"pending","artifact":null,"completedAt":null},
  {"name":"Create implementation plan","skill":"creating-implementation-plans","context":"fork","status":"pending","artifact":null,"completedAt":null},
  {"name":"Plan approval","skill":null,"context":"pause","status":"pending","artifact":null,"completedAt":null},
  {"name":"Document QA test plan","skill":"documenting-qa","context":"main","status":"pending","artifact":null,"completedAt":null}
]
STEPS
}

# Generate the chore chain step sequence (FR-1)
# Fixed 7-step sequence with a single PR-review pause point, no phase loop
generate_chore_steps() {
  cat <<'STEPS'
[
  {"name":"Document chore","skill":"documenting-chores","context":"main","status":"pending","artifact":null,"completedAt":null},
  {"name":"Review requirements (standard)","skill":"reviewing-requirements","context":"fork","status":"pending","artifact":null,"completedAt":null},
  {"name":"Document QA test plan","skill":"documenting-qa","context":"main","status":"pending","artifact":null,"completedAt":null},
  {"name":"Execute chore","skill":"executing-chores","context":"fork","status":"pending","artifact":null,"completedAt":null},
  {"name":"PR review","skill":null,"context":"pause","status":"pending","artifact":null,"completedAt":null},
  {"name":"Execute QA","skill":"executing-qa","context":"main","status":"pending","artifact":null,"completedAt":null},
  {"name":"Finalize","skill":"finalizing-workflow","context":"fork","status":"pending","artifact":null,"completedAt":null}
]
STEPS
}

# Generate the bug chain step sequence (FR-1)
# Fixed 7-step sequence mirroring the chore chain but with bug-specific skills, no phase loop
generate_bug_steps() {
  cat <<'STEPS'
[
  {"name":"Document bug","skill":"documenting-bugs","context":"main","status":"pending","artifact":null,"completedAt":null},
  {"name":"Review requirements (standard)","skill":"reviewing-requirements","context":"fork","status":"pending","artifact":null,"completedAt":null},
  {"name":"Document QA test plan","skill":"documenting-qa","context":"main","status":"pending","artifact":null,"completedAt":null},
  {"name":"Execute bug fix","skill":"executing-bug-fixes","context":"fork","status":"pending","artifact":null,"completedAt":null},
  {"name":"PR review","skill":null,"context":"pause","status":"pending","artifact":null,"completedAt":null},
  {"name":"Execute QA","skill":"executing-qa","context":"main","status":"pending","artifact":null,"completedAt":null},
  {"name":"Finalize","skill":"finalizing-workflow","context":"fork","status":"pending","artifact":null,"completedAt":null}
]
STEPS
}

# Post-phase steps appended after phase steps are populated
generate_post_phase_steps() {
  cat <<'STEPS'
[
  {"name":"Create PR","skill":"orchestrator","context":"fork","status":"pending","artifact":null,"completedAt":null},
  {"name":"PR review","skill":null,"context":"pause","status":"pending","artifact":null,"completedAt":null},
  {"name":"Execute QA","skill":"executing-qa","context":"main","status":"pending","artifact":null,"completedAt":null},
  {"name":"Finalize","skill":"finalizing-workflow","context":"fork","status":"pending","artifact":null,"completedAt":null}
]
STEPS
}

# --- Commands ---

cmd_init() {
  local id="$1"
  local type="$2"
  validate_id "$id"

  ensure_dir
  local file
  file=$(state_file "$id")

  # Idempotency: if state file exists, return current state
  if [[ -f "$file" ]]; then
    cat "$file"
    return 0
  fi

  local steps
  case "$type" in
    feature)
      steps=$(generate_feature_steps)
      ;;
    chore)
      steps=$(generate_chore_steps)
      ;;
    bug)
      steps=$(generate_bug_steps)
      ;;
    *)
      echo "Error: Unknown chain type '${type}'. Supported: feature, chore, bug." >&2
      exit 1
      ;;
  esac

  local now
  now=$(now_iso)

  jq -n \
    --arg id "$id" \
    --arg type "$type" \
    --arg now "$now" \
    --argjson steps "$steps" \
    '{
      id: $id,
      type: $type,
      currentStep: 0,
      status: "in-progress",
      pauseReason: null,
      gate: null,
      steps: $steps,
      phases: { total: 0, completed: 0 },
      prNumber: null,
      branch: null,
      startedAt: $now,
      lastResumedAt: null,
      complexity: null,
      complexityStage: "init",
      modelOverride: null,
      modelSelections: []
    }' > "${file}.tmp" && mv "${file}.tmp" "$file"

  cat "$file"
}

cmd_status() {
  local id="$1"
  local file
  file=$(state_file "$id")
  validate_state_file "$file"
  cat "$file"
}

cmd_advance() {
  local id="$1"
  local artifact="${2:-}"
  local file
  file=$(state_file "$id")
  validate_state_file "$file"

  local current_step total_steps current_status
  current_step=$(jq -r '.currentStep' "$file")
  total_steps=$(jq -r '.steps | length' "$file")
  current_status=$(jq -r ".steps[${current_step}].status" "$file")

  # Idempotency: no-op if step already complete
  if [[ "$current_status" == "complete" ]]; then
    cat "$file"
    return 0
  fi

  local now
  now=$(now_iso)
  local next_step=$((current_step + 1))

  # Update current step to complete, advance currentStep
  local artifact_arg="null"
  if [[ -n "$artifact" ]]; then
    artifact_arg=$(jq -n --arg a "$artifact" '$a')
  fi

  jq \
    --argjson step "$current_step" \
    --argjson next "$next_step" \
    --arg now "$now" \
    --argjson artifact "$artifact_arg" \
    '.steps[$step].status = "complete"
     | .steps[$step].completedAt = $now
     | (if $artifact != null then .steps[$step].artifact = $artifact else . end)
     | .currentStep = $next
     | .gate = null' \
    "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"

  # Update phase completion count if the completed step had a phaseNumber
  local has_phase
  has_phase=$(jq --argjson step "$current_step" '.steps[$step] | has("phaseNumber")' "$file")
  if [[ "$has_phase" == "true" ]]; then
    jq '.phases.completed = ([.steps[] | select(has("phaseNumber") and .status == "complete")] | length)' \
      "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
  fi

  cat "$file"
}

cmd_pause() {
  local id="$1"
  local reason="$2"
  local file
  file=$(state_file "$id")
  validate_state_file "$file"

  if [[ "$reason" != "plan-approval" && "$reason" != "pr-review" && "$reason" != "review-findings" ]]; then
    echo "Error: Invalid pause reason '${reason}'. Expected 'plan-approval', 'pr-review', or 'review-findings'." >&2
    exit 1
  fi

  jq --arg reason "$reason" \
    '.status = "paused" | .pauseReason = $reason | .gate = null' \
    "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"

  cat "$file"
}

cmd_resume() {
  local id="$1"
  local file
  file=$(state_file "$id")
  validate_state_file "$file"

  local now
  now=$(now_iso)

  local current_step
  current_step=$(jq -r '.currentStep' "$file")

  jq --arg now "$now" --argjson step "$current_step" \
    '.status = "in-progress" | .pauseReason = null | .gate = null | .error = null | .lastResumedAt = $now
     | if .steps[$step].status == "failed" then .steps[$step].status = "pending" else . end' \
    "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"

  cat "$file"
}

cmd_set_gate() {
  local id="$1"
  local gate_type="$2"
  local file
  file=$(state_file "$id")
  validate_state_file "$file"

  local current_status
  current_status=$(jq -r '.status' "$file")
  if [[ "$current_status" != "in-progress" ]]; then
    echo "Error: Cannot set gate on a ${current_status} workflow. Gate is only valid for in-progress workflows." >&2
    exit 1
  fi

  if [[ "$gate_type" != "findings-decision" ]]; then
    echo "Error: Invalid gate type '${gate_type}'. Expected 'findings-decision'." >&2
    exit 1
  fi

  jq --arg gate "$gate_type" \
    '.gate = $gate' \
    "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"

  cat "$file"
}

cmd_clear_gate() {
  local id="$1"
  local file
  file=$(state_file "$id")
  validate_state_file "$file"

  jq '.gate = null' \
    "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"

  cat "$file"
}

cmd_record_findings() {
  local id="$1"
  local step_index="$2"
  local errors="$3"
  local warnings="$4"
  local info="$5"
  local decision="$6"
  local summary="$7"
  shift 7

  # Validate step_index is a non-negative integer.
  if [[ -z "$step_index" ]] || ! [[ "$step_index" =~ ^[0-9]+$ ]]; then
    echo "Error: record-findings requires a numeric <stepIndex>; got '${step_index}'." >&2
    exit 1
  fi

  # Validate errors, warnings, info are non-negative integers.
  if [[ -z "$errors" ]] || ! [[ "$errors" =~ ^[0-9]+$ ]]; then
    echo "Error: record-findings requires a numeric <errors>; got '${errors}'." >&2
    exit 1
  fi
  if [[ -z "$warnings" ]] || ! [[ "$warnings" =~ ^[0-9]+$ ]]; then
    echo "Error: record-findings requires a numeric <warnings>; got '${warnings}'." >&2
    exit 1
  fi
  if [[ -z "$info" ]] || ! [[ "$info" =~ ^[0-9]+$ ]]; then
    echo "Error: record-findings requires a numeric <info>; got '${info}'." >&2
    exit 1
  fi

  # Validate decision is one of the allowed values.
  case "$decision" in
    advanced|auto-advanced|user-advanced|auto-fixed|paused) ;;
    *)
      echo "Error: record-findings requires decision to be one of: advanced, auto-advanced, user-advanced, auto-fixed, paused; got '${decision}'." >&2
      exit 1
      ;;
  esac

  # Parse optional flags: --rerun and --details-file <path>.
  local rerun=false
  local details_file=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --rerun)
        rerun=true
        shift
        ;;
      --details-file)
        [[ $# -ge 2 ]] || { echo "Error: --details-file requires a path argument." >&2; exit 1; }
        details_file="$2"
        shift 2
        ;;
      *)
        echo "Error: record-findings unknown flag '${1}'." >&2
        exit 1
        ;;
    esac
  done

  local file
  file=$(state_file "$id")
  validate_state_file "$file"

  # Bounds check: stepIndex must be < length(.steps).
  local steps_len
  steps_len=$(jq '.steps | length' "$file")
  if (( step_index >= steps_len )); then
    echo "Error: stepIndex ${step_index} out of bounds for workflow ${id} (steps length: ${steps_len})." >&2
    exit 1
  fi

  # Determine target field name.
  local field_name="findings"
  if [[ "$rerun" == "true" ]]; then
    field_name="rerunFindings"
  fi

  # Build the base findings JSON object.
  local findings_json
  findings_json=$(jq -n \
    --argjson errors "$errors" \
    --argjson warnings "$warnings" \
    --argjson info "$info" \
    --arg decision "$decision" \
    --arg summary "$summary" \
    '{errors: $errors, warnings: $warnings, info: $info, decision: $decision, summary: $summary}')

  # Handle --details-file: only merge details when decision == "auto-advanced".
  if [[ -n "$details_file" && "$decision" == "auto-advanced" ]]; then
    if [[ ! -f "$details_file" ]]; then
      echo "[warn] Could not read details file — recording counts only." >&2
    else
      local details_content
      if details_content=$(jq -e '. | arrays' "$details_file" 2>/dev/null); then
        findings_json=$(echo "$findings_json" | jq --argjson details "$details_content" '. + {details: $details}')
      else
        echo "[warn] Could not read details file — recording counts only." >&2
      fi
    fi
  fi

  # Write findings object to the target field on the step entry.
  jq --argjson idx "$step_index" --argjson obj "$findings_json" \
    ".steps[\$idx].${field_name} = \$obj" "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"

  cat "$file"
}

cmd_fail() {
  local id="$1"
  local message="$2"
  local file
  file=$(state_file "$id")
  validate_state_file "$file"

  local current_step
  current_step=$(jq -r '.currentStep' "$file")

  jq --arg msg "$message" --argjson step "$current_step" \
    '.status = "failed" | .error = $msg | .steps[$step].status = "failed" | .gate = null' \
    "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"

  cat "$file"
}

cmd_complete() {
  local id="$1"
  local file
  file=$(state_file "$id")
  validate_state_file "$file"

  local now
  now=$(now_iso)

  jq --arg now "$now" \
    '.status = "complete" | .completedAt = $now' \
    "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"

  cat "$file"
}

cmd_set_pr() {
  local id="$1"
  local pr_number="$2"
  local branch="$3"
  local file
  file=$(state_file "$id")
  validate_state_file "$file"

  jq --argjson pr "$pr_number" --arg branch "$branch" \
    '.prNumber = $pr | .branch = $branch' \
    "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"

  cat "$file"
}

cmd_populate_phases() {
  local id="$1"
  local count="$2"
  local file
  file=$(state_file "$id")
  validate_state_file "$file"

  # Idempotency: if phase steps already exist, return current state
  local existing_phases
  existing_phases=$(jq '[.steps[] | select(has("phaseNumber"))] | length' "$file")
  if [[ "$existing_phases" -gt 0 ]]; then
    cat "$file"
    return 0
  fi

  # Generate phase steps
  local phase_steps="[]"
  for ((i = 1; i <= count; i++)); do
    phase_steps=$(echo "$phase_steps" | jq --argjson n "$i" --argjson total "$count" \
      '. + [{"name":"Implement phase \($n) of \($total)","skill":"implementing-plan-phases","context":"fork","status":"pending","artifact":null,"completedAt":null,"phaseNumber":$n}]')
  done

  local post_steps
  post_steps=$(generate_post_phase_steps)

  # Append phase steps + post-phase steps after the initial 6 steps, update phases.total
  jq --argjson phase_steps "$phase_steps" \
     --argjson post_steps "$post_steps" \
     --argjson total "$count" \
    '.steps = .steps[:6] + $phase_steps + $post_steps | .phases.total = $total' \
    "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"

  cat "$file"
}

cmd_phase_count() {
  local id="$1"

  # Find the implementation plan using sorted glob for deterministic results
  local plan_file=""
  if [[ -d "requirements/implementation" ]]; then
    plan_file=$(ls requirements/implementation/${id}-*.md 2>/dev/null | sort | head -1 || true)
  fi

  if [[ -z "$plan_file" ]]; then
    echo "Error: No implementation plan found for ${id} in requirements/implementation/" >&2
    exit 1
  fi

  local count
  count=$(grep -cE '^### Phase [0-9]+' "$plan_file" || true)

  if [[ "$count" -eq 0 ]]; then
    echo "Error: Implementation plan has 0 phases — plan may be malformed: ${plan_file}" >&2
    exit 1
  fi

  echo "$count"
}

cmd_phase_status() {
  local id="$1"
  local file
  file=$(state_file "$id")
  validate_state_file "$file"

  jq '[.steps[] | select(has("phaseNumber")) | {phaseNumber, status, completedAt}]' "$file"
}

# Set work-item complexity tier (FEAT-014 FR-15). Writes .complexity only.
# complexityStage is untouched — manual override is considered a user edit, not a
# stage transition. Tier must be one of low|medium|high.
cmd_set_complexity() {
  local id="$1"
  local tier="$2"
  local file
  file=$(state_file "$id")
  validate_state_file "$file"

  if [[ "$tier" != "low" && "$tier" != "medium" && "$tier" != "high" ]]; then
    echo "Error: Invalid complexity tier '${tier}'. Expected 'low', 'medium', or 'high'." >&2
    exit 1
  fi

  jq --arg tier "$tier" '.complexity = $tier' \
    "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"

  cat "$file"
}

# Resolve model tier for a named step (FEAT-014 FR-15).
#
# Thin wrapper around cmd_resolve_tier that omits CLI-flag handling. The full
# FR-3 precedence chain (including --model, --complexity, --model-for) lives in
# cmd_resolve_tier — this helper is the state-scope subset for dry-run
# inspection via the debug/get-model path.
#
# Semantics mirror FR-5 exactly:
#   1. Baseline-locked steps (finalizing-workflow, pr-creation) stay at
#      baseline regardless of .complexity and .modelOverride. Only hard
#      overrides (orchestrator-scope) bypass the lock.
#   2. For non-locked steps, resolved = max(baseline, complexity_tier,
#      modelOverride) — upgrade-only. .modelOverride is a soft override per
#      FR-5 #4 and cannot downgrade below the baseline floor or the computed
#      tier.
#
# Any divergence from cmd_resolve_tier would be a latent bug: this helper
# delegates to the same walker to guarantee both resolvers agree on identical
# inputs.
cmd_get_model() {
  local id="$1"
  local step_name="$2"
  # Delegate to the FR-3 walker without any CLI-flag overrides. This keeps
  # the state-scope semantics (baseline + work-item complexity + soft state
  # override) in lockstep with the full resolver.
  cmd_resolve_tier "$id" "$step_name"
}

# Append an entry to the modelSelections audit trail (FEAT-014 FR-7, NFR-3).
# Called by the orchestrator immediately before each fork so that a mid-fork
# crash still leaves a record of which model was chosen.
cmd_record_model_selection() {
  local id="$1"
  local step_index="$2"
  local skill="$3"
  local mode="$4"
  local phase="$5"
  local tier="$6"
  local complexity_stage="$7"
  local started_at="$8"

  # Guard: stepIndex must be a non-negative integer — jq --argjson on a
  # non-numeric value produces a cryptic parser error instead of a clear
  # usage message. Match the guard style used elsewhere in this file.
  if [[ -z "$step_index" ]] || ! [[ "$step_index" =~ ^[0-9]+$ ]]; then
    echo "Error: record-model-selection requires a numeric <stepIndex>; got '${step_index}'." >&2
    exit 1
  fi

  local file
  file=$(state_file "$id")
  validate_state_file "$file"

  # Normalize "null" literal into JSON null for the optional fields.
  # Phase is numeric when provided (integer phase number); mode is a string.
  local phase_arg="null"
  if [[ -n "$phase" && "$phase" != "null" ]]; then
    if [[ "$phase" =~ ^[0-9]+$ ]]; then
      phase_arg="$phase"
    else
      phase_arg=$(jq -n --arg v "$phase" '$v')
    fi
  fi
  local mode_arg="null"
  if [[ -n "$mode" && "$mode" != "null" ]]; then
    mode_arg=$(jq -n --arg v "$mode" '$v')
  fi

  jq \
    --argjson stepIndex "$step_index" \
    --arg skill "$skill" \
    --argjson mode "$mode_arg" \
    --argjson phase "$phase_arg" \
    --arg tier "$tier" \
    --arg complexityStage "$complexity_stage" \
    --arg startedAt "$started_at" \
    '.modelSelections += [{
       stepIndex: $stepIndex,
       skill: $skill,
       mode: $mode,
       phase: $phase,
       tier: $tier,
       complexityStage: $complexityStage,
       startedAt: $startedAt
     }]' \
    "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"

  cat "$file"
}

# --- FEAT-014 Phase 4: Retry, Resume, Version Compatibility ---

# FR-11 retry-with-tier-upgrade escalator. Given the current fork tier, emit the
# next tier up in the haiku → sonnet → opus progression. Exits 2 at opus (the
# caller is expected to record `fail` state after that, per FR-11).
cmd_next_tier_up() {
  local current="$1"
  case "$current" in
    haiku)
      echo "sonnet"
      ;;
    sonnet)
      echo "opus"
      ;;
    opus)
      echo "Error: retry exhausted at opus — no higher tier available" >&2
      exit 2
      ;;
    *)
      echo "Error: next-tier-up requires a known tier (haiku|sonnet|opus); got '${current}'" >&2
      exit 1
      ;;
  esac
}

# FR-12 stage-aware, upgrade-only re-computation on resume. Reads the persisted
# complexityStage, re-runs the init-stage classifier (always) and the post-plan
# classifier (only when stage is already post-plan), applies upgrade-only
# max(persisted, new), and persists the new tier when it strictly increased.
# Echoes the resolved tier on stdout and the FR-12 upgrade log line on stderr
# when an upgrade occurred. Proceeds silently otherwise. complexityStage is
# never regressed — `init` stays `init`, `post-plan` stays `post-plan`.
cmd_resume_recompute() {
  local id="$1"
  shift || true

  local doc_override=""
  local plan_override=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --doc)
        doc_override="${2:-}"; shift 2 ;;
      --plan)
        plan_override="${2:-}"; shift 2 ;;
      *)
        echo "Error: Unknown resume-recompute flag '$1'." >&2
        exit 1
        ;;
    esac
  done

  local file
  file=$(state_file "$id")
  validate_state_file "$file"

  local chain_type persisted stage
  chain_type=$(jq -r '.type' "$file")
  persisted=$(jq -r '.complexity // ""' "$file")
  stage=$(jq -r '.complexityStage // "init"' "$file")

  # Re-compute init-stage signals (always, per FR-12).
  local doc="$doc_override"
  if [[ -z "$doc" ]]; then
    doc=$(_default_doc_path "$id" "$chain_type")
  fi

  local init_tier=""
  if [[ -n "$doc" && -f "$doc" ]]; then
    case "$chain_type" in
      chore)   init_tier=$(_classify_chore "$doc") ;;
      bug)     init_tier=$(_classify_bug "$doc") ;;
      feature) init_tier=$(_classify_feature_init "$doc") ;;
    esac
  fi
  if [[ -z "$init_tier" ]]; then
    # Unparseable / missing → FR-10 fallback.
    init_tier="medium"
  fi

  # If already in post-plan stage and chain is a feature, also re-read phases.
  local post_plan_tier=""
  if [[ "$stage" == "post-plan" && "$chain_type" == "feature" ]]; then
    local plan="$plan_override"
    if [[ -z "$plan" ]]; then
      plan=$(_default_plan_path "$id")
    fi
    if [[ -n "$plan" && -f "$plan" ]]; then
      post_plan_tier=$(_classify_feature_post_plan "$plan")
    fi
  fi

  # Compute the upgrade-only candidate: max(persisted, init_tier, post_plan_tier).
  #
  # init_tier is never empty at this point: the FR-10 fallback above defaults
  # it to "medium" when the doc is missing or unparseable. post_plan_tier CAN
  # be empty (e.g., plan file absent while stage=post-plan — NFR-5 says we
  # retain the init-stage tier and do NOT upgrade in that case). _max_complexity
  # treats an empty operand as rank 0, so passing "" on one side returns the
  # non-empty side unchanged — that's exactly the "retain init-stage" semantic
  # we want. The subsequent max(persisted, candidate) preserves upgrade-only
  # behavior even when persisted is itself empty (first-run after migration).
  local candidate="$init_tier"
  if [[ -n "$post_plan_tier" ]]; then
    candidate=$(_max_complexity "$candidate" "$post_plan_tier")
  fi

  local resolved="$persisted"
  if [[ -z "$resolved" ]]; then
    resolved="$candidate"
  else
    resolved=$(_max_complexity "$resolved" "$candidate")
    if [[ -z "$resolved" ]]; then
      resolved="$candidate"
    fi
  fi

  # Persist when the state file has no complexity yet (FR-13 first-run after
  # migration) OR when the tier strictly upgraded. Never downgrade.
  if [[ -z "$persisted" ]]; then
    # No prior value — write the computed tier. No upgrade log (this is the
    # initial population, not a resume upgrade).
    if [[ -n "$resolved" ]]; then
      jq --arg tier "$resolved" '.complexity = $tier' \
        "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
    fi
  elif [[ "$resolved" != "$persisted" ]]; then
    # Sanity: the upgrade-only rule should already guarantee this, but assert.
    local ordered
    ordered=$(_max_complexity "$persisted" "$resolved")
    if [[ "$ordered" != "$resolved" ]]; then
      # Downgrade blocked — retain persisted tier silently.
      echo "$persisted"
      return
    fi
    jq --arg tier "$resolved" '.complexity = $tier' \
      "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
    echo "[model] Work-item complexity upgraded since last invocation: ${persisted} → ${resolved}. Audit trail continues." >&2
  fi

  echo "$resolved"
}

# NFR-6 Claude Code minimum-version check. Graceful on all failure modes:
#   - `claude` command not on PATH  → exit 0 (assume compatible, skip check)
#   - `claude --version` parse fails → exit 0 (same rationale)
#   - current >= required            → exit 0 silently
#   - current <  required            → exit 1 and emit the documented warning
# Intentionally additive: the orchestrator logs the warning and continues; the
# per-call-site NFR-6 fallback wrapper still kicks in on an Agent-tool rejection
# regardless of what this check decides.
cmd_check_claude_version() {
  local required="${1:-2.1.72}"

  local raw=""
  if command -v claude >/dev/null 2>&1; then
    raw=$(claude --version 2>/dev/null || true)
  fi

  # Parse the first N.N.N sequence out of the output (version strings sometimes
  # include a build suffix or a leading prefix like "Claude Code").
  local current=""
  if [[ -n "$raw" ]]; then
    current=$(echo "$raw" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
  fi

  if [[ -z "$current" ]]; then
    # Cannot determine — skip silently (graceful fallback).
    return 0
  fi

  # Compare semver: split into fields and compare numerically.
  local cur_major cur_minor cur_patch req_major req_minor req_patch
  IFS='.' read -r cur_major cur_minor cur_patch <<< "$current"
  IFS='.' read -r req_major req_minor req_patch <<< "$required"

  if (( cur_major > req_major )); then
    return 0
  elif (( cur_major == req_major )); then
    if (( cur_minor > req_minor )); then
      return 0
    elif (( cur_minor == req_minor )); then
      if (( cur_patch >= req_patch )); then
        return 0
      fi
    fi
  fi

  # Current < required — emit warning and signal the caller.
  echo "[model] Claude Code ${current} is below the minimum ${required} required for adaptive model selection. Forks will fall back to parent-model inheritance via the NFR-6 wrapper." >&2
  return 1
}

# --- Main ---

if [[ $# -lt 1 ]]; then
  usage
fi

command="$1"
shift

case "$command" in
  init)
    [[ $# -ge 2 ]] || { echo "Error: init requires <ID> <type>" >&2; exit 1; }
    cmd_init "$1" "$2"
    ;;
  status)
    [[ $# -ge 1 ]] || { echo "Error: status requires <ID>" >&2; exit 1; }
    cmd_status "$1"
    ;;
  advance)
    [[ $# -ge 1 ]] || { echo "Error: advance requires <ID> [artifact-path]" >&2; exit 1; }
    cmd_advance "$1" "${2:-}"
    ;;
  pause)
    [[ $# -ge 2 ]] || { echo "Error: pause requires <ID> <reason>" >&2; exit 1; }
    cmd_pause "$1" "$2"
    ;;
  resume)
    [[ $# -ge 1 ]] || { echo "Error: resume requires <ID>" >&2; exit 1; }
    cmd_resume "$1"
    ;;
  fail)
    [[ $# -ge 2 ]] || { echo "Error: fail requires <ID> <message>" >&2; exit 1; }
    cmd_fail "$1" "$2"
    ;;
  complete)
    [[ $# -ge 1 ]] || { echo "Error: complete requires <ID>" >&2; exit 1; }
    cmd_complete "$1"
    ;;
  set-pr)
    [[ $# -ge 3 ]] || { echo "Error: set-pr requires <ID> <pr-number> <branch>" >&2; exit 1; }
    cmd_set_pr "$1" "$2" "$3"
    ;;
  populate-phases)
    [[ $# -ge 2 ]] || { echo "Error: populate-phases requires <ID> <count>" >&2; exit 1; }
    cmd_populate_phases "$1" "$2"
    ;;
  phase-count)
    [[ $# -ge 1 ]] || { echo "Error: phase-count requires <ID>" >&2; exit 1; }
    cmd_phase_count "$1"
    ;;
  phase-status)
    [[ $# -ge 1 ]] || { echo "Error: phase-status requires <ID>" >&2; exit 1; }
    cmd_phase_status "$1"
    ;;
  set-complexity)
    [[ $# -ge 2 ]] || { echo "Error: set-complexity requires <ID> <tier>" >&2; exit 1; }
    cmd_set_complexity "$1" "$2"
    ;;
  get-model)
    [[ $# -ge 2 ]] || { echo "Error: get-model requires <ID> <step-name>" >&2; exit 1; }
    cmd_get_model "$1" "$2"
    ;;
  record-model-selection)
    [[ $# -ge 8 ]] || { echo "Error: record-model-selection requires <ID> <stepIndex> <skill> <mode> <phase> <tier> <complexityStage> <startedAt>" >&2; exit 1; }
    cmd_record_model_selection "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8"
    ;;
  classify-init)
    [[ $# -ge 1 ]] || { echo "Error: classify-init requires <ID> [doc-path]" >&2; exit 1; }
    cmd_classify_init "$1" "${2:-}"
    ;;
  classify-post-plan)
    [[ $# -ge 1 ]] || { echo "Error: classify-post-plan requires <ID> [plan-path]" >&2; exit 1; }
    cmd_classify_post_plan "$1" "${2:-}"
    ;;
  resolve-tier)
    [[ $# -ge 2 ]] || { echo "Error: resolve-tier requires <ID> <step-name> [flags...]" >&2; exit 1; }
    cmd_resolve_tier "$@"
    ;;
  resume-recompute)
    [[ $# -ge 1 ]] || { echo "Error: resume-recompute requires <ID> [--doc <path>] [--plan <path>]" >&2; exit 1; }
    cmd_resume_recompute "$@"
    ;;
  next-tier-up)
    [[ $# -ge 1 ]] || { echo "Error: next-tier-up requires <tier>" >&2; exit 1; }
    cmd_next_tier_up "$1"
    ;;
  check-claude-version)
    cmd_check_claude_version "${1:-}"
    ;;
  set-gate)
    [[ $# -ge 2 ]] || { echo "Error: set-gate requires <ID> <gate-type>" >&2; exit 1; }
    cmd_set_gate "$1" "$2"
    ;;
  clear-gate)
    [[ $# -ge 1 ]] || { echo "Error: clear-gate requires <ID>" >&2; exit 1; }
    cmd_clear_gate "$1"
    ;;
  record-findings)
    [[ $# -ge 7 ]] || { echo "Error: record-findings requires <ID> <stepIndex> <errors> <warnings> <info> <decision> <summary> [--rerun] [--details-file <path>]" >&2; exit 1; }
    cmd_record_findings "$@"
    ;;
  *)
    echo "Error: Unknown command '${command}'" >&2
    usage
    ;;
esac
