//
//  UserEntryInfo.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/7/15.
//

import Foundation

/// Stores user-specific information about an entry.
public struct UserEntryInfo: Equatable, Codable {
    public struct EpisodeProgressSnapshot: Equatable, Codable {
        public var seasonNumber: Int
        public var watchedThroughEpisode: Int
        public var updatedAt: Date

        public init(
            seasonNumber: Int,
            watchedThroughEpisode: Int,
            updatedAt: Date = .now
        ) {
            self.seasonNumber = seasonNumber
            self.watchedThroughEpisode = max(0, watchedThroughEpisode)
            self.updatedAt = updatedAt
        }
    }

    /// User's watch status for this entry.
    public var watchStatus: AnimeEntry.WatchStatus

    /// Date started watching.
    public var dateStarted: Date?

    /// Date marked finished.
    public var dateFinished: Date?

    /// Whether status changes should automatically manage tracking dates for this entry.
    public var isDateTrackingEnabled: Bool

    /// User's optional score for this entry.
    public var score: Int?

    /// Whether the entry is marked as favorite.
    public var favorite: Bool

    /// Notes for this entry.
    public var notes: String

    /// Whether the entry is using a custom poster image.
    public var usingCustomPoster: Bool

    /// Episode progress grouped by season/special partition.
    public var episodeProgresses: [EpisodeProgressSnapshot]

    private init(
        watchStatus: AnimeEntry.WatchStatus,
        dateStarted: Date? = nil,
        dateFinished: Date? = nil,
        isDateTrackingEnabled: Bool = true,
        score: Int? = nil,
        favorite: Bool,
        notes: String,
        usingCustomPoster: Bool,
        episodeProgresses: [EpisodeProgressSnapshot] = []
    ) {
        self.watchStatus = watchStatus
        self.dateStarted = dateStarted
        self.dateFinished = dateFinished
        self.isDateTrackingEnabled = isDateTrackingEnabled
        self.score = normalizedEntryScore(score)
        self.favorite = favorite
        self.notes = notes
        self.usingCustomPoster = usingCustomPoster
        self.episodeProgresses = Self.normalizedEpisodeProgresses(episodeProgresses)
    }

    public init(from entry: AnimeEntry) {
        self.watchStatus = entry.watchStatus
        self.dateStarted = entry.dateStarted
        self.dateFinished = entry.dateFinished
        self.isDateTrackingEnabled = entry.isDateTrackingEnabled
        self.score = normalizedEntryScore(entry.score)
        self.favorite = entry.favorite
        self.notes = entry.notes
        self.usingCustomPoster = entry.usingCustomPoster
        self.episodeProgresses = Self.normalizedEpisodeProgresses(
            entry.orderedEpisodeProgresses.map {
                EpisodeProgressSnapshot(
                    seasonNumber: $0.seasonNumber,
                    watchedThroughEpisode: $0.watchedThroughEpisode,
                    updatedAt: $0.updatedAt
                )
            }
        )
    }

