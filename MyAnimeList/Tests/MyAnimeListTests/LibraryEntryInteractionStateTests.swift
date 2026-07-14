//
//  LibraryEntryInteractionStateTests.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/7/14.
//

import DataProvider
import Testing

@testable import MyAnimeList

struct LibraryEntryInteractionStateTests {
    @Test @MainActor func focusingDoesNotPresentDetail() {
        let state = LibraryEntryInteractionState()
        let entry = AnimeEntry.template(id: 42)

        state.focus(entry)

        #expect(state.focusedEntryID == entry.syncIdentity)
        #expect(state.presentedDetailEntryID == nil)
    }

    @Test @MainActor func openingDetailSetsFocusAndPresentationIndependently() throws {
        let state = LibraryEntryInteractionState()
        let entry = AnimeEntry.template(id: 42)

        state.openDetails(for: entry)

        let presentation = try #require(state.detailPresentation)
        #expect(state.focusedEntryID == entry.syncIdentity)
        #expect(state.presentedDetailEntryID == entry.syncIdentity)
        #expect(presentation.entryIdentity == entry.syncIdentity)

        state.dismissDetails()

        #expect(state.focusedEntryID == entry.syncIdentity)
        #expect(state.presentedDetailEntryID == nil)
    }

    @Test @MainActor func editingPresentsDetailAndRequestsTheEditingSection() throws {
        let state = LibraryEntryInteractionState()
        let entry = AnimeEntry.template(id: 42)

        state.setEditingEntry(entry)

        let request = try #require(state.detailEditRequest)
        #expect(state.focusedEntryID == entry.syncIdentity)
        #expect(state.presentedDetailEntryID == entry.syncIdentity)
        #expect(request.entryIdentity == entry.syncIdentity)
        #expect(state.activeWorkflow == nil)

        state.consumeDetailEditRequest(request.id)

        #expect(state.detailEditRequest == nil)
        #expect(state.presentedDetailEntryID == entry.syncIdentity)
    }

    @Test @MainActor func multiSelectionDoesNotReplaceFocusedEntry() {
        let state = LibraryEntryInteractionState()
        let entry = AnimeEntry.template(id: 42)
        state.focus(entry)

        state.enterMultiSelection()
        state.toggleSelection(for: 7)
        state.toggleSelection(for: 9)

        #expect(state.focusedEntryID == entry.syncIdentity)
        #expect(state.selectedEntryIDs == [7, 9])
    }

    @Test @MainActor func workflowPresentationsUseTypeQualifiedIdentity() throws {
        let state = LibraryEntryInteractionState()
        let movie = AnimeEntry(name: "Movie", type: .movie, tmdbID: 42)
        let series = AnimeEntry(name: "Series", type: .series, tmdbID: 42)

        state.presentWorkflow(.sharing(movie.syncIdentity))
        #expect(state.activeWorkflow == .sharing(movie.syncIdentity))

        state.presentWorkflow(.sharing(series.syncIdentity))

        let presentation = try #require(state.workflowPresentation)
        #expect(presentation.workflow == .sharing(series.syncIdentity))
        #expect(movie.syncIdentity != series.syncIdentity)
    }

    @Test @MainActor func openingAnotherEntryClearsPendingEditingIntent() {
        let state = LibraryEntryInteractionState()
        let firstEntry = AnimeEntry.template(id: 42)
        let secondEntry = AnimeEntry.template(id: 43)
        state.setEditingEntry(firstEntry)

        state.openDetails(for: secondEntry)

        #expect(state.presentedDetailEntryID == secondEntry.syncIdentity)
        #expect(state.detailEditRequest == nil)
    }

    @Test @MainActor func newerWorkflowSupersedesPendingEditWithoutRetiringDetail() {
        let state = LibraryEntryInteractionState()
        let entry = AnimeEntry.template(id: 42)
        state.setEditingEntry(entry)
        let detailPresentationID = state.detailPresentation?.id

        state.presentWorkflow(.sharing(entry.syncIdentity))

        #expect(state.detailEditRequest == nil)
        #expect(state.detailPresentation?.id == detailPresentationID)
        #expect(state.activeWorkflow == .sharing(entry.syncIdentity))
    }

