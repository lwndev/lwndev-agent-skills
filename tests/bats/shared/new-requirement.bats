#!/usr/bin/env bats
# Bats fixture for new-requirement.sh (CHORE-036 item 1.3).

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/../../../plugins/lwndev-sdlc/scripts" && pwd)"
  NEW_REQ="${SCRIPT_DIR}/new-requirement.sh"
  TMPDIR_TEST="$(mktemp -d)"
  ORIG_PWD="$PWD"
  cd "$TMPDIR_TEST"
  # Each test starts with an empty git repo (no remote) by default.
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test"
}

teardown() {
  cd "$ORIG_PWD"
  rm -rf "$TMPDIR_TEST"
}

set_origin_ssh() {
  git remote add origin "git@github.com:lwndev/lwndev-marketplace.git"
}

set_origin_https() {
  git remote add origin "https://github.com/lwndev/lwndev-marketplace.git"
}

set_origin_non_github() {
  git remote add origin "https://gitlab.com/foo/bar.git"
}

# ---------- happy paths ----------

@test "FEAT happy path: writes FEAT-001 with title slug" {
  run bash "$NEW_REQ" FEAT "My New Feature"
  [ "$status" -eq 0 ]
  [ "$output" = "requirements/features/FEAT-001-my-new-feature.md" ]
  [ -f "requirements/features/FEAT-001-my-new-feature.md" ]
}

