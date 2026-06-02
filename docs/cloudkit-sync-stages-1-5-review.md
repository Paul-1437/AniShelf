# CloudKit Sync Feature Review

**Last Update Date:** 2026-06-02  
**Branch:** `feat/cloudkit-sync`

## ⚪ Out-of-Scope / Rollout-Stage Findings

These findings are legitimate rollout hardening concerns, but the staged plan assigns settings, restore policy, and manual two-device validation to Stages 6–8. They should not be treated as Stage 1–5 correctness bugs.

### WARN-4: No `CKAccountChanged` Observer

**File:** Missing  
**Status:** Out of scope for Stages 1–5; valid Stage 6–8 policy gap

No `CKAccountChanged` observer exists. That is a real account-transition policy gap for rollout. However, the token-leakage risk is overstated because token namespaces include the current CloudKit account identifier resolved from `userRecordID()`. The unresolved question is what to do with local dirty work and tokens when the account changes, which belongs with the pending Stage 6 settings/rollout and Stage 7 restore/reset policy.

**Fix:** Define account-change policy during rollout work, then observe `NSNotification.Name.CKAccountChanged` and apply that policy.

### WARN-8: Partial Failure Details Discarded on Save

**File:** `DataProvider/Sources/LibrarySync/CloudLibrarySyncDatabase.swift:143-153`  
**Status:** Valid limitation; out of Stage 1–5 scope

```swift
catch {
    guard let ckError = error as? CKError,
          ckError.code == .partialFailure,
          let partialErrors = ckError.partialErrorsByItemID
    else { throw error }
    let failedIDs = Set(partialErrors.keys.compactMap { $0 as? CKRecord.ID })
    return records.map(\.recordID).filter { !failedIDs.contains($0) }
}
```

Per-record failure reasons (`limitExceeded`, `quotaExceeded`, `notAuthenticated`, etc.) are discarded. The exporter cannot make intelligent retry decisions. This is not a Stage 1–5 correctness bug because the implemented plan only requires accepted records to be dequeued and partial failures to remain queued for retry.

**Fix:** Surface per-record error details through the `CloudLibrarySyncDatabase` protocol.

---

### WARN-9: No Handling of `zoneNotFound` / `userDeletedZone` During Fetch

**File:** `DataProvider/Sources/LibrarySync/CloudLibrarySyncImporter.swift`  
**Status:** Valid Stage 7/8 hardening; out of Stage 1–5 scope

If the user deletes the app's iCloud data (wiping the zone), `fetchRecordZoneChanges` returns `zoneNotFound` or `userDeletedZone`. The importer does not handle these specifically — they propagate as generic errors. Correct behavior would be:

- Reset the change token
- Re-create the zone
- Re-upload all local data (full sync)

The staged plan leaves restore/reset policy pending. Do not treat this as a Stage 1–5 defect until that policy exists.

**Fix:** Add specific error handling for zone deletion scenarios as part of the explicit restore/reset policy.

---

### WARN-10: No Rate Limit / Quota Handling

**File:** `DataProvider/Sources/LibrarySync/CloudLibrarySyncDatabase.swift`  
**Status:** Valid rollout hardening; out of Stage 1–5 scope

CloudKit can return `.rateLimited`, `.requestRateLimited`, or `.quotaExceeded`. None of these are handled specifically.

Stage 6 owns degraded status and user-facing setup state. Stage 1–5 can reasonably propagate these errors as sync failure.

**Fix:** Add exponential backoff for rate limits and user-facing messaging for quota exceeded during rollout/status work.

---

### WARN-11: `containerIdentifier` Falls Back to `Bundle.main.bundleIdentifier`

**File:** `DataProvider/Sources/LibrarySync/CloudLibrarySyncClient.swift:41-43`  
**Status:** Mostly overstated; test/custom-client cleanup

```swift
public var containerIdentifier: String? {
    container?.containerIdentifier ?? Bundle.main.bundleIdentifier
}
```

When `container` is nil (tests), this falls back to the app's bundle identifier. In the live async path, `changeTokenNamespace()` returns `nil` when there is no container, so this is not an app Stage 1–5 bug. It is a cleanup concern for manually constructed namespaces in tests or custom client usage.

**Fix:** Consider returning `nil` when `container` is nil and keeping test namespaces explicit.

---

## 🟡 Additional Valid Stage 1–5 Warning Issues

### WARN-12: Combine Publisher for `didSave` Not `@MainActor`-Isolated

**File:** `MyAnimeList/Sources/ViewModels/Library/LibrarySyncChangeRecorder.swift:287-294`  
**Status:** Valid under strict concurrency

```swift
private func observeSaves() {
    notificationCenter
        .publisher(for: ModelContext.didSave)
        .sink { [weak self] notification in
            self?.processSaveNotification(notification)  // ← no @MainActor dispatch
        }
        .store(in: &cancellables)
}
```

