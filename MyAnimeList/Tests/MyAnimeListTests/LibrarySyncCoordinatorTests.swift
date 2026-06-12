//
//  LibrarySyncCoordinatorTests.swift
//  MyAnimeListTests
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/31.
//

import CloudKit
import Foundation
import Testing

@testable import DataProvider
@testable import LibrarySync
@testable import MyAnimeList

@Suite(.serialized)
struct LibrarySyncCoordinatorTests {
    @Test @MainActor func localSyncSchedulerDebouncesLocalChanges() async throws {
        var syncCount = 0
        var hasPendingLocalWork = true
        let scheduler = LibrarySyncScheduler(
            localDebounceInterval: 0.05,
            failureRetryIntervals: [0.1],
            hasPendingLocalWork: {
                hasPendingLocalWork
            },
            sync: { trigger in
                #expect(trigger == .localChange)
                syncCount += 1
                hasPendingLocalWork = false
                return .success
            }
        )

        scheduler.schedulePendingLocalSync()
        try await Task.sleep(nanoseconds: 20_000_000)
        scheduler.schedulePendingLocalSync()
        try await Task.sleep(nanoseconds: 30_000_000)

        #expect(syncCount == 0)

        try await Task.sleep(nanoseconds: 60_000_000)

        #expect(syncCount == 1)
    }

    @Test @MainActor func localSyncSchedulerBacksOffAfterFailure() async throws {
        var syncCount = 0
        var hasPendingLocalWork = true
        let scheduler = LibrarySyncScheduler(
            localDebounceInterval: 0.01,
            failureRetryIntervals: [0.08],
            hasPendingLocalWork: {
                hasPendingLocalWork
            },
            sync: { _ in
                syncCount += 1
                if syncCount == 1 {
                    return .retryableFailure
                }
                hasPendingLocalWork = false
                return .success
            }
        )

        scheduler.schedulePendingLocalSync()
        try await Task.sleep(nanoseconds: 30_000_000)

        #expect(syncCount == 1)

        scheduler.schedulePendingLocalSync()
        try await Task.sleep(nanoseconds: 30_000_000)

        #expect(syncCount == 1)

        try await Task.sleep(nanoseconds: 80_000_000)

        #expect(syncCount == 2)
    }

    @Test @MainActor func localSyncSchedulerStopsAfterFinalIntervalRetryLimit() async throws {
        var syncCount = 0
        var retryStates: [LibraryCloudSyncRetryState] = []
        var degradedReason: String?
        let scheduler = LibrarySyncScheduler(
            localDebounceInterval: 0.001,
            failureRetryIntervals: [0.01, 0.02],
            maximumRetryAttemptsAtFinalInterval: 3,
            hasPendingLocalWork: {
                true
            },
            sync: { _ in
                syncCount += 1
                return .retryableFailure
            },
            retryStateDidChange: { retryStates.append($0) },
            degradedStateDidChange: { degradedReason = $0 }
        )

        scheduler.schedulePendingLocalSync()
        for _ in 0..<200 where retryStates.last?.automaticRetriesExhausted != true {
            try await Task.sleep(nanoseconds: 1_000_000)
        }

        #expect(syncCount == 5)
        #expect(retryStates.last?.automaticRetriesExhausted == true)
        #expect(degradedReason != nil)

        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(syncCount == 5)
    }

    @Test @MainActor func localSyncSchedulerResetRestartsFailureRetryPolicy() async throws {
        var syncCount = 0
        var retryStates: [LibraryCloudSyncRetryState] = []
        let scheduler = LibrarySyncScheduler(
            localDebounceInterval: 0.001,
            failureRetryIntervals: [0.01, 0.02],
            maximumRetryAttemptsAtFinalInterval: 3,
            hasPendingLocalWork: {
                true
            },
            sync: { _ in
                syncCount += 1
                return .retryableFailure
            },
            retryStateDidChange: { retryStates.append($0) }
        )

        scheduler.schedulePendingLocalSync()
        for _ in 0..<100 where retryStates.last?.automaticRetriesExhausted != true {
            try await Task.sleep(nanoseconds: 1_000_000)
        }

        #expect(syncCount == 5)
        #expect(retryStates.last?.automaticRetriesExhausted == true)

        scheduler.resetRetryBackoff()
        scheduler.schedulePendingLocalSync()
        for _ in 0..<50 where syncCount < 6 {
            try await Task.sleep(nanoseconds: 1_000_000)
        }

        #expect(syncCount == 6)
        #expect(retryStates.last?.failureRetryAttempt == 1)
        #expect(retryStates.last?.automaticRetriesExhausted == false)
    }

    @Test @MainActor func localSyncSchedulerDoesNotRetryPermanentFailure() async throws {
        var syncCount = 0
        var degradedReason: String?
        let scheduler = LibrarySyncScheduler(
            localDebounceInterval: 0.01,
            failureRetryIntervals: [0.02],
            hasPendingLocalWork: {
                true
            },
            sync: { _ in
                syncCount += 1
                return .permanentFailure
            },
            degradedStateDidChange: { degradedReason = $0 }
        )

        scheduler.schedulePendingLocalSync()
        try await Task.sleep(nanoseconds: 40_000_000)

        #expect(syncCount == 1)
        #expect(degradedReason != nil)
    }

    @Test @MainActor func localSyncSchedulerResetCancelsInFlightSyncHandling() async throws {
        var syncCount = 0
        var syncStarted = false
        var syncContinuation: CheckedContinuation<Void, Never>?
        var retryStates: [LibraryCloudSyncRetryState] = []
        let scheduler = LibrarySyncScheduler(
            localDebounceInterval: 0,
            failureRetryIntervals: [0.01],
            hasPendingLocalWork: {
                true
            },
            sync: { _ in
                syncCount += 1
                syncStarted = true
                await withCheckedContinuation { continuation in
                    syncContinuation = continuation
                }
                return .retryableFailure
            },
            retryStateDidChange: { retryStates.append($0) }
        )

        scheduler.flushPendingLocalSync()
        while !syncStarted {
            try await Task.sleep(nanoseconds: 1_000_000)
        }

        scheduler.resetRetryBackoff()
        syncContinuation?.resume()
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(syncCount == 1)
        #expect(retryStates.last?.failureRetryAttempt == 0)
        #expect(retryStates.last?.automaticRetriesExhausted == false)
    }

    @Test @MainActor func ordinarySyncSkipsWhenCloudSyncDisabled() async throws {
        let store = makeStore(
            enabled: false,
            bootstrapState: .completed,
            hasTMDbAPIKey: true
        )
        let database = FakeCloudLibrarySyncDatabase(changes: [makeEmptyChangeBatch()])
        let coordinator = LibrarySyncCoordinator(
            store: store,
            client: CloudLibrarySyncClient(),
            database: database,
            namespaceProvider: { makeNamespace() }
        )

        let result = await coordinator.syncResult(trigger: .manualRetry)

        #expect(result == .skipped(.disabled))
        #expect(database.ensureZoneCallCount == 0)
        #expect(store.libraryCloudSyncStatus.lastResult == .skipped)
    }

    @Test @MainActor func ordinarySyncSkipsWhenTMDbAPIKeyIsMissing() async throws {
        let store = makeStore(
            enabled: true,
            bootstrapState: .completed,
            hasTMDbAPIKey: false
        )
        let database = FakeCloudLibrarySyncDatabase(changes: [])
        let coordinator = LibrarySyncCoordinator(
            store: store,
            client: CloudLibrarySyncClient(),
            database: database,
            namespaceProvider: { makeNamespace() }
        )

        let result = await coordinator.syncResult(trigger: .manualRetry)

        #expect(result == .skipped(.missingTMDbAPIKey))
        #expect(database.ensureZoneCallCount == 0)
    }

    @Test @MainActor func ordinarySyncSkipsWhenBootstrapIsIncomplete() async throws {
        let store = makeStore(
            enabled: true,
            bootstrapState: .needsConflictChoice,
            hasTMDbAPIKey: true
        )
        let database = FakeCloudLibrarySyncDatabase(changes: [])
        let coordinator = LibrarySyncCoordinator(
            store: store,
            client: CloudLibrarySyncClient(),
            database: database,
            namespaceProvider: { makeNamespace() }
        )

        let result = await coordinator.syncResult(trigger: .manualRetry)

        #expect(result == .skipped(.bootstrapIncomplete))
        #expect(database.ensureZoneCallCount == 0)
    }

    @Test @MainActor func appLaunchResumesInterruptedFirstEnableBootstrap() async throws {
        let store = makeStore(
            enabled: true,
            bootstrapState: .running,
            hasTMDbAPIKey: true
        )
        let database = FakeCloudLibrarySyncDatabase(changes: [makeEmptyChangeBatch()])
        store.configureLibrarySyncCoordinator(
            client: CloudLibrarySyncClient(),
            database: database,
            namespaceProvider: { makeNamespace() }
        )

        let result = await store.performLibrarySyncResult(trigger: .appLaunch)

        #expect(result == .success)
        #expect(store.libraryCloudSyncStatus.isEnabled)
        #expect(store.libraryCloudSyncStatus.bootstrapState == .completed)
        #expect(store.libraryCloudSyncStatus.lastResult == .success)
        #expect(database.ensureZoneCallCount == 1)
    }

