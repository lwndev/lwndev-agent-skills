# qa-fixture-empty

Deliberately empty consumer-repo fixture used by `scripts/__tests__/qa-integration.test.ts`
to verify that `capability-discovery.sh` degrades to `mode: "exploratory-only"` when
no framework signals are present (no `package.json`, no `pyproject.toml`, no `go.mod`,
no config files).
