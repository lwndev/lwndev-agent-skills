#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# Bats fixture for backend-detect.sh (FEAT-033 / FR-1).
#
# Coverage:
#   * GitHub HTTPS origin → github JSON
#   * GitHub SSH origin → github JSON
#   * AzDO dev.azure.com HTTPS origin → azdo JSON
#   * AzDO *.visualstudio.com HTTPS origin → azdo JSON
#   * AzDO SSH origin (git@ssh.dev.azure.com:v3/...) → azdo JSON
#   * Unknown host → null
#   * No origin remote → null
#   * SDLC_SCM_BACKEND=github override on github origin → label preserved
#   * SDLC_SCM_BACKEND=azdo override on dev.azure.com origin → label preserved
#   * SDLC_SCM_BACKEND=azdo mismatch on github origin → null + [warn]
#   * SDLC_SCM_BACKEND=github mismatch on dev.azure.com origin → null + [warn]

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/../../../../plugins/lwndev-sdlc/skills/managing-source-control/scripts" && pwd)"
  DETECT="${SCRIPT_DIR}/backend-detect.sh"
  REPO_DIR="$(mktemp -d "${BATS_TMPDIR:-/tmp}/msc-backend-detect.XXXXXX")"
  cd "$REPO_DIR"
  git init --quiet --initial-branch=main >/dev/null 2>&1 || git init --quiet >/dev/null 2>&1
  # Ensure no inherited env override unless the test sets it explicitly.
  unset SDLC_SCM_BACKEND
}

teardown() {
  cd /
  rm -rf "$REPO_DIR"
}

set_origin() {
  git remote remove origin >/dev/null 2>&1 || true
  git remote add origin "$1"
}

@test "SSH GitHub origin → github JSON" {
  set_origin "git@github.com:lwndev/lwndev-marketplace.git"
  run bash "$DETECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"backend":"github"'* ]]
  [[ "$output" == *'"owner":"lwndev"'* ]]
  [[ "$output" == *'"repo":"lwndev-marketplace"'* ]]
}

@test "HTTPS GitHub origin → github JSON" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  run bash "$DETECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"backend":"github"'* ]]
  [[ "$output" == *'"owner":"lwndev"'* ]]
  [[ "$output" == *'"repo":"lwndev-marketplace"'* ]]
}

@test "HTTPS GitHub origin without .git suffix → github JSON" {
  set_origin "https://github.com/lwndev/lwndev-marketplace"
  run bash "$DETECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"backend":"github"'* ]]
  [[ "$output" == *'"repo":"lwndev-marketplace"'* ]]
}

@test "dev.azure.com HTTPS origin → azdo JSON" {
  set_origin "https://dev.azure.com/contoso/sdlc-tools/_git/plugin-repo"
  run bash "$DETECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"backend":"azdo"'* ]]
  [[ "$output" == *'"organization":"contoso"'* ]]
  [[ "$output" == *'"project":"sdlc-tools"'* ]]
  [[ "$output" == *'"repo":"plugin-repo"'* ]]
}

@test "*.visualstudio.com HTTPS origin → azdo JSON" {
  set_origin "https://contoso.visualstudio.com/sdlc-tools/_git/plugin-repo"
  run bash "$DETECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"backend":"azdo"'* ]]
  [[ "$output" == *'"organization":"contoso"'* ]]
  [[ "$output" == *'"project":"sdlc-tools"'* ]]
  [[ "$output" == *'"repo":"plugin-repo"'* ]]
}

@test "AzDO SSH origin (git@ssh.dev.azure.com:v3/...) → azdo JSON" {
  set_origin "git@ssh.dev.azure.com:v3/contoso/sdlc-tools/plugin-repo"
  run bash "$DETECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"backend":"azdo"'* ]]
  [[ "$output" == *'"organization":"contoso"'* ]]
  [[ "$output" == *'"project":"sdlc-tools"'* ]]
  [[ "$output" == *'"repo":"plugin-repo"'* ]]
}

@test "unknown host → null" {
  set_origin "https://gitlab.com/foo/bar.git"
  run bash "$DETECT"
  [ "$status" -eq 0 ]
  [ "$output" = "null" ]
}

@test "no origin remote → null" {
  # Fresh init has no origin. Don't add one.
  run bash "$DETECT"
  [ "$status" -eq 0 ]
  [ "$output" = "null" ]
}

@test "SDLC_SCM_BACKEND=github on github.com origin → label preserved, identity parsed" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  SDLC_SCM_BACKEND=github run bash "$DETECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"backend":"github"'* ]]
  [[ "$output" == *'"owner":"lwndev"'* ]]
  [[ "$output" == *'"repo":"lwndev-marketplace"'* ]]
}

@test "SDLC_SCM_BACKEND=azdo on dev.azure.com origin → label preserved, identity parsed" {
  set_origin "https://dev.azure.com/contoso/sdlc-tools/_git/plugin-repo"
  SDLC_SCM_BACKEND=azdo run bash "$DETECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"backend":"azdo"'* ]]
  [[ "$output" == *'"organization":"contoso"'* ]]
}

@test "SDLC_SCM_BACKEND=azdo on github.com origin (mismatch) → null + [warn]" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  SDLC_SCM_BACKEND=azdo run bash "$DETECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"null"* ]]
  [[ "$stderr" == *"[warn]"* ]] || [[ "$output" == *"[warn]"* ]] || {
    # `run` captures both streams into $output when --separate-stderr is not used.
    # Use combined check on $output for environments without --separate-stderr.
    [[ "$output" == *"SDLC_SCM_BACKEND=azdo"* ]] || [ "$output" = "null" ]
  }
}