    @Test @MainActor func manualRetryClearsDegradedStateAfterSuccessfulSync() async throws {
        let store = makeSyncReadyStore()
        store.updateLibraryCloudSyncStatus { status in
            status.retryState = .init(
                failureRetryAttempt: 4,
                nextRetryAllowedAt: referenceDate(year: 2026, month: 6, day: 2),
                automaticRetriesExhausted: true
            )
            status.degradedReason = "Automatic retries were exhausted."
        }
        let database = FakeCloudLibrarySyncDatabase(changes: [makeEmptyChangeBatch()])
        store.configureLibrarySyncCoordinator(
            client: CloudLibrarySyncClient(),
            database: database,
            namespaceProvider: { makeNamespace() }
        )

        let succeeded = await store.retryLibraryCloudSync()

        #expect(succeeded)
        #expect(store.libraryCloudSyncStatus.retryState == .idle)
        #expect(store.libraryCloudSyncStatus.degradedReason == nil)
        #expect(store.libraryCloudSyncStatus.lastResult == .success)
    }

    @Test @MainActor func remoteUpdateDoesNotEnqueueDirtyUpsert() async throws {
        let store = makeSyncReadyStore()
        let entry = AnimeEntry(name: "Remote Update", type: .series, tmdbID: 701)
        entry.markCreatedForLibrary(at: referenceDate(year: 2026, month: 5, day: 1))
        try store.repository.newEntry(entry)
        try store.syncChangeRecorder.dirtyQueueStore.replaceEntries([])
        store.rebuildSyncChangeTracking()

        let client = CloudLibrarySyncClient()
        let namespace = makeNamespace()
        let remoteSnapshot = makeSnapshot(
            identity: entry.syncIdentity,
            tmdbID: entry.tmdbID,
            notes: "Remote notes",
            trackingUpdatedAt: referenceDate(year: 2026, month: 5, day: 5)
        )
        let database = FakeCloudLibrarySyncDatabase(changes: [
            .init(
                modifiedRecordsByID: [
                    client.recordID(for: entry.syncIdentity): try client.record(from: remoteSnapshot)
                ],
                deletedRecordIDs: [],
                changeToken: makeToken(),
                moreComing: false
            )
        ])
        let coordinator = LibrarySyncCoordinator(
            store: store,
            client: client,
            database: database,
            namespaceProvider: { namespace }
        )

        await coordinator.sync(trigger: .manualRetry)

        try store.refreshLibrary()
        let refreshed = try #require(store.library.first { $0.syncIdentity == entry.syncIdentity })
        #expect(refreshed.notes == "Remote notes")
        #expect(database.savedRecords.isEmpty)
        #expect(store.syncChangeRecorder.dirtyQueueStore.load().entries.isEmpty)
    }

    @Test @MainActor func newerRemoteSettingsApplyLocally() async throws {
        let store = makeSyncReadyStore()
        store.preferences.saveCloudSyncedDefaultsUpdatedAt(referenceDate(year: 2026, month: 6, day: 1))
        store.preferences.applyCloudSyncedSettingsSnapshot(
            .init(
                updatedAt: referenceDate(year: 2026, month: 6, day: 1),
                payload: [.useTMDbRelayServer: .bool(false)]
            )
        )
        store.reloadPersistedPreferences()

        let client = CloudLibrarySyncClient()
        let remoteSettings = LibrarySettingsSyncSnapshot(
            updatedAt: referenceDate(year: 2026, month: 6, day: 5),
            payload: [
                .useTMDbRelayServer: .bool(true),
                .preferredAnimeInfoLanguage: .string("ja"),
                .useCurrentLocaleForAnimeInfoLanguage: .bool(false)
            ]
        )
        let database = FakeCloudLibrarySyncDatabase(changes: [
            .init(
                modifiedRecordsByID: [client.librarySettingsRecordID: try client.record(from: remoteSettings)],
                deletedRecordIDs: [],
                changeToken: makeToken(),
                moreComing: false
            )
        ])
        let coordinator = LibrarySyncCoordinator(
            store: store,
            client: client,
            database: database,
            namespaceProvider: { makeNamespace() }
        )

        let result = await coordinator.syncResult(trigger: .manualRetry)

        #expect(result == .success)
        #expect(store.preferences.cloudSyncedDefaultsUpdatedAt() == remoteSettings.updatedAt)
        #expect(store.preferences.loadCloudSyncedSettingsSnapshot().payload[.useTMDbRelayServer] == .bool(true))
        #expect(store.language == .japanese)
    }

    @Test @MainActor func olderRemoteSettingsAreIgnored() async throws {
        let store = makeSyncReadyStore()
        let localSettings = LibrarySettingsSyncSnapshot(
            updatedAt: referenceDate(year: 2026, month: 6, day: 5),
            payload: [.useTMDbRelayServer: .bool(true)]
        )
        store.preferences.applyCloudSyncedSettingsSnapshot(localSettings)
        store.preferences.saveCloudSyncedDefaultsUpdatedAt(localSettings.updatedAt)
        store.reloadPersistedPreferences()

        let client = CloudLibrarySyncClient()
        let remoteSettings = LibrarySettingsSyncSnapshot(
            updatedAt: referenceDate(year: 2026, month: 6, day: 1),
            payload: [.useTMDbRelayServer: .bool(false)]
        )
        let database = FakeCloudLibrarySyncDatabase(changes: [
            .init(
                modifiedRecordsByID: [client.librarySettingsRecordID: try client.record(from: remoteSettings)],
                deletedRecordIDs: [],
                changeToken: makeToken(),
                moreComing: false
            )
        ])
        let coordinator = LibrarySyncCoordinator(
            store: store,
            client: client,
            database: database,
            namespaceProvider: { makeNamespace() }
        )

        let result = await coordinator.syncResult(trigger: .manualRetry)

        #expect(result == .success)
        #expect(store.preferences.cloudSyncedDefaultsUpdatedAt() == localSettings.updatedAt)
        #expect(store.preferences.loadCloudSyncedSettingsSnapshot().payload[.useTMDbRelayServer] == .bool(true))
    }

