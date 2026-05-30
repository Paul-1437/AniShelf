//
//  CloudLibrarySyncChangeTokenStore.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/30.
//

import CloudKit
import Foundation

public final class CloudLibrarySyncChangeTokenStore: @unchecked Sendable {
    public struct Namespace: Hashable, Sendable {
        public let containerIdentifier: String
        public let accountIdentifier: String

        public init(containerIdentifier: String, accountIdentifier: String) {
            self.containerIdentifier = containerIdentifier
            self.accountIdentifier = accountIdentifier
        }
    }

    private let userDefaults: UserDefaults
    private let keyPrefix: String

    public init(
        userDefaults: UserDefaults = .standard,
        keyPrefix: String = "AniShelf.LibrarySync.ChangeToken"
    ) {
        self.userDefaults = userDefaults
        self.keyPrefix = keyPrefix
    }

    public func token(for zoneID: CKRecordZone.ID, namespace: Namespace) -> CKServerChangeToken? {
        let key = tokenKey(for: zoneID, namespace: namespace)
        guard let data = userDefaults.data(forKey: key) else { return nil }

        do {
            return try decodeToken(from: data)
        } catch {
            userDefaults.removeObject(forKey: key)
            return nil
        }
    }

    public func setToken(
        _ token: CKServerChangeToken?,
        for zoneID: CKRecordZone.ID,
        namespace: Namespace
    ) {
        let key = tokenKey(for: zoneID, namespace: namespace)
        guard let token else {
            userDefaults.removeObject(forKey: key)
            return
        }

        do {
            userDefaults.set(try encodeToken(token), forKey: key)
        } catch {
            userDefaults.removeObject(forKey: key)
        }
    }

    public func removeToken(for zoneID: CKRecordZone.ID, namespace: Namespace) {
        userDefaults.removeObject(forKey: tokenKey(for: zoneID, namespace: namespace))
    }
}

extension CloudLibrarySyncChangeTokenStore {
    func tokenKey(for zoneID: CKRecordZone.ID, namespace: Namespace) -> String {
        "\(keyPrefix).\(namespace.containerIdentifier).\(namespace.accountIdentifier).\(zoneID.ownerName).\(zoneID.zoneName)"
    }

    func encodeToken(_ token: CKServerChangeToken) throws -> Data {
        try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    }

    func decodeToken(from data: Data) throws -> CKServerChangeToken {
        let coder = try NSKeyedUnarchiver(forReadingFrom: data)
        guard let token = coder.decodeObject(of: CKServerChangeToken.self, forKey: NSKeyedArchiveRootObjectKey)
        else {
            throw CocoaError(.coderReadCorrupt)
        }
        return token
    }
}
