#!/usr/bin/env bats
# Bats fixture for slugify.sh (FR-2).

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  SLUGIFY="${SCRIPT_DIR}/slugify.sh"
}

@test "AC-9 contract: 'The Quick Brown Fox Jumps' → quick-brown-fox-jumps" {
  run bash "$SLUGIFY" "The Quick Brown Fox Jumps"
  [ "$status" -eq 0 ]
  [ "$output" = "quick-brown-fox-jumps" ]
}

@test "stopword stripping: 'The Art of War' → art-war" {
  run bash "$SLUGIFY" "The Art of War"
  [ "$status" -eq 0 ]
  [ "$output" = "art-war" ]
}

@test "all listed stopwords are dropped" {
  run bash "$SLUGIFY" "a an the of for to and or keep"
  [ "$status" -eq 0 ]
  [ "$output" = "keep" ]
}

@test "token truncation: six non-stopword tokens keeps first four" {
  run bash "$SLUGIFY" "Alpha Beta Gamma Delta Epsilon Zeta"
  [ "$status" -eq 0 ]
  [ "$output" = "alpha-beta-gamma-delta" ]
}

@test "stopwords do not count toward the 4-token budget" {
  run bash "$SLUGIFY" "The Alpha Beta Gamma Delta Epsilon"
  [ "$status" -eq 0 ]
  [ "$output" = "alpha-beta-gamma-delta" ]
}

@test "all-stopword title: exit 1 with error" {
  run bash "$SLUGIFY" "the and or"
  [ "$status" -eq 1 ]
  [[ "$output" == *"error:"* ]]
}

@test "punctuation-only title: exit 1" {
  run bash "$SLUGIFY" "!!"
  [ "$status" -eq 1 ]
  [[ "$output" == *"error:"* ]]
}

@test "missing arg: exit 2" {
  run bash "$SLUGIFY"
  [ "$status" -eq 2 ]
  [[ "$output" == *"error:"* ]]
}

@test "determinism: same input twice → same output" {
  run bash "$SLUGIFY" "The Quick Brown Fox Jumps"
  first="$output"
  run bash "$SLUGIFY" "The Quick Brown Fox Jumps"
  second="$output"
  [ "$first" = "$second" ]
}

@test "no trailing newline on stdout" {
  # `run` strips trailing newlines from $output but preserves them in lines.
  # Use printf and xxd to detect trailing newline.
  result=$(bash "$SLUGIFY" "Hello World")
  # Capture raw bytes count.
  raw=$(bash "$SLUGIFY" "Hello World" | wc -c | tr -d ' ')
  # "hello-world" is 11 characters; no trailing newline → 11 bytes.
  [ "$result" = "hello-world" ]
  [ "$raw" = "11" ]
}

@test "punctuation collapsed to single dash" {
  run bash "$SLUGIFY" "hello,,,world"
  [ "$status" -eq 0 ]
  [ "$output" = "hello-world" ]
}

@test "mixed case is lowercased" {
  run bash "$SLUGIFY" "FooBar BAZ"
  [ "$status" -eq 0 ]
  [ "$output" = "foobar-baz" ]
}