@test "FEAT happy path: stdout has trailing newline" {
  raw=$(bash "$NEW_REQ" FEAT "Hello World" | wc -c | tr -d ' ')
  # 'requirements/features/FEAT-001-hello-world.md' is 45 chars; with the
  # trailing newline (matching next-id.sh convention) that is 46 bytes.
  expected_path="requirements/features/FEAT-001-hello-world.md"
  expected=$(( ${#expected_path} + 1 ))
  [ "$raw" = "$expected" ]
}

@test "CHORE happy path: writes CHORE-001 with category substituted" {
  run bash "$NEW_REQ" CHORE "Update Prettier Config" --category refactoring
  [ "$status" -eq 0 ]
  [ -f "requirements/chores/CHORE-001-update-prettier-config.md" ]
  grep -q '^`refactoring`$' requirements/chores/CHORE-001-update-prettier-config.md
  grep -q '^`CHORE-001`$' requirements/chores/CHORE-001-update-prettier-config.md
  grep -q '^# Chore: Update Prettier Config' requirements/chores/CHORE-001-update-prettier-config.md
}

@test "BUG happy path: writes BUG-001 with category and severity substituted" {
  run bash "$NEW_REQ" BUG "Token Crash" --category runtime-error --severity high
  [ "$status" -eq 0 ]
  [ -f "requirements/bugs/BUG-001-token-crash.md" ]
  grep -q '^`runtime-error`$' requirements/bugs/BUG-001-token-crash.md
  grep -q '^`high`$' requirements/bugs/BUG-001-token-crash.md
  grep -q '^`BUG-001`$' requirements/bugs/BUG-001-token-crash.md
}

# ---------- --issue resolution ----------

@test "--issue with SSH origin renders full GitHub URL" {
  set_origin_ssh
  run bash "$NEW_REQ" CHORE "SSH Test" --issue 42
  [ "$status" -eq 0 ]
  grep -q '^\[#42\](https://github.com/lwndev/lwndev-marketplace/issues/42)$' \
    requirements/chores/CHORE-001-ssh-test.md
}

@test "--issue with HTTPS origin renders full GitHub URL" {
  set_origin_https
  run bash "$NEW_REQ" CHORE "HTTPS Test" --issue 99
  [ "$status" -eq 0 ]
  grep -q '^\[#99\](https://github.com/lwndev/lwndev-marketplace/issues/99)$' \
    requirements/chores/CHORE-001-https-test.md
}

@test "--issue with non-GitHub origin falls back to bare ref" {
  set_origin_non_github
  run bash "$NEW_REQ" CHORE "Non GitHub" --issue 7
  [ "$status" -eq 0 ]
  grep -q '^#7$' requirements/chores/CHORE-001-non-github.md
  # The GitHub Issue placeholder (issues/N) must NOT contain a resolved
  # URL — only the unrelated Pull Request placeholder line keeps github.com.
  ! grep -q 'issues/7' requirements/chores/CHORE-001-non-github.md
}

@test "--issue with no remote falls back to bare ref" {
  # No remote configured (setup leaves the repo without one)
  run bash "$NEW_REQ" CHORE "No Remote" --issue 5
  [ "$status" -eq 0 ]
  grep -q '^#5$' requirements/chores/CHORE-001-no-remote.md
}

@test "--issue accepts a leading '#' and strips it" {
  set_origin_ssh
  run bash "$NEW_REQ" CHORE "Hash Issue" --issue "#88"
  [ "$status" -eq 0 ]
  grep -q '^\[#88\](https://github.com/lwndev/lwndev-marketplace/issues/88)$' \
    requirements/chores/CHORE-001-hash-issue.md
}

@test "--issue omitted: GitHub Issue line stays in template state" {
  run bash "$NEW_REQ" CHORE "No Issue Flag"
  [ "$status" -eq 0 ]
  grep -q '\[#N\](https://github.com/org/repo/issues/N)' \
    requirements/chores/CHORE-001-no-issue-flag.md
}

# ---------- monotonic ID allocation ----------

@test "re-run with identical args allocates a fresh ID and never overwrites" {
  run bash "$NEW_REQ" CHORE "Same Title" --category cleanup
  [ "$status" -eq 0 ]
  [ "$output" = "requirements/chores/CHORE-001-same-title.md" ]
  run bash "$NEW_REQ" CHORE "Same Title" --category cleanup
  [ "$status" -eq 0 ]
  [ "$output" = "requirements/chores/CHORE-002-same-title.md" ]
  [ -f "requirements/chores/CHORE-001-same-title.md" ]
  [ -f "requirements/chores/CHORE-002-same-title.md" ]
}

# ---------- flag-vs-type rules ----------

@test "FEAT + --category: exit 2 with FEAT rejection error" {
  run bash "$NEW_REQ" FEAT "Foo" --category dependencies
  [ "$status" -eq 2 ]
  [[ "$output" == *"error: --category not accepted for FEAT (features have no category enum)"* ]]
  [ ! -d "requirements/features" ] || [ -z "$(ls -A requirements/features 2>/dev/null)" ]
}

@test "CHORE + --severity: exit 2 with severity rejection error" {
  run bash "$NEW_REQ" CHORE "Foo" --severity high
  [ "$status" -eq 2 ]
  [[ "$output" == *"error: --severity only accepted for BUG"* ]]
}

@test "FEAT + --severity: exit 2 with severity rejection error" {
  run bash "$NEW_REQ" FEAT "Foo" --severity high
  [ "$status" -eq 2 ]
  [[ "$output" == *"error: --severity only accepted for BUG"* ]]
}

@test "CHORE + invalid --category: exit 2 with category error from validator" {
  run bash "$NEW_REQ" CHORE "Foo" --category bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"error: invalid chore category 'bogus'"* ]]
}

@test "BUG + invalid --category: exit 2 with bug category error" {
  run bash "$NEW_REQ" BUG "Foo" --category cleanup
  [ "$status" -eq 2 ]
  [[ "$output" == *"error: invalid bug category 'cleanup'"* ]]
}

# ---------- usage errors ----------

@test "missing args: exit 2 with usage error" {
  run bash "$NEW_REQ"
  [ "$status" -eq 2 ]
  [[ "$output" == *"error: usage:"* ]]
}

@test "single arg: exit 2 with usage error" {
  run bash "$NEW_REQ" CHORE
  [ "$status" -eq 2 ]
  [[ "$output" == *"error: usage:"* ]]
}

@test "invalid type: exit 2" {
  run bash "$NEW_REQ" feat "title"
  [ "$status" -eq 2 ]
  [[ "$output" == *"error: invalid type 'feat'"* ]]
}

@test "unknown flag: exit 2" {
  run bash "$NEW_REQ" CHORE "Foo" --bogus value
  [ "$status" -eq 2 ]
  [[ "$output" == *"error: unknown argument:"* ]]
}

@test "--issue without value: exit 2" {
  run bash "$NEW_REQ" CHORE "Foo" --issue
  [ "$status" -eq 2 ]
  [[ "$output" == *"--issue requires a value"* ]]
}

@test "empty title (after slugify): exit 2 (slugify failure)" {
  # Punctuation-only title -> slugify exits 1; new-requirement maps to exit 2
  # (validation error class).
  run bash "$NEW_REQ" CHORE "!!"
  [ "$status" -eq 2 ]
  [[ "$output" == *"error:"* ]]
}

# ---------- exit code 1 (filesystem/template error) ----------

@test "missing template returns exit 1" {
  # Move the FEAT template aside to force the template-not-found branch.
  local repo_root
  repo_root="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  TEMPLATE="${repo_root}/plugins/lwndev-sdlc/skills/documenting-features/assets/feature-requirements.md"
  if [ -f "$TEMPLATE" ]; then
    mv "$TEMPLATE" "${TEMPLATE}.bats-bak"
  fi
  run bash "$NEW_REQ" FEAT "Foo"
  rc=$status
  out="$output"
  if [ -f "${TEMPLATE}.bats-bak" ]; then
    mv "${TEMPLATE}.bats-bak" "$TEMPLATE"
  fi
  [ "$rc" -eq 1 ]
  [[ "$out" == *"template not found"* ]]
}