    @Test @MainActor func newerLocalSettingsExport() async throws {
        let store = makeSyncReadyStore()
        let localSettings = LibrarySettingsSyncSnapshot(
            updatedAt: referenceDate(year: 2026, month: 6, day: 5),
            payload: [.useTMDbRelayServer: .bool(true)]
        )
        store.preferences.applyCloudSyncedSettingsSnapshot(localSettings)
        store.preferences.saveCloudSyncedDefaultsUpdatedAt(localSettings.updatedAt)
        store.reloadPersistedPreferences()

        let client = CloudLibrarySyncClient()
        let remoteSettings = LibrarySettingsSyncSnapshot(
            updatedAt: referenceDate(year: 2026, month: 6, day: 1),
            payload: [.useTMDbRelayServer: .bool(false)]
        )
        let database = FakeCloudLibrarySyncDatabase(changes: [
            .init(
                modifiedRecordsByID: [client.librarySettingsRecordID: try client.record(from: remoteSettings)],
                deletedRecordIDs: [],
                changeToken: makeToken(),
                moreComing: false
            )
        ])
        let coordinator = LibrarySyncCoordinator(
            store: store,
            client: client,
            database: database,
            namespaceProvider: { makeNamespace() }
        )

        let result = await coordinator.syncResult(trigger: .manualRetry)

        #expect(result == .success)
        let savedSettingsRecord = try #require(
            database.savedRecords.first { $0.recordID == client.librarySettingsRecordID }
        )
        #expect(try client.settingsSnapshot(from: savedSettingsRecord) == localSettings)
    }

    @Test @MainActor func settingsEditedDuringInFlightExportRemainPending() async throws {
        let store = makeSyncReadyStore()
        let originalSettings = LibrarySettingsSyncSnapshot(
            updatedAt: referenceDate(year: 2026, month: 6, day: 5),
            payload: [.useTMDbRelayServer: .bool(false)]
        )
        store.preferences.applyCloudSyncedSettingsSnapshot(originalSettings)
        store.preferences.saveCloudSyncedDefaultsUpdatedAt(originalSettings.updatedAt)
        store.reloadPersistedPreferences()

        let client = CloudLibrarySyncClient()
        let database = FakeCloudLibrarySyncDatabase(changes: [
            makeEmptyChangeBatch(),
            makeEmptyChangeBatch()
        ])
        database.suspendNextSave = true
        let coordinator = LibrarySyncCoordinator(
            store: store,
            client: client,
            database: database,
            namespaceProvider: { makeNamespace() }
        )

        let syncTask = Task {
            await coordinator.syncResult(trigger: .localChange)
        }
        for _ in 0..<50 where !database.isSaveSuspended {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        #expect(database.isSaveSuspended)

        let updatedSettings = LibrarySettingsSyncSnapshot(
            updatedAt: referenceDate(year: 2026, month: 6, day: 6),
            payload: [.useTMDbRelayServer: .bool(true)]
        )
        store.preferences.applyCloudSyncedSettingsSnapshot(updatedSettings)
        store.preferences.saveCloudSyncedDefaultsUpdatedAt(updatedSettings.updatedAt)
        store.reloadPersistedPreferences()

        database.resumeSuspendedSave()
        let firstResult = await syncTask.value

        #expect(firstResult == .success)
        var savedSettingsRecords = database.savedRecords.filter {
            $0.recordID == client.librarySettingsRecordID
        }
        #expect(savedSettingsRecords.count == 1)
        #expect(try client.settingsSnapshot(from: try #require(savedSettingsRecords.first)) == originalSettings)
        #expect(store.hasPendingCloudSyncedSettingsSyncWork())

        let followUpResult = await coordinator.syncResult(trigger: .localChange)

        #expect(followUpResult == .success)
        savedSettingsRecords = database.savedRecords.filter {
            $0.recordID == client.librarySettingsRecordID
        }
        #expect(savedSettingsRecords.count == 2)
        #expect(try client.settingsSnapshot(from: try #require(savedSettingsRecords.last)) == updatedSettings)
        #expect(!store.hasPendingCloudSyncedSettingsSyncWork())
    }

    @Test @MainActor func partialSettingsExportDoesNotAdvanceReconciledSettingsWatermark() async throws {
        let store = makeSyncReadyStore()
        let previousReconciledUpdatedAt = referenceDate(year: 2026, month: 6, day: 4)
        store.updateLibraryCloudSyncStatus { status in
            status.lastReconciledCloudSyncedSettingsUpdatedAt = previousReconciledUpdatedAt
        }
        let localSettings = LibrarySettingsSyncSnapshot(
            updatedAt: referenceDate(year: 2026, month: 6, day: 5),
            payload: [.useTMDbRelayServer: .bool(true)]
        )
        store.preferences.applyCloudSyncedSettingsSnapshot(localSettings)
        store.preferences.saveCloudSyncedDefaultsUpdatedAt(localSettings.updatedAt)
        store.reloadPersistedPreferences()

        let client = CloudLibrarySyncClient()
        let database = FakeCloudLibrarySyncDatabase(
            changes: [makeEmptyChangeBatch()],
            successfulSaveRecordIDs: []
        )
        let coordinator = LibrarySyncCoordinator(
            store: store,
            client: client,
            database: database,
            namespaceProvider: { makeNamespace() }
        )

        let result = await coordinator.syncResult(trigger: .manualRetry)

        #expect(result == .success)
        #expect(database.savedRecords.count == 1)
        #expect(
            store.libraryCloudSyncStatus.lastReconciledCloudSyncedSettingsUpdatedAt
                == previousReconciledUpdatedAt
        )
        #expect(store.hasPendingCloudSyncedSettingsSyncWork())
    }

    @Test @MainActor func remoteSettingsApplyDoesNotRestampLocalClockAsFreshEdit() async throws {
        let store = makeSyncReadyStore()
        store.preferences.saveCloudSyncedDefaultsUpdatedAt(referenceDate(year: 2026, month: 6, day: 1))
        let client = CloudLibrarySyncClient()
        let remoteSettings = LibrarySettingsSyncSnapshot(
            updatedAt: referenceDate(year: 2026, month: 6, day: 5),
            payload: [.useTMDbRelayServer: .bool(true)]
        )
        let database = FakeCloudLibrarySyncDatabase(changes: [
            .init(
                modifiedRecordsByID: [client.librarySettingsRecordID: try client.record(from: remoteSettings)],
                deletedRecordIDs: [],
                changeToken: makeToken(),
                moreComing: false
            )
        ])
        let coordinator = LibrarySyncCoordinator(
            store: store,
            client: client,
            database: database,
            namespaceProvider: { makeNamespace() }
        )

        let result = await coordinator.syncResult(trigger: .manualRetry)

        #expect(result == .success)
        #expect(store.preferences.cloudSyncedDefaultsUpdatedAt() == remoteSettings.updatedAt)
        #expect(
            store.libraryCloudSyncStatus.lastReconciledCloudSyncedSettingsUpdatedAt
                == remoteSettings.updatedAt
        )
        #expect(!store.hasPendingCloudSyncedSettingsSyncWork())
        let savedSettingsRecords = database.savedRecords.filter { $0.recordID == client.librarySettingsRecordID }
        #expect(savedSettingsRecords.isEmpty)
    }

    @Test @MainActor func missingRowHydratesInsertsAndAppliesSnapshot() async throws {
        let store = makeSyncReadyStore()
        let namespace = makeNamespace()
        let identity = LibraryEntrySyncIdentity(entryType: .movie, tmdbID: 702)
        let client = CloudLibrarySyncClient()
        let snapshot = makeSnapshot(
            identity: identity,
            tmdbID: 702,
            entryType: .movie,
            notes: "Hydrated"
        )
        let database = FakeCloudLibrarySyncDatabase(changes: [
            .init(
                modifiedRecordsByID: [client.recordID(for: identity): try client.record(from: snapshot)],
                deletedRecordIDs: [],
                changeToken: makeToken(),
                moreComing: false
            )
        ])
        let coordinator = LibrarySyncCoordinator(
            store: store,
            client: client,
            database: database,
            namespaceProvider: { namespace },
            hydrateMissingEntry: { snapshot, store in
                let entry = AnimeEntry(
                    name: "Hydrated Placeholder",
                    type: snapshot.entryType,
                    tmdbID: snapshot.tmdbID
                )
                store.repository.insert(entry)
                return entry
            }
        )

        await coordinator.sync(trigger: .manualRetry)

        try store.refreshLibrary()
        let hydrated = try #require(store.library.first { $0.syncIdentity == identity })
        #expect(hydrated.notes == "Hydrated")
        #expect(hydrated.tmdbID == 702)
    }

    @Test @MainActor func missingRowWithNilClocksAppliesRemoteState() async throws {
        let store = makeSyncReadyStore()
        let namespace = makeNamespace()
        let identity = LibraryEntrySyncIdentity(entryType: .series, tmdbID: 706)
        let client = CloudLibrarySyncClient()
        var snapshot = makeSnapshot(
            identity: identity,
            tmdbID: 706,
            notes: "Nil clock remote",
            trackingUpdatedAt: nil
        )
        snapshot.libraryUpdatedAt = nil
        snapshot.favorite = true
        snapshot.score = 5
        snapshot.watchStatus = .dropped
        let database = FakeCloudLibrarySyncDatabase(changes: [
            .init(
                modifiedRecordsByID: [client.recordID(for: identity): try client.record(from: snapshot)],
                deletedRecordIDs: [],
                changeToken: makeToken(),
                moreComing: false
            )
        ])
        let coordinator = LibrarySyncCoordinator(
            store: store,
            client: client,
            database: database,
            namespaceProvider: { namespace },
            hydrateMissingEntry: { snapshot, store in
                let entry = AnimeEntry(
                    name: "Hydrated Defaults",
                    type: snapshot.entryType,
                    tmdbID: snapshot.tmdbID
                )
                store.repository.insert(entry)
                return entry
            }
        )

        await coordinator.sync(trigger: .manualRetry)

        try store.refreshLibrary()
        let hydrated = try #require(store.library.first { $0.syncIdentity == identity })
        #expect(hydrated.notes == "Nil clock remote")
        #expect(hydrated.favorite)
        #expect(hydrated.score == 5)
        #expect(hydrated.watchStatus == .dropped)
        #expect(store.syncChangeRecorder.dirtyQueueStore.load().entries.isEmpty)
    }

    @Test @MainActor func userEditDuringHydrationStillExports() async throws {
        let store = makeSyncReadyStore()
        let unrelated = AnimeEntry(name: "Unrelated Local", type: .movie, tmdbID: 709)
        unrelated.markCreatedForLibrary(at: referenceDate(year: 2026, month: 5, day: 1))
        try store.repository.newEntry(unrelated)
        try store.syncChangeRecorder.dirtyQueueStore.replaceEntries([])
        store.rebuildSyncChangeTracking()

        let namespace = makeNamespace()
        let remoteIdentity = LibraryEntrySyncIdentity(entryType: .movie, tmdbID: 710)
        let client = CloudLibrarySyncClient()
        let remoteSnapshot = makeSnapshot(
            identity: remoteIdentity,
            tmdbID: 710,
            entryType: .movie,
            notes: "Hydrated remote"
        )
        let database = FakeCloudLibrarySyncDatabase(changes: [
            .init(
                modifiedRecordsByID: [client.recordID(for: remoteIdentity): try client.record(from: remoteSnapshot)],
                deletedRecordIDs: [],
                changeToken: makeToken(),
                moreComing: false
            )
        ])
        var hydrationContinuation: CheckedContinuation<Void, Never>?
        var isHydrationSuspended = false
        let coordinator = LibrarySyncCoordinator(
            store: store,
            client: client,
            database: database,
            namespaceProvider: { namespace },
            hydrateMissingEntry: { snapshot, store in
                isHydrationSuspended = true
                await withCheckedContinuation { continuation in
                    hydrationContinuation = continuation
                }
                let entry = AnimeEntry(
                    name: "Hydrated Placeholder",
                    type: snapshot.entryType,
                    tmdbID: snapshot.tmdbID
                )
                store.repository.insert(entry)
                return entry
            }
        )

        let syncTask = Task {
            await coordinator.sync(trigger: .manualRetry)
        }
        while !isHydrationSuspended {
            await Task.yield()
        }

        unrelated.updateNotes(
            "User edit during hydration",
            at: referenceDate(year: 2026, month: 5, day: 12)
        )
        try store.repository.save()
        hydrationContinuation?.resume()

        _ = await syncTask.value

        let savedSnapshots = try database.savedRecords.map {
            try savedSnapshot(from: $0, client: client)
        }
        #expect(
            savedSnapshots.contains { snapshot in
                snapshot.identity == unrelated.syncIdentity
                    && snapshot.notes == "User edit during hydration"
            })
        #expect(store.syncChangeRecorder.dirtyQueueStore.load().entries.isEmpty)
    }

    @Test @MainActor func pendingLocalDeletePreventsStaleRemoteSnapshotHydration() async throws {
        let store = makeSyncReadyStore()
        let entry = AnimeEntry(
            name: "Deleted Local",
            type: .series,
            tmdbID: 711,
            dateSaved: referenceDate(year: 2026, month: 5, day: 1)
        )
        entry.libraryUpdatedAt = referenceDate(year: 2026, month: 5, day: 1)
        try store.repository.newEntry(entry)
        let identity = entry.syncIdentity
        try store.repository.deleteEntry(entry)

        let client = CloudLibrarySyncClient()
        let staleRemoteSnapshot = makeSnapshot(
            identity: identity,
            tmdbID: 711,
            notes: "Stale remote",
            trackingUpdatedAt: referenceDate(year: 2026, month: 5, day: 1)
        )
        let database = FakeCloudLibrarySyncDatabase(changes: [
            .init(
                modifiedRecordsByID: [
                    client.recordID(for: identity): try client.record(from: staleRemoteSnapshot)
                ],
                deletedRecordIDs: [],
                changeToken: makeToken(),
                moreComing: false
            )
        ])
        let coordinator = LibrarySyncCoordinator(
            store: store,
            client: client,
            database: database,
            namespaceProvider: { makeNamespace() }
        )

        let result = await coordinator.syncResult(trigger: .localChange)

        #expect(result == .success)
        #expect(store.repository.existingEntry(identity: identity) == nil)
        #expect(store.syncChangeRecorder.dirtyQueueStore.load().entry(for: identity) == nil)
        let savedRecord = try #require(
            database.savedRecords.first { $0.recordID == client.recordID(for: identity) }
        )
        guard case .tombstone(let savedTombstone) = try client.remoteChange(from: savedRecord) else {
            Issue.record("Expected the pending local delete to export a tombstone.")
            return
        }
        #expect(savedTombstone.identity == identity)
    }

    @Test @MainActor func staleTombstonePreservesNewerLocalState() async throws {
        let store = makeSyncReadyStore()
        let entry = AnimeEntry(
            name: "Stale Tombstone",
            type: .series,
            tmdbID: 703,
            dateSaved: referenceDate(year: 2026, month: 5, day: 20)
        )
        entry.libraryUpdatedAt = referenceDate(year: 2026, month: 5, day: 20)
        try store.repository.newEntry(entry)
        try store.syncChangeRecorder.dirtyQueueStore.replaceEntries([
            .upsert(
                .init(
                    identity: entry.syncIdentity,
                    dirtyAt: referenceDate(year: 2026, month: 5, day: 20)
                ))
        ])
        store.rebuildSyncChangeTracking()

        let client = CloudLibrarySyncClient()
        let remoteTombstone = LibraryEntrySyncTombstone(
            identity: entry.syncIdentity,
            tmdbID: entry.tmdbID,
            parentSeriesID: entry.type.parentSeriesID,
            seasonNumber: entry.type.seasonNumber,
            entryType: entry.type,
            deletedAt: referenceDate(year: 2026, month: 5, day: 3)
        )
        let database = FakeCloudLibrarySyncDatabase(changes: [
            .init(
                modifiedRecordsByID: [
                    client.recordID(for: entry.syncIdentity): try client.record(from: remoteTombstone)
                ],
                deletedRecordIDs: [],
                changeToken: makeToken(),
                moreComing: false
            )
        ])
        let coordinator = LibrarySyncCoordinator(
            store: store,
            client: client,
            database: database,
            namespaceProvider: { makeNamespace() }
        )

        await coordinator.sync(trigger: .manualRetry)

        try store.refreshLibrary()
        let refreshed = try #require(store.library.first { $0.syncIdentity == entry.syncIdentity })
        #expect(refreshed.onDisplay)
        #expect(database.savedRecords.count == 1)
        #expect(store.syncChangeRecorder.dirtyQueueStore.load().entries.isEmpty)
    }

    @Test @MainActor func newerTombstoneSuppressesStaleLocalDirtyExport() async throws {
        let store = makeSyncReadyStore()
        let entry = AnimeEntry(
            name: "Fresh Tombstone",
            type: .series,
            tmdbID: 704,
            dateSaved: referenceDate(year: 2026, month: 5, day: 3)
        )
        entry.libraryUpdatedAt = referenceDate(year: 2026, month: 5, day: 3)
        try store.repository.newEntry(entry)
        try store.syncChangeRecorder.dirtyQueueStore.replaceEntries([
            .upsert(
                .init(
                    identity: entry.syncIdentity,
                    dirtyAt: referenceDate(year: 2026, month: 5, day: 3)
                ))
        ])
        store.rebuildSyncChangeTracking()

        let client = CloudLibrarySyncClient()
        let remoteTombstone = LibraryEntrySyncTombstone(
            identity: entry.syncIdentity,
            tmdbID: entry.tmdbID,
            parentSeriesID: entry.type.parentSeriesID,
            seasonNumber: entry.type.seasonNumber,
            entryType: entry.type,
            deletedAt: referenceDate(year: 2026, month: 5, day: 11)
        )
        let database = FakeCloudLibrarySyncDatabase(changes: [
            .init(
                modifiedRecordsByID: [
                    client.recordID(for: entry.syncIdentity): try client.record(from: remoteTombstone)
                ],
                deletedRecordIDs: [],
                changeToken: makeToken(),
                moreComing: false
            )
        ])
        let coordinator = LibrarySyncCoordinator(
            store: store,
            client: client,
            database: database,
            namespaceProvider: { makeNamespace() }
        )

        await coordinator.sync(trigger: .manualRetry)

        let stored = try #require(store.repository.existingEntry(identity: entry.syncIdentity))
        #expect(!stored.onDisplay)
        #expect(store.syncChangeRecorder.dirtyQueueStore.load().entry(for: entry.syncIdentity) == nil)
        #expect(database.savedRecords.isEmpty)
    }

    @Test @MainActor func duplicateRemoteChangesCoalesceBeforeDirtyQueueReconciliation() throws {
        let identity = LibraryEntrySyncIdentity(entryType: .series, tmdbID: 712)
        let olderRemoteSnapshot = makeSnapshot(
            identity: identity,
            tmdbID: 712,
            notes: "Older remote",
            trackingUpdatedAt: referenceDate(year: 2026, month: 5, day: 2)
        )
        let newerRemoteSnapshot = makeSnapshot(
            identity: identity,
            tmdbID: 712,
            notes: "Newer remote",
            trackingUpdatedAt: referenceDate(year: 2026, month: 5, day: 9)
        )

        let changesByIdentity = try LibrarySyncCoordinator.coalescedRemoteChangesByIdentity([
            .snapshot(olderRemoteSnapshot),
            .snapshot(newerRemoteSnapshot)
        ])

        let mergedChange = try #require(changesByIdentity[identity])
        guard case .snapshot(let mergedSnapshot) = mergedChange else {
            Issue.record("Expected duplicate snapshots to merge into a snapshot.")
            return
        }
        #expect(mergedSnapshot.notes == "Newer remote")
        #expect(mergedSnapshot.trackingUpdatedAt == referenceDate(year: 2026, month: 5, day: 9))
    }

    @Test @MainActor func partialExportOnlyDequeuesAcceptedDirtyEntries() async throws {
        let store = makeSyncReadyStore()
        let first = AnimeEntry(name: "First Export", type: .movie, tmdbID: 707)
        let second = AnimeEntry(name: "Second Export", type: .series, tmdbID: 708)
        first.markCreatedForLibrary(at: referenceDate(year: 2026, month: 5, day: 1))
        second.markCreatedForLibrary(at: referenceDate(year: 2026, month: 5, day: 1))
        try store.repository.newEntry(first)
        try store.repository.newEntry(second)
        try store.syncChangeRecorder.dirtyQueueStore.replaceEntries([
            .upsert(
                .init(
                    identity: first.syncIdentity,
                    dirtyAt: referenceDate(year: 2026, month: 5, day: 8)
                )),
            .upsert(
                .init(
                    identity: second.syncIdentity,
                    dirtyAt: referenceDate(year: 2026, month: 5, day: 9)
                ))
        ])
        store.rebuildSyncChangeTracking()

        let client = CloudLibrarySyncClient()
        let database = FakeCloudLibrarySyncDatabase(
            changes: [
                .init(
                    modifiedRecordsByID: [:],
                    deletedRecordIDs: [],
                    changeToken: makeToken(),
                    moreComing: false
                )
            ],
            successfulSaveRecordIDs: [client.recordID(for: first.syncIdentity)]
        )
        let coordinator = LibrarySyncCoordinator(
            store: store,
            client: client,
            database: database,
            namespaceProvider: { makeNamespace() }
        )

        await coordinator.sync(trigger: .manualRetry)

        let remainingEntries = store.syncChangeRecorder.dirtyQueueStore.load().entries
        #expect(database.savedRecords.count == 2)
        #expect(remainingEntries.count == 1)
        #expect(remainingEntries.first?.identity == second.syncIdentity)
        #expect(store.syncChangeRecorder.dirtyQueueStore.load().entry(for: first.syncIdentity) == nil)
    }

    @Test @MainActor func partialExportFailureDequeuesAcceptedBatchesBeforeRetry() async throws {
        let store = makeSyncReadyStore()
        var dirtyEntries: [LibraryEntrySyncDirtyQueueEntry] = []
        for offset in 0..<360 {
            let tmdbID = 10_000 + offset
            let entry = AnimeEntry(
                name: "Large Export \(offset)",
                type: .series,
                tmdbID: tmdbID
            )
            entry.markCreatedForLibrary(at: referenceDate(year: 2026, month: 5, day: 1))
            try store.repository.newEntry(entry)
            dirtyEntries.append(
                .upsert(
                    .init(
                        identity: entry.syncIdentity,
                        dirtyAt: referenceDate(year: 2026, month: 5, day: 8)
                    ))
            )
        }
        try store.syncChangeRecorder.dirtyQueueStore.replaceEntries(dirtyEntries)
        store.rebuildSyncChangeTracking()

        let client = CloudLibrarySyncClient()
        let database = FakeCloudLibrarySyncDatabase(
            changes: [makeEmptyChangeBatch()],
            saveErrorsByCallIndex: [2: CKError(.networkFailure)]
        )
        let coordinator = LibrarySyncCoordinator(
            store: store,
            client: client,
            database: database,
            namespaceProvider: { makeNamespace() }
        )

        let result = await coordinator.sync(trigger: .manualRetry)

        #expect(!result)
        #expect(store.libraryCloudSyncStatus.lastResult == .retryableFailure)
        #expect(database.saveBatchSizes == [350, 10])
        #expect(database.savedRecords.count == 350)
        #expect(store.syncChangeRecorder.dirtyQueueStore.load().entries.count == 10)
    }

    @Test @MainActor func duplicateDirtyQueueEntriesDoNotCrashExportConfirmation() async throws {
        let store = makeSyncReadyStore()
        let entry = AnimeEntry(name: "Duplicate Dirty", type: .movie, tmdbID: 713)
        entry.markCreatedForLibrary(at: referenceDate(year: 2026, month: 5, day: 1))
        try store.repository.newEntry(entry)
        store.rebuildSyncChangeTracking()

        let olderEntry = LibraryEntrySyncDirtyQueueEntry.upsert(
            .init(
                identity: entry.syncIdentity,
                dirtyAt: referenceDate(year: 2026, month: 5, day: 8)
            ))
        let newerEntry = LibraryEntrySyncDirtyQueueEntry.upsert(
            .init(
                identity: entry.syncIdentity,
                dirtyAt: referenceDate(year: 2026, month: 5, day: 9)
            ))
        try writeRawDirtyQueueEntries([olderEntry, newerEntry], in: store)

        let client = CloudLibrarySyncClient()
        let database = FakeCloudLibrarySyncDatabase(changes: [makeEmptyChangeBatch()])
        let coordinator = LibrarySyncCoordinator(
            store: store,
            client: client,
            database: database,
            namespaceProvider: { makeNamespace() }
        )

        await coordinator.sync(trigger: .manualRetry)

        #expect(database.savedRecords.count == 1)
        #expect(store.syncChangeRecorder.dirtyQueueStore.load().entries.isEmpty)
    }

    @Test @MainActor func duplicateLocalSnapshotsChooseRepositoryPreferredWinner() async throws {
        let store = makeSyncReadyStore()
        let olderEntry = AnimeEntry(
            name: "Older Duplicate",
            type: .movie,
            tmdbID: 714,
            dateSaved: referenceDate(year: 2026, month: 5, day: 1)
        )
        olderEntry.notes = "Older local"
        let newerEntry = AnimeEntry(
            name: "Newer Duplicate",
            type: .movie,
            tmdbID: 714,
            dateSaved: referenceDate(year: 2026, month: 5, day: 3)
        )
        newerEntry.notes = "Preferred local"
        try store.repository.newEntry(olderEntry)
        try store.repository.newEntry(newerEntry)
        try store.syncChangeRecorder.dirtyQueueStore.replaceEntries([
            .upsert(
                .init(
                    identity: newerEntry.syncIdentity,
                    dirtyAt: referenceDate(year: 2026, month: 5, day: 9)
                ))
        ])
        store.rebuildSyncChangeTracking()

        let client = CloudLibrarySyncClient()
        let database = FakeCloudLibrarySyncDatabase(changes: [makeEmptyChangeBatch()])
        let coordinator = LibrarySyncCoordinator(
            store: store,
            client: client,
            database: database,
            namespaceProvider: { makeNamespace() }
        )

        await coordinator.sync(trigger: .manualRetry)

        let savedSnapshot = try savedSnapshot(from: try #require(database.savedRecords.first), client: client)
        #expect(database.savedRecords.count == 1)
        #expect(savedSnapshot.identity == newerEntry.syncIdentity)
        #expect(savedSnapshot.notes == "Preferred local")
        #expect(store.syncChangeRecorder.dirtyQueueStore.load().entries.isEmpty)
    }

    @Test @MainActor func exportConfirmationKeepsNewerSameIdentityDirtyEntry() async throws {
        let store = makeSyncReadyStore()
        let entry = AnimeEntry(name: "Export Race", type: .movie, tmdbID: 711)
        let initialDirtyAt = referenceDate(year: 2026, month: 5, day: 8)
        let newerDirtyAt = referenceDate(year: 2026, month: 5, day: 9)
        entry.markCreatedForLibrary(at: referenceDate(year: 2026, month: 5, day: 1))
        entry.updateNotes("Before export", at: initialDirtyAt)
        try store.repository.newEntry(entry)
        try store.syncChangeRecorder.dirtyQueueStore.replaceEntries([
            .upsert(.init(identity: entry.syncIdentity, dirtyAt: initialDirtyAt))
        ])
        store.rebuildSyncChangeTracking()

        let client = CloudLibrarySyncClient()
        let database = FakeCloudLibrarySyncDatabase(changes: [makeEmptyChangeBatch()])
        database.suspendNextSave = true
        let coordinator = LibrarySyncCoordinator(
            store: store,
            client: client,
            database: database,
            namespaceProvider: { makeNamespace() }
        )

        let syncTask = Task {
            await coordinator.sync(trigger: .manualRetry)
        }
        while !database.isSaveSuspended {
            await Task.yield()
        }

        entry.updateNotes("After export started", at: newerDirtyAt)
        try store.repository.save()
        database.resumeSuspendedSave()

        _ = await syncTask.value

        let remainingEntry = try #require(
            store.syncChangeRecorder.dirtyQueueStore.load().entry(for: entry.syncIdentity))
        guard case .upsert(let pendingUpsert) = remainingEntry else {
            Issue.record("Expected the newer same-identity upsert to remain queued.")
            return
        }
        #expect(pendingUpsert.dirtyAt == newerDirtyAt)
        #expect(database.savedRecords.count == 1)
    }

    @Test @MainActor func failedHydrationLeavesTokenUncommitted() async throws {
        let store = makeSyncReadyStore()
        let client = CloudLibrarySyncClient()
        let namespace = makeNamespace()
        let identity = LibraryEntrySyncIdentity(entryType: .movie, tmdbID: 705)
        let snapshot = makeSnapshot(
            identity: identity,
            tmdbID: 705,
            entryType: .movie,
            notes: "Needs hydrate"
        )
        let database = FakeCloudLibrarySyncDatabase(changes: [
            .init(
                modifiedRecordsByID: [client.recordID(for: identity): try client.record(from: snapshot)],
                deletedRecordIDs: [],
                changeToken: makeToken(),
                moreComing: false
            )
        ])
        let tokenStore = CloudLibrarySyncChangeTokenStore(
            userDefaults: UserDefaults(suiteName: "LibrarySyncCoordinatorTests.\(UUID().uuidString)")!)
        let coordinator = LibrarySyncCoordinator(
            store: store,
            client: client,
            database: database,
            changeTokenStore: tokenStore,
            namespaceProvider: { namespace },
            hydrateMissingEntry: { _, _ in
                throw HydrationFailure.unavailable
            }
        )

        await coordinator.sync(trigger: .manualRetry)

        #expect(tokenStore.token(for: CloudLibrarySyncClient.recordZoneID, namespace: namespace) == nil)
        #expect(store.syncChangeRecorder.dirtyQueueStore.load().entries.isEmpty)
    }

    @Test @MainActor func firstEnableBootstrapWithoutRemoteOverlapSeedsAndExportsLocalLibrary() async throws {
        let store = makeStore(
            enabled: false,
            bootstrapState: .notStarted,
            hasTMDbAPIKey: true
        )
        let entry = AnimeEntry(
            name: "Local Only",
            type: .movie,
            tmdbID: 801,
            dateSaved: referenceDate(year: 2026, month: 5, day: 1)
        )
        try store.repository.newEntry(entry)
        try store.syncChangeRecorder.dirtyQueueStore.replaceEntries([])
        store.preferences.saveSortReversed(false)
        store.rebuildSyncChangeTracking()

        let client = CloudLibrarySyncClient()
        let exportDate = referenceDate(year: 2026, month: 6, day: 1)
        let database = FakeCloudLibrarySyncDatabase(changes: [makeEmptyChangeBatch()])
        store.configureLibrarySyncCoordinator(
            client: client,
            database: database,
            namespaceProvider: { makeNamespace() },
            dateProvider: { exportDate }
        )

        let succeeded = await store.enableLibraryCloudSync()

        #expect(succeeded)
        #expect(store.libraryCloudSyncStatus.bootstrapState == .completed)
        #expect(store.libraryCloudSyncStatus.lastSuccessfulSyncDate != nil)
        #expect(store.preferences.load().cloudSyncStatus.lastSuccessfulSyncDate != nil)
        #expect(database.savedRecords.count == 2)
        let savedEntryRecord = try #require(
            database.savedRecords.first { $0.recordID == client.recordID(for: entry.syncIdentity) }
        )
        let savedSnapshot = try savedSnapshot(from: savedEntryRecord, client: client)
        #expect(savedSnapshot.identity == entry.syncIdentity)
        let savedSettingsRecord = try #require(
            database.savedRecords.first { $0.recordID == client.librarySettingsRecordID }
        )
        let savedSettings = try client.settingsSnapshot(from: savedSettingsRecord)
        #expect(savedSettings.updatedAt == exportDate)
        #expect(savedSettings.payload[.librarySortReversed] == .bool(false))
        #expect(store.preferences.cloudSyncedDefaultsUpdatedAt() == exportDate)
        #expect(store.syncChangeRecorder.dirtyQueueStore.load().entries.isEmpty)
    }

    @Test @MainActor func firstEnableBootstrapClockedOverlapUsesNormalResolutionWithoutPrompting()
        async throws
    {
        let store = makeStore(
            enabled: false,
            bootstrapState: .notStarted,
            hasTMDbAPIKey: true
        )
        let entry = AnimeEntry(
            name: "Clocked Local",
            type: .series,
            tmdbID: 802,
            dateSaved: referenceDate(year: 2026, month: 5, day: 1)
        )
        entry.notes = "Local notes"
        entry.libraryUpdatedAt = referenceDate(year: 2026, month: 5, day: 10)
        entry.trackingUpdatedAt = referenceDate(year: 2026, month: 5, day: 10)
        try store.repository.newEntry(entry)
        try store.syncChangeRecorder.dirtyQueueStore.replaceEntries([])
        store.rebuildSyncChangeTracking()

        let client = CloudLibrarySyncClient()
        let remoteSnapshot = makeSnapshot(
            identity: entry.syncIdentity,
            tmdbID: entry.tmdbID,
            notes: "Remote notes",
            trackingUpdatedAt: referenceDate(year: 2026, month: 5, day: 2)
        )
        let database = FakeCloudLibrarySyncDatabase(changes: [
            try makeChangeBatch(client: client, snapshots: [remoteSnapshot])
        ])
        store.configureLibrarySyncCoordinator(
            client: client,
            database: database,
            namespaceProvider: { makeNamespace() }
        )

        let succeeded = await store.enableLibraryCloudSync()

        #expect(succeeded)
        #expect(store.libraryCloudSyncStatus.pendingConflictSummary == nil)
        let savedSnapshot = try savedSnapshot(from: try #require(database.savedRecords.first), client: client)
        #expect(savedSnapshot.notes == "Local notes")
        #expect(savedSnapshot.trackingUpdatedAt == referenceDate(year: 2026, month: 5, day: 10))
    }

    @Test @MainActor func firstEnableBootstrapClocklessDifferingOverlapPausesForConflictChoice()
        async throws
    {
        let fixture = try makeClocklessTrackingConflictFixture()

        let succeeded = await fixture.store.enableLibraryCloudSync()

        #expect(!succeeded)
        #expect(fixture.store.libraryCloudSyncStatus.bootstrapState == .needsConflictChoice)
        #expect(fixture.store.libraryCloudSyncStatus.pendingConflictSummary?.entryCount == 1)
        #expect(fixture.store.libraryCloudSyncStatus.pendingConflictSummary?.trackingDomainCount == 1)
        #expect(fixture.database.savedRecords.isEmpty)
        let local = try #require(fixture.store.repository.existingEntry(identity: fixture.identity))
        #expect(local.notes == "Local notes")
    }

    @Test @MainActor func resolvingFirstEnableConflictPreferCloudAppliesRemoteAmbiguousDomain()
        async throws
    {
        let fixture = try makeClocklessTrackingConflictFixture(repeatedRemoteFetches: 2)

        _ = await fixture.store.enableLibraryCloudSync()
        let succeeded = await fixture.store.resolveLibraryCloudSyncConflicts(preference: .preferCloud)

        #expect(succeeded)
        #expect(fixture.store.libraryCloudSyncStatus.bootstrapState == .completed)
        let local = try #require(fixture.store.repository.existingEntry(identity: fixture.identity))
        #expect(local.notes == "Remote notes")
        #expect(local.trackingUpdatedAt == nil)
        #expect(fixture.database.savedRecords.isEmpty)
        #expect(fixture.store.syncChangeRecorder.dirtyQueueStore.load().entries.isEmpty)
    }

    @Test @MainActor func resolvingFirstEnableConflictStillWorksAfterSkippedOrdinarySync()
        async throws
    {
        let fixture = try makeClocklessTrackingConflictFixture(repeatedRemoteFetches: 2)

        _ = await fixture.store.enableLibraryCloudSync()
        let skippedResult = await fixture.store.performLibrarySyncResult(trigger: .foreground)
        let succeeded = await fixture.store.resolveLibraryCloudSyncConflicts(preference: .preferCloud)

        #expect(skippedResult == .skipped(.bootstrapIncomplete))
        #expect(succeeded)
        #expect(fixture.store.libraryCloudSyncStatus.bootstrapState == .completed)
    }

    @Test @MainActor func queuedOrdinarySyncDuringConflictBootstrapWaitsForConflictResolution()
        async throws
    {
        let fixture = try makeClocklessTrackingConflictFixture(repeatedRemoteFetches: 3)
        fixture.database.suspendedFetchCount = 1

        let bootstrapTask = Task { await fixture.store.enableLibraryCloudSync() }
        while !fixture.database.isFetchSuspended {
            try await Task.sleep(nanoseconds: 1_000_000)
        }

        let queuedSyncTask = Task {
            await fixture.store.performLibrarySyncResult(trigger: .foreground)
        }
        try await Task.sleep(nanoseconds: 5_000_000)
        #expect(fixture.store.libraryCloudSyncStatus.bootstrapState == .running)

        fixture.database.resumeSuspendedFetch()
        let bootstrapSucceeded = await bootstrapTask.value
        #expect(!bootstrapSucceeded)
        #expect(fixture.store.libraryCloudSyncStatus.bootstrapState == .needsConflictChoice)

        let resolutionSucceeded = await fixture.store.resolveLibraryCloudSyncConflicts(
            preference: .preferCloud
        )
        let queuedSyncResult = await queuedSyncTask.value

        #expect(resolutionSucceeded)
        #expect(queuedSyncResult == .success)
        #expect(fixture.store.libraryCloudSyncStatus.bootstrapState == .completed)
        #expect(fixture.database.ensureZoneCallCount == 3)
    }

    @Test @MainActor func resolvingFirstEnableConflictPreferLocalStampsAndExportsAmbiguousDomain()
        async throws
    {
        let decisionDate = referenceDate(year: 2026, month: 6, day: 2)
        let fixture = try makeClocklessTrackingConflictFixture(
            repeatedRemoteFetches: 2,
            dateProvider: { decisionDate }
        )

        _ = await fixture.store.enableLibraryCloudSync()
        let succeeded = await fixture.store.resolveLibraryCloudSyncConflicts(preference: .preferLocal)

        #expect(succeeded)
        let local = try #require(fixture.store.repository.existingEntry(identity: fixture.identity))
        #expect(local.notes == "Local notes")
        #expect(local.trackingUpdatedAt == decisionDate)
        #expect(local.libraryUpdatedAt == nil)
        let savedSnapshot = try savedSnapshot(
            from: try #require(fixture.database.savedRecords.first),
            client: fixture.client
        )
        #expect(savedSnapshot.notes == "Local notes")
        #expect(savedSnapshot.trackingUpdatedAt == decisionDate)
    }

    @Test @MainActor func cancelingFirstEnableConflictLeavesSyncDisabledAndAvoidsMutation() async throws {
        let fixture = try makeClocklessTrackingConflictFixture()

        _ = await fixture.store.enableLibraryCloudSync()
        fixture.store.cancelLibraryCloudSyncEnablement()

        #expect(!fixture.store.libraryCloudSyncStatus.isEnabled)
        #expect(fixture.store.libraryCloudSyncStatus.bootstrapState == .notStarted)
        let local = try #require(fixture.store.repository.existingEntry(identity: fixture.identity))
        #expect(local.notes == "Local notes")
        #expect(fixture.database.savedRecords.isEmpty)
    }

    @Test @MainActor func disablingLibraryCloudSyncClearsTransientStateAndPersists() {
        let store = makeStore(
            enabled: true,
            bootstrapState: .completed,
            hasTMDbAPIKey: true
        )
        store.updateLibraryCloudSyncStatus { status in
            status.currentPhase = .syncing
            status.pendingConflictSummary = .init(
                entryCount: 2,
                libraryDomainCount: 1,
                trackingDomainCount: 1,
                episodeProgressDomainCount: 0
            )
            status.retryState = .init(
                failureRetryAttempt: 2,
                nextRetryAllowedAt: referenceDate(year: 2026, month: 6, day: 2),
                automaticRetriesExhausted: true
            )
            status.lastResult = .retryableFailure
            status.lastFailureReason = "Network unavailable."
            status.degradedReason = "Automatic retries are exhausted."
        }

        store.disableLibraryCloudSync()

        #expect(!store.libraryCloudSyncStatus.isEnabled)
        #expect(store.libraryCloudSyncStatus.bootstrapState == .notStarted)
        #expect(store.libraryCloudSyncStatus.pendingConflictSummary == nil)
        #expect(store.libraryCloudSyncStatus.currentPhase == nil)
        #expect(store.libraryCloudSyncStatus.retryState == .idle)
        #expect(store.libraryCloudSyncStatus.lastResult == .skipped)
        #expect(store.libraryCloudSyncStatus.lastFailureReason == nil)
        #expect(store.libraryCloudSyncStatus.degradedReason == nil)
        #expect(store.preferences.load().cloudSyncStatus == store.libraryCloudSyncStatus)
    }

    @Test @MainActor func disablingLibraryCloudSyncCancelsInFlightOrdinarySyncBeforeExport()
        async throws
    {
        let store = makeSyncReadyStore()
        let entry = AnimeEntry(
            name: "Cancelable Ordinary",
            type: .movie,
            tmdbID: 854,
            dateSaved: referenceDate(year: 2026, month: 5, day: 1)
        )
        try store.repository.newEntry(entry)
        try store.syncChangeRecorder.dirtyQueueStore.replaceEntries([
            .upsert(
                .init(
                    identity: entry.syncIdentity,
                    dirtyAt: referenceDate(year: 2026, month: 5, day: 2)
                ))
        ])

        let database = FakeCloudLibrarySyncDatabase(changes: [makeEmptyChangeBatch()])
        database.suspendNextFetch = true
        store.configureLibrarySyncCoordinator(
            client: CloudLibrarySyncClient(),
            database: database,
            namespaceProvider: { makeNamespace() }
        )

        let syncTask = Task {
            await store.performLibrarySyncResult(trigger: .foreground)
        }
        while !database.isFetchSuspended {
            try await Task.sleep(nanoseconds: 1_000_000)
        }

        store.disableLibraryCloudSync()
        database.resumeSuspendedFetch()
        let result = await syncTask.value

        #expect(result == .skipped(.disabled))
        #expect(!store.libraryCloudSyncStatus.isEnabled)
        #expect(store.libraryCloudSyncStatus.bootstrapState == .notStarted)
        #expect(store.libraryCloudSyncStatus.currentPhase == nil)
        #expect(store.libraryCloudSyncStatus.lastResult == .skipped)
        #expect(database.savedRecords.isEmpty)
    }

    @Test @MainActor func recordingLibraryCloudSyncFailureClearsActivePhase() {
        let store = makeSyncReadyStore()
        let lastSuccessDate = referenceDate(year: 2026, month: 6, day: 1)
        let retryDate = referenceDate(year: 2026, month: 6, day: 2)
        let failureDate = referenceDate(year: 2026, month: 6, day: 3)
        store.updateLibraryCloudSyncStatus { status in
            status.lastResult = .retryableFailure
            status.lastFailureReason = "Network unavailable."
            status.degradedReason = "Automatic retries are exhausted."
            status.lastSuccessfulSyncDate = lastSuccessDate
        }

        store.recordLibraryCloudSyncPhase(
            trigger: .manualRetry,
            phase: .exporting,
            at: retryDate
        )

        #expect(store.libraryCloudSyncStatus.currentPhase == .exporting)
        #expect(store.libraryCloudSyncStatus.lastResult == nil)
        #expect(store.libraryCloudSyncStatus.lastFailureReason == nil)
        #expect(store.libraryCloudSyncStatus.degradedReason == nil)

        store.recordLibraryCloudSyncFailure(
            trigger: .manualRetry,
            phase: .exporting,
            result: .retryableFailure,
            reason: "Network unavailable.",
            at: failureDate
        )

        #expect(store.libraryCloudSyncStatus.currentPhase == nil)
        #expect(store.libraryCloudSyncStatus.lastResult == .retryableFailure)
        #expect(store.libraryCloudSyncStatus.lastAttemptDate == failureDate)
        #expect(store.libraryCloudSyncStatus.lastSuccessfulSyncDate == lastSuccessDate)
        #expect(store.libraryCloudSyncStatus.lastFailureReason == "Network unavailable.")
        #expect(store.preferences.load().cloudSyncStatus == store.libraryCloudSyncStatus)
    }

    @Test @MainActor func cancelingInFlightFirstEnableBootstrapStopsBeforeExport() async throws {
        let store = makeStore(
            enabled: false,
            bootstrapState: .notStarted,
            hasTMDbAPIKey: true
        )
        let entry = AnimeEntry(
            name: "Cancelable Local",
            type: .movie,
            tmdbID: 804,
            dateSaved: referenceDate(year: 2026, month: 5, day: 1)
        )
        try store.repository.newEntry(entry)
        try store.syncChangeRecorder.dirtyQueueStore.replaceEntries([])
        store.rebuildSyncChangeTracking()

        let database = FakeCloudLibrarySyncDatabase(changes: [makeEmptyChangeBatch()])
        database.suspendNextFetch = true
        store.configureLibrarySyncCoordinator(
            client: CloudLibrarySyncClient(),
            database: database,
            namespaceProvider: { makeNamespace() }
        )

        let bootstrapTask = Task { await store.enableLibraryCloudSync() }
        while !database.isFetchSuspended {
            try await Task.sleep(nanoseconds: 1_000_000)
        }

        store.cancelLibraryCloudSyncEnablement()
        database.resumeSuspendedFetch()
        let succeeded = await bootstrapTask.value

        #expect(!succeeded)
        #expect(!store.libraryCloudSyncStatus.isEnabled)
        #expect(store.libraryCloudSyncStatus.bootstrapState == .notStarted)
        #expect(database.savedRecords.isEmpty)
    }
}