@test "SDLC_SCM_BACKEND=github on dev.azure.com origin (mismatch) → null + [warn]" {
  set_origin "https://dev.azure.com/contoso/sdlc-tools/_git/plugin-repo"
  SDLC_SCM_BACKEND=github run bash "$DETECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"null"* ]] || [ "$output" = "null" ]
}

@test "SDLC_SCM_BACKEND=azdo mismatch emits [warn] line on stderr" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  SDLC_SCM_BACKEND=azdo run --separate-stderr bash "$DETECT"
  [ "$status" -eq 0 ]
  [ "$output" = "null" ]
  [[ "$stderr" == *"[warn] SDLC_SCM_BACKEND=azdo"* ]]
}

@test "SDLC_SCM_BACKEND=github mismatch emits [warn] line on stderr" {
  set_origin "https://dev.azure.com/contoso/sdlc-tools/_git/plugin-repo"
  SDLC_SCM_BACKEND=github run --separate-stderr bash "$DETECT"
  [ "$status" -eq 0 ]
  [ "$output" = "null" ]
  [[ "$stderr" == *"[warn] SDLC_SCM_BACKEND=github"* ]]
}

# BUG-019: user-prefixed HTTPS origin coverage

@test "user-prefixed dev.azure.com HTTPS origin → azdo JSON" {
  set_origin "https://alice@dev.azure.com/contoso/sdlc-tools/_git/plugin-repo"
  run bash "$DETECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"backend":"azdo"'* ]]
  [[ "$output" == *'"organization":"contoso"'* ]]
  [[ "$output" == *'"project":"sdlc-tools"'* ]]
  [[ "$output" == *'"repo":"plugin-repo"'* ]]
}

@test "user-prefixed dev.azure.com: organization field does not contain @ or user string" {
  set_origin "https://alice@dev.azure.com/contoso/sdlc-tools/_git/plugin-repo"
  run bash "$DETECT"
  [ "$status" -eq 0 ]
  org=$(echo "$output" | grep -o '"organization":"[^"]*"' | cut -d'"' -f4)
  [[ "$org" != *"@"* ]]
  [[ "$org" != *"alice"* ]]
}

@test "user-prefixed *.visualstudio.com HTTPS origin → azdo JSON" {
  set_origin "https://alice@contoso.visualstudio.com/sdlc-tools/_git/plugin-repo"
  run bash "$DETECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"backend":"azdo"'* ]]
  [[ "$output" == *'"organization":"contoso"'* ]]
  [[ "$output" == *'"project":"sdlc-tools"'* ]]
  [[ "$output" == *'"repo":"plugin-repo"'* ]]
}

@test "user-prefixed *.visualstudio.com: organization field does not contain @ or user string" {
  set_origin "https://alice@contoso.visualstudio.com/sdlc-tools/_git/plugin-repo"
  run bash "$DETECT"
  [ "$status" -eq 0 ]
  org=$(echo "$output" | grep -o '"organization":"[^"]*"' | cut -d'"' -f4)
  [[ "$org" != *"@"* ]]
  [[ "$org" != *"alice"* ]]
}

@test "user-prefixed *.visualstudio.com/DefaultCollection/ HTTPS origin → azdo JSON" {
  set_origin "https://alice@contoso.visualstudio.com/DefaultCollection/sdlc-tools/_git/plugin-repo"
  run bash "$DETECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"backend":"azdo"'* ]]
  [[ "$output" == *'"organization":"contoso"'* ]]
  [[ "$output" == *'"project":"sdlc-tools"'* ]]
  [[ "$output" == *'"repo":"plugin-repo"'* ]]
}

@test "user-prefixed *.visualstudio.com/DefaultCollection/: organization field does not contain @ or user string" {
  set_origin "https://alice@contoso.visualstudio.com/DefaultCollection/sdlc-tools/_git/plugin-repo"
  run bash "$DETECT"
  [ "$status" -eq 0 ]
  org=$(echo "$output" | grep -o '"organization":"[^"]*"' | cut -d'"' -f4)
  [[ "$org" != *"@"* ]]
  [[ "$org" != *"alice"* ]]
}

@test "token-prefixed GitHub HTTPS origin → github JSON" {
  set_origin "https://ghp_redacted@github.com/lwndev/lwndev-marketplace.git"
  run bash "$DETECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"backend":"github"'* ]]
  [[ "$output" == *'"owner":"lwndev"'* ]]
  [[ "$output" == *'"repo":"lwndev-marketplace"'* ]]
}

@test "token-prefixed GitHub HTTPS: owner field does not contain @ or token string" {
  set_origin "https://ghp_redacted@github.com/lwndev/lwndev-marketplace.git"
  run bash "$DETECT"
  [ "$status" -eq 0 ]
  owner=$(echo "$output" | grep -o '"owner":"[^"]*"' | cut -d'"' -f4)
  [[ "$owner" != *"@"* ]]
  [[ "$owner" != *"ghp_redacted"* ]]
}

@test "SDLC_SCM_BACKEND=azdo on user-prefixed dev.azure.com origin → no [warn], azdo JSON" {
  set_origin "https://alice@dev.azure.com/contoso/sdlc-tools/_git/plugin-repo"
  SDLC_SCM_BACKEND=azdo run --separate-stderr bash "$DETECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"backend":"azdo"'* ]]
  [[ "$output" == *'"organization":"contoso"'* ]]
  [[ "$stderr" != *"[warn]"* ]]
}
