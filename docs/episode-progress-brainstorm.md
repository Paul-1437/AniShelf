# Episode-Level Progress Brainstorm

Branch context: `feat/episode-level-status-record`

This note is intentionally loose. The goal is to capture the main product and implementation constraints before the first schema/UI pass.

## Why this feature exists

Right now AniShelf tracks an entry at the entry level: status, dates, score, notes, favorite, custom poster. That works well for lightweight library tracking, but it starts to feel coarse for long-running shows where "Watching" is not enough and the user wants to record actual progress.

The feature should make AniShelf feel more useful for ongoing watching without turning the detail page into a control panel.

## Product principles

- Episode progress should be opt-in, not silently imposed on everyone.
- Turning the feature off should hide or disable the related UI cleanly.
- The feature should enrich existing tracking, not replace the current simple status flow.
- The default path should stay fast. A user who only wants `Planned / Watching / Watched / Dropped` should not feel punished.
- The detail page is already quite dense. Any new UI needs to earn its place.
- Persistence needs to be designed up front. This is not a "just add a slider" feature.

## First scope split

There are really two different problems here:

1. Aggregate progress
Example: `8 / 12 episodes watched`

2. Per-episode record
Example: episode 1 watched, episode 2 watched, episode 3 partially watched, episode 4 skipped, etc.

It is probably safer to decide whether v1 is truly "episode-wise recording" or "entry-level progress with optional episode checklist backing".

My current instinct:

- User-facing promise should be episode-level progress.
- V1 interaction should probably optimize for "mark watched through episode N" rather than forcing users to tap every episode one by one.
- True per-episode editing can wait unless v1 proves it is necessary.

That keeps the common path fast and better matches the intended v1.

## Opt-in model

The setting should likely live alongside other library behavior toggles in settings, not inside a hidden detail-page menu.

Candidate setting:

- `Episode Progress Tracking`
- When off:
  - hide progress controls
  - hide progress bars
  - hide episode completion affordances
  - avoid showing empty placeholders

Important question: what happens to stored progress when the feature is turned off?

Recommended answer:

- Do not delete stored progress.
- Treat the toggle as a visibility/behavior switch, not a destructive data reset.

That is much safer and easier to reverse.

Decision for now:

- scope is global only, not per-entry

## Persistence model questions

This is the part to settle early.

Current entry-level tracking is centered around `UserEntryInfo` and the persisted `AnimeEntry` fields for watch status, dates, score, favorite, notes, and poster customization. Episode progress likely means at least one new persisted concept and probably a schema bump.

### Minimum data we may need

- feature enabled flag at app/settings level
- watched-through progress per entry
- progress partitioning data for entries that span multiple seasons or specials
- optional last-updated timestamp for sync/merge/export friendliness

### Model shape options

#### Option A: aggregate only

Store:

- `watchedThrough`

Pros:

- simple UI
- simple migration
- easy to show progress bars in library

Cons:

- not truly episode-wise
- ambiguous for series entries that span multiple seasons or specials
- cannot represent holes, rewatches, skipped specials, or manual corrections cleanly

#### Option B: watched-through core + structured partitions

Store:

- `watchedThrough`
- optional per-season / specials partitions when an entry spans multiple logical buckets

Pros:

- fast default UX
- can support "mark watched through episode N"
- more intuitive for long-running series if seasons are treated independently
- likely best balance

Cons:

- more logic
- need clear rules for how series, seasons, and specials are partitioned

#### Option C: full per-episode records only

Store:

- one record per episode with status

Pros:

- most principled model
- future-proof for rich episode interactions

Cons:

- heavier persistence and migration footprint
- more UI complexity
- more risk of clutter and performance overhead in large episode lists

Current preference: Option B.

That feels most aligned with AniShelf's current style: lightweight by default, but still capable when the user goes deeper.

## Primary semantic direction

Decisions so far:

- the feature is global only
- v1 semantics are `watched through`
- status synchronization should work both ways
  - reaching completion can promote to `Watched`
  - reducing progress from complete can demote back to `Watching`
- library enrichment should appear in all styles
- v1 should avoid a dedicated editor unless it becomes clearly necessary

## Relationship with watch status

Episode progress and watch status need explicit rules, otherwise the UI will become confusing.

Candidate rules:

- `Planned` -> progress is `0 / N`
- moving progress above zero can auto-promote to `Watching`
- reaching all regular episodes can suggest or auto-set `Watched`
- `Dropped` freezes active progress editing unless we explicitly want otherwise

Current direction:

- manual status changes remain allowed
- progress-aware actions should still apply sensible auto-updates

The tricky part is completion semantics when specials exist. "All episodes watched" is not always the same as "all episode-like content watched".

## Biggest modeling problem: series entries, seasons, and specials

This now looks like the core design problem.

If a user tracks a `series` entry and we say `watched through episode N`, what exactly is `N` measured against?

Possible interpretations:

- absolute count across the whole series
- watched through within the latest surfaced season
- watched through within each season independently
- watched through regular episodes, with specials tracked separately

Why this matters:

- a single absolute count is compact, but unintuitive for long-running shows
- per-season progress is more intuitive, but adds UI and model complexity
- specials can easily distort completion if they are merged into the main count

Current instinct:

- for long-running series, independent season progress is likely more intuitive than one giant total
- specials probably should not block a show from being considered `Watched`
- but exposing that distinction in UI without clutter is hard

This suggests that the persistence design may need to distinguish:

- regular progress
- special-episode progress
- potentially season-scoped progress buckets

Even if v1 UI stays simple, the model should probably leave room for this.

## Where the recording UI should live

This is probably the most important UX decision.

### Option 1: inside the existing Tracking section

Pros:

- conceptually correct
- discoverable
- close to watch status and dates