fileprivate enum HydrationFailure: Error {
    case unavailable
}

@MainActor
fileprivate func makeSyncReadyStore() -> LibraryStore {
    makeStore(
        enabled: true,
        bootstrapState: .completed,
        hasTMDbAPIKey: true
    )
}

@MainActor
fileprivate func makeStore(
    enabled: Bool,
    bootstrapState: LibraryCloudSyncBootstrapState,
    hasTMDbAPIKey: Bool
) -> LibraryStore {
    let suiteName = "LibrarySyncCoordinatorTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    let preferences = LibraryPreferences(defaults: defaults)
    var status = LibraryCloudSyncStatus.defaultValue
    status.isEnabled = enabled
    status.bootstrapState = bootstrapState
    preferences.saveCloudSyncStatus(status)
    return LibraryStore(
        dataProvider: DataProvider(inMemory: true),
        preferences: preferences,
        hasTMDbAPIKey: { hasTMDbAPIKey }
    )
}

fileprivate struct ClocklessTrackingConflictFixture {
    let store: LibraryStore
    let client: CloudLibrarySyncClient
    let database: FakeCloudLibrarySyncDatabase
    let identity: LibraryEntrySyncIdentity
}

@MainActor
fileprivate func makeClocklessTrackingConflictFixture(
    repeatedRemoteFetches: Int = 1,
    dateProvider: @escaping @MainActor @Sendable () -> Date = {
        referenceDate(year: 2026, month: 6, day: 1)
    }
) throws -> ClocklessTrackingConflictFixture {
    let store = makeStore(
        enabled: false,
        bootstrapState: .notStarted,
        hasTMDbAPIKey: true
    )
    let entry = AnimeEntry(
        name: "Clockless Local",
        type: .series,
        tmdbID: 803,
        dateSaved: referenceDate(year: 2026, month: 5, day: 1)
    )
    entry.notes = "Local notes"
    entry.libraryUpdatedAt = nil
    entry.trackingUpdatedAt = nil
    try store.repository.newEntry(entry)
    try store.syncChangeRecorder.dirtyQueueStore.replaceEntries([])
    store.rebuildSyncChangeTracking()

    let client = CloudLibrarySyncClient()
    var remoteSnapshot = makeSnapshot(
        identity: entry.syncIdentity,
        tmdbID: entry.tmdbID,
        notes: "Remote notes",
        trackingUpdatedAt: nil
    )
    remoteSnapshot.libraryUpdatedAt = nil
    let batch = try makeChangeBatch(client: client, snapshots: [remoteSnapshot])
    let database = FakeCloudLibrarySyncDatabase(
        changes: Array(repeating: batch, count: repeatedRemoteFetches)
    )
    store.configureLibrarySyncCoordinator(
        client: client,
        database: database,
        namespaceProvider: { makeNamespace() },
        dateProvider: dateProvider
    )
    return .init(
        store: store,
        client: client,
        database: database,
        identity: entry.syncIdentity
    )
}

