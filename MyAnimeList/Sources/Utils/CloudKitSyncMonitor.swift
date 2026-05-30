//
//  CloudKitSyncMonitor.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on 2026/5/30.
//

import CoreData
import Foundation

@Observable
@MainActor
final class CloudKitSyncMonitor {
    enum Status: Equatable {
        case idle
        case importing
        case exporting
        case error(String)
    }

    private var observation: NotificationObservation?

    private(set) var status: Status = .idle

    init(notificationCenter: NotificationCenter = .default) {
        self.observation = NotificationObservation(
            notificationCenter: notificationCenter,
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
        ) { [weak self] notification in
            let status = Self.status(from: notification)
            Task { @MainActor [weak self] in
                self?.status = status
            }
        }
    }

    private nonisolated static func status(from notification: Notification) -> Status {
        guard
            let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event
        else {
            return .idle
        }

        if let error = event.error {
            return .error(error.localizedDescription)
        }

        if event.endDate != nil {
            return .idle
        }

        switch event.type {
        case .import:
            return .importing
        case .export:
            return .exporting
        default:
            return .idle
        }
    }
}

fileprivate final class NotificationObservation {
    private let notificationCenter: NotificationCenter
    private let observer: NSObjectProtocol

    init(
        notificationCenter: NotificationCenter,
        forName name: Notification.Name,
        using block: @escaping @Sendable (Notification) -> Void
    ) {
        self.notificationCenter = notificationCenter
        observer = notificationCenter.addObserver(
            forName: name,
            object: nil,
            queue: .main,
            using: block)
    }

    deinit {
        notificationCenter.removeObserver(observer)
    }
}
