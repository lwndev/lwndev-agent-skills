---
name: managing-source-control
description: Centralizes git and pull-request operations into a single delegatable skill. Dispatches between GitHub (gh CLI) and Azure DevOps (az CLI) backends based on origin URL or SDLC_SCM_BACKEND env override. Use when the orchestrator or a consumer skill needs to create, view, list, merge, or diff pull requests, or perform branch/commit/push work backed by either SCM provider.
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
argument-hint: "<operation> [args...]"
---

# Managing Source Control

Centralized git and pull-request operations for GitHub and Azure DevOps, invoked inline by the orchestrator and by consumer skills at workflow integration points.

## When to Use This Skill

- Create / view / list / merge a pull request
- Diff a pull request against its base branch
- Build a canonical branch name and ensure the branch exists
- Stage and commit work with conventional commit format
- Detect the SCM backend from the repo's `origin` remote (or honor `SDLC_SCM_BACKEND` env override)

This `SKILL.md` is a **reference document read inline by the orchestrator's main context** -- the orchestrator and consumer skills `Read` it once at workflow start and then execute the skill-scoped scripts in `scripts/` directly using their existing `Bash` access. It is **not** forked via the Agent tool and **not** invoked via the Skill tool; all invocations are inline (mirrors `managing-work-items`). PR operations are **supplementary** in the graceful-degradation sense -- any backend or tool failure logs `[warn]`/`[info]` and skips rather than halting the workflow (NFR-1).

## Script Entry Points

| Script | Purpose | Dispatch |
|--------|---------|----------|
| `backend-detect.sh` | Parse `git remote get-url origin` + `SDLC_SCM_BACKEND` env; emit JSON identifying the backend. | n/a (pure parser) |
| `ensure-branch.sh` | Idempotently create or check out a branch with `feat/`/`chore/`/`fix/` prefix. | backend-agnostic |
| `build-branch-name.sh` | Build canonical branch name from `<type>` + `<ID>` + slug. | backend-agnostic |
| `commit-work.sh` | Stage, commit (conventional format), verify success. | backend-agnostic |
| `create-pr.sh` | Open a pull request. | dispatched (`gh pr create` / `az repos pr create`) |
| `merge-pr.sh` | Merge a pull request and delete the source branch. | dispatched (`gh pr merge` / `az repos pr update --status completed`) |
| `view-pr.sh` | Fetch PR state, reviews, file list. | dispatched (`gh pr view --json ...` / `az repos pr show`) |
| `list-pr.sh` | List PRs filtered by head branch. | dispatched (`gh pr list --head ...` / `az repos pr list --source-branch ...`) |
| `pr-diff.sh` | Emit unified diff of the PR against its base. | dispatched (`gh pr diff` / `git diff origin/<base>...HEAD`) |
| `pr-comment.sh` | Post a top-level PR comment or reply to an existing thread. | dispatched |
| `list-pr-comments.sh` | List PR comments as NDJSON, one record per comment. | dispatched |

## Backend Detection

Detect the SCM backend by inspecting `git remote get-url origin` and the `SDLC_SCM_BACKEND` env override:

| Origin URL | Backend | JSON Output |
|------------|---------|-------------|
| `https://github.com/<owner>/<repo>(.git)?` | GitHub | `{"backend":"github","owner":"...","repo":"..."}` |
| `git@github.com:<owner>/<repo>(.git)?` | GitHub | same |
| `https://dev.azure.com/<org>/<project>/_git/<repo>` | Azure DevOps | `{"backend":"azdo","organization":"...","project":"...","repo":"..."}` |
| `https://<org>.visualstudio.com/<project>/_git/<repo>` | Azure DevOps | same |
| `git@ssh.dev.azure.com:v3/<org>/<project>/<repo>` | Azure DevOps | same |
| no origin / unrecognized host | -- | literal `null` |

The `organization` field is the bare name (e.g. `contoso`); dispatchers downstream construct the `--organization https://dev.azure.com/<org>/` URL form when invoking `az`.

### `SDLC_SCM_BACKEND` Env Override

When `SDLC_SCM_BACKEND=github|azdo` is set, the override flips the **backend label only**. The script still parses the origin URL against the overridden backend's pattern to populate identity fields. If the URL does not match, emit literal `null` and log `[warn] SDLC_SCM_BACKEND=<x> set but origin does not match <x> URL pattern.` on stderr. The override never invents identity values out of thin air.

See `${CLAUDE_PLUGIN_ROOT}/skills/managing-source-control/scripts/backend-detect.sh` for the detection implementation. Exit codes: `0` on all detection outcomes (including `null`); `2` only on internal parse error (jq failure).

## Output Style

Follow the lite-narration rules below. Load-bearing carve-outs MUST be emitted as specified; they are not narration. This skill is executed inline from the orchestrator's main context (not forked via the Agent tool), so its output flows directly through the main conversation.

### Lite narration rules

- No preamble before tool calls. Do not announce "let me check" or "I'll run" -- issue the tool call.
- No end-of-turn summaries beyond one short sentence. Do not recap what the user can read from tool output.
- No emoji. ASCII punctuation only.
- No restating what the user just said.
- No status echoes that tools already show.
- Prefer ASCII arrows (`->`) and punctuation over Unicode alternatives in skill-authored prose. Existing Unicode em dashes in tables and reference docs are retained. Tool-emitted output (`gh` / `az` stdout, JSON responses) is out of scope.
- Short sentences over paragraphs. Bullet lists over prose when listing more than two items.

