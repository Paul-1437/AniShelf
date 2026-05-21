import DataProvider
import Foundation
import SwiftUI

struct LibraryEntryDisplayItem: Identifiable {
    let entry: AnimeEntry
    let snapshot: LibraryEntrySnapshot

    var id: Int { snapshot.id }

    init(entry: AnimeEntry) {
        self.entry = entry
        self.snapshot = LibraryEntrySnapshot(entry: entry)
    }
}

struct LibraryEntrySnapshot: Identifiable, Equatable {
    let id: Int
    let posterURL: URL?
    let title: String
    let overview: String?
    let primaryMetadata: [String]
    let secondaryMetadata: String?
    let watchStatus: AnimeEntry.WatchStatus
    let score: Int?
    let isFavorite: Bool
    let episodeProgressLabel: String?
    let episodeProgressFraction: Double?
    let dateStarted: Date?
    let dateFinished: Date?

    init(entry: AnimeEntry) {
        let progressSummary = Self.latestEpisodeProgressSummary(for: entry)

        id = entry.tmdbID
        posterURL = entry.posterURL
        title = entry.displayName
        overview = Self.cleanOverview(entry.displayOverview)
        primaryMetadata = Self.primaryMetadata(for: entry)
        secondaryMetadata = Self.secondaryMetadata(for: entry)
        watchStatus = entry.watchStatus
        score = entry.score
        isFavorite = entry.favorite
        episodeProgressLabel = Self.episodeProgressLabel(for: entry, summary: progressSummary)
        episodeProgressFraction = Self.episodeProgressFraction(for: progressSummary)
        dateStarted = entry.dateStarted
        dateFinished = entry.dateFinished
    }

    private static func cleanOverview(_ overview: String?) -> String? {
        guard
            let overview = overview?
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !overview.isEmpty
        else {
            return nil
        }

        return overview
    }

    private static func primaryMetadata(for entry: AnimeEntry) -> [String] {
        [
            dateText(for: entry.onAirDate),
            typeSummaryText(for: entry)
        ].compactMap(\.self)
    }

    private static func secondaryMetadata(for entry: AnimeEntry) -> String? {
        guard case .season(let seasonNumber, _) = entry.type else { return nil }
        return String(localized: seasonSummaryResource(seasonNumber: seasonNumber))
    }

    private static func dateText(for date: Date?) -> String? {
        date?.formatted(.dateTime.year().month().day())
    }

    private static func typeSummaryText(for entry: AnimeEntry) -> String? {
        switch entry.type {
        case .movie:
            return String(localized: movieSummaryResource(runtime: entry.detail?.runtimeMinutes))
        case .series:
            return entry.detail?.episodeCount.map { String(localized: episodeCountResource($0)) }
                ?? String(localized: "Series")
        case .season(let seasonNumber, _):
            return entry.detail?.episodeCount.map { String(localized: episodeCountResource($0)) }
                ?? String(localized: seasonSummaryResource(seasonNumber: seasonNumber))
        }
    }

    private static func movieSummaryResource(runtime: Int?) -> LocalizedStringResource {
        if let runtime {
            return "\(runtime) min"
        }
        return "Movie"
    }

    private static func seasonSummaryResource(seasonNumber: Int) -> LocalizedStringResource {
        if seasonNumber == 0 {
            return "Specials"
        }
        return "Season \(seasonNumber)"
    }

    private static func episodeCountResource(_ count: Int) -> LocalizedStringResource {
        "\(count) episodes"
    }

    private static func latestEpisodeProgressSummary(
        for entry: AnimeEntry
    ) -> AnimeEntryEpisodeProgressSummary? {
        guard entry.watchStatus == .watching else { return nil }

        switch entry.type {
        case .movie:
            return nil
        case .series, .season:
            return entry.latestEpisodeProgressSummary
        }
    }

    private static func episodeProgressLabel(
        for entry: AnimeEntry,
        summary: AnimeEntryEpisodeProgressSummary?
    ) -> String? {
        guard let summary else { return nil }

        switch entry.type {
        case .movie:
            return nil
        case .series:
            if summary.seasonNumber == 0 {
                return "SP\(summary.watchedThroughEpisode)"
            }
            return "S\(summary.seasonNumber)E\(summary.watchedThroughEpisode)"
        case .season:
            return "EP\(summary.watchedThroughEpisode)"
        }
    }

    private static func episodeProgressFraction(
        for summary: AnimeEntryEpisodeProgressSummary?
    ) -> Double? {
        guard
            let summary,
            let episodeCount = summary.episodeCount,
            episodeCount > 0
        else {
            return nil
        }

        let rawFraction = Double(summary.watchedThroughEpisode) / Double(episodeCount)
        return min(max(rawFraction, 0), 1)
    }
}
