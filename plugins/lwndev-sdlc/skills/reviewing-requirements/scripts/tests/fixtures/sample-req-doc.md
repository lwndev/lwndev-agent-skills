# Sample Requirement Doc (extract-references fixture)

## File path references

See `scripts/foo.sh` for the runner and the bare-path `plugins/lwndev-sdlc/SKILL.md`.
Also check `assets/templates/template.yaml` and `tests/runner.bats`.

## Identifier references

Calls `getSourcePlugins` and the class `MyClass`. Skip false positives:
`true`, `false`, `null`, single-letter `x`, and keywords `const`, `return`.

## Cross references

This relates to FEAT-020 and CHORE-003 and BUG-001. See also FEAT-020 (duplicate).

## GitHub references

Tracked as #184 plus the long URL
https://github.com/lwndev/lwndev-marketplace/issues/184 (should normalize).
External: https://github.com/other-owner/other-repo/pull/5 (kept as full URL).

Duplicate mention: #184 again. `getSourcePlugins` again. `scripts/foo.sh` again.
