import Foundation
import Security
import LocalAuthentication

public struct Credential: Codable, Sendable {
    public let baseURL: URL
    public let token: String
    public let deviceID: String
    public init(baseURL: URL, token: String, deviceID: String) {
        self.baseURL = baseURL; self.token = token; self.deviceID = deviceID
    }
}

public enum CredentialStore {
    private static let accessLock = NSLock()
    private static let service = "CAPA.bridge"
    private static let account = "paired-device"
    public static func load(allowInteraction: Bool = true) -> Credential? {
        accessLock.lock(); defer { accessLock.unlock() }
        #if os(macOS)
        // This item uses the legacy macOS Keychain. LAContext alone does not
        // suppress its ACL dialog. Serialize access while scoping its UI flag.
        var previousInteraction: DarwinBoolean = true
        SecKeychainGetUserInteractionAllowed(&previousInteraction)
        SecKeychainSetUserInteractionAllowed(allowInteraction)
        defer { SecKeychainSetUserInteractionAllowed(previousInteraction.boolValue) }
        #endif
        let context = LAContext()
        context.interactionNotAllowed = !allowInteraction
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(Credential.self, from: data)
    }

    public static func save(_ credential: Credential) throws {
        accessLock.lock(); defer { accessLock.unlock() }
        let data = try JSONEncoder().encode(credential)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account]
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw BridgeError.message("Could not save the device credential securely.") }
    }

    public static func remove() {
        accessLock.lock(); defer { accessLock.unlock() }
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account] as CFDictionary)
    }
}
