# Bug: [Brief Title]

<!--
Replace [Brief Title] with a concise description (2-5 words)
Examples: "Auth Token Expiry Crash", "CSV Export Missing Columns", "Memory Leak in Polling"
-->

## Bug ID

`BUG-XXX`

<!--
Replace XXX with the next available number.
Check requirements/bugs/ for existing bugs and increment.
-->

## GitHub Issue

[#N](https://github.com/org/repo/issues/N)

<!--
Optional: Link to GitHub issue if one exists.
If no issue exists, either:
- Create one and link it here
- Remove this section entirely
-->

## Category

`[runtime-error|logic-error|ui-defect|performance|security|regression]`

<!--
Choose ONE category that best describes this bug:
- runtime-error: Crashes, unhandled exceptions, fatal errors
- logic-error: Incorrect behavior, wrong calculations, bad state
- ui-defect: Visual glitches, layout issues, rendering problems
- performance: Slowness, memory leaks, resource exhaustion
- security: Vulnerabilities, auth bypasses, data exposure
- regression: Previously working functionality that broke
-->

## Severity

`[critical|high|medium|low]`

<!--
Choose ONE severity level:
- critical: Application unusable, data loss, security breach
- high: Major feature broken, no workaround
- medium: Feature impaired, workaround exists
- low: Minor issue, cosmetic, edge case
-->

## Description

[1-2 sentences describing the defect]

<!--
Be specific about what is broken and the impact.
Example: "The session token is not refreshed after expiry, causing
authenticated API calls to fail with a 401 error after 30 minutes."
-->

## Steps to Reproduce

1. Step 1
2. Step 2
3. Step 3

<!--
Provide clear, numbered steps to trigger the bug.
Include any required preconditions (e.g., "Log in as an admin user").
Be specific enough that someone unfamiliar with the codebase can reproduce the issue.
-->

## Expected Behavior

[What should happen]

<!--
Describe the correct behavior that users expect.
Example: "The session token should be refreshed automatically before expiry,
and API calls should continue to succeed without interruption."
-->

## Actual Behavior

[What actually happens]

<!--
Describe what currently happens instead.
Include error messages, stack traces, or screenshots if applicable.
Example: "After 30 minutes, all API calls return 401 Unauthorized.
The user must manually log out and log back in to restore functionality."
-->

## Root Cause(s)

1. [First root cause with file reference]
2. [Second root cause with file reference, if applicable]

<!--
Investigate the codebase before completing this section.
Read the relevant files, trace call paths, and identify the underlying causes.
Distinguish between symptoms and root causes.

Use numbered entries so acceptance criteria can reference them with (RC-N) tags.
Include file path references where applicable.

Examples:
1. The token refresh interceptor in `src/middleware/auth.ts:42` only checks
   expiry on page load, not before each API call.
2. The refresh endpoint in `src/api/session.ts:118` does not handle the case
   where the refresh token itself has expired.

If the root cause cannot be fully determined, document what is known and
note that further investigation is needed.
-->

## Affected Files

- `path/to/file1`
- `path/to/file2`

<!--
List all files that will likely need modification to fix the bug.
Use relative paths from the project root.
If uncertain, list likely candidates with a note.
-->

## Acceptance Criteria

- [ ] Criterion 1 (RC-1)
- [ ] Criterion 2 (RC-1)
- [ ] Criterion 3 (RC-2)

<!--
Define clear, testable criteria for the fix.
Each criterion MUST reference at least one root cause using (RC-N) tags.
Every root cause must have at least one corresponding criterion.

Examples:
- [ ] Token refresh interceptor runs before each API call, not only on page load (RC-1)
- [ ] Expired refresh tokens trigger a re-authentication flow instead of a silent failure (RC-2)
- [ ] Unit tests cover token refresh for both valid and expired refresh tokens (RC-1, RC-2)
-->

## Completion

**Status:** `Pending`

<!--
Update status as work progresses:
- Pending: Not yet started
- In Progress: Branch created, work underway
- Completed: PR merged

When completed, fill in the fields below:
-->

**Completed:** YYYY-MM-DD

**Pull Request:** [#N](https://github.com/org/repo/pull/N)

<!--
Optional: Brief summary of implementation if it differs from the plan
or if there are noteworthy details for future reference.
-->

## Notes

<!--
Optional: Any additional context, constraints, or considerations.
Remove this section if not needed.

Examples of useful notes:
- Environment details (OS, browser, Node version)
- Workarounds currently in use
- Related bugs or feature requests
- Frequency and conditions under which the bug occurs
-->
