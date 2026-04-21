#!/usr/bin/env bash
# slugify.sh — Produce a filename/branch-safe kebab-case slug from a title.
#
# Usage: slugify.sh <title>
#
# Behavior:
#   1. Lowercase.
#   2. Strip non-ASCII.
#   3. Replace runs of non-alphanumeric with a single '-'.
#   4. Trim leading/trailing '-'.
#   5. Drop stopwords (a, an, the, of, for, to, and, or) as whole tokens.
#   6. Keep the first four remaining tokens.
#   7. Join with '-'.
#
# Exit codes:
#   0 success
#   1 slug is empty after normalization
#   2 usage error (missing arg)

set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "error: usage: slugify.sh <title>" >&2
  exit 2
fi

title="$1"

# 1. Lowercase. 2. Strip non-ASCII. 3. Collapse non-alphanumerics to '-'.
lower=$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]')
# Strip bytes outside printable ASCII range (retain a-z, 0-9, space, and punctuation which will be collapsed).
ascii=$(printf '%s' "$lower" | LC_ALL=C tr -cd 'a-z0-9 \t\n\r!"#$%&'"'"'()*+,./:;<=>?@[\\]^_`{|}~-')
# Replace runs of non-[a-z0-9] with a single '-'.
collapsed=$(printf '%s' "$ascii" | LC_ALL=C tr -cs 'a-z0-9' '-')
# 4. Trim leading/trailing '-'.
trimmed="${collapsed#-}"
trimmed="${trimmed%-}"

if [ -z "$trimmed" ]; then
  echo "error: slug is empty after normalization" >&2
  exit 1
fi

# 5. Drop stopwords. 6. Keep first 4. 7. Join.
kept=()
count=0
# shellcheck disable=SC2206
IFS='-' read -r -a tokens <<< "$trimmed"
for tok in "${tokens[@]}"; do
  [ -z "$tok" ] && continue
  case "$tok" in
    a|an|the|of|for|to|and|or) continue ;;
  esac
  kept+=("$tok")
  count=$((count + 1))
  if [ "$count" -ge 4 ]; then
    break
  fi
done

if [ "${#kept[@]}" -eq 0 ]; then
  echo "error: slug is empty after normalization" >&2
  exit 1
fi

# Join tokens with '-'. Print without trailing newline.
slug=""
for tok in "${kept[@]}"; do
  if [ -z "$slug" ]; then
    slug="$tok"
  else
    slug="$slug-$tok"
  fi
done

printf '%s' "$slug"
