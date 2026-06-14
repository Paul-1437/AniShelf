//
//  LibraryMetadataRefreshTests.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/6/12.
//

import Foundation
import SwiftData
import TMDb
import Testing

@testable import DataProvider
@testable import MyAnimeList

struct LibraryMetadataRefreshTests {
    @Test @MainActor func testLibraryImageCacheBuildsCorePrefetchTargets() throws {
        let posterURL = try #require(URL(string: "https://example.com/poster.jpg"))
        let backdropURL = try #require(URL(string: "https://example.com/backdrop.jpg"))
        let logoURL = try #require(URL(string: "https://example.com/logo.png"))

        let targets = Set(
            LibraryImageCacheService.imagePrefetchTargets(
                posterURL: posterURL,
                backdropURL: backdropURL,
                logoImageURL: logoURL
            )
        )

        #expect(
            targets
                == Set([
                    .init(url: posterURL, targetSize: CGSize(width: 240, height: 360)),
                    .init(url: posterURL, targetSize: CGSize(width: 360, height: 540)),
                    .init(url: posterURL, targetSize: CGSize(width: 1_000, height: 1_500)),
                    .init(url: backdropURL, targetSize: CGSize(width: 1_200, height: 675)),
                    .init(url: logoURL, targetSize: CGSize(width: 500, height: 500))
                ])
        )
    }

    @Test @MainActor func testLibraryImageCacheBuildsURLLevelPrefetchWorkItems() throws {
        let posterURL = try #require(URL(string: "https://example.com/poster.jpg"))
        let heroURL = try #require(URL(string: "https://example.com/hero.jpg"))

        let targets = [
            LibraryImageCacheService.ImagePrefetchTarget(
                url: posterURL,
                targetSize: CGSize(width: 240, height: 360)
            ),
            LibraryImageCacheService.ImagePrefetchTarget(
                url: posterURL,
                targetSize: CGSize(width: 360, height: 540)
            ),
            LibraryImageCacheService.ImagePrefetchTarget(
                url: posterURL,
                targetSize: CGSize(width: 240, height: 360)
            ),
            LibraryImageCacheService.ImagePrefetchTarget(
                url: heroURL,
                targetSize: CGSize(width: 1_200, height: 675)
            )
        ]

        let workItems = LibraryImageCacheService.imagePrefetchWorkItems(from: targets)
            .sorted { $0.url.absoluteString < $1.url.absoluteString }

        #expect(workItems.count == 2)
        #expect(
            workItems
                == [
                    .init(
                        url: heroURL,
                        targetSizes: [CGSize(width: 1_200, height: 675)]
                    ),
                    .init(
                        url: posterURL,
                        targetSizes: [
                            CGSize(width: 240, height: 360),
                            CGSize(width: 360, height: 540)
                        ]
                    )
                ]
        )
    }

    @Test @MainActor func testLibraryImageCacheCollectsRelatedDetailURLs() throws {
        let posterURL = try #require(URL(string: "https://image.tmdb.org/t/p/original/poster.jpg"))
        let backdropURL = try #require(URL(string: "https://image.tmdb.org/t/p/w1280/backdrop.jpg"))
        let logoURL = try #require(URL(string: "https://image.tmdb.org/t/p/w500/logo.png"))
        let characterURL = try #require(URL(string: "https://image.tmdb.org/t/p/w185/character.jpg"))
        let staffURL = try #require(URL(string: "https://image.tmdb.org/t/p/w185/staff.jpg"))
        let seasonURL = try #require(URL(string: "https://image.tmdb.org/t/p/w342/season.jpg"))
        let episodeURL = try #require(URL(string: "https://image.tmdb.org/t/p/original/episode.jpg"))

        let entry = AnimeEntry(
            name: "Cache Test",
            type: .series,
            posterPath: "/poster.jpg",
            backdropPath: "/backdrop.jpg",
            tmdbID: 4
        )
        entry.detail = AnimeEntryDetail(
            language: "en",
            title: "Cache Test",
            logoImagePath: "/logo.png",
            characters: [
                AnimeEntryCharacter(
                    id: 1,
                    characterName: "Character",
                    actorName: "Actor",
                    profilePath: "/character.jpg"
                )
            ],
            staff: [
                AnimeEntryStaff(
                    id: 10,
                    name: "Director",
                    role: "Director",
                    profilePath: "/staff.jpg"
                )
            ],
            seasons: [
                AnimeEntrySeasonSummary(
                    id: 2,
                    seasonNumber: 1,
                    title: "Season",
                    posterPath: "/season.jpg"
                )
            ],
            episodes: [
                AnimeEntryEpisodeSummary(
                    id: 3,
                    episodeNumber: 1,
                    title: "Episode",
                    imagePath: "/episode.jpg"
                )
            ]
        )

        let urls = LibraryImageCacheService.relatedImageURLs(for: entry)

        #expect(
            urls
                == Set([
                    posterURL,
                    backdropURL,
                    logoURL,
                    characterURL,
                    staffURL,
                    seasonURL,
                    episodeURL
                ])
        )
    }

    @Test @MainActor func testLibrarySearchServiceUsesCurrentLibraryStoreEntries() throws {
        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
        store.newEntryFromEntryMetadata(
            EntryMetadata(
                name: "First Match",
                nameTranslations: [:],
                overview: nil,
                overviewTranslations: [:],
                posterURL: nil,
                backdropURL: nil,
                logoURL: nil,
                tmdbID: 500_001,
                onAirDate: nil,
                linkToDetails: nil,
                type: .movie
            )
        )
        try store.refreshLibrary()

        let service = LibrarySearchService(
            entriesProvider: { store.library }
        )

        service.updateResults(query: "first")
        #expect(service.results.map(\.tmdbID) == [500_001])

        store.newEntryFromEntryMetadata(
            EntryMetadata(
                name: "Second Match",
                nameTranslations: [:],
                overview: nil,
                overviewTranslations: [:],
                posterURL: nil,
                backdropURL: nil,
                logoURL: nil,
                tmdbID: 500_002,
                onAirDate: nil,
                linkToDetails: nil,
                type: .movie
            )
        )
        try store.refreshLibrary()

        service.updateResults(query: "second")
        #expect(service.results.map(\.tmdbID) == [500_002])
    }

    @Test @MainActor func testRefreshInfosIncludesSharedHiddenParentEntryOnce() throws {
        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
        let parent = AnimeEntry(
            name: "Frieren",
            type: .series,
            tmdbID: 209_867
        )
        parent.onDisplay = false

        let firstSeason = AnimeEntry(
            name: "Season 1",
            type: .season(seasonNumber: 1, parentSeriesID: 209_867),
            tmdbID: 400_234
        )
        firstSeason.parentSeriesEntry = parent

        let secondSeason = AnimeEntry(
            name: "Season 2",
            type: .season(seasonNumber: 2, parentSeriesID: 209_867),
            tmdbID: 400_235
        )
        secondSeason.parentSeriesEntry = parent

        try store.repository.newEntry(parent)
        try store.repository.newEntry(firstSeason)
        try store.repository.newEntry(secondSeason)
        try store.refreshLibrary()

        #expect(store.library.count == 2)

        let capturedEntries = try LibraryProfileSettingsActions.getRefreshEntries(for: store)

        #expect(capturedEntries.count == 3)
        #expect(Set(capturedEntries.map(\.id)).count == 3)
        #expect(capturedEntries.filter { !$0.onDisplay && $0.tmdbID == 209_867 }.count == 1)
    }

    @Test @MainActor func testMetadataRefreshSaveDoesNotEnqueueDirtyWork() async throws {
        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
        let hiddenParent = AnimeEntry(
            name: "Frieren",
            type: .series,
            tmdbID: 209_867
        )
        hiddenParent.updateDisplayState(false, at: referenceDate(year: 2026, month: 6, day: 5))
        store.repository.insert(hiddenParent)

        try await store.performWithoutSyncRecording {
            try store.repository.save()
        }

        #expect(store.syncChangeRecorder.dirtyQueueStore.load().entries.isEmpty)

        hiddenParent.name = "Frieren: Beyond Journey's End"
        try await store.performWithoutSyncRecording {
            try store.repository.save()
        }

        #expect(store.syncChangeRecorder.dirtyQueueStore.load().entries.isEmpty)
    }

    @Test @MainActor func testBackgroundMetadataRefreshWriterRepairsParentLinksWithoutSyncDirtyWork()
        async throws
    {
        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
        let oldParent = AnimeEntry(
            name: "Old Parent",
            type: .series,
            tmdbID: 100
        )
        oldParent.setDisplayState(false)
        let child = AnimeEntry(
            name: "Season 1",
            type: .season(seasonNumber: 1, parentSeriesID: 100),
            tmdbID: 200
        )
        child.parentSeriesEntry = oldParent

        try store.repository.newEntry(oldParent)
        try store.repository.newEntry(child)
        store.rebuildSyncChangeTracking()
        try store.syncChangeRecorder.dirtyQueueStore.replaceEntries([])

        let modelContainer = store.dataProvider.sharedModelContainer
        try await store.performWithoutSyncRecording {
            let writer = await Task.detached(priority: .utility) {
                LibraryMetadataRefreshWriter(modelContainer: modelContainer)
            }.value
            try await writer.apply(
                updates: [
                    .init(
                        entryID: child.id,
                        info: EntryMetadata(
                            name: "Season 1 Refreshed",
                            nameTranslations: [:],
                            overview: nil,
                            overviewTranslations: [:],
                            posterURL: nil,
                            backdropURL: nil,
                            logoURL: nil,
                            tmdbID: 200,
                            onAirDate: nil,
                            linkToDetails: nil,
                            type: .season(seasonNumber: 1, parentSeriesID: 300)
                        ),
                        detail: AnimeEntryDetailDTO(
                            language: "en-US",
                            title: "Season 1 Refreshed"
                        ),
                        preservingCustomPoster: false
                    )
                ],
                parentUpdates: [
                    .init(
                        childEntryID: child.id,
                        parentSeriesID: 300,
                        parentInfo: EntryMetadata(
                            name: "New Parent",
                            nameTranslations: [:],
                            overview: nil,
                            overviewTranslations: [:],
                            posterURL: nil,
                            backdropURL: nil,
                            logoURL: nil,
                            tmdbID: 300,
                            onAirDate: nil,
                            linkToDetails: nil,
                            type: .series
                        ),
                        parentDetail: AnimeEntryDetailDTO(
                            language: "en-US",
                            title: "New Parent"
                        )
                    )
                ]
            )
        }
        try store.refreshLibrary()

        let refreshedChild = try #require(
            store.dataProvider.getModels(
                ofType: AnimeEntry.self,
                predicate: #Predicate { $0.tmdbID == 200 }
            ).first
        )
        let insertedParent = try #require(
            store.dataProvider.getModels(
                ofType: AnimeEntry.self,
                predicate: #Predicate { $0.tmdbID == 300 }
            ).first
        )

        #expect(refreshedChild.name == "Season 1 Refreshed")
        #expect(refreshedChild.parentSeriesEntry?.tmdbID == 300)
        #expect(insertedParent.onDisplay == false)
        #expect(store.syncChangeRecorder.dirtyQueueStore.load().entries.isEmpty)
    }

    @Test @MainActor func testHydrateHiddenHelperParentAppliesDefaultsAndDetail() throws {
        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
        store.defaultNewEntryWatchStatus = .watching

        let hiddenParent = AnimeEntry(
            name: "Frieren",
            type: .series,
            tmdbID: 209_867
        )
        hiddenParent.onDisplay = false
        try store.repository.newEntry(hiddenParent)

        try store.hydrateExistingEntry(
            hiddenParent,
            from: EntryMetadata(
                name: "Frieren: Beyond Journey's End",
                nameTranslations: [:],
                overview: "Elf mage travels onward.",
                overviewTranslations: [:],
                posterURL: nil,
                backdropURL: nil,
                logoURL: nil,
                tmdbID: 209_867,
                onAirDate: nil,
                linkToDetails: nil,
                type: .series
            ),
            detail: AnimeEntryDetailDTO(
                language: "en-US",
                title: "Frieren: Beyond Journey's End",
                runtimeMinutes: 24,
                episodeCount: 28,
                seasonCount: 1
            )
        )

        #expect(hiddenParent.onDisplay)
        #expect(hiddenParent.watchStatus == .watching)
        #expect(hiddenParent.dateStarted == nil)
        #expect(hiddenParent.detail?.runtimeMinutes == 24)
        #expect(hiddenParent.detail?.episodeCount == 28)
        #expect(hiddenParent.name == "Frieren: Beyond Journey's End")

        try store.refreshLibrary()
        #expect(store.library.map(\.tmdbID) == [209_867])
    }

    @Test @MainActor func testRefreshInfosReportsPartialCompletionAfterLaterChunkSaveFailure()
        async throws
    {
        let repository = LibraryRepository(dataProvider: DataProvider(inMemory: true))
        let library = (1...9).map { index in
            AnimeEntry(
                name: "Movie \(index)",
                type: .movie,
                tmdbID: index
            )
        }
        for entry in library {
            try repository.newEntry(entry)
        }

        let fetcher = makeLibraryMetadataRefreshTestFetcher()
        let latestInfo = try await fetcher.latestInfo(
            entryType: .movie,
            tmdbID: 1,
            language: .english
        )
        #expect(latestInfo.0.name == "Fight Club")

        var applyCallCount = 0
        var completions: [LibraryRefreshCompletion] = []
        let reporter = LibraryRefreshReporter { event in
            if case .refreshComplete(let completion) = event {
                completions.append(completion)
            }
        }
        let refresher = LibraryMetadataRefresher(
            repository: repository,
            applyMetadataRefresh: { updates, _ in
                applyCallCount += 1
                if applyCallCount == 2 {
                    throw TestApplyError.failed
                }
                #expect(updates.count == 8)
            }
        )

        await refresher.refreshInfos(
            for: library,
            fetcher: fetcher,
            language: .english,
            options: .init(
                reporter: reporter,
                prefetchImages: false
            )
        )

        #expect(applyCallCount == 2)
        #expect(completions.count == 1)
        #expect(completions[0].state == .partialComplete)
        #expect(completions[0].successfulItemCount == 8)
        #expect(completions[0].failedItemCount == 1)
    }
}

