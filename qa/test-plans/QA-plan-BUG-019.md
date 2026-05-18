---
id: BUG-019
version: 2
timestamp: 2026-05-18T02:19:00Z
persona: qa
---

## User Summary

`backend-detect.sh` in `managing-source-control` fails to recognize Azure DevOps and GitHub HTTPS origin URLs when the URL embeds an HTTP basic-auth `<user>@` prefix (e.g. `https://boldorange@dev.azure.com/<org>/<project>/_git/<repo>`), even though such origins are the macOS default after `git-credential-osxkeychain` or `git-credential-manager-core` persists a PAT. The detection script silently emits `null`, which makes every downstream consumer (`create-pr.sh`, `finalizing-workflow`, `pr-comment`, etc.) graceful-skip even when `az` is installed and authenticated. The fix adds an optional `([^/@]+@)?` capture group between `https?://` and the host in the three HTTPS branches (`dev.azure.com`, `<org>.visualstudio.com`, `github.com`), renumbers the existing `BASH_REMATCH` indices, and adds Bats coverage for every user-prefixed variant. SSH branches (`git@github.com:`, `git@ssh.dev.azure.com:v3/`) are intentionally untouched.

## Capability Report

- Mode: test-framework
- Framework: vitest (+ bats for shell scripts under test)
- Package manager: npm
- Test command: npm test
- Language: typescript (shell scripts under test via bats)

## Scenarios (by dimension)

### Inputs

