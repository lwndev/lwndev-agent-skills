#!/usr/bin/env bats
# End-to-end integration fixtures for finalize.sh (Phase 6).
#
# Unlike finalize.bats (which stubs every subscript), this suite stubs only
# the external world:
#   - `gh` is PATH-shadowed to return canonical JSON for `pr view`, succeed
#     for `pr merge`, and return a curated file list for `pr view --json files`.
#   - Remote git ops (`push`, `fetch`, `pull`) are shadowed via a `git`
#     wrapper that delegates all LOCAL ops to the real git binary but
#     intercepts the remote ones.
#
# The real subscripts (preflight-checks.sh, check-idempotent.sh,
# completion-upsert.sh, reconcile-affected-files.sh, plus the plugin-shared
# branch-id-parse.sh, resolve-requirement-doc.sh, checkbox-flip-all.sh) all
# RUN against a real fixture git repo so composition bugs surface.

REAL_SKILL_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
REAL_PLUGIN_ROOT="$(cd "$REAL_SKILL_DIR/../../.." && pwd)"
FINALIZE="${REAL_SKILL_DIR}/finalize.sh"
REAL_GIT="$(command -v git)"

setup() {
  FIXTURE_DIR="$(mktemp -d)"
  REPO_DIR="${FIXTURE_DIR}/repo"
  STUB_DIR="${FIXTURE_DIR}/stubs"
  TRACER="${FIXTURE_DIR}/tracer.log"
  mkdir -p "$REPO_DIR" "$STUB_DIR"
  : > "$TRACER"

  # Default stub-state env values; individual tests override as needed.
  export TRACER REAL_GIT
  export GH_PR_NUMBER="101"
  export GH_PR_TITLE="feat(FEAT-001): demo"
  export GH_PR_URL="https://github.com/example/repo/pull/101"
  export GH_PR_STATE="OPEN"
  export GH_PR_MERGEABLE="MERGEABLE"
  export GH_MERGE_RC="0"
  # Space-separated list of files `gh pr view --json files` should report.
  export GH_PR_FILES=""

  # Put stubs first on PATH so our shadows win.
  export PATH="${STUB_DIR}:${PATH}"

  # Override finalize.sh resolution to point at the REAL scripts even when
  # cwd changes.
  export SKILL_DIR="$REAL_SKILL_DIR"
  export PLUGIN_ROOT="$REAL_PLUGIN_ROOT"
}

teardown() {
  if [ -n "${FIXTURE_DIR:-}" ] && [ -d "$FIXTURE_DIR" ]; then
    rm -rf "$FIXTURE_DIR"
  fi
}

# ---------- gh stub ----------------------------------------------------------

# `gh` stub: handles `auth status`, `pr view` (with/without args), `pr merge`.
write_gh_stub() {
  cat > "${STUB_DIR}/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "TRACE:gh:$*" >> "$TRACER"

case "$1" in
  auth)
    # `gh auth status` always succeeds.
    exit 0
    ;;
esac

if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
  # Detect --json files form → emit one path per line.
  if printf '%s\n' "$@" | grep -q -- "--json files"; then
    # Support both `--jq '.files[].path'` and plain JSON output; in practice
    # reconcile-affected-files.sh pipes through --jq so we emit raw lines.
    for p in $GH_PR_FILES; do
      printf '%s\n' "$p"
    done
    exit 0
  fi
  # Generic `gh pr view --json number,title,state,mergeable,url` form.
  if command -v jq >/dev/null 2>&1; then
    jq -cn \
      --argjson number "$GH_PR_NUMBER" \
      --arg title "$GH_PR_TITLE" \
      --arg state "$GH_PR_STATE" \
      --arg mergeable "$GH_PR_MERGEABLE" \
      --arg url "$GH_PR_URL" \
      '{number: $number, title: $title, state: $state, mergeable: $mergeable, url: $url}'
  else
    printf '{"number":%s,"title":"%s","state":"%s","mergeable":"%s","url":"%s"}\n' \
      "$GH_PR_NUMBER" "$GH_PR_TITLE" "$GH_PR_STATE" "$GH_PR_MERGEABLE" "$GH_PR_URL"
  fi
  exit 0
