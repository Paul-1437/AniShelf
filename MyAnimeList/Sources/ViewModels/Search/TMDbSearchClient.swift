//
//  TMDbSearchClient.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/6/12.
//

import DataProvider
import Foundation
import TMDb
import os

fileprivate let logger = Logger(subsystem: .bundleIdentifier, category: "TMDbSearchService")

struct TMDbSearchClient: Sendable {
    let searchMovies: @Sendable (String, Language) async throws -> [EntryMetadata]
    let searchTVSeries: @Sendable (String, Language) async throws -> [EntryMetadata]
    let fetchMovieByID: @Sendable (Int, Language) async throws -> EntryMetadata?
    let fetchTVSeriesByID: @Sendable (Int, Language) async throws -> EntryMetadata?
    let fetchSeasons: @Sendable (EntryMetadata, Language) async throws -> [EntryMetadata]

    init(
        searchMovies: @escaping @Sendable (String, Language) async throws -> [EntryMetadata],
        searchTVSeries: @escaping @Sendable (String, Language) async throws -> [EntryMetadata],
        fetchMovieByID: @escaping @Sendable (Int, Language) async throws -> EntryMetadata? = {
            _, _ in nil
        },
        fetchTVSeriesByID: @escaping @Sendable (Int, Language) async throws -> EntryMetadata? = {
            _, _ in nil
        },
        fetchSeasons: @escaping @Sendable (EntryMetadata, Language) async throws -> [EntryMetadata]
    ) {
        self.searchMovies = searchMovies
        self.searchTVSeries = searchTVSeries
        self.fetchMovieByID = fetchMovieByID
        self.fetchTVSeriesByID = fetchTVSeriesByID
        self.fetchSeasons = fetchSeasons
    }

    static func live(fetcher: InfoFetcher = .init()) -> Self {
        Self(
            searchMovies: { query, language in
                let movies = try await fetcher.searchMovies(name: query, language: language)
                let posterURLs = try await fetchPosterURLMap(
                    fetcher: fetcher,
                    from: movies.map { (tmdbID: $0.id, path: $0.posterPath) }
                )
                return movies.map { movie in
                    EntryMetadata(
                        name: movie.title,
                        nameTranslations: [:],
                        overview: movie.overview,
                        overviewTranslations: [:],
                        posterURL: posterURLs[movie.id] ?? nil,
                        tmdbID: movie.id,
                        onAirDate: movie.releaseDate,
                        type: .movie
                    )
                }
            },
            searchTVSeries: { query, language in
                let tvSeries = try await fetcher.searchTVSeries(name: query, language: language)
                let posterURLs = try await fetchPosterURLMap(
                    fetcher: fetcher,
                    from: tvSeries.map { (tmdbID: $0.id, path: $0.posterPath) }
                )
                return tvSeries.map { series in
                    EntryMetadata(
                        name: series.name,
                        nameTranslations: [:],
                        overview: series.overview,
                        overviewTranslations: [:],
                        posterURL: posterURLs[series.id] ?? nil,
                        tmdbID: series.id,
                        onAirDate: series.firstAirDate,
                        type: .series
                    )
                }
            },
            fetchMovieByID: { tmdbID, language in
                do {
                    return try await fetcher.animeMovieInfo(tmdbID: tmdbID, language: language)
                } catch TMDbError.notFound {
                    logger.info("Direct TMDb movie lookup missed for \(tmdbID).")
                    return nil
                } catch {
                    logger.error("Direct TMDb movie lookup failed for \(tmdbID): \(error)")
                    throw error
                }
            },
            fetchTVSeriesByID: { tmdbID, language in
                do {
                    return try await fetcher.animeTVSeriesInfo(tmdbID: tmdbID, language: language)
                } catch TMDbError.notFound {
                    logger.info("Direct TMDb series lookup missed for \(tmdbID).")
                    return nil
                } catch {
                    logger.error("Direct TMDb series lookup failed for \(tmdbID): \(error)")
                    throw error
                }
            },
            fetchSeasons: { seriesInfo, language in
                let series = try await fetcher.tvSeries(seriesInfo.tmdbID, language: language)
                guard let seasons = series.seasons else { return [] }

                let infos = try await withThrowingTaskGroup(of: EntryMetadata.self) { group in
                    for season in seasons {
                        group.addTask {
                            let posterURL = try await fetcher.tmdbClient.imagesConfiguration
                                .posterURL(for: season.posterPath, idealWidth: 200)
                            return EntryMetadata(
                                name: season.name,
                                nameTranslations: [:],
                                overview: season.overview,
                                overviewTranslations: [:],
                                posterURL: posterURL,
                                tmdbID: season.id,
                                onAirDate: season.airDate,
                                type: .season(
                                    seasonNumber: season.seasonNumber,
                                    parentSeriesID: seriesInfo.tmdbID
                                )
                            )
                        }
                    }

                    var results: [EntryMetadata] = []
                    for try await result in group {
                        results.append(result)
                    }
                    return results.sorted(by: {
                        if case .season(let seasonNumber1, _) = $0.type,
                            case .season(let seasonNumber2, _) = $1.type
                        {
                            return seasonNumber1 < seasonNumber2
                        }
                        return false
                    })
                }
                return infos
            }
        )
    }
}

fileprivate func fetchPosterURLMap(
    fetcher: InfoFetcher,
    from items: [(tmdbID: Int, path: URL?)]
) async throws -> [Int: URL?] {
    let posterURLs = try await withThrowingTaskGroup(of: (tmdbID: Int, url: URL?).self) { group in
        for item in items {
            group.addTask {
                let url =
                    try await fetcher
                    .tmdbClient
                    .imagesConfiguration
                    .posterURL(for: item.path, idealWidth: 200)
                return (tmdbID: item.tmdbID, url: url)
            }
        }

        var results: [(tmdbID: Int, url: URL?)] = []
        for try await result in group {
            results.append(result)
        }
        return results
    }

    return Dictionary(uniqueKeysWithValues: posterURLs.map { ($0.tmdbID, $0.url) })
}