- [P0] AzDO HTTPS with `<user>@` prefix on `dev.azure.com` — assert exit 0 and stdout is exactly `{"backend":"azdo","organization":"<org>","project":"<project>","repo":"<repo>"}` with the captured `organization` field stripped of any `<user>@` prefix | mode: test-framework | expected: bats — `set_origin "https://alice@dev.azure.com/contoso/sdlc/_git/plugin"`, assert exact JSON shape via `jq -e '.backend=="azdo" and .organization=="contoso"'`
- [P0] AzDO HTTPS without `<user>@` (regression) — assert the existing user-less form continues to match and produce the same JSON it produced before the change | mode: test-framework | expected: bats — pre-existing fixture's exact assertions remain green
- [P0] AzDO `<org>.visualstudio.com` HTTPS with `<user>@` prefix — assert exit 0 and JSON with `organization` set to the bare `<org>` (no `<user>@`), `project` and `repo` correctly captured | mode: test-framework | expected: bats — `set_origin "https://alice@contoso.visualstudio.com/sdlc/_git/plugin"`, assert via `jq -e`
- [P0] AzDO `<org>.visualstudio.com/DefaultCollection/` HTTPS with `<user>@` prefix — assert the optional `DefaultCollection/` group still parses correctly when combined with the new user-prefix group; assert `project` is the post-DefaultCollection segment, not `DefaultCollection` itself | mode: test-framework | expected: bats — `set_origin "https://alice@contoso.visualstudio.com/DefaultCollection/sdlc/_git/plugin"`, assert `.project=="sdlc"`
- [P0] AzDO `<org>.visualstudio.com/DefaultCollection/` HTTPS WITHOUT prefix — assert the existing fixture continues to pass after the BASH_REMATCH index shift; this catches the most common index-renumbering miss | mode: test-framework | expected: bats — explicit assertion that `.organization=="contoso"` and `.project=="sdlc"` (not the other way around)
- [P0] GitHub HTTPS with `<token>@` prefix — assert exit 0 and stdout is exactly `{"backend":"github","owner":"<owner>","repo":"<repo>"}` with `owner` field free of the token prefix | mode: test-framework | expected: bats — `set_origin "https://ghp_redacted@github.com/lwndev/lwndev-marketplace.git"`, assert `.owner=="lwndev"`
- [P0] GitHub HTTPS without prefix and with `.git` suffix (regression) — assert the existing user-less HTTPS form keeps matching after the index renumbering in `parse_github()` | mode: test-framework | expected: bats — existing fixture must remain green
- [P0] GitHub SSH (`git@github.com:<owner>/<repo>.git`) — assert UNCHANGED behavior (SSH branch must not be touched by the fix; SSH origins do not carry HTTP basic-auth) | mode: test-framework | expected: bats — existing fixture remains green; assertion verifies the SSH branch was not accidentally edited
- [P0] AzDO SSH (`git@ssh.dev.azure.com:v3/<org>/<project>/<repo>`) — assert UNCHANGED | mode: test-framework | expected: bats — existing fixture remains green
- [P0] BASH_REMATCH index sanity: for every HTTPS variant (with and without user-prefix), assert the captured organization/owner does NOT contain `@` and does NOT contain the literal user/token prefix string — this is the canary test for the index-shift mistake | mode: test-framework | expected: bats — parameterized test over all HTTPS shapes asserting `[[ ! "$(echo "$output" | jq -r .organization // .owner)" =~ @ ]]`
- [P1] Pathological empty user-prefix `https://@dev.azure.com/...` — assert null OR azdo (document the chosen behavior — `[^/@]+@` requires at least one non-`/`/non-`@` char before the `@`, so this should not match); MUST NOT crash or produce malformed JSON | mode: test-framework | expected: bats — exact assertion against the documented behavior
- [P1] User prefix with `:` (basic-auth `user:pass@` form, e.g. `https://alice:secret@dev.azure.com/...`) — assert behavior is documented and not surprising (current regex `[^/@]+@` would match `alice:secret` and capture into the optional group); assert the captured `organization` field is still the bare `<org>`, not anything containing `:secret` | mode: test-framework | expected: bats — `set_origin "https://alice:secret@dev.azure.com/contoso/sdlc/_git/plugin"`, assert `.organization=="contoso"`
- [P1] User prefix containing URL-encoded `@` (`https://alice%40acme.com@dev.azure.com/...`) — assert the regex either matches with `alice%40acme.com` in the optional group OR cleanly returns null; assert no garbage in captured fields either way | mode: test-framework | expected: bats — assert documented behavior
- [P1] Multiple `@` chars (`https://a@b@dev.azure.com/...`) — assert behavior is deterministic (likely null because `[^/@]+@` is non-greedy in `[[ =~ ]]` and the second `@` breaks the host anchor); MUST NOT produce a JSON object with a wrong organization | mode: test-framework | expected: bats — assert `output == null` or assert exact deterministic JSON shape
- [P1] Origin with port (`https://alice@dev.azure.com:443/...`) — assert null (current regex anchors `dev\.azure\.com/`, not `dev\.azure\.com:443/`); MUST NOT silently capture `dev.azure.com:443` into a field | mode: test-framework | expected: bats — assert `output == null`
- [P1] Origin to a non-AzDO/non-GitHub host with a `<user>@` prefix (`https://alice@gitlab.com/foo/bar.git`) — assert null (the fix must not over-broaden the regex to other hosts) | mode: test-framework | expected: bats — assert `output == null`
- [P1] Origin with trailing `.git` AND `<user>@` prefix on every HTTPS variant — assert the `%.git` suffix-strip still applies after the index shift (regression for an easy refactor miss) | mode: test-framework | expected: bats — assert `.repo` never ends in `.git` for any user-prefixed input
- [P2] Origin with leading whitespace around the URL (the script already trims trailing whitespace; leading whitespace is unspecified) — assert documented behavior; if rejected, assert null cleanly | mode: test-framework | expected: bats — `set_origin "  https://alice@dev.azure.com/..."`, observe behavior
- [P2] Very long user prefix (e.g. a PAT longer than 1KB) — assert no buffer issues, normal match | mode: test-framework | expected: bats — generate a 1KB user prefix, assert match

### State transitions

- [P0] `SDLC_SCM_BACKEND=azdo` set on a user-prefixed AzDO HTTPS origin — assert the label-preservation behavior matches the user-less form (no `[warn]` on stderr, identity fields populated correctly) | mode: test-framework | expected: bats — assert `--separate-stderr` shows empty stderr AND stdout is the `{"backend":"azdo",...}` shape
- [P0] `SDLC_SCM_BACKEND=github` set on a user-prefixed GitHub HTTPS origin — symmetry with AzDO; assert no `[warn]` and correct identity | mode: test-framework | expected: bats — analogous to the AzDO assertion
- [P0] `SDLC_SCM_BACKEND=azdo` set on a user-prefixed GitHub HTTPS origin (mismatch) — assert null AND `[warn] SDLC_SCM_BACKEND=azdo set but origin does not match azdo URL pattern.` on stderr (no regression of the existing mismatch behavior) | mode: test-framework | expected: bats — assert exact stderr warning text
- [P0] `SDLC_SCM_BACKEND=github` set on a user-prefixed AzDO HTTPS origin (mismatch) — symmetric mismatch assertion | mode: test-framework | expected: bats — assert exact stderr warning text
- [P1] Override unset (`unset SDLC_SCM_BACKEND`) followed by user-prefixed AzDO origin — assert auto-detect path triggers and returns the same JSON as the override path would have | mode: test-framework | expected: bats — assert byte-identical JSON whether or not the override is set
- [P1] Repeated invocation against the same origin (idempotency) — assert two back-to-back invocations produce identical output (no stateful side effects in the script) | mode: test-framework | expected: bats — run twice, `diff` outputs