Cons:

- the tracking card already carries status, date controls, and optionally score nearby
- this risks turning a concise card into a busy editor

### Option 2: a compact summary in Tracking, detailed editing elsewhere

Example:

- tracking card shows `Progress 8 / 12`
- quick actions: `-1`, `+1`, `Edit`
- tapping `Edit` opens a dedicated sheet or bottom sheet with richer episode controls

Pros:

- preserves detail-page balance
- keeps common interactions nearby
- leaves room for richer episode editing without cluttering the main page

Cons:

- adds one more layer
- needs a well-designed sheet

### Option 3: put everything in the Episodes section

Pros:

- semantically precise
- direct proximity to episode list

Cons:

- too far from watch status
- poor discoverability for users who just want to update progress quickly
- feels inconvenient for frequent use

Current preference for v1:

- keep the compact summary in Tracking
- do not assume a dedicated editor is necessary yet
- only add a deeper editing surface later if the inline interaction proves too limiting

## Recording interaction ideas

The interaction should optimize for the most common action: "I just watched the next episode."

### Candidate v1 interaction

In the Tracking section:

- show `Progress 8 / 12`
- show a subtle progress bar
- show compact `-` and `+` controls, or `Mark Next Episode`
- optionally allow direct adjustment via a compact picker or menu

For v1, this may be enough on its own if the interaction feels clean.

### Native picker

Pros:

- familiar
- low engineering/design risk

Cons:

- not especially expressive
- can feel detached from the episode list

### Custom slider

Pros:

- visually communicates progress well

Cons:

- awkward for precise episode numbers
- not ideal for accessibility unless designed carefully
- can feel gimmicky if it replaces better controls

### Custom checklist/list

Pros:

- true episode-wise affordance
- easy to understand

Cons:

- too heavy for the main detail page
- poor fit for long shows unless collapsed or virtualized

### More creative direction

Possibly a horizontal "episode milestone strip" or compact segmented progress capsule in the sheet, but I would avoid getting too fancy in v1. This feature has enough state complexity already.

Current preference:

- simple stepper or plus/minus for the fast path
- maybe a compact native picker/menu for direct jumps
- no dedicated editor in v1 unless the inline approach feels inadequate

## How progress should appear in library views

This part feels important if the feature is enabled. Otherwise the recorded data will feel trapped.

### Library list

Likely the easiest place to enrich without clutter:

- keep the existing watch-status badge
- add a single compact secondary line such as `8 / 12 episodes`
- optionally add a thin progress bar beneath metadata or above the status row

The text alone may already be enough. A bar should only stay if it still feels quiet.

### Library grid / gallery

Need to be careful here. Space is tight.

Possible treatments:

- tiny bottom overlay progress bar on posters
- small `8/12` capsule
- progress ring integrated with the existing status dot

Current instinct:

- start with a very subtle translucent bottom status/progress bar on posters
- avoid mixing too much information into the existing watch-status indicator

Decision for now:

- all library styles should participate
- grid/gallery can use a translucent bottom poster bar

### Search results / other entry rows

Probably follow the list-row treatment where practical, but only when the feature is enabled.

## Episode section integration

Even if the main editing entry point is in Tracking, the Episodes section should probably reflect recorded state.

Ideas:

- watched episodes get a checkmark tint
- current episode gets a highlighted accent
- unwatched episodes remain unchanged
- deeper editing can come later if needed

The Episodes section should feel informative first, editable second.

That helps avoid clutter in normal browsing.

## Clutter control

This needs explicit guardrails.

- Do not add a full checklist directly into the main detail page by default.
- Do not add multiple new rows plus a large control plus explanatory text all at once.
- Prefer one compact progress summary card area over several scattered progress indicators.
- If score is enabled, progress UI should visually coexist with the current score/tracking composition instead of creating another equally heavy card.
- If a dedicated sheet exists, keep the detail page as the summary surface, not the full editor.

## Edge cases to think through

- movies should probably ignore the feature entirely, or map to a trivial watched/not watched state
- series with unknown episode counts
- currently airing shows where total episodes change
- specials / season 0 handling
- whether specials count toward completion, or are tracked separately from the main watched-through progress
- how `series` entries partition progress across seasons
- users marking the final episode before metadata includes it
- dropped shows with partial progress
- rewatch scenarios, if ever supported later
- bulk import/export and backup compatibility
- performance for large episode lists

## Suggested rollout

### Phase 0: design/persistence decision

Settle:

- whether v1 uses a single watched-through value or watched-through plus season/special partitions
- status auto-transition rules
- settings toggle behavior
- export/backup implications

### Phase 1: persistence and basic progress UI

- schema change
- store progress per entry
- settings toggle
- compact tracking summary in detail page
- library display in all styles
- basic cross-sync with watch status

### Phase 2: richer inline control or fallback editor

- fast increment/decrement path
- precise picker
- only add a separate editor surface if inline controls are not enough

### Phase 3: richer episode-wise correction

- per-episode toggles
- special handling for holes/skips/specials
- nicer visual polish if still justified

## Working recommendation

If I were choosing a practical first direction right now:

- make the feature optional via a settings toggle
- use `watched through` as the primary v1 interaction
- persist progress in a way that leaves room for season/special partitions later
- add a compact progress summary to the Tracking section
- keep editing inline for v1 if possible
- surface progress quietly in all library styles when enabled
- keep the main detail page focused on summary, not full episode management

That seems like the best shot at increasing usefulness without breaking AniShelf's current balance.

## Open questions

- For `series` entries, should progress be one absolute total, or partitioned by season?
- How should specials participate in progress and completion?
- What is the cleanest inline control that still allows quick jumps, not just `+1/-1`?
- How do we present season/special partitions, if needed, without creating clutter?
