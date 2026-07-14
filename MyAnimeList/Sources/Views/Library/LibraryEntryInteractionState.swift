//
//  LibraryEntryInteractionState.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/10/13.
//

import DataProvider
import LibrarySync
import Observation
import SwiftUI
import UIKit

enum LibraryEntryWorkflow: Identifiable, Equatable, Sendable {
    case posterSelection(LibraryEntrySyncIdentity)
    case sharing(LibraryEntrySyncIdentity)

    var id: String {
        switch self {
        case .posterSelection(let identity):
            "poster:\(identity.rawID)"
        case .sharing(let identity):
            "sharing:\(identity.rawID)"
        }
    }

    var entryIdentity: LibraryEntrySyncIdentity {
        switch self {
        case .posterSelection(let identity),
            .sharing(let identity):
            identity
        }
    }
}

struct LibraryEntryDetailEditRequest: Equatable, Sendable {
    let id = UUID()
    let entryIdentity: LibraryEntrySyncIdentity
}

struct LibraryEntryPasteRequest: Identifiable, Equatable {
    let id = UUID()
    let entryIdentity: LibraryEntrySyncIdentity
    let userInfo: UserEntryInfo
}

struct LibraryEntryDetailPresentation: Identifiable, Equatable, Sendable {
    let id = UUID()
    let entryIdentity: LibraryEntrySyncIdentity
}

struct LibraryEntryWorkflowPresentation: Identifiable, Equatable, Sendable {
    let id = UUID()
    let workflow: LibraryEntryWorkflow
}

@Observable
@MainActor
final class LibraryEntryInteractionState {
    var focusedEntryID: LibraryEntrySyncIdentity?
    private(set) var detailEditRequest: LibraryEntryDetailEditRequest?
    var deletingEntryID: LibraryEntrySyncIdentity?
    private(set) var pendingPasteRequest: LibraryEntryPasteRequest?
    var isMultiSelecting: Bool = false
    var selectedEntryIDs: Set<Int> = []
    private(set) var detailPresentation: LibraryEntryDetailPresentation?
    private(set) var workflowPresentation: LibraryEntryWorkflowPresentation?

    var presentedDetailEntryID: LibraryEntrySyncIdentity? {
        detailPresentation?.entryIdentity
    }

    var activeWorkflow: LibraryEntryWorkflow? {
        workflowPresentation?.workflow
    }

    var selectedEntryCount: Int {
        selectedEntryIDs.count
    }

    var isDeletingEntry: Bool {
        deletingEntryID != nil
    }

    var isPresentingDetail: Bool {
        presentedDetailEntryID != nil
    }

    func focus(_ entry: AnimeEntry) {
        focusedEntryID = entry.syncIdentity
    }

    func focus(entryID: LibraryEntrySyncIdentity?) {
        focusedEntryID = entryID
    }

    func openDetails(for entry: AnimeEntry) {
        if detailEditRequest?.entryIdentity != entry.syncIdentity {
            detailEditRequest = nil
        }
        focus(entry)
        detailPresentation = LibraryEntryDetailPresentation(entryIdentity: entry.syncIdentity)
    }

    func dismissDetails() {
        detailPresentation = nil
        detailEditRequest = nil
    }

    func dismissDetails(ifPresentationID presentationID: UUID) {
        guard detailPresentation?.id == presentationID else { return }
        dismissDetails()
    }

    func detailPresentationDidDismiss(_ presentation: LibraryEntryDetailPresentation) {
        guard detailPresentation?.id == presentation.id else { return }
        dismissDetails()
    }

    func presentWorkflow(_ workflow: LibraryEntryWorkflow) {
        detailEditRequest = nil
        workflowPresentation = LibraryEntryWorkflowPresentation(workflow: workflow)
    }

    func workflowPresentationDidDismiss(_ presentation: LibraryEntryWorkflowPresentation) {
        guard workflowPresentation?.id == presentation.id else { return }
        workflowPresentation = nil
    }

    func isCurrentDetailPresentation(_ presentationID: UUID) -> Bool {
        detailPresentation?.id == presentationID
    }

    func enterMultiSelection() {
        isMultiSelecting = true
    }

    func exitMultiSelection() {
        isMultiSelecting = false
        selectedEntryIDs.removeAll()
    }

    func toggleSelection(for entryID: Int) {
        if selectedEntryIDs.contains(entryID) {
            selectedEntryIDs.remove(entryID)
        } else {
            selectedEntryIDs.insert(entryID)
        }
    }

    func isSelected(_ entryID: Int) -> Bool {
        selectedEntryIDs.contains(entryID)
    }