### Environment

- [P0] macOS `osxkeychain`-style origin (the reported repro: `https://<user>@dev.azure.com/...`) — the canonical regression case; assert the canonical JSON shape | mode: test-framework | expected: bats — pinned exact-string assertion on every JSON field
- [P0] No origin remote (fresh `git init`, no `git remote add`) — assert null (regression of existing behavior; the fix must not change the no-origin branch) | mode: test-framework | expected: bats — existing fixture remains green
- [P1] `git remote get-url origin` returns a value with trailing whitespace (script's trim loop should still strip it after the regex change) — assert trim continues to work for user-prefixed origins | mode: test-framework | expected: bats — write `printf 'https://alice@dev.azure.com/contoso/sdlc/_git/plugin\n   '` via a wrapper, assert normal match
- [P1] `LANG` / locale set to non-UTF-8 (e.g. `LC_ALL=C`) — assert bash `[[ =~ ]]` still matches; regex uses ASCII only so this should be a no-op, but worth a smoke test | mode: test-framework | expected: bats — set `LC_ALL=C`, assert normal match
- [P2] `git` missing from PATH — assert the existing `2>/dev/null` swallow + null emission still applies (no regression from the regex change) | mode: test-framework | expected: bats — empty-PATH stub, assert `output == null`

### Dependency failure

- [P1] `git remote get-url origin` exits non-zero (e.g. corrupted `.git/config`) — assert null and exit 0 (existing graceful-skip behavior); the regex change must not affect this path | mode: test-framework | expected: bats — corrupt `.git/config` to force `git remote get-url` failure, assert documented behavior
- [P2] `git` version differences (the `[[ =~ ]]` behavior is bash, not git, but worth verifying on minimum supported bash) — assert behavior under bash 3.2 (macOS default) and bash 5.x | mode: exploratory | expected: manual — run the bats suite under both bash versions if reachable, document any divergence

### Cross-cutting (a11y, i18n, concurrency, permissions)

- [P0] Two concurrent invocations of `backend-detect.sh` against the same repo (the script is pure-read so this should be trivially safe, but assert no `[warn]` from one bleeding into the other's stderr) | mode: test-framework | expected: bats — fork two instances in the background, assert identical stdout from each
- [P1] User prefix containing characters that could be regex-significant (`*`, `.`, `(`, `)`, `|`) — assert the regex treats them as literals (`[[ =~ ]]` does not expand the source — the regex is the right-hand pattern, not the variable) but the captured group includes them; assert the captured group does NOT corrupt downstream JSON | mode: test-framework | expected: bats — `set_origin "https://a.b*c@dev.azure.com/..."`, assert clean match
- [P1] User prefix containing a single quote or double quote — assert `printf "%s"` JSON formatting handles them safely (the script uses `printf '%s'` with single-quoted format strings so the captured value goes through as-is; potential JSON-escaping concern) | mode: test-framework | expected: bats — `set_origin "https://a'b@dev.azure.com/..."`, assert downstream JSON parser accepts it
- [P2] PAT in user-prefix logged to stderr or stdout — assert NO logging of the user-prefix value anywhere (no debug echoes); the captured org/owner field never contains credential material | mode: test-framework | expected: bats — `set_origin` with a sentinel PAT-like string, assert that string never appears in `output` or `stderr`
- [P2] Permissions: read-only filesystem on `/tmp` — assert the script does not write to disk (it's pure-read), no regression | mode: test-framework | expected: bats — set up read-only tmp, assert exit 0

## Non-applicable dimensions

- security/data-loss: this script is pure-read on the origin URL; it does not write, network, or touch credentials. The only security-adjacent concern is leaking credential material in stdout/stderr, which is captured under cross-cutting [P2] above.
- a11y/i18n UI surface: the script has no UI; locale concerns are captured under environment.
- network dependency failure: the script makes no network calls; only `git remote get-url origin` is invoked locally.