fileprivate final class FakeCloudLibrarySyncDatabase: CloudLibrarySyncDatabase, @unchecked Sendable {
    private var changes: [CloudLibrarySyncZoneChangeBatch]
    private let successfulSaveRecordIDs: [CKRecord.ID]?
    private let saveErrorsByCallIndex: [Int: any Error]
    private var fetchContinuation: CheckedContinuation<Void, Never>?
    private var saveContinuation: CheckedContinuation<Void, Never>?
    private var saveCallCount = 0
    var savedRecords: [CKRecord] = []
    var saveBatchSizes: [Int] = []
    var ensureZoneCallCount = 0
    var suspendNextFetch = false
    var suspendNextSave = false
    var suspendedFetchCount = 0
    var isFetchSuspended = false
    var isSaveSuspended = false

    init(
        changes: [CloudLibrarySyncZoneChangeBatch],
        successfulSaveRecordIDs: [CKRecord.ID]? = nil,
        saveErrorsByCallIndex: [Int: any Error] = [:]
    ) {
        self.changes = changes
        self.successfulSaveRecordIDs = successfulSaveRecordIDs
        self.saveErrorsByCallIndex = saveErrorsByCallIndex
    }

    func ensureZoneAndSubscription(
        zoneID: CKRecordZone.ID,
        subscriptionID: CKSubscription.ID
    ) async throws {
        ensureZoneCallCount += 1
    }

    func fetchRecordZoneChanges(
        in zoneID: CKRecordZone.ID,
        since changeToken: CKServerChangeToken?
    ) async throws -> CloudLibrarySyncZoneChangeBatch {
        if suspendNextFetch || suspendedFetchCount > 0 {
            if suspendNextFetch {
                suspendNextFetch = false
            }
            if suspendedFetchCount > 0 {
                suspendedFetchCount -= 1
            }
            isFetchSuspended = true
            await withCheckedContinuation { continuation in
                fetchContinuation = continuation
            }
            isFetchSuspended = false
        }
        return changes.removeFirst()
    }

    func save(records: [CKRecord]) async throws -> [CKRecord.ID] {
        saveCallCount += 1
        saveBatchSizes.append(records.count)
        if let error = saveErrorsByCallIndex[saveCallCount] {
            throw error
        }
        savedRecords.append(contentsOf: records)
        if suspendNextSave {
            suspendNextSave = false
            isSaveSuspended = true
            await withCheckedContinuation { continuation in
                saveContinuation = continuation
            }
            isSaveSuspended = false
        }
        return successfulSaveRecordIDs ?? records.map(\.recordID)
    }

    func resumeSuspendedFetch() {
        fetchContinuation?.resume()
        fetchContinuation = nil
    }

    func resumeSuspendedSave() {
        saveContinuation?.resume()
        saveContinuation = nil
    }
}