    /// Whether this user info is "empty", i.e. has no meaningful user data.
    public var isEmpty: Bool {
        watchStatus == .planToWatch && dateStarted == nil && dateFinished == nil
            && isDateTrackingEnabled
            && score == nil && favorite == false && notes.isEmpty && usingCustomPoster == false
            && episodeProgresses.isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case watchStatus
        case dateStarted
        case dateFinished
        case isDateTrackingEnabled
        case score
        case favorite
        case notes
        case usingCustomPoster
        case episodeProgresses
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            watchStatus: try container.decode(AnimeEntry.WatchStatus.self, forKey: .watchStatus),
            dateStarted: try container.decodeIfPresent(Date.self, forKey: .dateStarted),
            dateFinished: try container.decodeIfPresent(Date.self, forKey: .dateFinished),
            isDateTrackingEnabled: try container.decodeIfPresent(Bool.self, forKey: .isDateTrackingEnabled) ?? true,
            score: normalizedEntryScore(try container.decodeIfPresent(Int.self, forKey: .score)),
            favorite: try container.decode(Bool.self, forKey: .favorite),
            notes: try container.decode(String.self, forKey: .notes),
            usingCustomPoster: try container.decode(Bool.self, forKey: .usingCustomPoster),
            episodeProgresses: try container.decodeIfPresent(
                [EpisodeProgressSnapshot].self,
                forKey: .episodeProgresses
            ) ?? []
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(watchStatus, forKey: .watchStatus)
        try container.encodeIfPresent(dateStarted, forKey: .dateStarted)
        try container.encodeIfPresent(dateFinished, forKey: .dateFinished)
        try container.encode(isDateTrackingEnabled, forKey: .isDateTrackingEnabled)
        try container.encodeIfPresent(normalizedEntryScore(score), forKey: .score)
        try container.encode(favorite, forKey: .favorite)
        try container.encode(notes, forKey: .notes)
        try container.encode(usingCustomPoster, forKey: .usingCustomPoster)
        try container.encode(episodeProgresses, forKey: .episodeProgresses)
    }

    fileprivate static func normalizedEpisodeProgresses(
        _ episodeProgresses: [EpisodeProgressSnapshot]
    ) -> [EpisodeProgressSnapshot] {
        Dictionary(
            grouping: episodeProgresses.filter {
                $0.seasonNumber > 0 && $0.watchedThroughEpisode > 0
            },
            by: \.seasonNumber
        )
        .values
        .compactMap { progresses in
            progresses.max { lhs, rhs in
                if lhs.updatedAt == rhs.updatedAt {
                    return lhs.watchedThroughEpisode < rhs.watchedThroughEpisode
                }
                return lhs.updatedAt < rhs.updatedAt
            }
        }
        .sorted { lhs, rhs in
            let lhsKey = lhs.seasonNumber == 0 ? Int.max : lhs.seasonNumber
            let rhsKey = rhs.seasonNumber == 0 ? Int.max : rhs.seasonNumber
            if lhsKey == rhsKey {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhsKey < rhsKey
        }
    }

    public func isSemanticallyEquivalent(to other: UserEntryInfo) -> Bool {
        watchStatus == other.watchStatus
            && dateStarted == other.dateStarted
            && dateFinished == other.dateFinished
            && isDateTrackingEnabled == other.isDateTrackingEnabled
            && score == other.score
            && favorite == other.favorite
            && notes == other.notes
            && usingCustomPoster == other.usingCustomPoster
            && semanticEpisodeProgresses == other.semanticEpisodeProgresses
    }

    private var semanticEpisodeProgresses: [EpisodeProgressValue] {
        episodeProgresses.map(EpisodeProgressValue.init)
    }

    private struct EpisodeProgressValue: Equatable {
        let seasonNumber: Int
        let watchedThroughEpisode: Int

        init(_ snapshot: EpisodeProgressSnapshot) {
            seasonNumber = snapshot.seasonNumber
            watchedThroughEpisode = snapshot.watchedThroughEpisode
        }
    }
}

extension AnimeEntry.WatchStatus: CustomStringConvertible {
    public var description: String {
        switch self {
        case .planToWatch: return "Planned"
        case .watching: return "Watching"
        case .watched: return "Watched"
        case .dropped: return "Dropped"
        }
    }
}

extension UserEntryInfo: CustomStringConvertible {
    public var description: String {
        """
        Status: \(watchStatus)
        Started: \(dateStarted?.description ?? "N/A")
        Finished: \(dateFinished?.description ?? "N/A")
        Track Dates: \(isDateTrackingEnabled)
        Score: \(score.map(String.init) ?? "No score")
        Favorite: \(favorite)
        Notes: \(notes)
        Custom Poster: \(usingCustomPoster)
        Episode Progress: \(Self.episodeProgressDescription(episodeProgresses))
        """
    }

