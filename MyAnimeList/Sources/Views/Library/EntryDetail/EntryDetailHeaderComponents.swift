//
//  EntryDetailHeaderComponents.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/21.
//

import SwiftUI

struct DetailStatCard: View {
    let card: EntryDetailStatCard

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: card.symbolName)
                .font(.headline)
                .foregroundStyle(.blue)
            Text(card.value)
                .font(.title3.weight(.bold))
            Text(String(localized: card.title))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
        .padding(16)
        .popupGlassPanel(cornerRadius: 24)
    }
}

struct EntryDetailQuickActionsRow: View {
    let detailURL: URL?
    let isFavorite: Bool
    let showsConvertAction: Bool
    let conversionInProgress: Bool
    let convertMenuTitle: () -> LocalizedStringResource
    let dropActionTitle: LocalizedStringResource
    let dropActionSystemImage: String
    let dropActionIsDestructive: Bool
    let onShare: () -> Void
    let onToggleFavorite: () -> Void
    let onChangePoster: () -> Void
    let onConvert: () async -> Void
    let onToggleDroppedStatus: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)

            if let detailURL {
                Link(destination: detailURL) {
                    Image(systemName: "safari")
                        .font(.title2)
                        .frame(width: 20, height: 20)
                        .padding(10)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .tint(.primary)
            }

            PopupActionCircleButton(
                systemImage: "square.and.arrow.up",
                verticalOffset: -1,
                action: onShare
            )

            PopupActionCircleButton(
                systemImage: isFavorite ? "heart.fill" : "heart",
                tint: isFavorite ? .pink : .primary,
                action: onToggleFavorite
            )

            Menu {
                Button(action: onChangePoster) {
                    Label(EntryDetailL10n.changePoster, systemImage: "photo.on.rectangle")
                }

                if showsConvertAction {
                    Button {
                        Task { await onConvert() }
                    } label: {
                        Label(convertMenuTitle(), systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(conversionInProgress)
                }

                Divider()

                Button(
                    dropActionTitle,
                    systemImage: dropActionSystemImage,
                    role: dropActionIsDestructive ? .destructive : nil,
                    action: onToggleDroppedStatus
                )
                .tint(dropActionIsDestructive ? .red : .primary)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title2)
                    .frame(width: 20, height: 20)
                    .padding(10)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .tint(.primary)

            Spacer(minLength: 0)
        }
    }
}
