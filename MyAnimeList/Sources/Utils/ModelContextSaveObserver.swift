//
//  ModelContextSaveObserver.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/6/11.
//

import Combine
import Foundation
import SwiftData

struct ModelContextSaveChanges: Sendable {
    var insertedIdentifiers: Set<PersistentIdentifier>
    var updatedIdentifiers: Set<PersistentIdentifier>
    var deletedIdentifiers: Set<PersistentIdentifier>

    init(
        insertedIdentifiers: Set<PersistentIdentifier>,
        updatedIdentifiers: Set<PersistentIdentifier>,
        deletedIdentifiers: Set<PersistentIdentifier>
    ) {
        self.insertedIdentifiers = insertedIdentifiers
        self.updatedIdentifiers = updatedIdentifiers
        self.deletedIdentifiers = deletedIdentifiers
    }

    init(from notification: Notification) {
        self.init(
            insertedIdentifiers: Self.persistentIdentifiers(for: .insertedIdentifiers, in: notification),
            updatedIdentifiers: Self.persistentIdentifiers(for: .updatedIdentifiers, in: notification),
            deletedIdentifiers: Self.persistentIdentifiers(for: .deletedIdentifiers, in: notification)
        )
    }

    private static func persistentIdentifiers(
        for key: ModelContext.NotificationKey,
        in notification: Notification
    ) -> Set<PersistentIdentifier> {
        if let identifiers = notification.userInfo?[key.rawValue] as? Set<PersistentIdentifier> {
            return identifiers
        }
        if let identifiers = notification.userInfo?[key.rawValue] as? [PersistentIdentifier] {
            return Set(identifiers)
        }
        return []
    }
}

final class ModelContextSaveObserver {
    private var cancellable: AnyCancellable?

    init(
        notificationCenter: NotificationCenter = .default,
        handler: @escaping @MainActor (ModelContextSaveChanges) -> Void
    ) {
        cancellable = Self.makeCancellable(
            notificationCenter: notificationCenter,
            handler: handler
        )
    }

    private static func makeCancellable(
        notificationCenter: NotificationCenter,
        handler: @escaping @MainActor (ModelContextSaveChanges) -> Void
    ) -> AnyCancellable {
        notificationCenter
            .publisher(for: ModelContext.didSave)
            .sink { notification in
                routeSaveNotification(notification, to: handler)
            }
    }

    private static func routeSaveNotification(
        _ notification: Notification,
        to handler: @escaping @MainActor (ModelContextSaveChanges) -> Void
    ) {
        let changes = ModelContextSaveChanges(from: notification)
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                handler(changes)
            }
        } else {
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    handler(changes)
                }
            }
        }
    }
}
