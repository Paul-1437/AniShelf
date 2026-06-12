//
//  LibrarySyncCoordinatorTests+Settings.swift
//  MyAnimeListTests
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/6/12.
//

import CloudKit
import Foundation
import Testing

@testable import DataProvider
@testable import LibrarySync
@testable import MyAnimeList

extension LibrarySyncCoordinatorTests {
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
}
