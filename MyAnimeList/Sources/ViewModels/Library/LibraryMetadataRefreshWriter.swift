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
    var preservingCustomPoster: Bool
}

struct LibraryMetadataRefreshParentUpdate: Sendable {
    var childEntryID: PersistentIdentifier
    var parentSeriesID: Int
    var parentInfo: EntryMetadata?
    var parentDetail: AnimeEntryDetailDTO?
}

@ModelActor
actor LibraryMetadataRefreshWriter {
    func apply(
        updates: [LibraryMetadataRefreshUpdate],
        parentUpdates: [LibraryMetadataRefreshParentUpdate]
    ) throws {
        do {
            var entriesByID: [PersistentIdentifier: AnimeEntry] = [:]

            for update in updates {
                guard let entry = try entry(for: update.entryID) else { continue }
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
                    fetchedChildEntry = try entry(for: parentUpdate.childEntryID)
                }

                guard let childEntry = fetchedChildEntry else { continue }

                if childEntry.parentSeriesEntry?.tmdbID == parentUpdate.parentSeriesID {
                    continue
                }

                let parentEntry: AnimeEntry?
                if let existingParent = try existingEntry(tmdbID: parentUpdate.parentSeriesID) {
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

    private func entry(for id: PersistentIdentifier) throws -> AnimeEntry? {
        var descriptor = FetchDescriptor(
            predicate: #Predicate<AnimeEntry> { entry in
                entry.persistentModelID == id
            }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func existingEntry(tmdbID: Int) throws -> AnimeEntry? {
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
