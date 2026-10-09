import Foundation
import Security

protocol CoursePathCredentialStorage {
    func read(server: CoursePathServer) throws -> String?
    func save(_ token: String, server: CoursePathServer) throws
    func delete(server: CoursePathServer) throws
}

struct CoursePathKeychain: CoursePathCredentialStorage {
    // macOS login Keychain supports this fork's ad-hoc signing. The data-protection
    // Keychain requires application-identifier entitlements from a signing team.
    let service: String
    init(service: String = "dev.coursepath.notch.desktop") { self.service = service }
    private func query(_ server: CoursePathServer) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: server.baseURL.absoluteString,
         kSecAttrSynchronizable as String: false]
    }
    func read(server: CoursePathServer) throws -> String? {
        var attributes = query(server)
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw CoursePathError.keychain(status) }
        guard let data = result as? Data, let token = String(data: data, encoding: .utf8) else { throw CoursePathError.invalidToken }
        return token
    }
    func save(_ token: String, server: CoursePathServer) throws {
        let values = [kSecValueData as String: Data(token.utf8),
                      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly] as [String: Any]
        let update = SecItemUpdate(query(server) as CFDictionary, values as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw CoursePathError.keychain(update) }
        let status = SecItemAdd(query(server).merging(values) { _, value in value } as CFDictionary, nil)
        guard status == errSecSuccess else { throw CoursePathError.keychain(status) }
    }
    func delete(server: CoursePathServer) throws {
        let status = SecItemDelete(query(server) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CoursePathError.keychain(status) }
    }
}
