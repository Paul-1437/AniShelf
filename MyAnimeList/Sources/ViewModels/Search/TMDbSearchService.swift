//
//  TMDbSearchService.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/5/5.
//

import Collections
import DataProvider
import Foundation
import SwiftUI
import TMDb
import os

fileprivate let logger = Logger(subsystem: .bundleIdentifier, category: "TMDbSearchService")

struct SearchResult: Hashable, Sendable {
    var tmdbID: Int
    var type: AnimeType
}

struct TMDbBatchPromptResult: Identifiable, Equatable, Hashable, Sendable {
    let id: Int
    let prompt: String
    let series: BasicInfo?
    let movie: BasicInfo?
    var hasNoResults: Bool { series == nil && movie == nil }
    var allInfos: [BasicInfo] { [series, movie].compactMap { $0 } }
}

enum TMDbBatchPrompt: Equatable, Sendable {
    case title(displayText: String)
    case movieID(displayText: String, tmdbID: Int)
    case seriesID(displayText: String, tmdbID: Int)
    case season(displayText: String, seriesTMDbID: Int, seasonNumber: Int)

    var displayText: String {
        switch self {
        case .title(let displayText),
            .movieID(let displayText, _),
            .seriesID(let displayText, _),
            .season(let displayText, _, _):
            displayText
        }
    }

    init(displayText: String) {
        self = Self.parse(displayText: displayText)
    }

    private static func parse(displayText: String) -> Self {
        let parts = displayText.split(separator: ":", omittingEmptySubsequences: false)

        if parts.count == 2,
            parts[0] == "movie",
            let tmdbID = parseInteger(parts[1])
        {
            return .movieID(displayText: displayText, tmdbID: tmdbID)
        }

        if parts.count == 2,
            parts[0] == "series",
            let tmdbID = parseInteger(parts[1])
        {
            return .seriesID(displayText: displayText, tmdbID: tmdbID)
        }

        if parts.count == 3,
            parts[0] == "season",
            let seriesTMDbID = parseInteger(parts[1]),
            let seasonNumber = parseInteger(parts[2])
        {
            return .season(
                displayText: displayText,
                seriesTMDbID: seriesTMDbID,
                seasonNumber: seasonNumber
            )
        }

        return .title(displayText: displayText)
    }

    private static func parseInteger(_ component: Substring) -> Int? {
        let text = String(component)
        guard !text.isEmpty else { return nil }

        let digitCharacters: Substring
        if text.hasPrefix("-") {
            digitCharacters = text.dropFirst()
        } else {
            digitCharacters = Substring(text)
        }

        guard !digitCharacters.isEmpty,
            digitCharacters.unicodeScalars.allSatisfy({ $0.value >= 48 && $0.value <= 57 })
        else {
            return nil
        }

        return Int(text)
    }
}

enum TMDbSelectionContext: Sendable {
    case regular
    case batch
}

enum TMDbSeriesSelectionMode: CaseIterable, Equatable, Sendable {
    case series
    case season
}

enum TMDbSeasonFetchStatus: Equatable, Sendable {
    case notStarted
    case fetching
    case fetched
}

struct TMDbSeriesSelectionState: Equatable, Sendable {
    var selectedMode: TMDbSeriesSelectionMode = .series
    var seasons: [BasicInfo] = []
    var seasonFetchStatus: TMDbSeasonFetchStatus = .notStarted
    var selectedSeasonIDs: Set<Int> = []
}

struct TMDbSearchClient: Sendable {
    let searchMovies: @Sendable (String, Language) async throws -> [BasicInfo]
    let searchTVSeries: @Sendable (String, Language) async throws -> [BasicInfo]
    let fetchMovieByID: @Sendable (Int, Language) async throws -> BasicInfo?
    let fetchTVSeriesByID: @Sendable (Int, Language) async throws -> BasicInfo?
    let fetchSeasons: @Sendable (BasicInfo, Language) async throws -> [BasicInfo]

