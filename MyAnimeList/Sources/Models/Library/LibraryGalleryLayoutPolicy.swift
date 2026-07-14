//
//  LibraryGalleryLayoutPolicy.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/7/14.
//

import SwiftUI

/// Selects the Gallery arrangement from the space available to Gallery itself.
struct LibraryGalleryLayoutPolicy {
    struct GeometryTokens: Equatable {
        var minimumShelfHeight: CGFloat = 480
        var verticalChromeHeight: CGFloat = 160
        var minimumCardWidth: CGFloat = 220
        var maximumCardWidth: CGFloat = 420
        var cardSpacing: CGFloat = 24
        var visibleCardSpan: CGFloat = 1.55

        static let standard = GeometryTokens()
    }

    enum Arrangement: Equatable {
        case singlePage
        case shelf(cardWidth: CGFloat)
    }

    struct Input: Equatable {
        var availableSize: CGSize
        var dynamicTypeSize: DynamicTypeSize

        init(
            availableSize: CGSize,
            dynamicTypeSize: DynamicTypeSize = .large
        ) {
            self.availableSize = availableSize
            self.dynamicTypeSize = dynamicTypeSize
        }
    }

    var tokens: GeometryTokens

    init(tokens: GeometryTokens = .standard) {
        self.tokens = tokens
    }

    func arrangement(for input: Input) -> Arrangement {
        let scale = contentScale(for: input.dynamicTypeSize)
        guard input.availableSize.height >= tokens.minimumShelfHeight * scale else {
            return .singlePage
        }

        let availableCardHeight = max(
            0,
            input.availableSize.height - tokens.verticalChromeHeight * scale
        )
        let heightDerivedCardWidth = availableCardHeight * 2 / 3
        let cardWidth = min(
            max(heightDerivedCardWidth, tokens.minimumCardWidth * scale),
            tokens.maximumCardWidth * scale
        )
        let requiredWidth =
            cardWidth * tokens.visibleCardSpan
            + tokens.cardSpacing * scale

        guard input.availableSize.width >= requiredWidth else {
            return .singlePage
        }

        return .shelf(cardWidth: cardWidth)
    }

    private func contentScale(for dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        switch dynamicTypeSize {
        case .xSmall, .small, .medium, .large:
            1
        case .xLarge:
            1.04
        case .xxLarge:
            1.08
        case .xxxLarge:
            1.14
        case .accessibility1:
            1.2
        case .accessibility2:
            1.3
        case .accessibility3:
            1.42
        case .accessibility4:
            1.56
        case .accessibility5:
            1.72
        @unknown default:
            1
        }
    }
}
