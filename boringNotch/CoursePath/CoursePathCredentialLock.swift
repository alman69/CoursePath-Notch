import Foundation
import CryptoKit
import Darwin

// Kernel-owned lease: process death releases it. All copies with the same app
// container/service share the lock; no tokens or identifiers are written here.
final class CoursePathCredentialLock {
    private let descriptor: Int32
    init(namespace: String, server: CoursePathServer) throws {
        let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("CoursePathCredentialLocks", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let key = SHA256.hash(data: Data((namespace + "|" + server.rawValue).utf8)).map { String(format: "%02x", $0) }.joined()
        descriptor = Darwin.open(folder.appendingPathComponent(key).path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw CoursePathError.keychain(errSecIO) }
    }
    func acquire() async throws {
        let deadline = Date().addingTimeInterval(25)
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK, Date() < deadline else { throw CoursePathError.http(429) }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }
    deinit { flock(descriptor, LOCK_UN); Darwin.close(descriptor) }
}
