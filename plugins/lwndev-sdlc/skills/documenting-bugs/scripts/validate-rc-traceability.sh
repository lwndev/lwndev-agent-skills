#!/usr/bin/env bash
# validate-rc-traceability.sh — Enforce the RC <-> AC round-trip rule on a
# bug document. (CHORE-036 item 1.5, scoped to documenting-bugs.)
#
# Usage: validate-rc-traceability.sh <bug-doc-path>
#
# Behavior:
#   1. Parse the `## Root Cause(s)` section: extract every `RC-N` token
#      (regex `\bRC-[0-9]+\b`), scoped from the heading to the next `^## `.
#   2. Parse the `## Acceptance Criteria` section: extract every line
#      matching `^- \[[ x]\] ` (the AC bullet shape), scoped from the
#      heading to the next `^## `. For each AC bullet, collect every
#      `RC-N` token that appears inside a parenthesized group on the
#      line — supports both `(RC-1)` and the comma-separated form
#      `(RC-1, RC-2)` shown in the bug-document template. Lines inside
#      HTML comment blocks (`<!-- ... -->`) are EXCLUDED.
#   3. Compute:
#        missingRCs   = RC IDs declared but referenced by zero ACs
#        untaggedACs  = AC bullets that have no `(RC-N)` tag at all
#   4. Print the result on stdout as a single JSON line:
#        {"missingRCs": [...], "untaggedACs": [...]}
#
# Exit codes:
#   0 round-trip satisfied (both arrays empty)
#   1 violations present (JSON still printed for the caller)
#   2 usage error or unparseable document — file unreadable, missing
#     `## Root Cause(s)` section entirely, or missing `## Acceptance Criteria`
#     section entirely. An empty Root Cause section (heading present, no
#     `RC-N` tokens) or an empty Acceptance Criteria section (heading present,
#     no AC bullets) is parseable and yields exit 0/1 per the round-trip rule.
#
# This script depends on python3 for stdlib JSON emission and regex parsing.
# python3 is available on the supported platforms (macOS, Linux CI images);
# this matches the dependency assumption used by `new-requirement.sh`.

set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "error: usage: validate-rc-traceability.sh <bug-doc-path>" >&2
  exit 2
fi

doc_path="$1"

if [ ! -f "$doc_path" ] || [ ! -r "$doc_path" ]; then
  echo "error: bug document not readable: $doc_path" >&2
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "error: python3 is required for validate-rc-traceability.sh" >&2
  exit 1
fi

DOC_PATH="$doc_path" python3 - <<'PY'
import json
import os
import re
import sys

doc_path = os.environ["DOC_PATH"]

try:
    with open(doc_path, "r", encoding="utf-8") as fh:
        text = fh.read()
except OSError as exc:
    sys.stderr.write(f"error: failed to read {doc_path}: {exc}\n")
    sys.exit(2)


def slice_section(src, heading):
    """Return the text between `## <heading>` and the next `^## `, or None.

    The boundary line itself is excluded. None signals the heading was not
    found at all (structural error).
    """
    lines = src.splitlines()
    start = None
    for i, line in enumerate(lines):
        if line.strip() == f"## {heading}":
            start = i + 1
            break
    if start is None:
        return None
    end = len(lines)
    for j in range(start, len(lines)):
        if lines[j].startswith("## "):
            end = j
            break
    return "\n".join(lines[start:end])


def strip_html_comments(block):
    """Remove `<!-- ... -->` blocks (including multi-line) from the text."""
    return re.sub(r"<!--.*?-->", "", block, flags=re.DOTALL)


rc_section = slice_section(text, "Root Cause(s)")
ac_section = slice_section(text, "Acceptance Criteria")

if rc_section is None:
    sys.stderr.write("error: missing '## Root Cause(s)' section\n")
    sys.exit(2)
if ac_section is None:
    sys.stderr.write("error: missing '## Acceptance Criteria' section\n")
    sys.exit(2)

# Strip HTML comments from BOTH sections — example bullets inside guidance
# comments must not be mistaken for real ACs or RC references.
rc_section_clean = strip_html_comments(rc_section)
ac_section_clean = strip_html_comments(ac_section)

# Declared RC IDs (deduplicated, preserve first-seen order).
declared_rcs = []
seen = set()
for tok in re.findall(r"\bRC-[0-9]+\b", rc_section_clean):
    if tok not in seen:
        seen.add(tok)
        declared_rcs.append(tok)

# AC bullets: `^- [ ] ` or `^- [x] ` lines, NOT in HTML comments.
ac_bullet_re = re.compile(r"^- \[[ x]\] (.+)$")

ac_bullets = []  # list of (criterion_text, set_of_referenced_rcs)
# An AC is considered "tagged" if it contains at least one RC reference
# inside parentheses. The bug-document template's own example uses
# comma-separated form (RC-1, RC-2), so we collect every RC-N token that
# appears inside any parenthesized group on the AC line.
parens_re = re.compile(r"\(([^()]*)\)")
rc_token_re = re.compile(r"\bRC-([0-9]+)\b")
for line in ac_section_clean.splitlines():
    m = ac_bullet_re.match(line)
    if not m:
        continue
    text_part = m.group(1)
    refs = set()
    for parens_match in parens_re.findall(text_part):
        for rc_num in rc_token_re.findall(parens_match):
            refs.add(f"RC-{rc_num}")
    ac_bullets.append((text_part, refs))

# missingRCs: declared RCs referenced by zero AC bullets.
referenced_rcs = set()
for _, refs in ac_bullets:
    referenced_rcs.update(refs)
missing_rcs = [rc for rc in declared_rcs if rc not in referenced_rcs]

# untaggedACs: AC bullets with no (RC-N) tag at all.
untagged_acs = [text_part for text_part, refs in ac_bullets if not refs]

result = {"missingRCs": missing_rcs, "untaggedACs": untagged_acs}
print(json.dumps(result))

if missing_rcs or untagged_acs:
    sys.exit(1)
sys.exit(0)
PY
