import XCTest
import Security
@testable import CoursePathConnection

@MainActor
final class CoursePathKeychainTests: XCTestCase {
    // Exercise real query construction with an isolated Security adapter. Values
    // are synthetic; no personal Keychain items or machine lock state are changed.
    func testMigrationVerifiesProtectedCopyBeforeDeletingLegacyAndSurvivesRestart() throws {
        var rows = [false: Data("synthetic".utf8)]
        var accessible: CFString?
        var storage = CoursePathKeychain(service: "test", dataProtection: true)
        storage.copy = { query, result in
            let q = query as! [String: Any]
            XCTAssertEqual(q[kSecAttrSynchronizable as String] as? Bool, false)
            let protected = q[kSecUseDataProtectionKeychain as String] as! Bool
            guard let value = rows[protected] else { return errSecItemNotFound }
            result?.pointee = value as CFData; return errSecSuccess
        }
        storage.update = { query, values in
            let q = query as! [String: Any], v = values as! [String: Any]
            XCTAssertEqual(q[kSecUseDataProtectionKeychain as String] as? Bool, true)
            accessible = v[kSecAttrAccessible as String] as! CFString?
            guard rows[true] != nil else { return errSecItemNotFound }
            rows[true] = v[kSecValueData as String] as? Data; return errSecSuccess
        }
        storage.add = { query, _ in
            let q = query as! [String: Any]
            XCTAssertEqual(q[kSecUseDataProtectionKeychain as String] as? Bool, true)
            XCTAssertEqual(q[kSecAttrSynchronizable as String] as? Bool, false)
            accessible = q[kSecAttrAccessible as String] as! CFString?
            rows[true] = q[kSecValueData as String] as? Data; return errSecSuccess
        }
        storage.remove = { query in
            let q = query as! [String: Any], protected = q[kSecUseDataProtectionKeychain as String] as! Bool
            if !protected { XCTAssertNotNil(rows[true]) }
            rows.removeValue(forKey: protected); return errSecSuccess
        }
        XCTAssertEqual(try storage.read(server: .local), "synthetic")
        XCTAssertEqual(accessible, kSecAttrAccessibleWhenUnlockedThisDeviceOnly); XCTAssertNil(rows[false])
        let restarted = storage
        XCTAssertEqual(try restarted.read(server: .local), "synthetic")
        try restarted.save("updated", server: .local)
        XCTAssertEqual(try restarted.read(server: .local), "updated")
        storage.remove = { query in rows.removeValue(forKey: (query as! [String: Any])[kSecUseDataProtectionKeychain as String] as! Bool); return errSecSuccess }
        try storage.delete(server: .local); XCTAssertTrue(rows.isEmpty)
    }
    func testLockedOrUnentitledKeychainNeverFallsBackOrDeletesCredentials() throws {
        for status in [errSecInteractionNotAllowed, errSecMissingEntitlement] {
            var copies = 0, deletes = 0
            var storage = CoursePathKeychain(service: "test", dataProtection: true)
            storage.copy = { _, _ in copies += 1; return status }
            storage.remove = { _ in deletes += 1; return errSecSuccess }
            XCTAssertThrowsError(try storage.read(server: .local))
            XCTAssertEqual(copies, 1); XCTAssertEqual(deletes, 0)
            let auth = CoursePathAuth(storage: storage, enabled: true)
            XCTAssertThrowsError(try auth.load(server: .local))
            XCTAssertEqual(deletes, 0)
        }
    }
    func testFailedMigrationPreservesLegacyItem() throws {
        var deletes = 0
        var storage = CoursePathKeychain(service: "test", dataProtection: true)
        storage.copy = { query, result in
            if (query as! [String: Any])[kSecUseDataProtectionKeychain as String] as! Bool { return errSecItemNotFound }
            result?.pointee = Data("synthetic".utf8) as CFData; return errSecSuccess
        }
        storage.update = { _, _ in errSecInteractionNotAllowed }
        storage.remove = { _ in deletes += 1; return errSecSuccess }
        XCTAssertThrowsError(try storage.read(server: .local)); XCTAssertEqual(deletes, 0)
    }
    func testInterruptedMigrationRetriesLegacyDeletionBeforeReturningProtectedCredential() throws {
        var deletes = 0, locked = true
        var storage = CoursePathKeychain(service: "test", dataProtection: true)
        storage.copy = { _, result in result?.pointee = Data("synthetic".utf8) as CFData; return errSecSuccess }
        storage.remove = { query in
            XCTAssertEqual((query as! [String: Any])[kSecUseDataProtectionKeychain as String] as? Bool, false)
            deletes += 1; return locked ? errSecInteractionNotAllowed : errSecSuccess
        }
        XCTAssertThrowsError(try storage.read(server: .local)); XCTAssertEqual(deletes, 1)
        locked = false; XCTAssertEqual(try storage.read(server: .local), "synthetic"); XCTAssertEqual(deletes, 2)
    }

}