Under **Swift 6 strict concurrency checking**, calling a `@MainActor` method from a non-isolated closure is a compile error. Under current relaxed mode, SwiftData's `mainContext` posts on the main thread, so this works in practice. However, it is a latent migration risk.

**Fix:** Wrap the sink body in `Task { @MainActor [weak self] in ... }`.

---

### WARN-13: Brittle Timing in Scheduler Tests

**File:** `MyAnimeList/Tests/MyAnimeListTests/LibrarySyncCoordinatorTests.swift`  
**Status:** Confirmed valid

`dirtyQueueSchedulerDebouncesLocalChanges` and `dirtyQueueSchedulerBacksOffAfterFailure` use hardcoded nanosecond sleeps (`20_000_000`, `30_000_000`, etc.). These are inherently flaky on slow CI runners.

**Fix:** Inject a controllable clock or use `Clock` protocol conformance.

---

### WARN-14: No Test for Partial Export Failure in Coordinator

**File:** `MyAnimeList/Tests/MyAnimeListTests/LibrarySyncCoordinatorTests.swift`  
**Status:** Confirmed valid, with lower-level coverage caveat

No test simulates a scenario where the exporter saves 2 of 3 records and verifies that:

- The 2 successful identities are removed from the dirty queue
- The 1 failed identity remains queued

`CloudLibrarySyncExporter` has lower-level partial-success coverage, but the coordinator's dirty-queue removal behavior after a partial export is not directly tested.

**Fix:** Add a test with a fake database that reports partial success.

## Top Priorities to Fix

### Before Stage 6 (Settings & Rollout)

1. **WARN-12:** Add `@MainActor` dispatch in Combine sink for future Swift 6 compatibility
2. **Hydration cleanup:** Add coverage or cleanup for staged hydrated inserts if later apply/save fails; this is a downgraded partial finding, not a confirmed critical orphan bug

### Before Stage 8 (Manual Validation)

4. **WARN-4:** Define account-change policy, then add `CKAccountChanged` observer behavior
5. **WARN-8:** Surface per-record CloudKit error details if rollout needs smarter retry/status
6. **WARN-9 / WARN-10:** Add specific handling for `zoneNotFound`, `userDeletedZone`, rate limits, and quota exceeded as part of restore/status policy
7. **All remaining must-add tests** (see Test Coverage section above)

---

## Files Reviewed

**Implementation:**

- `DataProvider/Sources/LibrarySync/LibraryEntrySyncSnapshot.swift`
- `DataProvider/Sources/LibrarySync/CloudLibrarySyncClient.swift`
- `DataProvider/Sources/LibrarySync/CloudLibrarySyncChangeTokenStore.swift`
- `DataProvider/Sources/LibrarySync/LibraryEntrySyncDirtyQueueStore.swift`
- `DataProvider/Sources/LibrarySync/CloudLibrarySyncImporter.swift`
- `DataProvider/Sources/LibrarySync/CloudLibrarySyncExporter.swift`
- `DataProvider/Sources/LibrarySync/CloudLibrarySyncDatabase.swift`
- `DataProvider/Sources/LibrarySync/CloudLibrarySyncDecodeError.swift`
- `MyAnimeList/Sources/ViewModels/Library/LibrarySyncCoordinator.swift`
- `MyAnimeList/Sources/ViewModels/Library/LibrarySyncChangeRecorder.swift`
- `MyAnimeList/Sources/ViewModels/Library/LibrarySyncScheduler.swift`
- `MyAnimeList/Sources/App/LibrarySyncNotificationBridge.swift`
- `DataProvider/Sources/DataProvider/DataProvider.swift`
- `DataProvider/Sources/DataProvider/Models/Other/UserEntryInfo.swift`
- `DataProvider/Sources/DataProvider/Models/Other/AnimeEntryEpisodeProgressHelpers.swift`
- `MyAnimeList/Sources/ViewModels/Library/LibraryStore.swift`
- `MyAnimeList/Sources/ViewModels/Library/LibraryRepository.swift`

**Tests:**

- `DataProvider/Tests/LibrarySyncTests/LibraryEntrySyncTests.swift`
- `DataProvider/Tests/LibrarySyncTests/CloudLibrarySyncClientTests.swift`
- `DataProvider/Tests/LibrarySyncTests/CloudLibrarySyncImporterExporterTests.swift`
- `DataProvider/Tests/LibrarySyncTests/LibraryEntrySyncDirtyQueueStoreTests.swift`
- `MyAnimeList/Tests/MyAnimeListTests/LibrarySyncCoordinatorTests.swift`
- `MyAnimeList/Tests/MyAnimeListTests/LibrarySyncNotificationBridgeTests.swift`
- `MyAnimeList/Tests/MyAnimeListTests/LibraryPreferencesAndActionsTests.swift`