    init(
        searchMovies: @escaping @Sendable (String, Language) async throws -> [BasicInfo],
        searchTVSeries: @escaping @Sendable (String, Language) async throws -> [BasicInfo],
        fetchMovieByID: @escaping @Sendable (Int, Language) async throws -> BasicInfo? = {
            _, _ in nil
        },
        fetchTVSeriesByID: @escaping @Sendable (Int, Language) async throws -> BasicInfo? = {
            _, _ in nil
        },
        fetchSeasons: @escaping @Sendable (BasicInfo, Language) async throws -> [BasicInfo]
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
                    BasicInfo(
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
                    BasicInfo(
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

                let infos = try await withThrowingTaskGroup(of: BasicInfo.self) { group in
                    for season in seasons {
                        group.addTask {
                            let posterURL = try await fetcher.tmdbClient.imagesConfiguration
                                .posterURL(for: season.posterPath, idealWidth: 200)
                            return BasicInfo(
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

                    var results: [BasicInfo] = []
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

@Observable @MainActor
class TMDbSearchService {
    private struct SearchRequest: Equatable {
        let query: String
        let language: Language
    }

    private struct BatchSeasonPreselection: Equatable, Sendable {
        let seriesID: Int
        let seasons: [BasicInfo]
        let selectedSeason: BasicInfo
    }

    private struct BatchPromptResolution: Equatable, Sendable {
        let result: TMDbBatchPromptResult
        let seasonPreselection: BatchSeasonPreselection?
    }

    private static let batchPromptChunkSize = 8

    @ObservationIgnored private let client: TMDbSearchClient
    private(set) var status: Status = .loaded
    private(set) var movieResults: [BasicInfo] = []
    private(set) var seriesResults: [BasicInfo] = []
    private(set) var batchStatus: BatchStatus = .idle
    private(set) var batchResults: [TMDbBatchPromptResult] = []
    private(set) var batchSearchGeneration = 0

    private var regularResultsToSubmit: OrderedSet<SearchResult> = []
    private var batchResultsToSubmit: OrderedSet<SearchResult> = []
    private var regularSeriesSelectionStates: [Int: TMDbSeriesSelectionState] = [:]
    private var batchSeriesSelectionStates: [Int: TMDbSeriesSelectionState] = [:]

    @ObservationIgnored private var latestRequest: SearchRequest?
    @ObservationIgnored private var latestBatchRequestID: UUID?
    @ObservationIgnored private var batchPromptCacheKey: [String] = []
    @ObservationIgnored var checkDuplicate: (Int) -> Bool
    @ObservationIgnored var processResults: (OrderedSet<SearchResult>) -> Void

    init(
        client: TMDbSearchClient = .live(),
        checkDuplicate: @escaping (Int) -> Bool = { _ in false },
        processResults: @escaping (OrderedSet<SearchResult>) -> Void = { _ in }
    ) {
        self.client = client
        self.checkDuplicate = checkDuplicate
        self.processResults = processResults
    }

    /// Submit the final results.
    func submit() { processResults(OrderedSet(regularResultsToSubmit.reversed())) }
    /// Submit the final batch results.
    func submitBatch() { processResults(OrderedSet(batchResultsToSubmit.reversed())) }
    /// The count of all regular-search results pending submission.
    var registeredCount: Int { regularResultsToSubmit.count }
    var batchRegisteredCount: Int { batchResultsToSubmit.count }
    var batchRegisteredSeriesCount: Int { batchRegisteredCount(for: .series) }
    var batchRegisteredSeasonCount: Int { batchSelectionSeasonCount() }
    var batchRegisteredMovieCount: Int { batchRegisteredCount(for: .movie) }

    func isRegistered(info: BasicInfo) -> Bool {
        containsSelection(.init(tmdbID: info.tmdbID, type: info.type), in: .regular)
    }

    func isBatchSelected(info: BasicInfo) -> Bool {
        containsSelection(.init(tmdbID: info.tmdbID, type: info.type), in: .batch)
    }

    func seriesSelectionState(
        for series: BasicInfo,
        context: TMDbSelectionContext
    ) -> TMDbSeriesSelectionState {
        seriesSelectionState(forSeriesID: series.tmdbID, context: context)
    }

    /// Appends a result to the regular-search submission queue.
    func register(_ result: SearchResult) {
        setSelection(true, result: result, context: .regular)
    }

    /// Creates a result from a `BasicInfo` to the regular-search submission queue.
    func register(info: BasicInfo) {
        setSelection(true, info: info, context: .regular)
    }

    /// Removes a result from the regular-search submission queue if it is present.
    func unregister(_ result: SearchResult) {
        setSelection(false, result: result, context: .regular)
    }

    /// Removes a result corresponding to the provided `BasicInfo` from the regular-search submission queue if it is present.
    func unregister(info: BasicInfo) {
        setSelection(false, info: info, context: .regular)
    }

    /// Registers a result that belongs to the active batch session.
    func registerBatchSelection(info: BasicInfo) {
        setSelection(true, info: info, context: .batch)
    }

    /// Removes a batch-owned result from the submission queue if it is present.
    func unregisterBatchSelection(info: BasicInfo) {
        setSelection(false, info: info, context: .batch)
    }

    func setSelection(_ isSelected: Bool, for info: BasicInfo, context: TMDbSelectionContext) {
        setSelection(isSelected, info: info, context: context)
    }

    func setSeasonSelection(
        _ isSelected: Bool,
        for season: BasicInfo,
        context: TMDbSelectionContext
    ) {
        setSelection(isSelected, info: season, context: context)
    }

    func setSeriesSelectionMode(
        _ mode: TMDbSeriesSelectionMode,
        for series: BasicInfo,
        language: Language,
        context: TMDbSelectionContext
    ) async {
        var state = seriesSelectionState(forSeriesID: series.tmdbID, context: context)
        state.selectedMode = mode

        switch mode {
        case .series:
            clearSeasonSelections(forSeriesID: series.tmdbID, context: context, state: &state)
        case .season:
            setSelection(false, info: series, context: context)
        }

        setSeriesSelectionState(state, forSeriesID: series.tmdbID, context: context)

        guard mode == .season else { return }
        await fetchSeasonsIfNeeded(for: series, language: language, context: context)
    }

    /// Removes all regular-search selections.
    func clearAll() {
        clearSelections(in: .regular)
        logger.info("Cleared all regular registered results.")
    }

    func updateResults(query: String, language: Language) {
        let request = SearchRequest(query: query, language: language)
        latestRequest = request

        guard !query.isEmpty else {
            withAnimation {
                movieResults = []
                seriesResults = []
            }
            status = .loaded
            return
        }
        Task {
            status = .loading
            do {
                async let searchMovieResults = client.searchMovies(query, language)
                async let searchTVSeriesResults = client.searchTVSeries(query, language)
                let resolvedMovieResults = try await searchMovieResults
                let resolvedSeriesResults = try await searchTVSeriesResults

                if request == latestRequest {
                    withAnimation {
                        movieResults = resolvedMovieResults
                        seriesResults = resolvedSeriesResults
                    }
                    status = .loaded
                }
            } catch {
                logger.error("Error fetching search results: \(error)")
                guard request == latestRequest else { return }
                status = .error(error)
            }
        }
    }

    func performBatchSearch(input: String, language: Language) async {
        let prompts = Self.parsedBatchPrompts(from: input)

        guard !prompts.isEmpty else {
            clearBatchSession()
            return
        }

        if canReuseBatchResults(for: prompts) {
            return
        }

        let requestID = UUID()
        latestBatchRequestID = requestID
        clearSelections(in: .batch)
        withAnimation {
            batchResults = []
            batchStatus = .loading
            batchSearchGeneration += 1
        }

        do {
            let promptResults = try await fetchBatchResults(prompts: prompts, language: language)
            guard latestBatchRequestID == requestID else { return }
            withAnimation {
                applyBatchResults(promptResults, prompts: prompts)
                batchStatus = .loaded
                batchSearchGeneration += 1
            }
        } catch {
            guard latestBatchRequestID == requestID else { return }
            logger.error("Error fetching batch search results: \(error)")
            withAnimation {
                batchResults = []
                batchStatus = .error(error)
                batchSearchGeneration += 1
            }
        }
    }

    func clearBatchSession() {
        latestBatchRequestID = UUID()
        clearSelections(in: .batch)
        withAnimation {
            batchResults = []
            batchPromptCacheKey = []
            batchStatus = .idle
            batchSearchGeneration += 1
        }
    }

    func canReuseBatchResults(for input: String) -> Bool {
        let prompts = Self.parsedBatchPrompts(from: input)
        return canReuseBatchResults(for: prompts)
    }

    nonisolated static func batchPrompts(from input: String) -> [String] {
        input
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    nonisolated static func parsedBatchPrompts(from input: String) -> [TMDbBatchPrompt] {
        batchPrompts(from: input).map(TMDbBatchPrompt.init(displayText:))
    }

    nonisolated static func chunkedBatchPrompts(
        _ prompts: [String],
        chunkSize: Int = 8
    ) -> [[String]] {
        let normalizedChunkSize = max(1, chunkSize)
        return stride(from: 0, to: prompts.count, by: normalizedChunkSize).map { start in
            let end = min(start + normalizedChunkSize, prompts.count)
            return Array(prompts[start..<end])
        }
    }

    nonisolated static func chunkedBatchPrompts(
        _ prompts: [TMDbBatchPrompt],
        chunkSize: Int = 8
    ) -> [[TMDbBatchPrompt]] {
        let normalizedChunkSize = max(1, chunkSize)
        return stride(from: 0, to: prompts.count, by: normalizedChunkSize).map { start in
            let end = min(start + normalizedChunkSize, prompts.count)
            return Array(prompts[start..<end])
        }
    }

    private func fetchBatchResults(prompts: [TMDbBatchPrompt], language: Language) async throws
        -> [BatchPromptResolution]
    {
        let chunks = Self.chunkedBatchPrompts(prompts)
        var orderedResults = [BatchPromptResolution?](repeating: nil, count: prompts.count)

        for (chunkIndex, chunk) in chunks.enumerated() {
            let baseIndex = chunkIndex * Self.batchPromptChunkSize
            let chunkResults = try await withThrowingTaskGroup(
                of: (Int, BatchPromptResolution).self
            ) { group in
                for (offset, prompt) in chunk.enumerated() {
                    let index = baseIndex + offset
                    group.addTask { [client] in
                        (
                            index,
                            try await Self.resolveBatchPrompt(
                                prompt,
                                id: index,
                                language: language,
                                client: client
                            )
                        )
                    }
                }

                var results: [(Int, BatchPromptResolution)] = []
                for try await result in group {
                    results.append(result)
                }
                return results
            }

            for (index, result) in chunkResults {
                orderedResults[index] = result
            }
        }

        return orderedResults.compactMap { $0 }
    }

    private nonisolated static func resolveBatchPrompt(
        _ prompt: TMDbBatchPrompt,
        id: Int,
        language: Language,
        client: TMDbSearchClient
    ) async throws -> BatchPromptResolution {
        switch prompt {
        case .title(let displayText):
            async let seriesResults = client.searchTVSeries(displayText, language)
            async let movieResults = client.searchMovies(displayText, language)
            let resolvedSeriesResults = try await seriesResults
            let resolvedMovieResults = try await movieResults
            return BatchPromptResolution(
                result: TMDbBatchPromptResult(
                    id: id,
                    prompt: displayText,
                    series: resolvedSeriesResults.first,
                    movie: resolvedMovieResults.first
                ),
                seasonPreselection: nil
            )

        case .movieID(let displayText, let tmdbID):
            let movie = try await client.fetchMovieByID(tmdbID, language)
            return BatchPromptResolution(
                result: TMDbBatchPromptResult(
                    id: id,
                    prompt: displayText,
                    series: nil,
                    movie: movie
                ),
                seasonPreselection: nil
            )

        case .seriesID(let displayText, let tmdbID):
            let series = try await client.fetchTVSeriesByID(tmdbID, language)
            return BatchPromptResolution(
                result: TMDbBatchPromptResult(
                    id: id,
                    prompt: displayText,
                    series: series,
                    movie: nil
                ),
                seasonPreselection: nil
            )

        case .season(let displayText, let seriesTMDbID, let seasonNumber):
            guard let series = try await client.fetchTVSeriesByID(seriesTMDbID, language) else {
                return BatchPromptResolution(
                    result: TMDbBatchPromptResult(
                        id: id,
                        prompt: displayText,
                        series: nil,
                        movie: nil
                    ),
                    seasonPreselection: nil
                )
            }

            let seasons = try await client.fetchSeasons(series, language)
            guard let selectedSeason = seasons.first(where: { $0.type.seasonNumber == seasonNumber })
            else {
                return BatchPromptResolution(
                    result: TMDbBatchPromptResult(
                        id: id,
                        prompt: displayText,
                        series: nil,
                        movie: nil
                    ),
                    seasonPreselection: nil
                )
            }

            return BatchPromptResolution(
                result: TMDbBatchPromptResult(
                    id: id,
                    prompt: displayText,
                    series: series,
                    movie: nil
                ),
                seasonPreselection: BatchSeasonPreselection(
                    seriesID: series.tmdbID,
                    seasons: seasons,
                    selectedSeason: selectedSeason
                )
            )
        }
    }

    private func applyBatchResults(_ resolutions: [BatchPromptResolution], prompts: [TMDbBatchPrompt]) {
        batchResults = resolutions.map(\.result)
        batchPromptCacheKey = prompts.map(\.displayText)

        let structuredSeasonResultIDs = Set(
            resolutions.compactMap { $0.seasonPreselection?.seriesID }
        )
        for resolution in resolutions where resolution.seasonPreselection == nil {
            for info in resolution.result.allInfos {
                if case .series = info.type, structuredSeasonResultIDs.contains(info.tmdbID) {
                    continue
                }
                guard !checkDuplicate(info.tmdbID) else { continue }
                registerBatchSelection(info: info)
            }
        }

        for preselection in resolutions.compactMap(\.seasonPreselection) {
            var state = seriesSelectionState(forSeriesID: preselection.seriesID, context: .batch)
            state.selectedMode = .season
            state.seasons = preselection.seasons
            state.seasonFetchStatus = .fetched
            setSeriesSelectionState(state, forSeriesID: preselection.seriesID, context: .batch)
            _ = removeResult(.init(tmdbID: preselection.seriesID, type: .series), context: .batch)

            guard !checkDuplicate(preselection.selectedSeason.tmdbID) else { continue }
            registerBatchSelection(info: preselection.selectedSeason)
        }
    }

    private func canReuseBatchResults(for prompts: [TMDbBatchPrompt]) -> Bool {
        batchStatus == .loaded && batchPromptCacheKey == prompts.map(\.displayText)
    }

    private func batchRegisteredCount(for type: AnimeType) -> Int {
        batchResultsToSubmit.reduce(into: 0) { count, result in
            if result.type == type {
                count += 1
            }
        }
    }

    private func batchSelectionSeasonCount() -> Int {
        batchResultsToSubmit.reduce(into: 0) { count, result in
            if case .season = result.type {
                count += 1
            }
        }
    }

    @discardableResult
    private func insertResult(_ result: SearchResult, context: TMDbSelectionContext) -> Bool {
        let inserted: Bool
        switch context {
        case .regular:
            let (didInsert, _) = regularResultsToSubmit.insert(result, at: 0)
            inserted = didInsert
        case .batch:
            let (didInsert, _) = batchResultsToSubmit.insert(result, at: 0)
            inserted = didInsert
        }
        if inserted {
            logger.info(
                "Registered \(self.selectionContextLabel(context)) result: \(result.tmdbID) of type \(result.type)."
            )
        } else {
            logger.info(
                "\(self.selectionContextLabel(context)) result already registered: \(result.tmdbID) of type \(result.type)."
            )
        }
        return inserted
    }

    @discardableResult
    private func removeResult(_ result: SearchResult, context: TMDbSelectionContext) -> Bool {
        let removed: Bool
        switch context {
        case .regular:
            removed = regularResultsToSubmit.remove(result) != nil
        case .batch:
            removed = batchResultsToSubmit.remove(result) != nil
        }
        if removed {
            logger.info(
                "Unregistered \(self.selectionContextLabel(context)) result: \(result.tmdbID) of type \(result.type)."
            )
        } else {
            logger.info(
                "\(self.selectionContextLabel(context)) result not found for unregistration: \(result.tmdbID) of type \(result.type)."
            )
        }
        return removed
    }

    private func containsSelection(_ result: SearchResult, in context: TMDbSelectionContext) -> Bool {
        switch context {
        case .regular:
            regularResultsToSubmit.contains(result)
        case .batch:
            batchResultsToSubmit.contains(result)
        }
    }

    private func setSelection(
        _ isSelected: Bool,
        info: BasicInfo,
        context: TMDbSelectionContext
    ) {
        setSelection(
            isSelected,
            result: .init(tmdbID: info.tmdbID, type: info.type),
            context: context
        )
    }

    private func setSelection(
        _ isSelected: Bool,
        result: SearchResult,
        context: TMDbSelectionContext
    ) {
        if isSelected {
            _ = insertResult(result, context: context)
        } else {
            _ = removeResult(result, context: context)
        }
        syncSeriesSelectionState(for: result, context: context, isSelected: isSelected)
    }

    private func syncSeriesSelectionState(
        for result: SearchResult,
        context: TMDbSelectionContext,
        isSelected: Bool
    ) {
        switch result.type {
        case .series:
            var state = seriesSelectionState(forSeriesID: result.tmdbID, context: context)
            state.selectedMode = .series
            setSeriesSelectionState(state, forSeriesID: result.tmdbID, context: context)
        case .season(_, let parentSeriesID):
            var state = seriesSelectionState(forSeriesID: parentSeriesID, context: context)
            state.selectedMode = .season
            if isSelected {
                state.selectedSeasonIDs.insert(result.tmdbID)
            } else {
                state.selectedSeasonIDs.remove(result.tmdbID)
            }
            setSeriesSelectionState(state, forSeriesID: parentSeriesID, context: context)
        case .movie:
            break
        }
    }

    private func seriesSelectionState(
        forSeriesID seriesID: Int,
        context: TMDbSelectionContext
    ) -> TMDbSeriesSelectionState {
        switch context {
        case .regular:
            regularSeriesSelectionStates[seriesID] ?? .init()
        case .batch:
            batchSeriesSelectionStates[seriesID] ?? .init()
        }
    }

    private func setSeriesSelectionState(
        _ state: TMDbSeriesSelectionState,
        forSeriesID seriesID: Int,
        context: TMDbSelectionContext
    ) {
        switch context {
        case .regular:
            regularSeriesSelectionStates[seriesID] = state
        case .batch:
            batchSeriesSelectionStates[seriesID] = state
        }
    }

    private func clearSeasonSelections(
        forSeriesID seriesID: Int,
        context: TMDbSelectionContext,
        state: inout TMDbSeriesSelectionState
    ) {
        for season in state.seasons where state.selectedSeasonIDs.contains(season.tmdbID) {
            _ = removeResult(.init(tmdbID: season.tmdbID, type: season.type), context: context)
        }
        state.selectedSeasonIDs.removeAll()
    }

    private func clearSelections(in context: TMDbSelectionContext) {
        switch context {
        case .regular:
            regularResultsToSubmit.removeAll()
            regularSeriesSelectionStates.removeAll()
        case .batch:
            batchResultsToSubmit.removeAll()
            batchSeriesSelectionStates.removeAll()
        }
    }

    private func selectionContextLabel(_ context: TMDbSelectionContext) -> String {
        switch context {
        case .regular:
            "regular"
        case .batch:
            "batch"
        }
    }

    private func fetchSeasonsIfNeeded(
        for seriesInfo: BasicInfo,
        language: Language,
        context: TMDbSelectionContext
    ) async {
        var state = seriesSelectionState(forSeriesID: seriesInfo.tmdbID, context: context)
        guard state.seasonFetchStatus == .notStarted else { return }

        state.seasonFetchStatus = .fetching
        setSeriesSelectionState(state, forSeriesID: seriesInfo.tmdbID, context: context)

        let generation = context == .batch ? batchSearchGeneration : nil
        let seasons = await fetchSeasons(for: seriesInfo, language: language)

        if let generation, generation != batchSearchGeneration {
            return
        }

        state = seriesSelectionState(forSeriesID: seriesInfo.tmdbID, context: context)
        state.seasons = seasons
        state.seasonFetchStatus = .fetched
        state.selectedSeasonIDs.formIntersection(Set(seasons.map(\.tmdbID)))
        setSeriesSelectionState(state, forSeriesID: seriesInfo.tmdbID, context: context)
    }

    private func fetchSeasons(for seriesInfo: BasicInfo, language: Language) async -> [BasicInfo] {
        do {
            return try await client.fetchSeasons(seriesInfo, language)
        } catch {
            logger.error("Error fetching seasons for series \(seriesInfo.tmdbID): \(error)")
            status = .error(error)
            ToastCenter.global.completionState = .failed("Network Error!")
            return []
        }
    }

    enum Status {
        case loading
        case loaded
        case error(Error)
    }

    enum BatchStatus {
        case idle
        case loading
        case loaded
        case error(Error)
    }
}

extension TMDbSearchService.Status: Equatable {
    static func == (lhs: TMDbSearchService.Status, rhs: TMDbSearchService.Status) -> Bool {
        switch (lhs, rhs) {
        case (.loading, .loading), (.loaded, .loaded):
            return true
        case (.error(let e1), .error(let e2)):
            return (e1 as NSError).domain == (e2 as NSError).domain
                && (e1 as NSError).code == (e2 as NSError).code
        default:
            return false
        }
    }
}

extension TMDbSearchService.BatchStatus: Equatable {
    static func == (lhs: TMDbSearchService.BatchStatus, rhs: TMDbSearchService.BatchStatus) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading), (.loaded, .loaded):
            return true
        case (.error(let e1), .error(let e2)):
            return (e1 as NSError).domain == (e2 as NSError).domain
                && (e1 as NSError).code == (e2 as NSError).code
        default:
            return false
        }
    }
}
