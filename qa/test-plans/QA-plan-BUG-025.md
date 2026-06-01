---
id: BUG-025
version: 2
timestamp: 2026-06-01T13:29:00Z
persona: qa
---

## User Summary

`adopt-qa-test.sh` previously refused to adopt any QA test that resolved more than one peer test, blocking the QA loop's adopt phase. The change makes adoption tolerate multi-SUT QA tests: when more than one distinct peer resolves, it deterministically picks the lexicographically-first peer (by full repo-relative path) and `git mv`s the QA file to that peer's `*.qa.*` sibling. Multi-peer no longer fails; only a genuine no-peer case still exits 2. Applies to both the vitest/jest (`.test.{ts,tsx,js,jsx,mjs,cjs}`) and bats (`.bats`) dispatch paths.

## Capability Report

- Mode: test-framework
- Framework: vitest
- Package manager: npm
- Test command: npm test
- Language: typescript

> Caveat: the system-under-test is a Bash script (`adopt-qa-test.sh`). Its behavior is exercised by Bats (`tests/bats/skills/addressing-qa-findings/adopt-qa-test.bats`), not vitest. `test-framework` scenarios below are expressed as Bats cases run via `npx bats` and asserted on exit code + stdout/stderr. capability-discovery reports the repo's primary vitest framework, but run-framework parsing is vitest-only (run bats QA via `npx bats` + exit code).

## Scenarios (by dimension)

### Inputs
- [P0] vitest QA test imports 3+ distinct SUTs, each with an existing peer test in different directories | mode: test-framework | expected: exit 0; QA file git-mv'd to the lexicographically-first peer's `*.qa.test.<ext>` sibling (not first-import-seen, not basename order)
- [P0] two candidate peers whose basenames sort opposite to their full paths (e.g. `src/zeta/a.test.ts` vs `src/alpha/z.test.ts`) | mode: test-framework | expected: pick is by FULL repo-relative path, deterministic; basename-only sort would pick the wrong one
- [P0] vitest QA test resolves ZERO peers (imports SUTs with no peer test) | mode: test-framework | expected: still exit 2 with `no existing peer test found for any imported SUT` — tolerate-multi must not weaken the genuine no-peer guard
- [P1] bats QA test `load`s two scripts each having a `.bats` peer | mode: test-framework | expected: exit 0; git-mv to lexicographically-first peer's `*.qa.bats` sibling
- [P1] QA test imports the SAME SUT twice (duplicate import lines) | mode: test-framework | expected: deduped to a single peer; adopt exit 0; not mis-counted as multi-peer
- [P1] import specs mixing extension and extensionless forms for the same SUT (`./foo` and `./foo.ts`) | mode: test-framework | expected: both resolve to one peer after extension stripping; single-peer adopt, exit 0
- [P2] import paths containing `..`/`./` segments that normpath collapses to an already-seen peer | mode: test-framework | expected: collapsed to one peer, no spurious second-peer ambiguity
- [P2] `<<MULTI>>` parallel-test-root case: one SUT base name matches multiple `*.test.*` files under `tests/` AND at least one other import resolves a singular peer | mode: test-framework | expected: deterministic pick across the combined candidate set, exit 0 (no longer the catch-all multi-peer exit 2)

### State transitions
- [P0] adopt runs twice on the same QA path; second run after the file is already moved | mode: test-framework | expected: second run exit 2 `file not found`; no partial state, no second git-mv
- [P1] target `*.qa.test.<ext>` sibling already exists for the chosen peer | mode: test-framework | expected: exit 1 `target path already exists`; the picker must NOT silently fall through to a different peer to dodge the collision
- [P1] multi-peer pick still routes through `git mv` (the move IS the deletion) | mode: test-framework | expected: on exit 0 the original `qa-*` file no longer exists and the sibling is git-tracked; adopt remains the sole deleter
- [P2] `git mv` fails (e.g. unstaged conflicting change at target) after a peer is chosen | mode: exploratory | expected: non-zero exit, error surfaced verbatim, no silent success and no orphaned half-rename

### Environment
- [P0] lexicographic ordering under a non-C locale (`LC_ALL`/`LC_COLLATE` set to a UTF-8 locale) | mode: exploratory | expected: pick is byte-stable regardless of locale collation — implementation must pin `LC_ALL=C` (or equivalent) for the sort/compare, else "lexicographically-first" is non-deterministic across machines
- [P1] `python3` unavailable so `normpath` falls back to the textual best-effort | mode: exploratory | expected: peer resolution and the deterministic pick still succeed; uncollapsed `..` segments must not cause a real peer to be missed or double-counted
- [P2] QA path is untracked / outside the git repo | mode: test-framework | expected: `git mv` refuses; exit 1 with git stderr passed through

### Dependency failure
- [P1] unrecognized QA extension forces the `capability-discovery.sh` fallback and the script is missing/errors | mode: test-framework | expected: framework treated as unknown; exit 2 `unrecognized QA test extension and no supported framework detected` — the multi-peer change must not alter the fallback path
- [P2] `jq` absent during the capability-discovery fallback | mode: exploratory | expected: framework parsed as empty -> graceful exit 2 (unrecognized), no crash

### Cross-cutting (a11y, i18n, concurrency, permissions)
- [P1] determinism is reproducible: the SAME multi-peer QA test adopted on two machines / two runs picks the identical peer | mode: test-framework | expected: identical chosen sibling path across runs (ties broken only by the documented full-path rule)
- [P1] post-adopt, the finalize write-surface gate (`git ls-files qa-* globs`) passes because the `qa-*` prefix is gone | mode: test-framework | expected: no tracked `qa-*` files remain after a multi-SUT adoption; the chosen sibling carries the `*.qa.*` prefix the gate allows
- [P2] read-only checkout / permission-denied on the target directory | mode: exploratory | expected: `git mv` fails with a permission error surfaced verbatim; exit non-zero

## Non-applicable dimensions

- Accessibility (a11y): `adopt-qa-test.sh` is a non-interactive CLI script with no UI surface — keyboard navigation, screen-reader, focus-trapping, and color-contrast checks do not apply.
- Internationalization (RTL layout / pluralization / date-number formatting): the script emits only fixed-format ASCII diagnostic lines and machine paths; there is no localized user-facing copy. (Locale-sensitive sort collation IS in scope and is covered under Environment.)
- Network / offline / third-party API / queue / database failure: the script performs only local filesystem reads and `git mv`; it makes no network calls and depends on no external service, so 5xx/timeout/429/disconnect scenarios cannot occur.
- Authn/authz / token expiry: no authentication surface — the script operates on local files with the invoking user's existing filesystem and git permissions (covered as a permissions edge case under Cross-cutting, not an auth flow).
