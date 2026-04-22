#!/usr/bin/env bats
# Bats fixture for branch-id-parse.sh (FR-10).

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  PARSE="${SCRIPT_DIR}/branch-id-parse.sh"
}

@test "happy path: feat/FEAT-001-scaffold-skill" {
  run bash "$PARSE" "feat/FEAT-001-scaffold-skill"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"id":"FEAT-001"'* ]]
  [[ "$output" == *'"type":"feature"'* ]]
  [[ "$output" == *'"dir":"requirements/features"'* ]]
}

@test "happy path: chore/CHORE-023-cleanup" {
  run bash "$PARSE" "chore/CHORE-023-cleanup"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"id":"CHORE-023"'* ]]
  [[ "$output" == *'"type":"chore"'* ]]
  [[ "$output" == *'"dir":"requirements/chores"'* ]]
}

@test "happy path: fix/BUG-011-null-crash" {
  run bash "$PARSE" "fix/BUG-011-null-crash"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"id":"BUG-011"'* ]]
  [[ "$output" == *'"type":"bug"'* ]]
  [[ "$output" == *'"dir":"requirements/bugs"'* ]]
}

@test "main branch: exit 1 with pattern error" {
  run bash "$PARSE" main
  [ "$status" -eq 1 ]
  [[ "$output" == *"error: branch name does not match any work-item pattern"* ]]
}

@test "happy path: release/lwndev-sdlc-v1.16.0" {
  run bash "$PARSE" "release/lwndev-sdlc-v1.16.0"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"type":"release"'* ]]
  [[ "$output" == *'"id":null'* ]]
  [[ "$output" == *'"dir":null'* ]]
}

@test "happy path: release/foo-bar-v0.1.2" {
  run bash "$PARSE" "release/foo-bar-v0.1.2"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"type":"release"'* ]]
  [[ "$output" == *'"id":null'* ]]
  [[ "$output" == *'"dir":null'* ]]
}

@test "happy path: release/x-v10.20.30" {
  run bash "$PARSE" "release/x-v10.20.30"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"type":"release"'* ]]
  [[ "$output" == *'"id":null'* ]]
  [[ "$output" == *'"dir":null'* ]]
}

@test "malformed release: release/foo (no version) exit 1" {
  run bash "$PARSE" "release/foo"
  [ "$status" -eq 1 ]
  [[ "$output" == *"error: branch name does not match any work-item pattern"* ]]
}

@test "malformed release: release/foo-v1.2 (incomplete version) exit 1" {
  run bash "$PARSE" "release/foo-v1.2"
  [ "$status" -eq 1 ]
  [[ "$output" == *"error: branch name does not match any work-item pattern"* ]]
}

@test "malformed release: release/foo/bar-v1.0.0 (nested path) exit 1" {
  run bash "$PARSE" "release/foo/bar-v1.0.0"
  [ "$status" -eq 1 ]
  [[ "$output" == *"error: branch name does not match any work-item pattern"* ]]
}

@test "non-canonical prefix bug/: exit 1" {
  run bash "$PARSE" "bug/BUG-011-foo"
  [ "$status" -eq 1 ]
}

@test "missing slash after FEAT-NNN: exit 1 (trailing '-' required)" {
  run bash "$PARSE" "feat/FEAT-001"
  [ "$status" -eq 1 ]
}

@test "missing arg: exit 2" {
  run bash "$PARSE"
  [ "$status" -eq 2 ]
  [[ "$output" == *"error:"* ]]
}

@test "jq-absent fallback: valid JSON still emitted" {
  # Shadow jq with a stub that always fails, earlier in PATH.
  shadow_dir="$(mktemp -d)"
  cat > "$shadow_dir/jq" <<'EOF'
#!/usr/bin/env bash
exit 127
EOF
  chmod +x "$shadow_dir/jq"
  # Hide the real jq entirely by making ours the PATH entry AND also making
  # `command -v jq` not find it: our stub IS executable, so `command -v` will
  # find it; but the script's `if command -v jq` branch would then call the
  # failing stub. To force the fallback path, we instead strip jq from PATH.
  # Strategy: build a PATH without the normal jq-bearing dirs. Use /usr/bin
  # only as baseline and strip /usr/bin/jq and brew jq.
  empty_path="$(mktemp -d)"
  # Symlink just the utilities we know we need.
  for bin in bash env grep sed awk tr cut wc mktemp head tail cat printf chmod rm mkdir ls true false test dirname basename; do
    if [ -x "/bin/$bin" ]; then
      ln -s "/bin/$bin" "$empty_path/$bin" 2>/dev/null || true
    elif [ -x "/usr/bin/$bin" ]; then
      ln -s "/usr/bin/$bin" "$empty_path/$bin" 2>/dev/null || true
    fi
  done
  PATH="$empty_path" run bash "$PARSE" "feat/FEAT-001-foo"
  rm -rf "$shadow_dir" "$empty_path"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"id":"FEAT-001"'* ]]
  [[ "$output" == *'"type":"feature"'* ]]
  [[ "$output" == *'"dir":"requirements/features"'* ]]
  # Output must be valid JSON (single object on single line).
  echo "$output" | grep -Eq '^\{.*\}$'
}

@test "jq-absent fallback: release case emits literal null for id/dir" {
  # Force the hand-assembled JSON fallback path by stripping jq from PATH
  # (same strategy as the feature-case fallback test above).
  empty_path="$(mktemp -d)"
  for bin in bash env grep sed awk tr cut wc mktemp head tail cat printf chmod rm mkdir ls true false test dirname basename; do
    if [ -x "/bin/$bin" ]; then
      ln -s "/bin/$bin" "$empty_path/$bin" 2>/dev/null || true
    elif [ -x "/usr/bin/$bin" ]; then
      ln -s "/usr/bin/$bin" "$empty_path/$bin" 2>/dev/null || true
    fi
  done
  PATH="$empty_path" run bash "$PARSE" "release/lwndev-sdlc-v1.16.0"
  rm -rf "$empty_path"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"type":"release"'* ]]
  # Must be literal JSON null, not the string "null".
  [[ "$output" == *'"id":null'* ]]
  [[ "$output" == *'"dir":null'* ]]
  [[ "$output" != *'"id":"null"'* ]]
  [[ "$output" != *'"dir":"null"'* ]]
  # Output must be valid JSON (single object on single line).
  echo "$output" | grep -Eq '^\{.*\}$'
}

@test "feat/FEAT-001- without trailing content still matches" {
  run bash "$PARSE" "feat/FEAT-001-"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"id":"FEAT-001"'* ]]
}
