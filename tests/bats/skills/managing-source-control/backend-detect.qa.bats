#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

# Adversarial QA coverage for BUG-019 — backend-detect.sh AzDO/GitHub user@host
# regex fix. The implementation tests (tests/bats/skills/managing-source-control/
# backend-detect.bats) cover the canonical scenarios. This file covers the
# pathological / corner-case inputs from qa/test-plans/QA-plan-BUG-019.md that
# go beyond the implementation's checklist:
#
#  - empty user@ prefix
#  - basic-auth user:pass@ form
#  - URL-encoded @ in user component
#  - multiple @ characters
#  - origin with port specifier
#  - user-prefix to unknown host
#  - SDLC_SCM_BACKEND override symmetry under user-prefix
#  - PAT-style user prefix does not leak to stdout/stderr (security)
#  - .git suffix-strip composes with user-prefix
#  - BASH_REMATCH index-shift canary on every HTTPS variant

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/../../../plugins/lwndev-sdlc/skills/managing-source-control/scripts" && pwd)"
  DETECT="${SCRIPT_DIR}/backend-detect.sh"
  REPO_DIR="$(mktemp -d "${BATS_TMPDIR:-/tmp}/qa-bug-019.XXXXXX")"
  cd "$REPO_DIR"
  git init --quiet --initial-branch=main >/dev/null 2>&1 || git init --quiet >/dev/null 2>&1
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

# ----- Pathological inputs (Inputs dimension, P1) -----

@test "empty user@ prefix (https://@dev.azure.com/...) does not match azdo" {
  set_origin "https://@dev.azure.com/contoso/sdlc/_git/plugin"
  run bash "$DETECT"
  [ "$status" -eq 0 ]
  # Regex requires at least one non-`/`/non-`@` char in the optional group, so
  # an empty `@` prefix must NOT match the azdo branch. Acceptable: emit null.
  [ "$output" = "null" ]
}

@test "basic-auth user:pass@ form captures only the bare org (no :pass leakage)" {
  set_origin "https://alice:secret@dev.azure.com/contoso/sdlc/_git/plugin"
  run bash "$DETECT"
  [ "$status" -eq 0 ]
  # Whatever the regex chose to do, the captured organization MUST be `contoso`,
  # not `alice:secret` or anything containing the password.
  if [ "$output" != "null" ]; then
    [[ "$output" == *'"organization":"contoso"'* ]]
    [[ "$output" != *'secret'* ]]
    [[ "$output" != *'alice'* ]]
  fi
}

@test "URL-encoded @ in user prefix does not corrupt captured fields" {
  set_origin "https://alice%40acme.com@dev.azure.com/contoso/sdlc/_git/plugin"
  run bash "$DETECT"
  [ "$status" -eq 0 ]
  # Either match cleanly OR null; never garbage in the JSON.
  if [ "$output" != "null" ]; then
    [[ "$output" == *'"organization":"contoso"'* ]]
    [[ "$output" != *'acme.com'* ]]
    [[ "$output" != *'alice'* ]]
  fi
}

@test "multiple @ chars (https://a@b@dev.azure.com/...) does not produce wrong org" {
  set_origin "https://a@b@dev.azure.com/contoso/sdlc/_git/plugin"
  run bash "$DETECT"
  [ "$status" -eq 0 ]
  # The regex must be deterministic. If it matches, organization must be
  # `contoso`. If it doesn't match, null is acceptable.
  if [ "$output" != "null" ]; then
    [[ "$output" == *'"organization":"contoso"'* ]]
  fi
}

@test "origin with port (https://alice@dev.azure.com:443/...) emits null" {
  set_origin "https://alice@dev.azure.com:443/contoso/sdlc/_git/plugin"
  run bash "$DETECT"
  [ "$status" -eq 0 ]
  # The regex anchors `dev\.azure\.com/`, not `dev\.azure\.com:443/`. Must not
  # silently capture `dev.azure.com:443` into a field or treat it as azdo.
  [ "$output" = "null" ]
}

@test "user-prefixed origin to non-recognized host emits null" {
  set_origin "https://alice@gitlab.com/foo/bar.git"
  run bash "$DETECT"
  [ "$status" -eq 0 ]
  [ "$output" = "null" ]
}

# ----- Composition with .git suffix -----

@test "user-prefixed dev.azure.com with .git suffix strips suffix from repo field" {
  set_origin "https://alice@dev.azure.com/contoso/sdlc/_git/plugin.git"
  run bash "$DETECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"backend":"azdo"'* ]]
  [[ "$output" == *'"repo":"plugin"'* ]]
  [[ "$output" != *'plugin.git'* ]]
}

@test "user-prefixed github.com with .git suffix strips suffix from repo field" {
  set_origin "https://ghp_redacted@github.com/lwndev/lwndev-marketplace.git"
  run bash "$DETECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"backend":"github"'* ]]
  [[ "$output" == *'"repo":"lwndev-marketplace"'* ]]
  [[ "$output" != *'lwndev-marketplace.git'* ]]
}

# ----- BASH_REMATCH index-shift canary -----

@test "BASH_REMATCH canary: dev.azure.com user-prefixed organization free of @" {
  set_origin "https://alice@dev.azure.com/contoso/sdlc/_git/plugin"
  run bash "$DETECT"
  [ "$status" -eq 0 ]
  [[ "$output" != *'"organization":"alice'* ]]
  [[ "$output" != *'@'* ]] || {
    # Allow `@` only in the case of an unmatchable input emitting null.
    [ "$output" = "null" ]
  }
}

