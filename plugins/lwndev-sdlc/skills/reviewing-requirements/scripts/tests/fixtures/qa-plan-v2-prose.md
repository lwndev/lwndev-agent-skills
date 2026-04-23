# QA Plan — FEAT-999 (version-2 prose format)

## Scenarios

[P0] FR-1 widget creation emits confirmation | mode: executable | expected: users create widgets through the CLI and see a helpful confirmation line
[P1] FR-2 widget deletion scenario | mode: executable | expected: removes registry entry
[P0] NFR-1 performance budget holds | mode: executable | expected: operations under fifty milliseconds
[P1] Exploratory surplus check with no IDs referenced | mode: exploratory | expected: nothing specific
[P0] Reference to FR-99 which does not exist in requirement doc | mode: executable | expected: should surface as surplus
[P1] AC-1 confirmation appears on stdout | mode: manual | expected: quietly silent no output at all