    func selectedEntries(from entries: [AnimeEntry]) -> [AnimeEntry] {
        entries.filter { selectedEntryIDs.contains($0.tmdbID) }
    }

    func prepareDeletion(for entry: AnimeEntry) {
        deletingEntryID = entry.syncIdentity
    }

    func confirmDeletion(
        resolveEntry: (LibraryEntrySyncIdentity) -> AnimeEntry?,
        deleteEntry: (AnimeEntry) -> Void
    ) {
        guard let identity = deletingEntryID,
            let entry = resolveEntry(identity)
        else { return }

        clearDeletionRequest()
        deleteEntry(entry)
    }

    func clearDeletionRequest() {
        deletingEntryID = nil
    }

    func setEditingEntry(_ entry: AnimeEntry) {
        detailEditRequest = LibraryEntryDetailEditRequest(
            entryIdentity: entry.syncIdentity
        )
        openDetails(for: entry)
    }

    func consumeDetailEditRequest(_ requestID: UUID) {
        guard detailEditRequest?.id == requestID else { return }
        detailEditRequest = nil
    }

    func pasteInfo(for entry: AnimeEntry) {
        guard let pasted = UserEntryInfo.fromPasteboard() else {
            ToastCenter.global.completionState = .init(
                state: .failed,
                messageResource: "No info found on pasteboard."
            )
            return
        }
        preparePaste(pasted, for: entry)
    }

    func preparePaste(_ userInfo: UserEntryInfo, for entry: AnimeEntry) {
        if entry.userInfo.isEmpty {
            entry.updateUserInfoFromUserAction(userInfo)
            ToastCenter.global.pasted = true
        } else {
            pendingPasteRequest = LibraryEntryPasteRequest(
                entryIdentity: entry.syncIdentity,
                userInfo: userInfo
            )
        }
    }

    func confirmPaste(
        requestID: UUID,
        resolveEntry: (LibraryEntrySyncIdentity) -> AnimeEntry?
    ) {
        guard let request = pendingPasteRequest,
            request.id == requestID
        else { return }

        pendingPasteRequest = nil
        guard let entry = resolveEntry(request.entryIdentity) else { return }
        entry.updateUserInfoFromUserAction(request.userInfo)
        ToastCenter.global.pasted = true
    }

    func clearPasteRequest(requestID: UUID) {
        guard pendingPasteRequest?.id == requestID else { return }
        pendingPasteRequest = nil
    }

    func highlightBinding(for entry: AnimeEntry, highlightedEntryID: Binding<Int?>) -> Binding<Bool> {
        highlightBinding(for: entry.tmdbID, highlightedEntryID: highlightedEntryID)
    }

    func highlightBinding(for entryID: Int, highlightedEntryID: Binding<Int?>) -> Binding<Bool> {
        Binding(
            get: { highlightedEntryID.wrappedValue == entryID },
            set: { if !$0 { highlightedEntryID.wrappedValue = nil } }
        )
    }
}

enum LibraryEntryDetailActivation: Equatable, Sendable {
    case userPreference
    case singleTap

    func usesSingleTap(userPreference: Bool) -> Bool {
        self == .singleTap || userPreference
    }
}

fileprivate struct LibraryEntryDetailActivationKey: EnvironmentKey {
    static let defaultValue = LibraryEntryDetailActivation.userPreference
}

extension EnvironmentValues {
    var libraryEntryDetailActivation: LibraryEntryDetailActivation {
        get { self[LibraryEntryDetailActivationKey.self] }
        set { self[LibraryEntryDetailActivationKey.self] = newValue }
    }

    @Entry var libraryEntryOpenDetailAction: ((AnimeEntry) -> Void)?
    @Entry var libraryEntryEditAction: ((AnimeEntry) -> Void)?
}

extension LibraryEntryInteractionState {
    func favoriteButton(for entry: AnimeEntry, toggleFavorite: @escaping (AnimeEntry) -> Void) -> some View {
        EntryFavoriteButton(favorited: entry.favorite) {
            toggleFavorite(entry)
            if entry.favorite {
                ToastCenter.global.favorited = true
            } else {
                ToastCenter.global.unFavorited = true
            }
        }
    }

    func shareButton(for entry: AnimeEntry) -> some View {
        Button("Share", systemImage: "square.and.arrow.up") {
            self.presentWorkflow(.sharing(entry.syncIdentity))
        }
    }

    func editButton(
        for entry: AnimeEntry,
        editEntry: ((AnimeEntry) -> Void)? = nil
    ) -> some View {
        Button("Edit", systemImage: "pencil") {
            if let editEntry {
                editEntry(entry)
            } else {
                self.setEditingEntry(entry)
            }
        }
    }

