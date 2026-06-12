//
//  LibrarySyncCoordinatorTests+Scheduler.swift
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
}