fi

if [ "$1" = "pr" ] && [ "$2" = "merge" ]; then
  exit "${GH_MERGE_RC:-0}"
fi

# Default: succeed silently.
exit 0
EOF
  chmod +x "${STUB_DIR}/gh"
}

# ---------- git wrapper stub -------------------------------------------------

# `git` wrapper: intercepts push/fetch/pull (remote) and delegates everything
# else to the real git binary so local repo ops (status/add/commit/branch/
# checkout/rev-parse/config) are faithful.
write_git_stub() {
  cat > "${STUB_DIR}/git" <<EOF
#!/usr/bin/env bash
printf '%s\n' "TRACE:git:\$*" >> "$TRACER"

case "\$1" in
  push|fetch|pull)
    # Remote operations: succeed silently, do NOT invoke real git.
    exit 0
    ;;
  revert|reset)
    # Log loudly for no-rollback assertions but still succeed.
    printf '%s\n' "TRACE:git-forbidden:\$*" >> "$TRACER"
    exit 0
    ;;
esac

exec "$REAL_GIT" "\$@"
EOF
  chmod +x "${STUB_DIR}/git"
}

# ---------- fixture repo + doc helpers --------------------------------------

# init_repo [<branch>] — build a minimal git repo with `main` baseline, then
# optionally check out <branch> as a new branch.
init_repo() {
  local branch="${1:-}"
  cd "$REPO_DIR"
  "$REAL_GIT" init -q -b main
  "$REAL_GIT" config user.name "Test User"
  "$REAL_GIT" config user.email "test@example.com"
  "$REAL_GIT" config commit.gpgsign false
  # Seed main with a trivial file so we have a commit to diverge from.
  printf 'main\n' > README.md
  "$REAL_GIT" add README.md
  "$REAL_GIT" commit -q -m "initial"
  if [ -n "$branch" ]; then
    "$REAL_GIT" checkout -q -b "$branch"
  fi
}

# Commit the given path(s) on the current branch.
commit_paths() {
  local msg="$1"; shift
  "$REAL_GIT" add "$@"
  "$REAL_GIT" commit -q -m "$msg"
}

# Write a minimal feature-style requirement doc (unticked ACs, one Affected
# Files bullet, no ## Completion).
write_feature_doc() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<'EOF'
# Feature: Demo

## Overview

Demo feature.

## Acceptance Criteria

- [ ] First criterion
- [ ] Second criterion
- [ ] Third criterion

## Affected Files

- `src/existing.ts`
EOF
}

# Fenced-completion-example variant (Phase 6 edge case 6/8).
write_feature_doc_with_fenced_example() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<'EOF'
# Feature: Fenced Example Demo

## Overview

Shows how to document the Completion section format.

## Acceptance Criteria

- [ ] Do the thing

## Affected Files

- `src/existing.ts`

## Format Reference

The finalizer writes a block like:

```
## Completion

**Status:** `Complete`

**Completed:** 2025-01-01

**Pull Request:** [#999](https://example.com/pr/999)
```

End of reference.
EOF
}

# Feature doc with ticked ACs but no Affected Files section.
write_feature_doc_no_affected_files() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<'EOF'
# Feature: No Affected Files Demo

## Overview

Demo.

## Acceptance Criteria

- [ ] Only item
EOF
}

# CRLF-ending variant.
write_feature_doc_crlf() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  # Printf with explicit \r\n.
  printf '# Feature: CRLF\r\n\r\n## Overview\r\n\r\nDemo.\r\n\r\n## Acceptance Criteria\r\n\r\n- [ ] First\r\n- [ ] Second\r\n\r\n## Affected Files\r\n\r\n- `src/existing.ts`\r\n' > "$path"
}