    @Test @MainActor func pasteConfirmationResolvesTheCurrentModelByIdentity() throws {
        let state = LibraryEntryInteractionState()
        let original = AnimeEntry.template(id: 42)
        original.notes = "Original model"
        let replacement = AnimeEntry.template(id: 42)
        replacement.notes = "Replacement model"
        let source = AnimeEntry.template(id: 99)
        source.notes = "Pasted note"

        state.preparePaste(source.userInfo, for: original)
        let request = try #require(state.pendingPasteRequest)
        state.confirmPaste(requestID: request.id) { identity in
            identity == replacement.syncIdentity ? replacement : nil
        }

        #expect(original.notes == "Original model")
        #expect(replacement.notes == "Pasted note")
        #expect(state.pendingPasteRequest == nil)
    }

    @Test @MainActor func stalePasteCallbacksCannotAffectANewerRequest() throws {
        let state = LibraryEntryInteractionState()
        let first = AnimeEntry.template(id: 41)
        first.notes = "First original"
        let second = AnimeEntry.template(id: 42)
        second.notes = "Second original"
        let firstSource = AnimeEntry.template(id: 91)
        firstSource.notes = "First pasted"
        let secondSource = AnimeEntry.template(id: 92)
        secondSource.notes = "Second pasted"

        state.preparePaste(firstSource.userInfo, for: first)
        let firstRequest = try #require(state.pendingPasteRequest)
        state.preparePaste(secondSource.userInfo, for: second)
        let secondRequest = try #require(state.pendingPasteRequest)
        var staleConfirmationResolved = false

        state.confirmPaste(requestID: firstRequest.id) { _ in
            staleConfirmationResolved = true
            return second
        }
        state.clearPasteRequest(requestID: firstRequest.id)

        #expect(!staleConfirmationResolved)
        #expect(state.pendingPasteRequest?.id == secondRequest.id)
        #expect(second.notes == "Second original")

        state.confirmPaste(requestID: secondRequest.id) { _ in second }

        #expect(second.notes == "Second pasted")
        #expect(state.pendingPasteRequest == nil)
    }

    @Test @MainActor func unresolvedPasteConfirmationClearsTheRequest() throws {
        let state = LibraryEntryInteractionState()
        let target = AnimeEntry.template(id: 42)
        target.notes = "Existing note"
        let source = AnimeEntry.template(id: 99)
        source.notes = "Pasted note"
        state.preparePaste(source.userInfo, for: target)
        let request = try #require(state.pendingPasteRequest)

        state.confirmPaste(requestID: request.id) { _ in nil }

        #expect(target.notes == "Existing note")
        #expect(state.pendingPasteRequest == nil)
    }

    @Test @MainActor func pasteIntoEmptyEntryAppliesImmediatelyWithoutARequest() {
        let state = LibraryEntryInteractionState()
        let target = AnimeEntry.template(id: 42)
        let source = AnimeEntry.template(id: 99)
        source.notes = "Pasted note"

        state.preparePaste(source.userInfo, for: target)

        #expect(target.notes == "Pasted note")
        #expect(state.pendingPasteRequest == nil)
    }

    @Test @MainActor func currentDetailDismissalClosesDetail() throws {
        let state = LibraryEntryInteractionState()
        let entry = AnimeEntry.template(id: 42)
        state.openDetails(for: entry)
        let presentation = try #require(state.detailPresentation)

        state.detailPresentationDidDismiss(presentation)

        #expect(state.presentedDetailEntryID == nil)
    }

    @Test @MainActor func staleDetailDismissalCannotCloseAReopenedDetail() throws {
        let state = LibraryEntryInteractionState()
        let entry = AnimeEntry.template(id: 42)
        state.openDetails(for: entry)
        let firstPresentation = try #require(state.detailPresentation)

        state.dismissDetails()
        state.openDetails(for: entry)
        let secondPresentation = try #require(state.detailPresentation)
        state.detailPresentationDidDismiss(firstPresentation)
        state.dismissDetails(ifPresentationID: firstPresentation.id)

        #expect(firstPresentation.id != secondPresentation.id)
        #expect(state.detailPresentation?.id == secondPresentation.id)
        #expect(state.presentedDetailEntryID == entry.syncIdentity)
    }

