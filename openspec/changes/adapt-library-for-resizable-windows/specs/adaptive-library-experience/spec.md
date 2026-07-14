## ADDED Requirements

### Requirement: Device-independent Gallery layout policy
Gallery SHALL select its arrangement from its own proposed content size and viable card geometry. It MUST NOT use device idiom, named device model, fold state, or interface orientation as the structural layout decision. Entry detail SHALL rely on the system inspector's context-dependent presentation instead of this policy.

#### Scenario: Gallery gains useful shelf space
- **WHEN** Gallery's proposed size can show a viable focused card and neighboring content
- **THEN** Gallery uses the shelf arrangement without checking device identity

#### Scenario: Gallery loses useful shelf space
- **WHEN** Gallery's proposed width or height cannot support the shelf geometry
- **THEN** Gallery returns to its single-page arrangement without changing the detail presentation route

### Requirement: Full-canvas library modes
The system SHALL give Gallery, List, and Grid the complete library canvas whenever entry detail is not presented. The system MUST NOT reserve an empty permanent detail column.

#### Scenario: Detail is closed
- **WHEN** the user closes or has not opened entry detail
- **THEN** the active library mode expands to all available library content space

#### Scenario: User changes display mode
- **WHEN** the user switches among Gallery, List, and Grid
- **THEN** the newly selected mode becomes the primary full-canvas library without being placed in a navigation sidebar

### Requirement: Adaptive Gallery shelf
The system SHALL preserve the current one-entry-per-page Gallery at current on-device iPhone sizes and SHALL reveal neighboring Gallery entries when additional usable space can display them at the required card size. Gallery MUST remain a large-card horizontal focus experience and MUST NOT become a narrow master column or gain multi-selection.

#### Scenario: Current iPhone Gallery
- **WHEN** Gallery runs at any supported current on-device iPhone portrait or landscape geometry
- **THEN** it retains the current full-width single-card paging, gestures, overlays, and detail-opening behavior

#### Scenario: Wide Gallery has surplus horizontal space
- **WHEN** Gallery can show the focused card at its viable size with horizontal space remaining
- **THEN** at least part of a neighboring entry is visible and scrolling remains aligned to a focused entry

#### Scenario: Inspector would compromise Gallery
- **WHEN** opening detail beside Gallery would reduce Gallery below its minimum viable width or height
- **THEN** Gallery returns to its single-page arrangement and does not become a narrow sidebar

### Requirement: On-demand adaptive entry detail
The system SHALL present entry detail only after an explicit open-detail action through one SwiftUI inspector. The app SHALL NOT measure the root geometry or migrate detail between application-owned sheet and inspector hosts.

#### Scenario: Detail opens in a spacious List or Grid
- **WHEN** the user opens an entry and the system inspector uses its trailing-column presentation
- **THEN** a dismissible trailing inspector appears while the library remains the primary surface

#### Scenario: Primary tap targets an entry in regular width
- **WHEN** the horizontal environment is regular and the user taps an entry once
- **THEN** that explicit tap opens or updates the inspector regardless of the constrained-layout tap preference

#### Scenario: System inspector adapts to a sheet
- **WHEN** the user opens an entry in a compact presentation environment
- **THEN** SwiftUI adapts the same inspector presentation to a sheet without an application-owned host transition

#### Scenario: Selection changes while inspector is open
- **WHEN** the user focuses another entry in List, Grid, or Gallery while the inspector is visible
- **THEN** the inspector updates to the newly focused entry without creating another presentation

#### Scenario: Inspector closes
- **WHEN** the user dismisses the inspector
- **THEN** the active library mode immediately reclaims the complete library canvas

### Requirement: Separate focus and presentation state
The system SHALL distinguish the focused library entry, an explicitly presented detail entry, multi-selection, and an active modal workflow. Presentation routes MUST carry lightweight stable identifiers rather than view instances.

#### Scenario: Gallery focus moves without opening detail
- **WHEN** the user pages to another Gallery card without invoking the open-detail gesture
- **THEN** the focused entry changes and no detail sheet or inspector is presented

#### Scenario: Multi-selection begins
- **WHEN** the user enters List or Grid multi-selection
- **THEN** focused-entry state does not replace or corrupt the set of selected entry identifiers

### Requirement: Non-destructive live resizing
The system SHALL preserve display mode, focused entry, scroll position, multi-selection, presented destination, and active workflow state while the scene resizes. Resizing MUST NOT dismiss or reset unsaved work.

#### Scenario: Passive detail crosses the system adaptation boundary
- **WHEN** the scene resizes while passive detail is presented and the system changes the inspector's physical form
- **THEN** the presentation adapts without losing the selected entry or detail session state

#### Scenario: Replaced detail finishes a delayed callback
- **WHEN** an older detail presentation reports an asynchronous callback after another entry or generation is presented
- **THEN** the callback is rejected without clearing the canonical detail route

#### Scenario: Editing during resize
- **WHEN** the scene resizes while entry edits are unsaved
- **THEN** the editing session remains presented with its changes and dismissal safeguards intact

#### Scenario: Library resizes with no detail open
- **WHEN** the scene crosses a layout boundary while the user is browsing
- **THEN** the focused entry and scroll position remain stable and no modal appears solely because of resizing

### Requirement: Current iPhone experience compatibility
At all supported current on-device iPhone portrait and landscape sizes, the system SHALL preserve the existing library composition and detail-opening semantics while using the system inspector's compact adaptation.

#### Scenario: Current iPhone uses any library mode
- **WHEN** Gallery, List, or Grid is used on a current on-device iPhone geometry
- **THEN** its composition, toolbars, gestures, transitions, and selection behavior match the pre-change experience

#### Scenario: Current iPhone opens detail or edit
- **WHEN** the user opens entry detail or editing on a current on-device iPhone geometry
- **THEN** the system-adapted inspector sheet preserves navigation, session state, editing, and dismissal safeguards

### Requirement: Adaptive accessibility capacity
The Gallery layout policy SHALL account for Dynamic Type and accessibility requirements when deciding whether the shelf remains viable.

#### Scenario: Larger text makes the shelf unusable
- **WHEN** the current accessibility configuration causes Gallery cards or chrome to exceed the shelf's viable content size
- **THEN** Gallery uses the single-page arrangement without truncating essential controls
