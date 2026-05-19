import DataProvider
import SwiftUI

struct LibraryWatchStatusIndicator: View {
    let status: AnimeEntry.WatchStatus
    var diameter: CGFloat
    var strokeColor: Color = .clear
    var strokeWidth: CGFloat = 0
    var shadowColor: Color = .clear
    var shadowRadius: CGFloat = 0
    var shadowYOffset: CGFloat = 0

    var body: some View {
        Circle()
            .fill(status.libraryTintColor)
            .frame(width: diameter, height: diameter)
            .overlay {
                if strokeWidth > 0 {
                    Circle()
                        .stroke(strokeColor, lineWidth: strokeWidth)
                }
            }
            .shadow(color: shadowColor, radius: shadowRadius, y: shadowYOffset)
    }
}

struct LibraryWatchStatusBadge: View {
    let status: AnimeEntry.WatchStatus

    var body: some View {
        HStack(spacing: 6) {
            LibraryWatchStatusIndicator(status: status, diameter: 5)
            Text(status.localizedStringResource)
                .font(Self.textFont)
                .foregroundStyle(status.libraryTintColor.opacity(0.92))
                .lineLimit(1)
        }
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.vertical, Self.verticalPadding)
        .background {
            Capsule(style: .continuous)
                .fill(status.libraryTintColor.opacity(0.09))
        }
    }

    fileprivate static let horizontalPadding: CGFloat = 8
    fileprivate static let verticalPadding: CGFloat = 4
    fileprivate static let textFont = Font.caption2.weight(.semibold)
    fileprivate static let iconFont = Font.system(size: 10).weight(.semibold)
}

struct LibraryScoreBadge: View {
    enum Style {
        case inline
        case posterOverlay
    }

    @AppStorage(.libraryScoringEnabled) private var scoringEnabled = true

    let score: Int?
    var style: Style = .inline

    var body: some View {
        if scoringEnabled, let score {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Image(systemName: "star.fill")
                    .font(iconFont)
                    .symbolRenderingMode(.hierarchical)
                Text("\(score)")
                    .font(textFont)
                    .monospacedDigit()
            }
            .foregroundStyle(foregroundStyle)
            .lineLimit(1)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background {
                Capsule(style: .continuous)
                    .fill(backgroundStyle)
            }
            .accessibilityLabel(Text("Score \(score)"))
        }
    }

    private var iconFont: Font {
        switch style {
        case .inline: LibraryWatchStatusBadge.iconFont
        case .posterOverlay: .system(size: 10, weight: .bold)
        }
    }

    private var textFont: Font {
        switch style {
        case .inline: LibraryWatchStatusBadge.textFont
        case .posterOverlay: .system(size: 11, weight: .bold)
        }
    }

    private var foregroundStyle: some ShapeStyle {
        switch style {
        case .inline: return .yellow.opacity(0.95)
        case .posterOverlay: return .white.opacity(0.96)
        }
    }

    private var backgroundStyle: some ShapeStyle {
        switch style {
        case .inline: return .yellow.opacity(0.12)
        case .posterOverlay: return .black.opacity(0.38)
        }
    }

    private var horizontalPadding: CGFloat {
        switch style {
        case .inline: 7
        case .posterOverlay: 7
        }
    }

    private var verticalPadding: CGFloat {
        switch style {
        case .inline: 4
        case .posterOverlay: 5
        }
    }
}

struct LibraryFavoriteSymbol: View {
    let isFavorite: Bool
    var font: Font
    var filledColor: Color = .pink.opacity(0.94)
    var emptyColor: Color = .secondary.opacity(0.9)
    var shadowColor: Color = .clear
    var shadowRadius: CGFloat = 0
    var shadowYOffset: CGFloat = 0

    var body: some View {
        Image(systemName: isFavorite ? "heart.fill" : "heart")
            .font(font)
            .foregroundStyle(isFavorite ? filledColor : emptyColor)
            .shadow(color: shadowColor, radius: shadowRadius, y: shadowYOffset)
            .contentTransition(.symbolEffect(.replace))
            .animation(.snappy(duration: 0.18), value: isFavorite)
    }
}

struct LibraryFavoriteToggle<Label: View>: View {
    @Environment(\.toggleFavorite) private var toggleFavorite
    @State private var favoriteOverride: Bool?

    let entry: AnimeEntry
    let displayedIsFavorite: Bool
    private let label: (Bool) -> Label

    init(
        entry: AnimeEntry,
        displayedIsFavorite: Bool? = nil,
        @ViewBuilder label: @escaping (Bool) -> Label
    ) {
        self.entry = entry
        self.displayedIsFavorite = displayedIsFavorite ?? entry.favorite
        self.label = label
    }

    var body: some View {
        Button {
            favoriteOverride = !isFavorite
            toggleFavorite(entry)
        } label: {
            label(isFavorite)
        }
        .buttonStyle(.borderless)
        .sensoryFeedback(.impact, trigger: isFavorite)
        .accessibilityLabel(Text(favoriteActionResource))
        .onChange(of: displayedIsFavorite, initial: true) { _, newValue in
            guard favoriteOverride != nil else { return }
            if favoriteOverride == newValue {
                favoriteOverride = nil
            }
        }
    }

    private var isFavorite: Bool {
        favoriteOverride ?? displayedIsFavorite
    }

    private var favoriteActionResource: LocalizedStringResource {
        isFavorite ? "Unfavorite" : "Favorite"
    }
}

extension AnimeEntry.WatchStatus {
    var libraryTintColor: Color {
        switch self {
        case .planToWatch:
            .secondary
        case .watching:
            .orange
        case .watched:
            .green
        case .dropped:
            .pink
        }
    }
}
