# Fixture Requirement (FEAT-999) — reconcile-test-plan coverage

Priority: P1

## Functional Requirements

### FR-1: Widget creation
Users create widgets through the CLI dispatcher and the dispatcher prints
a helpful confirmation.

- Priority: P0

### FR-2: Widget deletion
Users remove widgets via the remove subcommand.

### NFR-1: Performance budget
All widget operations complete in under fifty milliseconds.

### RC-1: Reproducing case
The crash only happens when the widget name contains spaces.

## Acceptance Criteria
- AC-1: Widget creation emits the confirmation line.
- AC-2: Widget deletion removes the registry entry.

## Testing Requirements

All scenarios must be executable via bats. Exploratory coverage is optional.