# Chore-style doc fixture.
write_chore_doc() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<'EOF'
# Chore: Demo

## Overview

Chore demo.

## Acceptance Criteria

- [ ] Cleanup the thing
- [ ] Ship it

## Affected Files

- `scripts/some-chore.sh`
EOF
}

# Bug-style doc fixture.
write_bug_doc() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<'EOF'
# Bug: Demo

## Overview

Bug demo.

## Acceptance Criteria

- [ ] Reproduce fixed
- [ ] Test added

## Affected Files

- `src/buggy.ts`
EOF
}

# Seed the branch with a committed requirement doc so `git status --porcelain`
# is clean at start. `doc_writer` is the name of a fn that writes the doc at
# <path>.
seed_doc_on_branch() {
  local doc_writer="$1" doc_path="$2"
  "$doc_writer" "$doc_path"
  commit_paths "add fixture doc" "$doc_path"
}

# ---------- Test cases -------------------------------------------------------

@test "1. feat branch: full BK happy path" {
  init_repo "feat/FEAT-001-demo"
  write_gh_stub
  write_git_stub
  export GH_PR_NUMBER=101
  export GH_PR_TITLE="feat(FEAT-001): demo"
  export GH_PR_URL="https://github.com/example/repo/pull/101"
  # PR files: one match, two new.
  export GH_PR_FILES="src/existing.ts src/new-a.ts src/new-b.ts"

  seed_doc_on_branch write_feature_doc "requirements/features/FEAT-001-demo.md"

  run bash "$FINALIZE" "feat/FEAT-001-demo"
  [ "$status" -eq 0 ]

  # Full summary.
  [[ "$output" == *"Merged PR #101"* ]]
  [[ "$output" == *"ticked 3 acceptance criteria"* ]]
  [[ "$output" == *"Completion section (appended)"* ]]
  [[ "$output" == *"reconciled 2 new + 0 annotated affected files"* ]]
  [[ "$output" == *"Pushed bookkeeping commit as"* ]]
  [[ "$output" == *"On main, up to date"* ]]

  # Tracer: merge + checkout + fetch + pull all ran (in order).
  grep -F "TRACE:gh:pr merge" "$TRACER"
  grep -F "TRACE:git:checkout main" "$TRACER"
  grep -F "TRACE:git:fetch origin" "$TRACER"
  grep -F "TRACE:git:pull" "$TRACER"
  # BK-5 commit and push.
  grep -E "TRACE:git:commit " "$TRACER"
  grep -E "TRACE:git:push" "$TRACER"

  # Post-merge branch state = main.
  run "$REAL_GIT" -C "$REPO_DIR" branch --show-current
  [ "$output" = "main" ]
}

@test "2. chore branch: BK path succeeds on chore requirements" {
  init_repo "chore/CHORE-001-demo"
  write_gh_stub
  write_git_stub
  export GH_PR_NUMBER=201
  export GH_PR_TITLE="chore(CHORE-001): demo"
  export GH_PR_URL="https://github.com/example/repo/pull/201"
  export GH_PR_FILES="scripts/some-chore.sh"

  seed_doc_on_branch write_chore_doc "requirements/chores/CHORE-001-demo.md"

  run bash "$FINALIZE" "chore/CHORE-001-demo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Merged PR #201"* ]]
  [[ "$output" == *"ticked 2 acceptance criteria"* ]]
  [[ "$output" == *"Completion section (appended)"* ]]
  grep -F "TRACE:gh:pr merge" "$TRACER"
}

@test "3. bug branch: BK path succeeds on bug requirements" {
  init_repo "fix/BUG-001-demo"
  write_gh_stub
  write_git_stub
  export GH_PR_NUMBER=301
  export GH_PR_TITLE="fix(BUG-001): demo"
  export GH_PR_URL="https://github.com/example/repo/pull/301"
  export GH_PR_FILES="src/buggy.ts"

  seed_doc_on_branch write_bug_doc "requirements/bugs/BUG-001-demo.md"

  run bash "$FINALIZE" "fix/BUG-001-demo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Merged PR #301"* ]]
  [[ "$output" == *"ticked 2 acceptance criteria"* ]]
  grep -F "TRACE:gh:pr merge" "$TRACER"
}

