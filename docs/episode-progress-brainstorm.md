# Episode-Level Progress Demands

Branch context: `feat/episode-level-status-record`

This note only keeps the product demands and constraints.

## Core demand

AniShelf should let users record anime progress at a more granular level than the current entry-level watch status.

The primary v1 semantic should be:

- `watched through episode N`

Not:

- full per-episode checklist as the default interaction

## Feature scope demands

- The feature is opt-in.
- The toggle is global only, not per-entry.
- Turning it off should hide or disable all related UI cleanly.
- Turning it off should not delete stored progress data.
- The feature must be more than a UI layer; persistence needs to be designed as part of the feature itself.

## UX demands

- The common action should feel fast: "I just watched the next episode."
- The detail page must stay concise.
- The feature should not turn the detail page into a dense management screen.
- V1 should prefer inline interaction over a dedicated editor, unless inline interaction proves clearly insufficient.
- The recording UI should stay close to the existing tracking controls, not be buried deep in the Episodes section.

## Tracking behavior demands

- Progress persistence and watch-status persistence should remain independent.
- The app should not automatically backfill watch status from episode counts.
- The app should not automatically rewrite episode progress because of watch-status changes.
- The app can show action prompts when it strongly looks like the user wants to update watch status too.
- Manual watch-status changes should remain allowed.

## Library display demands

- Progress should be reflected across all library styles.
- Library list should show progress in a quiet, compact way.
- Grid/gallery should use a subtle translucent bottom poster bar or similarly low-clutter treatment.
- The feature should enrich the library view when enabled, not keep progress trapped inside the detail page.

## Clutter-control demands

- Avoid visual clutter at all costs.
- Do not dump a full episode checklist onto the main detail page by default.
- Prefer one compact progress summary area over multiple separate progress widgets.
- The new UI must coexist with the existing score/tracking area without overwhelming it.
- The current detail page balance between conciseness and informativeness should be preserved.

## Biggest unresolved demand-level problem

The hardest product problem is how `watched through` should behave for entries that involve multiple seasons and specials.

Resolved demands:

- For a `series` entry, progress should be partitioned by season.
- Different seasons inside a series should be independent for watched-through progress.
- Specials should have separate progress just like seasons.
- Progress semantics and watch-status semantics are separate at the persistence level.

Still open:

- How should season and special partitions be surfaced in the UI without creating clutter?

This is the main area where the persistence model and the UI model need to be aligned from the start.

## Other demand-level constraints

- Long-running shows should feel intuitive to track.
- Users should not have to mentally calculate giant cross-season episode totals.
- Currently airing shows do not need special behavior as long as watched-through is stored as a count; normal episode-count growth should not invalidate progress.
- Dropped shows with partial progress should keep their independent progress data.
- Movies should ignore this feature entirely.