fileprivate func makeNamespace() -> CloudLibrarySyncChangeTokenStore.Namespace {
    .init(
        containerIdentifier: CloudLibrarySyncClient.defaultContainerIdentifier,
        accountIdentifier: "test-account"
    )
}

fileprivate func makeToken() -> CKServerChangeToken {
    class_createInstance(CKServerChangeToken.self, 0) as! CKServerChangeToken
}

fileprivate func makeEmptyChangeBatch() -> CloudLibrarySyncZoneChangeBatch {
    .init(
        modifiedRecordsByID: [:],
        deletedRecordIDs: [],
        changeToken: makeToken(),
        moreComing: false
    )
}

fileprivate struct RawDirtyQueue: Encodable {
    var schemaVersion: Int
    var entries: [LibraryEntrySyncDirtyQueueEntry]
}

@MainActor
fileprivate func writeRawDirtyQueueEntries(
    _ entries: [LibraryEntrySyncDirtyQueueEntry],
    in store: LibraryStore
) throws {
    let queue = RawDirtyQueue(
        schemaVersion: LibraryEntrySyncDirtyQueue.currentSchemaVersion,
        entries: entries
    )
    let data = try JSONEncoder().encode(queue)
    try data.write(to: store.syncChangeRecorder.dirtyQueueStore.url)
}

