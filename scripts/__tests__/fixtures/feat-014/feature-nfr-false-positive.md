# Feature Requirements: Author Metadata Rendering

## Feature ID

`FEAT-901`

## Functional Requirements

### FR-1: Render author name next to post title

The post header renders the author display name from the user profile.

### FR-2: Surface commit authorship in the sidebar

Each listing shows the commit author so readers can attribute changes.

## Non-Functional Requirements

### NFR-1: Author metadata loads with the post payload

The author field is populated from the same API call as the post body — no
separate request. A post authored by a deleted user still renders a
fallback string. An article performed well in the A/B test when the
author avatar was visible. The performer (analytics) dashboard shows the
same field for attribution purposes.

### NFR-2: Respect the existing rate limit

Reuses the post endpoint's existing quota.