@test "BASH_REMATCH canary: visualstudio.com user-prefixed organization free of @" {
  set_origin "https://alice@contoso.visualstudio.com/sdlc/_git/plugin"
  run bash "$DETECT"
  [ "$status" -eq 0 ]
  [[ "$output" != *'"organization":"alice'* ]]
  [[ "$output" != *'@'* ]] || {
    [ "$output" = "null" ]
  }
}

@test "BASH_REMATCH canary: DefaultCollection user-prefixed project is post-DefaultCollection segment" {
  set_origin "https://alice@contoso.visualstudio.com/DefaultCollection/sdlc/_git/plugin"
  run bash "$DETECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"backend":"azdo"'* ]]
  [[ "$output" == *'"organization":"contoso"'* ]]
  [[ "$output" == *'"project":"sdlc"'* ]]
  [[ "$output" != *'"project":"DefaultCollection"'* ]]
}

@test "BASH_REMATCH canary: github.com token-prefixed owner free of @ or token" {
  set_origin "https://ghp_supersecrettoken@github.com/lwndev/lwndev-marketplace"
  run bash "$DETECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"backend":"github"'* ]]
  [[ "$output" == *'"owner":"lwndev"'* ]]
  [[ "$output" != *'ghp_'* ]]
  [[ "$output" != *'supersecrettoken'* ]]
}

# ----- SDLC_SCM_BACKEND override symmetry under user-prefix -----

@test "SDLC_SCM_BACKEND=github on token-prefixed GitHub origin → no warn, github JSON" {
  set_origin "https://ghp_redacted@github.com/lwndev/lwndev-marketplace.git"
  SDLC_SCM_BACKEND=github run --separate-stderr bash "$DETECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"backend":"github"'* ]]
  [[ "$output" == *'"owner":"lwndev"'* ]]
  [ -z "$stderr" ] || [[ "$stderr" != *'[warn]'* ]]
}

@test "SDLC_SCM_BACKEND=github on user-prefixed AzDO origin (mismatch) → null + [warn]" {
  set_origin "https://alice@dev.azure.com/contoso/sdlc/_git/plugin"
  SDLC_SCM_BACKEND=github run --separate-stderr bash "$DETECT"
  [ "$status" -eq 0 ]
  [ "$output" = "null" ]
  [[ "$stderr" == *"[warn] SDLC_SCM_BACKEND=github"* ]]
}

@test "SDLC_SCM_BACKEND=azdo on token-prefixed GitHub origin (mismatch) → null + [warn]" {
  set_origin "https://ghp_redacted@github.com/lwndev/lwndev-marketplace.git"
  SDLC_SCM_BACKEND=azdo run --separate-stderr bash "$DETECT"
  [ "$status" -eq 0 ]
  [ "$output" = "null" ]
  [[ "$stderr" == *"[warn] SDLC_SCM_BACKEND=azdo"* ]]
}

@test "SDLC_SCM_BACKEND=azdo on user-prefixed AzDO origin → positive azdo JSON (not just absence of warn)" {
  set_origin "https://alice@dev.azure.com/contoso/sdlc/_git/plugin"
  SDLC_SCM_BACKEND=azdo run --separate-stderr bash "$DETECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"backend":"azdo"'* ]]
  [[ "$output" == *'"organization":"contoso"'* ]]
  [[ "$output" == *'"project":"sdlc"'* ]]
  [[ "$output" == *'"repo":"plugin"'* ]]
}

# ----- Security / credential-leak (cross-cutting, P2) -----

@test "PAT-style token in user prefix never appears in stdout or stderr" {
  PAT="ghp_supersecretdonotleak123"
  set_origin "https://${PAT}@github.com/lwndev/lwndev-marketplace"
  run --separate-stderr bash "$DETECT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"$PAT"* ]]
  [[ "$stderr" != *"$PAT"* ]]
}

@test "PAT-style token under SDLC_SCM_BACKEND=github never appears in output" {
  PAT="ghp_anothersupersecrettokendonotleak"
  set_origin "https://${PAT}@github.com/lwndev/lwndev-marketplace"
  SDLC_SCM_BACKEND=github run --separate-stderr bash "$DETECT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"$PAT"* ]]
  [[ "$stderr" != *"$PAT"* ]]
}

# ----- Regression: user-less forms still pass after the index-shift edit -----

@test "regression: user-less dev.azure.com still matches after index-shift" {
  set_origin "https://dev.azure.com/contoso/sdlc/_git/plugin"
  run bash "$DETECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"backend":"azdo"'* ]]
  [[ "$output" == *'"organization":"contoso"'* ]]
  [[ "$output" == *'"project":"sdlc"'* ]]
  [[ "$output" == *'"repo":"plugin"'* ]]
}

@test "regression: user-less visualstudio.com/DefaultCollection still matches after index-shift" {
  set_origin "https://contoso.visualstudio.com/DefaultCollection/sdlc/_git/plugin"
  run bash "$DETECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"backend":"azdo"'* ]]
  [[ "$output" == *'"organization":"contoso"'* ]]
  [[ "$output" == *'"project":"sdlc"'* ]]
}

@test "regression: user-less github.com HTTPS still matches after index-shift" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  run bash "$DETECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"backend":"github"'* ]]
  [[ "$output" == *'"owner":"lwndev"'* ]]
}

@test "regression: SSH origins (no @ prefix in path) unchanged" {
  set_origin "git@ssh.dev.azure.com:v3/contoso/sdlc/plugin"
  run bash "$DETECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"backend":"azdo"'* ]]
  [[ "$output" == *'"organization":"contoso"'* ]]
}