fileprivate func makeChangeBatch(
    client: CloudLibrarySyncClient,
    snapshots: [LibraryEntrySyncSnapshot]
) throws -> CloudLibrarySyncZoneChangeBatch {
    .init(
        modifiedRecordsByID: Dictionary(
            uniqueKeysWithValues: try snapshots.map { snapshot in
                (client.recordID(for: snapshot.identity), try client.record(from: snapshot))
            }
        ),
        deletedRecordIDs: [],
        changeToken: makeToken(),
        moreComing: false
    )
}

fileprivate func savedSnapshot(
    from record: CKRecord,
    client: CloudLibrarySyncClient
) throws -> LibraryEntrySyncSnapshot {
    guard case .snapshot(let snapshot) = try client.remoteChange(from: record) else {
        throw SavedRecordError.expectedSnapshot
    }
    return snapshot
}

fileprivate func makeSnapshot(
    identity: LibraryEntrySyncIdentity,
    tmdbID: Int,
    entryType: AnimeType = .series,
    notes: String = "",
    trackingUpdatedAt: Date? = referenceDate(year: 2026, month: 5, day: 1)
) -> LibraryEntrySyncSnapshot {
    LibraryEntrySyncSnapshot(
        identity: identity,
        tmdbID: tmdbID,
        parentSeriesID: entryType.parentSeriesID,
        seasonNumber: entryType.seasonNumber,
        entryType: entryType,
        onDisplay: true,
        dateSaved: referenceDate(year: 2026, month: 5, day: 1),
        watchStatus: .planToWatch,
        dateStarted: nil,
        dateFinished: nil,
        isDateTrackingEnabled: true,
        score: nil,
        favorite: false,
        notes: notes,
        usingCustomPoster: false,
        customPosterURL: nil,
        episodeProgresses: [],
        libraryUpdatedAt: referenceDate(year: 2026, month: 5, day: 1),
        trackingUpdatedAt: trackingUpdatedAt
    )
}

fileprivate enum SavedRecordError: Error {
    case expectedSnapshot
}