private enum TestApplyError: Error {
    case failed
}

private func makeLibraryMetadataRefreshTestFetcher() -> InfoFetcher {
    let httpClient = RecordingTMDbHTTPClient { request in
        HTTPResponse(data: libraryMetadataRefreshFixtureData(for: request.url.path))
    }

    return InfoFetcher(
        client: TMDbClient(
            apiKey: "test-key",
            httpClient: httpClient,
            configuration: .default
        ),
        fetchTranslationResponseData: { path in
            libraryMetadataRefreshFixtureData(for: path)
        }
    )
}

private func libraryMetadataRefreshFixtureData(for path: String) -> Data {
    switch path {
    case "/3/configuration":
        Data(
            #"""
            {
                "images": {
                    "base_url": "http://image.tmdb.org/t/p/",
                    "secure_base_url": "https://image.tmdb.org/t/p/",
                    "backdrop_sizes": ["w300", "w780", "w1280", "original"],
                    "logo_sizes": ["w45", "w92", "w154", "w185", "w300", "w500", "original"],
                    "poster_sizes": ["w92", "w154", "w185", "w342", "w500", "w780", "original"],
                    "profile_sizes": ["w45", "w185", "h632", "original"],
                    "still_sizes": ["w92", "w185", "w300", "original"]
                },
                "change_keys": []
            }
            """#.utf8
        )
    case let path where path.hasSuffix("/images"):
        Data(
            #"""
            {
                "id": 550,
                "backdrops": [
                    {
                        "aspect_ratio": 1.77777777777778,
                        "file_path": "/fCayJrkfRaCRCTh8GqN30f8oyQF.jpg",
                        "height": 720,
                        "iso_639_1": null,
                        "vote_average": 1.21,
                        "vote_count": 435,
                        "width": 1280
                    }
                ],
                "logos": [
                    {
                        "aspect_ratio": 2.5,
                        "file_path": "/fasasakfRaCRCTh8GqN30f8oyQF.jpg",
                        "height": 400,
                        "iso_639_1": null,
                        "vote_average": 5.31,
                        "vote_count": 345,
                        "width": 100
                    }
                ],
                "posters": [
                    {
                        "aspect_ratio": 0.666666666666667,
                        "file_path": "/fpemzjF623QVTe98pCVlwwtFC5N.jpg",
                        "height": 1800,
                        "iso_639_1": "en",
                        "vote_average": 5.21,
                        "vote_count": 3,
                        "width": 1200
                    }
                ]
            }
            """#.utf8
        )
    case let path where path.hasSuffix("/translations"):
        Data(
            #"""
            {
                "id": 550,
                "translations": [
                    {
                        "iso_3166_1": "US",
                        "iso_639_1": "en",
                        "name": "English",
                        "english_name": "English",
                        "data": {
                            "title": "Fight Club",
                            "overview": "A ticking-time-bomb insomniac and a slippery soap salesman channel primal male aggression into a shocking new form of therapy.",
                            "homepage": "https://www.foxmovies.com/movies/fight-club",
                            "tagline": "Mischief. Mayhem. Soap."
                        }
                    }
                ]
            }
            """#.utf8
        )
    case let path where path.hasSuffix("/credits"):
        Data(
            #"""
            {
                "id": 550,
                "cast": [
                    {
                        "cast_id": 4,
                        "character": "The Narrator",
                        "credit_id": "52fe4250c3a36847f80149f3",
                        "gender": 2,
                        "id": 819,
                        "name": "Edward Norton",
                        "order": 0,
                        "profile_path": "/eIkFHNlfretLS1spAcIoihKUS62.jpg"
                    }
                ],
                "crew": [
                    {
                        "credit_id": "56380f0cc3a3681b5c0200be",
                        "department": "Writing",
                        "gender": 0,
                        "id": 7469,
                        "job": "Screenplay",
                        "name": "Jim Uhls",
                        "profile_path": null
                    }
                ]
            }
            """#.utf8
        )
    case let path where path.starts(with: "/3/movie/"):
        Data(
            #"""
            {
                "adult": false,
                "backdrop_path": "/fCayJrkfRaCRCTh8GqN30f8oyQF.jpg",
                "belongs_to_collection": null,
                "budget": 63000000,
                "genres": [
                    {
                        "id": 18,
                        "name": "Drama"
                    }
                ],
                "homepage": null,
                "id": 550,
                "imdb_id": "tt0137523",
                "origin_country": ["US"],
                "original_language": "en",
                "original_title": "Fight Club",
                "overview": "A ticking-time-bomb insomniac and a slippery soap salesman channel primal male aggression into a shocking new form of therapy.",
                "popularity": 0.5,
                "poster_path": null,
                "production_companies": [
                    {
                        "id": 508,
                        "logo_path": "/7PzJdsLGlR7oW4J0J5Xcd0pHGRg.png",
                        "name": "Regency Enterprises",
                        "origin_country": "US"
                    }
                ],
                "production_countries": [
                    {
                        "iso_3166_1": "US",
                        "name": "United States of America"
                    }
                ],
                "release_date": "1999-10-12",
                "revenue": 100853753,
                "runtime": 139,
                "spoken_languages": [
                    {
                        "iso_639_1": "en",
                        "name": "English"
                    }
                ],
                "status": "Released",
                "tagline": "How much can you know about yourself if you've never been in a fight?",
                "title": "Fight Club",
                "video": false,
                "vote_average": 7.8,
                "vote_count": 3439
            }
            """#.utf8
        )
    default:
        Data()
    }
}
