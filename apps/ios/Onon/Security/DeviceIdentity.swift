import Foundation
import Security
import UIKit

struct DeviceIdentity {
    private static let deviceIDKey = "device-id"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var id: UUID {
        if let value = defaults.string(forKey: Self.deviceIDKey), let id = UUID(uuidString: value) {
            return id
        }
        let id = UUID()
        defaults.set(id.uuidString, forKey: Self.deviceIDKey)
        return id
    }

    @MainActor var displayName: String {
        UIDevice.current.name
    }
}

enum DeviceTokenStore {
    private static let service = "au.local.onon.device"
    private static let account = "device-token"

    static func save(_ token: String) throws {
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updated = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw PairingError.keychain(updated) }
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else { throw PairingError.keychain(status) }
    }

    static func load() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw PairingError.keychain(status) }
        return String(data: data, encoding: .utf8)
    }

    static func remove() throws {
        let status = SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw PairingError.keychain(status) }
    }
}

enum ServerConfiguration {
    private static let key = "paired-server-url"
    private static let approvedKey = "approved-pairing-origin"

    static var serverURL: URL? {
        get { UserDefaults.standard.string(forKey: key).flatMap(URL.init(string:)) }
        set {
            UserDefaults.standard.set(newValue?.absoluteString, forKey: key)
            if newValue == nil { UserDefaults.standard.removeObject(forKey: approvedKey) }
        }
    }

    static var approvedServerURL: URL? {
        guard let serverURL, let origin = try? LocalServer.origin(serverURL),
              UserDefaults.standard.string(forKey: approvedKey) == origin.absoluteString else { return nil }
        return origin
    }

    static func approve(_ origin: URL) {
        serverURL = origin
        UserDefaults.standard.set(origin.absoluteString, forKey: approvedKey)
    }

    static func endpoint(_ path: String) -> URL? {
        approvedServerURL?.appending(path: path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }
}

enum PairingError: LocalizedError {
    case invalidCode
    case invalidServer
    case rejected(Int)
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidCode: "The QR code is not an Onon pairing code."
        case .invalidServer: "Pairing requires a local laptop address (.local, localhost or a private LAN IP), without credentials or paths."
        case let .rejected(status): "Pairing was rejected (HTTP \(status))."
        case let .keychain(status): "The device token could not be saved (Keychain \(status))."
        }
    }
}
