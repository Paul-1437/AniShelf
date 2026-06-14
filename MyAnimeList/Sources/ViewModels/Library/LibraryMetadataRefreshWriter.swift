//
//  LibraryMetadataRefreshWriter.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/6/11.
//

import DataProvider
import Foundation
import SwiftData

struct LibraryMetadataRefreshUpdate: Sendable {
    var entryID: PersistentIdentifier
    var info: EntryMetadata
    var detail: AnimeEntryDetailDTO
    /// Keeps a user's selected poster intact while replacing TMDb-owned metadata.
    var preservingCustomPoster: Bool
    /// The selected poster path to continue prefetching when `preservingCustomPoster` is true.
    var customPosterPath: String? = nil
}

struct LibraryMetadataRefreshParentUpdate: Sendable {
    var childEntryID: PersistentIdentifier
    var parentSeriesID: Int
    var parentInfo: EntryMetadata?
    var parentDetail: AnimeEntryDetailDTO?
}

struct LibraryMetadataRefreshWriter: Sendable {
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func apply(
        updates: [LibraryMetadataRefreshUpdate],
        parentUpdates: [LibraryMetadataRefreshParentUpdate]
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let modelContext = ModelContext(modelContainer)
                do {
                    try apply(
                        updates: updates,
                        parentUpdates: parentUpdates,
                        in: modelContext
                    )
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func apply(
        updates: [LibraryMetadataRefreshUpdate],
        parentUpdates: [LibraryMetadataRefreshParentUpdate],
        in modelContext: ModelContext
    ) throws {
        assert(!Thread.isMainThread, "Metadata refresh should not run on the main thread.")
        do {
            var entriesByID: [PersistentIdentifier: AnimeEntry] = [:]

            for update in updates {
                guard let entry = try entry(for: update.entryID, in: modelContext) else { continue }
                entriesByID[update.entryID] = entry
                entry.replaceMetadata(
                    from: update.info,
                    preservingCustomPoster: update.preservingCustomPoster
                )
                entry.replaceDetail(from: update.detail)
                if update.info.type.parentSeriesID == nil {
                    entry.parentSeriesEntry = nil
                }
            }

            for parentUpdate in parentUpdates {
                let fetchedChildEntry: AnimeEntry?
                if let cachedEntry = entriesByID[parentUpdate.childEntryID] {
                    fetchedChildEntry = cachedEntry
                } else {
                    fetchedChildEntry = try entry(for: parentUpdate.childEntryID, in: modelContext)
                }

                guard let childEntry = fetchedChildEntry else { continue }

                if childEntry.parentSeriesEntry?.tmdbID == parentUpdate.parentSeriesID {
                    continue
                }

                let parentEntry: AnimeEntry?
                if let existingParent = try existingEntry(
                    tmdbID: parentUpdate.parentSeriesID,
                    in: modelContext
                ) {
                    parentEntry = existingParent
                } else if let parentInfo = parentUpdate.parentInfo,
                    let parentDetail = parentUpdate.parentDetail
                {
                    let insertedParent = AnimeEntry(fromInfo: parentInfo)
                    insertedParent.setDisplayState(false)
                    insertedParent.replaceDetail(from: parentDetail)
                    modelContext.insert(insertedParent)
                    parentEntry = insertedParent
                } else {
                    parentEntry = nil
                }

                if let parentEntry {
                    childEntry.parentSeriesEntry = parentEntry
                }
            }

            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func entry(
        for id: PersistentIdentifier,
        in modelContext: ModelContext
    ) throws -> AnimeEntry? {
        var descriptor = FetchDescriptor(
            predicate: #Predicate<AnimeEntry> { entry in
                entry.persistentModelID == id
            }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func existingEntry(
        tmdbID: Int,
        in modelContext: ModelContext
    ) throws -> AnimeEntry? {
        var descriptor = FetchDescriptor(
            predicate: #Predicate<AnimeEntry> { entry in
                entry.tmdbID == tmdbID
            }
        )
        descriptor.fetchLimit = 20
        return try modelContext.fetch(descriptor)
            .sorted(by: compareExistingEntries)
            .first
    }

    private func compareExistingEntries(_ lhs: AnimeEntry, _ rhs: AnimeEntry) -> Bool {
        if lhs.onDisplay != rhs.onDisplay {
            return lhs.onDisplay && !rhs.onDisplay
        }

        if lhs.childSeasonEntries.count != rhs.childSeasonEntries.count {
            return lhs.childSeasonEntries.count > rhs.childSeasonEntries.count
        }

        if (lhs.detail != nil) != (rhs.detail != nil) {
            return lhs.detail != nil
        }

        if lhs.dateSaved != rhs.dateSaved {
            return lhs.dateSaved > rhs.dateSaved
        }

        return lhs.name < rhs.name
    }
}
