//
//  AnimeEntryDetailV2_7_1.swift
//  DataProvider
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/9.
//

import Foundation
import SwiftData

extension SchemaV2_7_1 {
    @Model
    public final class AnimeEntryDetail {
        public var language: String
        public var title: String
        public var subtitle: String?
        public var overview: String?
        public var status: String?
        public var airDate: Date?
        public var primaryLinkURL: URL?
        public var heroImageURL: URL?
        public var logoImageURL: URL?
        public var genreIDs: [Int]
        public var voteAverage: Double?
        public var runtimeMinutes: Int?
        public var episodeCount: Int?
        public var seasonCount: Int?
        public var entry: AnimeEntry? = nil

        @Relationship(deleteRule: .cascade, inverse: \SchemaV2_7_1.AnimeEntryCharacter.detail)
        public var characters: [SchemaV2_7_1.AnimeEntryCharacter] = []

        @Relationship(deleteRule: .cascade, inverse: \SchemaV2_7_1.AnimeEntryStaff.detail)
        public var staff: [SchemaV2_7_1.AnimeEntryStaff] = []

        @Relationship(deleteRule: .cascade, inverse: \SchemaV2_7_1.AnimeEntrySeasonSummary.detail)
        public var seasons: [SchemaV2_7_1.AnimeEntrySeasonSummary] = []

        @Relationship(deleteRule: .cascade, inverse: \SchemaV2_7_1.AnimeEntryEpisodeSummary.detail)
        public var episodes: [SchemaV2_7_1.AnimeEntryEpisodeSummary] = []

        public init(
            language: String,
            title: String,
            subtitle: String? = nil,
            overview: String? = nil,
            status: String? = nil,
            airDate: Date? = nil,
            primaryLinkURL: URL? = nil,
            heroImageURL: URL? = nil,
            logoImageURL: URL? = nil,
            genreIDs: [Int] = [],
            voteAverage: Double? = nil,
            runtimeMinutes: Int? = nil,
            episodeCount: Int? = nil,
            seasonCount: Int? = nil,
            characters: [SchemaV2_7_1.AnimeEntryCharacter] = [],
            staff: [SchemaV2_7_1.AnimeEntryStaff] = [],
            seasons: [SchemaV2_7_1.AnimeEntrySeasonSummary] = [],
            episodes: [SchemaV2_7_1.AnimeEntryEpisodeSummary] = []
        ) {
            self.language = language
            self.title = title
            self.subtitle = subtitle
            self.overview = overview
            self.status = status
            self.airDate = airDate
            self.primaryLinkURL = primaryLinkURL
            self.heroImageURL = heroImageURL
            self.logoImageURL = logoImageURL
            self.genreIDs = genreIDs
            self.voteAverage = voteAverage
            self.runtimeMinutes = runtimeMinutes
            self.episodeCount = episodeCount
            self.seasonCount = seasonCount
            self.characters = characters
            self.staff = staff
            self.seasons = seasons
            self.episodes = episodes
            characters.forEach { $0.detail = self }
            staff.forEach { $0.detail = self }
            seasons.forEach { $0.detail = self }
            episodes.forEach { $0.detail = self }
        }
    }
}