    private static func episodeProgressDescription(
        _ episodeProgresses: [EpisodeProgressSnapshot]
    ) -> String {
        guard !episodeProgresses.isEmpty else { return "None" }
        return
            episodeProgresses
            .map { progress in
                let prefix = progress.seasonNumber == 0 ? "SP" : "S\(progress.seasonNumber)"
                return "\(prefix): \(progress.watchedThroughEpisode)"
            }
            .joined(separator: ", ")
    }
}

extension AnimeEntry {
    public static let validScoreRange = 1...5

    public func setDateTrackingEnabled(_ isEnabled: Bool, now: Date = .now) {
        isDateTrackingEnabled = isEnabled
        guard isEnabled else { return }
        normalizeTrackingDates(now: now)
    }

    public func setWatchStatus(_ status: WatchStatus, now: Date = .now) {
        watchStatus = status
        guard isDateTrackingEnabled else { return }
        normalizeTrackingDates(now: now)
    }

    public func setScore(_ score: Int?) {
        self.score = normalizedEntryScore(score)
    }

    public func normalizeTrackingDates(now: Date = .now) {
        guard watchStatus != .dropped else { return }
        let normalizedDates = watchStatus.normalizedDates(
            dateStarted: dateStarted,
            dateFinished: dateFinished,
            now: now
        )
        dateStarted = normalizedDates.dateStarted
        dateFinished = normalizedDates.dateFinished
    }

    public func updateUserInfo(from userInfo: UserEntryInfo) {
        watchStatus = userInfo.watchStatus
        dateStarted = userInfo.dateStarted
        dateFinished = userInfo.dateFinished
        isDateTrackingEnabled = userInfo.isDateTrackingEnabled
        score = normalizedEntryScore(userInfo.score)
        favorite = userInfo.favorite
        notes = userInfo.notes
        usingCustomPoster = userInfo.usingCustomPoster
        episodeProgresses.forEach { modelContext?.delete($0) }
        episodeProgresses.removeAll()
        for progress in filteredEpisodeProgresses(from: userInfo) {
            setEpisodeProgress(
                seasonNumber: progress.seasonNumber,
                watchedThroughEpisode: progress.watchedThroughEpisode,
                now: progress.updatedAt
            )
        }
        guard isDateTrackingEnabled else { return }
        normalizeTrackingDates()
    }

    private func filteredEpisodeProgresses(from userInfo: UserEntryInfo) -> [UserEntryInfo.EpisodeProgressSnapshot] {
        switch type {
        case .movie:
            return []
        case .series:
            return userInfo.episodeProgresses.filter { $0.seasonNumber > 0 }
        case .season(let seasonNumber, _):
            guard seasonNumber > 0 else { return [] }
            return userInfo.episodeProgresses.filter { $0.seasonNumber == seasonNumber }
        }
    }
}

extension AnimeEntry.WatchStatus {
    public func normalizedDates(
        dateStarted: Date?,
        dateFinished: Date?,
        now: Date = .now
    ) -> (dateStarted: Date?, dateFinished: Date?) {
        switch self {
        case .planToWatch:
            return (nil, nil)
        case .watching:
            return (dateStarted ?? now, nil)
        case .watched:
            let finished = dateFinished ?? dateStarted ?? now
            let started = min(dateStarted ?? finished, finished)
            return (started, finished)
        case .dropped:
            switch (dateStarted, dateFinished) {
            case (nil, nil):
                return (nil, nil)
            case (.some(let started), nil):
                return (started, nil)
            case (nil, .some(let finished)):
                return (finished, finished)
            case (.some(let started), .some(let finished)):
                return (started, max(started, finished))
            }
        }
    }
}

fileprivate func normalizedEntryScore(_ score: Int?) -> Int? {
    guard let score else { return nil }
    return AnimeEntry.validScoreRange.contains(score) ? score : nil
}