@test "4. release branch: BK fully skipped, merge runs, no branch-pattern messages" {
  init_repo "release/lwndev-sdlc-v1.16.0"
  write_gh_stub
  write_git_stub
  export GH_PR_NUMBER=401
  export GH_PR_TITLE="release(lwndev-sdlc): v1.16.0"
  export GH_PR_URL="https://github.com/example/repo/pull/401"
  # Still need at least one commit on the branch so it has divergence.
  printf 'release notes\n' > CHANGELOG.md
  commit_paths "release" "CHANGELOG.md"

  run bash -c "bash '$FINALIZE' 'release/lwndev-sdlc-v1.16.0' 2>'$FIXTURE_DIR/stderr'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Bookkeeping: skipped (release branch)"* ]]
  [[ "$output" == *"Merged PR #401"* ]]
  [[ "$output" == *"On main, up to date"* ]]

  err="$(cat "$FIXTURE_DIR/stderr")"
  # No branch-pattern info messages.
  [[ "$err" != *"does not match workflow ID pattern"* ]]
  [[ "$err" != *"skipping bookkeeping"* ]]

  # Tracer: merge/checkout/fetch/pull all ran; no BK subscripts (the subscripts
  # themselves don't log to tracer, but we can assert indirectly: no new
  # commits beyond the release commit, no completion block in any doc).
  grep -F "TRACE:gh:pr merge" "$TRACER"
  grep -F "TRACE:git:checkout main" "$TRACER"
  grep -F "TRACE:git:fetch origin" "$TRACER"
  grep -F "TRACE:git:pull" "$TRACER"
}

@test "5. adhoc branch: canonical info message, merge runs, no BK" {
  init_repo "adhoc/cleanup-branch"
  write_gh_stub
  write_git_stub
  export GH_PR_NUMBER=501
  export GH_PR_TITLE="adhoc cleanup"
  export GH_PR_URL="https://github.com/example/repo/pull/501"
  printf 'cleanup\n' > cleanup.txt
  commit_paths "cleanup" "cleanup.txt"

  run bash -c "bash '$FINALIZE' 'adhoc/cleanup-branch' 2>'$FIXTURE_DIR/stderr'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Bookkeeping: skipped (not a workflow branch)"* ]]
  [[ "$output" == *"Merged PR #501"* ]]

  err="$(cat "$FIXTURE_DIR/stderr")"
  [[ "$err" == *"[info] Branch adhoc/cleanup-branch does not match workflow ID pattern; skipping bookkeeping."* ]]

  grep -F "TRACE:gh:pr merge" "$TRACER"
}

