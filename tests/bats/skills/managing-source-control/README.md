# managing-source-control Bats fixtures

Unit tests in this directory use PATH-prepended stub binaries (`gh`, `az`, `curl`, `git`) so they run hermetically without credentials or network access. See `create-pr.bats` for the canonical stub pattern.

## Integration tests (env-gated)

Two test files exercise the actual CLI tools against real PRs. They are skipped automatically when their env vars are absent, so `npm run test:bats` stays green in CI without secrets.

| File                               | Gate vars                                           |
| ---------------------------------- | --------------------------------------------------- |
| `pr-comment-roundtrip-github.bats` | `SDLC_INTEGRATION_GITHUB_PR_URL`                    |
| `pr-comment-roundtrip-azdo.bats`   | `SDLC_INTEGRATION_AZDO_PR_URL` + `AZURE_DEVOPS_PAT` |

### Env var reference

**`SDLC_INTEGRATION_GITHUB_PR_URL`**
Full URL of an open GitHub PR on a repo you have write access to.
Example: `https://github.com/example/scratch-repo/pull/1`
Prerequisite: `gh auth login` must already be complete in the shell running the test.

**`SDLC_INTEGRATION_AZDO_PR_URL`**
Full URL of an open Azure DevOps PR on a project you have write access to.
Example: `https://dev.azure.com/myorg/myproject/_git/myrepo/pullrequest/42`

**`AZURE_DEVOPS_PAT`**
Personal Access Token with at minimum the `vso.code_write` scope. Required for the ADO round-trip test. Also used by `pr-comment.sh`'s raw-HTTP `curl` fallback path.

### Important

Both round-trip tests post **real comments** to real PRs and **do not clean them up**. Use sacrificial / scratch PRs that you do not mind accumulating test noise comments on. Comment bodies are generated GUIDs (e.g. `sdlc-rt-azdo-top-<uuid>`) so they are easy to identify.