    func switchPosterButton(for entry: AnimeEntry) -> some View {
        Button("Switch Poster", systemImage: "photo.badge.magnifyingglass") {
            self.presentWorkflow(.posterSelection(entry.syncIdentity))
        }
    }

    @ViewBuilder
    func savePosterButton(for entry: AnimeEntry) -> some View {
        if let posterURL = entry.posterURL {
            ShareLink(item: posterURL) {
                Label("Save Poster", systemImage: "photo.badge.arrow.down")
            }
        }
    }

    func userInfoMenu(for entry: AnimeEntry) -> some View {
        Menu("User Info", systemImage: "person.crop.circle") {
            Button("Copy Info", systemImage: "doc.on.doc") {
                entry.userInfo.copyToPasteboard()
                ToastCenter.global.copied = true
            }
            Button("Paste Info", systemImage: "doc.on.clipboard") {
                self.pasteInfo(for: entry)
            }
            .disabled(
                !UIPasteboard.general.contains(
                    pasteboardTypes: [UserEntryInfo.pasteboardUTType.identifier]
                )
            )
        }
    }

    func deleteButton(for entry: AnimeEntry) -> some View {
        Button("Delete", systemImage: "trash", role: .destructive) {
            self.prepareDeletion(for: entry)
        }
    }

    @ViewBuilder
    func contextMenu(
        for entry: AnimeEntry,
        toggleFavorite: @escaping (AnimeEntry) -> Void,
        editEntry: ((AnimeEntry) -> Void)? = nil
    ) -> some View {
        ControlGroup {
            favoriteButton(for: entry, toggleFavorite: toggleFavorite)
            shareButton(for: entry)
        }
        editButton(for: entry, editEntry: editEntry)
        switchPosterButton(for: entry)
        Divider()
        savePosterButton(for: entry)
        userInfoMenu(for: entry)
        deleteButton(for: entry)
    }
}

extension View {
    func libraryEntryInteractionOverlays(
        state: LibraryEntryInteractionState,
        deleteEntry: @escaping (AnimeEntry) -> Void,
        resolveEntry: @escaping (LibraryEntrySyncIdentity) -> AnimeEntry?
    ) -> some View {
        let presentedWorkflow = state.workflowPresentation
        let presentedPasteRequest = state.pendingPasteRequest
        let activeWorkflow = Binding<LibraryEntryWorkflowPresentation?>(
            get: { state.workflowPresentation },
            set: { destination in
                guard destination == nil, let presentedWorkflow else { return }
                state.workflowPresentationDidDismiss(presentedWorkflow)
            }
        )

        return
            self
            .alert(
                "Delete Anime?",
                isPresented: Binding(
                    get: { state.isDeletingEntry },
                    set: {
                        if !$0 {
                            state.clearDeletionRequest()
                        }
                    }
                ),
                presenting: state.deletingEntryID.flatMap(resolveEntry)
            ) { _ in
                Button("Delete", role: .destructive) {
                    state.confirmDeletion(
                        resolveEntry: resolveEntry,
                        deleteEntry: deleteEntry
                    )
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert(
                "Paste Info?",
                isPresented: Binding(
                    get: {
                        guard let requestID = presentedPasteRequest?.id else { return false }
                        return state.pendingPasteRequest?.id == requestID
                    },
                    set: { isPresented in
                        guard !isPresented,
                            let requestID = presentedPasteRequest?.id
                        else { return }
                        state.clearPasteRequest(requestID: requestID)
                    }
                ),
                presenting: presentedPasteRequest
            ) { request in
                Button("Paste", role: .destructive) {
                    state.confirmPaste(
                        requestID: request.id,
                        resolveEntry: resolveEntry
                    )
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("This anime already has edits. Pasting will overwrite current info.")
            }
            .sheet(
                item: activeWorkflow
            ) { presentation in
                if let entry = resolveEntry(presentation.workflow.entryIdentity) {
                    switch presentation.workflow {
                    case .posterSelection:
                        NavigationStack {
                            PosterSelectionView(
                                tmdbID: entry.tmdbID,
                                type: entry.type,
                                originalPosterLanguageCode: entry.originalLanguageCode
                                    ?? entry.parentSeriesEntry?.originalLanguageCode
                            ) { url in
                                if url != entry.posterURL
                                    || !entry.usingCustomPoster
                                {
                                    entry.updateCustomPosterURL(url)
                                }
                            }
                            .navigationTitle("Pick a poster")
                        }
                    case .sharing:
                        AnimeSharingSheet(entry: entry)
                    }
                }
            }
    }
}