@test "6. idempotent re-run: second invocation skips BK (doc already finalized)" {
  init_repo "feat/FEAT-006-idem"
  write_gh_stub
  write_git_stub
  export GH_PR_NUMBER=601
  export GH_PR_TITLE="feat(FEAT-006): idem"
  export GH_PR_URL="https://github.com/example/repo/pull/601"
  export GH_PR_FILES="src/existing.ts"

  seed_doc_on_branch write_feature_doc "requirements/features/FEAT-006-idem.md"

  # First run: full BK path + merge. Record the state.
  run bash "$FINALIZE" "feat/FEAT-006-idem"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Completion section (appended)"* ]]

  # Simulate second-run scenario: repo gets reset to pre-merge state
  # (re-create the branch pointing at the current tip of main, but restore
  # the finalized doc so it reflects BK-5's committed state; working tree
  # is clean).
  #
  # After run 1, branch was deleted by `gh pr merge --delete-branch` in the
  # stub — but the stub just exits 0 without actually mutating git. So the
  # branch still exists locally. We checkout the branch, verify the doc has
  # the Completion block (BK-5 committed it), clear tracer and run again.
  "$REAL_GIT" -C "$REPO_DIR" checkout -q "feat/FEAT-006-idem"
  # Sanity: doc should now contain `## Completion` and ticked criteria.
  grep -q "^## Completion" "${REPO_DIR}/requirements/features/FEAT-006-idem.md"
  grep -q "^- \[x\] First criterion" "${REPO_DIR}/requirements/features/FEAT-006-idem.md"

  : > "$TRACER"

  run bash "$FINALIZE" "feat/FEAT-006-idem"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Bookkeeping: skipped (requirement doc already finalized)"* ]]

  # BK-4 subscripts should NOT have been called. checkbox-flip-all writes
  # via `git`-touched files; we can't directly inspect subscript invocation,
  # but we can assert no new commit was produced (BK-5 didn't run).
  # Compare: there must be NO `TRACE:git:commit ` entry in this second-run
  # tracer snapshot.
  run grep -E "TRACE:git:commit " "$TRACER"
  [ "$status" -ne 0 ]
  # Merge still ran.
  grep -F "TRACE:gh:pr merge" "$TRACER"
}

@test "7. doc with no ## Affected Files section: reconcile reports 0 0" {
  init_repo "feat/FEAT-007-no-affected"
  write_gh_stub
  write_git_stub
  export GH_PR_NUMBER=701
  export GH_PR_TITLE="feat(FEAT-007): no-affected"
  export GH_PR_URL="https://github.com/example/repo/pull/701"
  # PR has a file; doc has no Affected Files section. Reconcile should emit
  # 0 0 because it skips reconciliation when the section is absent.
  export GH_PR_FILES="src/new.ts"

  seed_doc_on_branch write_feature_doc_no_affected_files "requirements/features/FEAT-007-no-affected.md"

  run bash "$FINALIZE" "feat/FEAT-007-no-affected"
  [ "$status" -eq 0 ]
  [[ "$output" == *"reconciled 0 new + 0 annotated affected files"* ]]

  # Post-run cwd is `main`; read the doc from the feature branch's tip.
  # Doc was mutated (AC ticked + Completion appended) but Affected Files
  # region doesn't exist, so no bullets were added.
  doc_path="requirements/features/FEAT-007-no-affected.md"
  doc_contents="$("$REAL_GIT" -C "$REPO_DIR" show "feat/FEAT-007-no-affected:${doc_path}")"
  [[ "$doc_contents" != *"## Affected Files"* ]]
}

@test "8. fenced ## Completion example is not mistaken for real section" {
  init_repo "feat/FEAT-008-fenced"
  write_gh_stub
  write_git_stub
  export GH_PR_NUMBER=801
  export GH_PR_TITLE="feat(FEAT-008): fenced"
  export GH_PR_URL="https://github.com/example/repo/pull/801"
  export GH_PR_FILES="src/existing.ts"

  doc_path="requirements/features/FEAT-008-fenced.md"
  seed_doc_on_branch write_feature_doc_with_fenced_example "$doc_path"

  run bash "$FINALIZE" "feat/FEAT-008-fenced"
  [ "$status" -eq 0 ]
  # Completion was appended (not upserted).
  [[ "$output" == *"Completion section (appended)"* ]]

  # Post-run cwd is `main`; read the finalized doc off the feature branch.
  doc_contents="$("$REAL_GIT" -C "$REPO_DIR" show "feat/FEAT-008-fenced:${doc_path}")"

  # Real `## Completion` now exists at end-of-file.
  [[ "$doc_contents" == *"## Completion"* ]]
  [[ "$doc_contents" == *"**Status:** \`Complete\`"* ]]

  # The fenced example body is byte-for-byte unchanged — verify the
  # documentary line inside the fence still says `[#999]`.
  [[ "$doc_contents" == *"**Pull Request:** [#999](https://example.com/pr/999)"* ]]

  # Two `## Completion` occurrences: one in the fence, one at the real
  # appended section.
  count="$(printf '%s\n' "$doc_contents" | grep -c "^## Completion")"
  [ "$count" -eq 2 ]
}

