# Feature Requirements: Pagination

## Feature ID

`FEAT-902`

## Functional Requirements

### FR-1: Cursor-based pagination

Clients paginate via opaque cursor tokens.

### FR-2: Limit parameter bounded at 100

Maximum page size is 100 items.

## Non-Functional Requirements

### NFR-1: Response shape

The endpoint responds with a JSON envelope. Example:

```yaml
page:
  cursor: abc123
  limit: 50
  authentication: required # fenced-code false positive — must be ignored
  performance: # fenced-code false positive — must be ignored
    target: 200ms
```

The prose after the example talks only about the page envelope and
about cache directives. No bump keywords appear in the prose itself.

### NFR-2: Cache-control headers

Responses include a `max-age=60` directive.
