import Foundation
import Security

protocol CoursePathCredentialStorage {
    var coordinationNamespace: String? { get }
    func read(server: CoursePathServer) throws -> String?
    func save(_ token: String, server: CoursePathServer) throws
    func delete(server: CoursePathServer) throws
}

extension CoursePathCredentialStorage { var coordinationNamespace: String? { nil } }

struct CoursePathKeychain: CoursePathCredentialStorage {
    // Ad-hoc MVP builds use login Keychain with its default per-app ACL.
    // Optional Developer ID builds require Data Protection and never fall back.
    static var publicStorage: Bool {
        #if COURSEPATH_PUBLIC_DISTRIBUTION
        true
        #else
        false
        #endif
    }
    let service: String
    let dataProtection: Bool
    var coordinationNamespace: String? { service }
    var copy: (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus = SecItemCopyMatching
    var update: (CFDictionary, CFDictionary) -> OSStatus = SecItemUpdate
    var add: (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus = SecItemAdd
    var remove: (CFDictionary) -> OSStatus = SecItemDelete
    init(service: String = "dev.coursepath.notch.desktop", dataProtection: Bool = Self.publicStorage) {
        self.service = service; self.dataProtection = dataProtection
    }
    private func query(_ server: CoursePathServer, protected: Bool? = nil) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: server.baseURL.absoluteString,
         kSecAttrSynchronizable as String: false,
         kSecUseDataProtectionKeychain as String: protected ?? dataProtection]
    }
    func read(server: CoursePathServer) throws -> String? {
        if let current = try readItem(server: server, protected: dataProtection) {
            // Also finish a migration interrupted after protected persistence.
            if dataProtection { try deleteItem(server: server, protected: false) }
            return current
        }
        guard dataProtection, let legacy = try readItem(server: server, protected: false) else { return nil }
        try save(legacy, server: server)
        guard try readItem(server: server, protected: true) == legacy else { throw CoursePathError.invalidResponse }
        // Delete legacy data only after protected persistence and read-back succeed.
        try deleteItem(server: server, protected: false)
        return legacy
    }
    private func readItem(server: CoursePathServer, protected: Bool) throws -> String? {
        var attributes = query(server, protected: protected)
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = copy(attributes as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw CoursePathError.keychain(status) }
        guard let data = result as? Data, let token = String(data: data, encoding: .utf8) else { throw CoursePathError.invalidToken }
        return token
    }
    func save(_ token: String, server: CoursePathServer) throws {
        var values: [String: Any] = [kSecValueData as String: Data(token.utf8)]
        if dataProtection { values[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly }
        let statusUpdate = update(query(server) as CFDictionary, values as CFDictionary)
        if statusUpdate == errSecSuccess { return }
        guard statusUpdate == errSecItemNotFound else { throw CoursePathError.keychain(statusUpdate) }
        let status = add(query(server).merging(values) { _, value in value } as CFDictionary, nil)
        guard status == errSecSuccess else { throw CoursePathError.keychain(status) }
    }
    func delete(server: CoursePathServer) throws {
        try deleteItem(server: server, protected: dataProtection)
        if dataProtection { try deleteItem(server: server, protected: false) }
    }
    private func deleteItem(server: CoursePathServer, protected: Bool) throws {
        let status = remove(query(server, protected: protected) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CoursePathError.keychain(status) }
    }
}
