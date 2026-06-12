//
//  MyAnimeListTestSupport.swift
//  MyAnimeListTests
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/10.
//

import Foundation
import SwiftData
import TMDb
import Testing

import struct TMDb.ImagesConfiguration

@testable import DataProvider
@testable import MyAnimeList

func referenceDate(year: Int, month: Int, day: Int) -> Date {
    Calendar(identifier: .gregorian).date(
        from: DateComponents(year: year, month: month, day: day)
    )!
}

@MainActor
func withRestoredLibrarySortingPreferences(_ body: () throws -> Void) throws {
    let defaults = UserDefaults.standard
    let keys = [
        String.libraryGroupStrategy,
        String.librarySortStrategy,
        String.librarySortReversed
    ]
    let originalValues = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })

    defer {
        for key in keys {
            if let value = originalValues[key] {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }

    try body()
}

func makeLibraryEntry(
    name: String,
    tmdbID: Int,
    watchStatus: AnimeEntry.WatchStatus = .planToWatch,
    daySaved: Int,
    score: Int? = nil,
    favorite: Bool = false
) -> AnimeEntry {
    let entry = AnimeEntry(
        name: name,
        type: .movie,
        tmdbID: tmdbID,
        dateSaved: referenceDate(year: 2026, month: 1, day: daySaved),
        score: score
    )
    entry.watchStatus = watchStatus
    entry.favorite = favorite
    return entry
}

func makeImagesConfiguration() -> ImagesConfiguration {
    ImagesConfiguration(
        baseURL: URL(string: "https://example.com/images/")!,
        secureBaseURL: URL(string: "https://example.com/images/")!,
        backdropSizes: ["w1280"],
        logoSizes: ["w500"],
        posterSizes: ["w780"],
        profileSizes: ["w185"],
        stillSizes: ["w300"]
    )
}

final class RecordingTMDbHTTPClient: HTTPClient {
    private let recorder = TMDbHTTPRequestRecorder()
    private let responseProvider: @Sendable (HTTPRequest) async throws -> HTTPResponse

    init(
        responseProvider: @escaping @Sendable (HTTPRequest) async throws -> HTTPResponse = { _ in
            HTTPResponse(data: Data(#"{"id":1,"posters":[],"logos":[],"backdrops":[]}"#.utf8))
        }
    ) {
        self.responseProvider = responseProvider
    }

    var requests: [HTTPRequest] {
        get async {
            await recorder.requests
        }
    }

    func perform(request: HTTPRequest) async throws -> HTTPResponse {
        await recorder.record(request)
        return try await responseProvider(request)
    }
}

private actor TMDbHTTPRequestRecorder {
    private var capturedRequests: [HTTPRequest] = []

    var requests: [HTTPRequest] {
        capturedRequests
    }

    func record(_ request: HTTPRequest) {
        capturedRequests.append(request)
    }
}

extension URL {
    func queryValue(named name: String) -> String? {
        URLComponents(url: self, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == name })?
            .value
    }
}

func makeImageMetadata(
    filePath: String,
    width: Int,
    languageCode: String?
) -> ImageMetadata {
    ImageMetadata(
        filePath: URL(string: filePath)!,
        width: width,
        height: Int(Float(width) * 1.5),
        aspectRatio: 2.0 / 3.0,
        voteAverage: nil,
        voteCount: nil,
        languageCode: languageCode
    )
}

@MainActor
func makeWhatsNewController(
    defaults: UserDefaults,
    currentVersion: String,
    entries: [String: WhatsNewEntry]
) -> WhatsNewController {
    WhatsNewController(
        defaults: defaults,
        currentVersion: currentVersion,
        entryProvider: { entries[$0] }
    )
}

func makeWhatsNewEntry(version: String) -> WhatsNewEntry {
    WhatsNewEntry(
        version: version,
        title: "Version \(version)",
        summary: "Release summary",
        highlights: ["A highlight"],
        primaryAction: .init(
            id: "refresh",
            title: "Refresh Metadata",
            systemImage: "arrow.clockwise",
            kind: .refreshMetadata
        )
    )
}