### Load-bearing carve-outs (never strip)

The following MUST always be emitted even when they resemble narration:

- **Error messages from `fail` calls** -- users need the reason the operation halted. Surface `gh` / `az` / git stderr verbatim.
- **Security-sensitive warnings** -- destructive-operation confirmations, credential prompts, auth-failure notices (`gh auth login`, `az login`, `az devops login`).
- **Interactive prompts** -- any prompt that blocks workflow progression must be visible.
- **Findings display from `reviewing-requirements`** -- N/A for this skill; bullet retained for cross-skill consistency.
- **FR-14 console echo lines** -- `[model] step {N} ({skill}) → {tier} (...)` audit-trail lines from `prepare-fork.sh`. The Unicode `→` is the documented emitter format; do not rewrite to ASCII. (Typically not emitted here since this skill is inline, not forked.)
- **Tagged structured logs** -- any line prefixed `[info]`, `[warn]`, or `[model]` is a structured log, not narration. Emit verbatim. WARNING-level mechanism-failure lines (e.g. `[warn] GitHub CLI (gh) not found on PATH.`, `[warn] Azure CLI not authenticated -- run az login.`) are load-bearing.
- **User-visible state transitions** -- skip notices (graceful-degradation info lines), backend fall-through notices, and operation confirmations (at most one line each).

### Inline execution note

`managing-source-control` is invoked **inline from the orchestrator's main context** (and from consumer skills' bash steps), NOT spawned via the Agent tool. The fork-to-orchestrator return contract (`done | artifact=<path> | <note>` / `failed | <reason>`) does **not** apply here -- there is no subagent boundary. Tool-call results (`gh` / `az` exit codes, JSON payloads) are consumed directly by the calling context.

**Precedence (in spirit)**: when a `[warn]` mechanism-failure line needs to be emitted (per the NFR-1 graceful-degradation matrix below), that line is load-bearing and MUST be emitted verbatim even if it reads like narration. The lite rules do not override WARNING-level structured-log emission.

## Graceful Degradation (NFR-1)

PR operations are supplementary -- they must **never** block workflow progression. All failure modes degrade gracefully; the workflow continues and only the PR step is skipped.

| Failure | Backend | Response |
|---------|---------|----------|
| `gh` not on PATH | GitHub | `[warn] GitHub CLI (gh) not found on PATH.` Skip PR step. Exit 0. |
| `gh` not authenticated | GitHub | `[warn] GitHub CLI not authenticated -- run gh auth login.` Skip. Exit 0. |
| `az` not on PATH | Azure DevOps | `[warn] Azure CLI (az) not found on PATH.` Skip. Exit 0. |
| `az devops` extension missing / auto-install failed | Azure DevOps | `[warn] az devops extension not available -- run az extension add --name azure-devops.` Skip. Exit 0. |
| `az` not logged in | Azure DevOps | `[warn] Azure CLI not authenticated -- run az login (Azure AD) or az devops login --pat <token>.` Skip. Exit 0. |
| Unrecognized origin remote | Any | `[info] No recognized SCM backend detected from origin.` Skip. Exit 0. |
| Network / not-found / non-zero CLI exit | Any | `[warn]` with the first line of CLI stderr; skip; workflow continues. Exit 0. |
| `AZURE_DEVOPS_PAT` not set on curl fallback path | Azure DevOps | `[warn] AZURE_DEVOPS_PAT not set; cannot post PR comment via raw HTTP. Skipping.` Skip. Exit 0. |
| ADO PR-thread resource probe exhausted | Azure DevOps | `[warn] ADO PR-thread resource probe failed across [PullRequestThreads, pullrequestthreads, threads]. Skipping comment.` Skip. Exit 0. |
| Internal script error (jq parse, missing required arg) | Any | Surface stderr verbatim. Exit non-zero. |

The "skip + exit 0" contract matches `managing-work-items` and ensures graceful-degradation never halts the workflow.

## Output Format

`backend-detect.sh` JSON (single line, no trailing whitespace):

```
{"backend":"github","owner":"lwndev","repo":"lwndev-marketplace"}
{"backend":"azdo","organization":"contoso","project":"sdlc-tools","repo":"plugin-repo"}
null
```

Tagged log lines (stderr) follow the existing repo convention:

```
[info] No recognized SCM backend detected from origin.
[warn] GitHub CLI (gh) not found on PATH.
[warn] Azure CLI not authenticated -- run az login.
[warn] SDLC_SCM_BACKEND=azdo set but origin does not match azdo URL pattern.
```

PR-create stdout (both backends; consumers parse the URL line):

```
https://github.com/lwndev/lwndev-marketplace/pull/127
https://dev.azure.com/contoso/sdlc-tools/_git/plugin-repo/pullrequest/42
```

## References

- **Branch conventions**: [references/branch-conventions.md](references/branch-conventions.md) -- branch prefix table, naming format, slug rules.
- **Commit conventions**: [references/commit-conventions.md](references/commit-conventions.md) -- conventional commit format per type, scope conventions, multi-line body guidance.
- **PR comments (GitHub)**: [references/pr-comments-github.md](references/pr-comments-github.md) -- `gh pr comment` flags, `gh api` comment shape, NDJSON field mapping with sentinel values.
- **PR comments (Azure DevOps)**: [references/pr-comments-azdo.md](references/pr-comments-azdo.md) -- ADO PR-thread API surface, probe rationale, cache rules, curl fallback.
