//
//  UserEntryInfo+Pasteboard.swift
//  MyAnimeList
//
//  Created by Samuel He on 7/15/25.
//

import DataProvider
import Foundation
import UIKit
import UniformTypeIdentifiers

extension UserEntryInfo {
    static let pasteboardUTType = UTType("com.samuelhe.myanimelist.userentryinfo")!

    /// Copies the UserEntryInfo to the general pasteboard using both a custom UTI and plain text.
    func copyToPasteboard() {
        guard let data = try? JSONEncoder().encode(self),
            let jsonString = String(data: data, encoding: .utf8)
        else { return }
        UIPasteboard.general.items = [
            [
                Self.pasteboardUTType.identifier: jsonString,
                UTType.plainText.identifier: description
            ]
        ]
    }

    /// Attempts to load UserEntryInfo from the general pasteboard.
    static func fromPasteboard() -> UserEntryInfo? {
        let pasteboard = UIPasteboard.general
        for item in pasteboard.items {
            if let jsonString = item[Self.pasteboardUTType.identifier] as? String,
                let data = jsonString.data(using: .utf8),
                let decoded = try? JSONDecoder().decode(UserEntryInfo.self, from: data)
            {
                return decoded
            }
        }
        return nil
    }
}