@test "9. CRLF round-trip: doc written CRLF remains CRLF after BK edits" {
  init_repo "feat/FEAT-009-crlf"
  write_gh_stub
  write_git_stub
  export GH_PR_NUMBER=901
  export GH_PR_TITLE="feat(FEAT-009): crlf"
  export GH_PR_URL="https://github.com/example/repo/pull/901"
  export GH_PR_FILES="src/existing.ts src/added.ts"

  doc_path="requirements/features/FEAT-009-crlf.md"
  write_feature_doc_crlf "$doc_path"
  commit_paths "add crlf fixture" "$doc_path"

  # Sanity-check the fixture is actually CRLF before the run.
  crlf_lines_before="$(LC_ALL=C grep -c $'\r$' "${REPO_DIR}/${doc_path}")"
  [ "$crlf_lines_before" -gt 0 ]

  run bash "$FINALIZE" "feat/FEAT-009-crlf"
  [ "$status" -eq 0 ]

  # Post-run cwd is `main`; materialize the finalized doc from the feature
  # branch to a tempfile so we can inspect bytes.
  finalized_doc="${FIXTURE_DIR}/finalized-crlf.md"
  "$REAL_GIT" -C "$REPO_DIR" show "feat/FEAT-009-crlf:${doc_path}" > "$finalized_doc"

  # After the run, the doc should still have CRLF endings on all lines.
  # Count CR-terminated lines and assert it's at least the pre-run count
  # (new lines appended also written as CRLF per the preserve-eol rule).
  crlf_lines_after="$(LC_ALL=C grep -c $'\r$' "$finalized_doc")"
  [ "$crlf_lines_after" -ge "$crlf_lines_before" ]

  # Spot-check: the appended Completion heading line is CRLF-terminated.
  LC_ALL=C grep -a $'^## Completion\r$' "$finalized_doc"
}

@test "10. wall-clock: full BK finalize completes in under 5s" {
  init_repo "feat/FEAT-010-perf"
  write_gh_stub
  write_git_stub
  export GH_PR_NUMBER=1001
  export GH_PR_TITLE="feat(FEAT-010): perf"
  export GH_PR_URL="https://github.com/example/repo/pull/1001"
  export GH_PR_FILES="src/existing.ts src/added.ts"

  seed_doc_on_branch write_feature_doc "requirements/features/FEAT-010-perf.md"

  # Record wall-clock via date +%s%N (with macOS fallback to %s).
  # BSD date doesn't support %N; fall back to SECONDS variable if needed.
  start_s=$SECONDS
  # Nanosecond-resolution timer when available (GNU date, gdate on mac).
  start_ns=""
  if command -v gdate >/dev/null 2>&1; then
    start_ns="$(gdate +%s%N)"
  elif date +%s%N 2>/dev/null | grep -q '^[0-9]\+$'; then
    # Non-BSD date.
    candidate="$(date +%s%N)"
    case "$candidate" in
      *N) : ;; # BSD date echoes `...N` literally.
      *) start_ns="$candidate" ;;
    esac
  fi

  run bash "$FINALIZE" "feat/FEAT-010-perf"
  [ "$status" -eq 0 ]

  end_s=$SECONDS

  # Prefer nanosecond delta when available; otherwise fall back to SECONDS
  # (1-second resolution).
  if [ -n "$start_ns" ]; then
    end_ns="$(date +%s%N)"
    elapsed_ns=$((end_ns - start_ns))
    elapsed_ms=$((elapsed_ns / 1000000))
  else
    elapsed_ms=$(( (end_s - start_s) * 1000 ))
  fi

  echo "elapsed=${elapsed_ms}ms" >&3

  # NFR-1 assertion: < 5000ms.
  [ "$elapsed_ms" -lt 5000 ]
}