    @Test @MainActor func replacingDetailRejectsOldPresentationCallbacks() throws {
        let state = LibraryEntryInteractionState()
        let first = AnimeEntry.template(id: 42)
        let second = AnimeEntry.template(id: 43)
        state.openDetails(for: first)
        let firstPresentation = try #require(state.detailPresentation)

        state.openDetails(for: second)
        let secondPresentation = try #require(state.detailPresentation)
        state.detailPresentationDidDismiss(firstPresentation)
        state.dismissDetails(ifPresentationID: firstPresentation.id)

        #expect(firstPresentation.id != secondPresentation.id)
        #expect(state.detailPresentation?.id == secondPresentation.id)
        #expect(state.presentedDetailEntryID == second.syncIdentity)
    }

    @Test @MainActor func staleWorkflowDismissalCannotCloseAReopenedWorkflow() throws {
        let state = LibraryEntryInteractionState()
        let entry = AnimeEntry.template(id: 42)
        let workflow = LibraryEntryWorkflow.sharing(entry.syncIdentity)
        state.presentWorkflow(workflow)
        let firstPresentation = try #require(state.workflowPresentation)
        state.workflowPresentationDidDismiss(firstPresentation)

        state.presentWorkflow(workflow)
        let secondPresentation = try #require(state.workflowPresentation)
        state.workflowPresentationDidDismiss(firstPresentation)

        #expect(firstPresentation.id != secondPresentation.id)
        #expect(state.workflowPresentation?.id == secondPresentation.id)
        #expect(state.activeWorkflow == workflow)
    }

    @Test @MainActor func workflowDoesNotRetirePresentedDetail() throws {
        let state = LibraryEntryInteractionState()
        let entry = AnimeEntry.template(id: 42)
        state.openDetails(for: entry)
        let detailPresentation = try #require(state.detailPresentation)

        state.presentWorkflow(.sharing(entry.syncIdentity))

        #expect(state.detailPresentation?.id == detailPresentation.id)
        #expect(state.workflowPresentation?.workflow == .sharing(entry.syncIdentity))
    }

    @Test func detailActivationRespectsLayoutAndUserPreference() {
        #expect(!LibraryEntryDetailActivation.userPreference.usesSingleTap(userPreference: false))
        #expect(LibraryEntryDetailActivation.userPreference.usesSingleTap(userPreference: true))
        #expect(LibraryEntryDetailActivation.singleTap.usesSingleTap(userPreference: false))
        #expect(LibraryEntryDetailActivation.singleTap.usesSingleTap(userPreference: true))
    }

    @Test @MainActor func switchingDetailEntriesKeepsPresentationWhileSessionCatchesUp() {
        let repository = LibraryRepository(dataProvider: DataProvider(inMemory: true))
        let state = LibraryEntryInteractionState()
        let sessionStore = EntryDetailSessionStore()
        let first = AnimeEntry.template(id: 42)
        let second = AnimeEntry.template(id: 43)
        let entries = [first.syncIdentity: first, second.syncIdentity: second]

        state.openDetails(for: first)
        sessionStore.synchronizePresentedDetail(
            identity: first.syncIdentity,
            repository: repository,
            resolveEntry: { entries[$0] }
        )

        state.openDetails(for: second)

        #expect(state.isPresentingDetail)
        #expect(sessionStore.session(for: second.syncIdentity) == nil)

        sessionStore.synchronizePresentedDetail(
            identity: second.syncIdentity,
            repository: repository,
            resolveEntry: { entries[$0] }
        )

        #expect(state.isPresentingDetail)
        #expect(sessionStore.session(for: second.syncIdentity)?.entryIdentity == second.syncIdentity)
    }
}
