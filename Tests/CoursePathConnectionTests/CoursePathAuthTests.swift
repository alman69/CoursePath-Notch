import XCTest
import CryptoKit
@testable import CoursePathConnection

private final class AuthStorage: CoursePathCredentialStorage {
    var values: [CoursePathServer: String] = [:]
    var writes = 0
    var failure: CoursePathError?
    func read(server: CoursePathServer) throws -> String? { values[server] }
    func save(_ token: String, server: CoursePathServer) throws { if let failure { throw failure }; values[server] = token; writes += 1 }
    func delete(server: CoursePathServer) throws { values.removeValue(forKey: server) }
}
@MainActor
private final class AuthAPI: CoursePathAuthAPI {
    var started: CoursePathPKCE?
    var renewals = 0, exchanges = 0, cancellations = 0, revocations = 0
    var held: CheckedContinuation<CoursePathPairedCredential, Error>?
    var hold = false
    var error: CoursePathError?
    var now: () -> Date = Date.init
    let deviceID = UUID().uuidString
    func value(_ letter: String = "a") -> CoursePathPairedCredential {
        CoursePathPairedCredential(accessToken: "cpna_" + String(repeating: letter, count: 43), refreshToken: "cpnr_" + String(repeating: letter, count: 43), deviceId: deviceID, accessExpiresAt: now().addingTimeInterval(600), sessionExpiresAt: now().addingTimeInterval(30 * 86400))
    }
    func start(server: CoursePathServer, pkce: CoursePathPKCE) async throws -> CoursePathPairing {
        started = pkce
        return CoursePathPairing(requestId: String(repeating: "a", count: 43), authorizationURL: "http://127.0.0.1:5173/desktop/connect?request=" + String(repeating: "a", count: 43), confirmation: "1234ABCD", expiresIn: 300)
    }
    func exchange(server: CoursePathServer, code: String, verifier: String) async throws -> CoursePathPairedCredential {
        XCTAssertEqual(verifier, started?.verifier); exchanges += 1; return value()
    }
    func renew(server: CoursePathServer, refreshToken: String) async throws -> CoursePathPairedCredential {
        renewals += 1
        if let error { throw error }
        if hold { return try await withCheckedThrowingContinuation { held = $0 } }
        return value("b")
    }
    func revoke(server: CoursePathServer, refreshToken: String) async throws { revocations += 1 }
    func cancel(server: CoursePathServer, requestId: String, verifier: String) async throws { cancellations += 1 }
    func callback() -> URL { URL(string: CoursePathPKCE.callback + "?state=" + started!.state + "&code=" + String(repeating: "c", count: 43))! }
}
private final class PairedCalendarAPI: CoursePathAPI {
    var tokens: [String] = []
    var revision = 1
    var completed = false
    var error: CoursePathError?
    func snapshot(server: CoursePathServer, token: String, today: String) async throws -> CoursePathSnapshot {
        if let error { throw error }; tokens.append(token)
        return CoursePathSnapshot(revision: revision, assignments: [], tasks: [CoursePathTask(id: "task", assignmentId: "a", title: "Synthetic", firstStep: "", date: today, minutes: 30, order: 0, completed: completed, completedAt: nil)], deadlines: [], upcomingDeadlines: [])
    }
    func complete(server: CoursePathServer, token: String, taskId: String, completed: Bool, revision: Int) async throws -> CoursePathCompletion {
        tokens.append(token); XCTAssertEqual(revision, self.revision); self.revision += 1; self.completed = completed
        return CoursePathCompletion(revision: self.revision, taskId: taskId, completed: completed, completedAt: nil, assignmentId: "a", assignmentCompleted: completed)
    }
}
@MainActor
final class CoursePathAuthTests: XCTestCase {
    private func connected(_ auth: CoursePathAuth, api: AuthAPI) async throws {
        try auth.load(server: .local)
        try await auth.authorize(server: .local, confirmation: { XCTAssertEqual($0, "1234ABCD") }, browser: { _ in api.callback() })
    }
    func testPKCEUsesRandom256BitSecretsAndValidatesExactCallbackAndState() throws {
        let first = try CoursePathPKCE(), second = try CoursePathPKCE()
        XCTAssertEqual(first.verifier.count, 43); XCTAssertEqual(first.state.count, 43)
        XCTAssertNotEqual(first.verifier, second.verifier); XCTAssertNotEqual(first.state, first.verifier)
        let expected = Data(SHA256.hash(data: Data(first.verifier.utf8))).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        XCTAssertEqual(first.challenge, expected)
        let code = String(repeating: "a", count: 43), good = CoursePathPKCE.callback + "?code=" + code + "&state=" + first.state
        XCTAssertEqual(try first.code(from: URL(string: good)!), code)
        for value in [good + "&state=" + first.state, good + "&error=access_denied", good + "&accessToken=secret", good.replacingOccurrences(of: first.state, with: second.state), good.replacingOccurrences(of: "notch:/", with: "notch://evil/"), good + "#fragment"] {
            XCTAssertThrowsError(try first.code(from: URL(string: value)!))
        }
        XCTAssertThrowsError(try first.code(from: URL(string: CoursePathPKCE.callback + "?error=access_denied&state=" + first.state)!)) { XCTAssertTrue($0 is CancellationError) }
    }
    func testPairingPersistsOnlyToItsSeparateKeychainAndRestoresWithoutNetwork() async throws {
        let service = "dev.coursepath.notch.paired-test." + UUID().uuidString
        let storage = CoursePathKeychain(service: service), manual = CoursePathKeychain(service: service + ".manual")
        defer { try? storage.delete(server: .local); try? manual.delete(server: .local) }
        let manualValue = "cpn_" + String(repeating: "x", count: 43)
        try manual.save(manualValue, server: .local)
        let api = AuthAPI(), auth = CoursePathAuth(api: api, storage: storage, enabled: true)
        try await connected(auth, api: api)
        XCTAssertEqual(api.exchanges, 1); XCTAssertNotNil(try storage.read(server: .local))
        let restored = CoursePathAuth(api: api, storage: storage, enabled: true)
        try restored.load(server: .local); XCTAssertEqual(restored.credential, auth.credential)
        XCTAssertEqual(api.renewals, 0); XCTAssertEqual(try manual.read(server: .local), manualValue)
        _ = try restored.remove(server: .local); XCTAssertNil(try storage.read(server: .local)); XCTAssertEqual(try manual.read(server: .local), manualValue)
    }
    func testDisabledAndProductionPairingCannotConnectOrReadStoredCredentials() async throws {
        let api = AuthAPI(), storage = AuthStorage()
        storage.values[.local] = String(decoding: try JSONEncoder().encode(api.value()), as: UTF8.self)
        let disabled = CoursePathAuth(api: api, storage: storage, enabled: false)
        try disabled.load(server: .local); XCTAssertNil(disabled.credential)
        do { try await disabled.authorize(server: .local, confirmation: { _ in }, browser: { _ in api.callback() }); XCTFail() } catch {}
        let enabled = CoursePathAuth(api: api, storage: storage, enabled: true)
        try enabled.load(server: .production); XCTAssertNil(enabled.credential)
        do { try await enabled.authorize(server: .production, confirmation: { _ in }, browser: { _ in api.callback() }); XCTFail() } catch {}
        XCTAssertNil(api.started); XCTAssertEqual(storage.writes, 0)
    }
    func testCancellationAndIncorrectCallbackDoNotExchangeOrPersistCredentials() async throws {
        for mode in [0, 1] {
            let api = AuthAPI(), storage = AuthStorage(), auth = CoursePathAuth(api: api, storage: storage, enabled: true)
            try auth.load(server: .local)
            do {
                try await auth.authorize(server: .local, confirmation: { _ in }, browser: { _ in
                    if mode == 0 { throw CancellationError() }
                    return URL(string: CoursePathPKCE.callback + "?state=" + String(repeating: "z", count: 43) + "&code=" + String(repeating: "a", count: 43))!
                }); XCTFail()
            } catch {}
            XCTAssertEqual(api.exchanges, 0); XCTAssertEqual(api.cancellations, 1); XCTAssertNil(auth.credential); XCTAssertTrue(storage.values.isEmpty)
        }
    }
    func testStorageFailureRevokesExchangedSessionAndDoesNotConnect() async throws {
        let api = AuthAPI(), storage = AuthStorage(), auth = CoursePathAuth(api: api, storage: storage, enabled: true)
        storage.failure = .keychain(-1)
        do { try await connected(auth, api: api); XCTFail() } catch {}
        XCTAssertEqual(api.exchanges, 1); XCTAssertEqual(api.revocations, 1); XCTAssertNil(auth.credential)
    }
    func testConcurrentRenewalUsesOneRequestAndPersistsRotationOnce() async throws {
        var clock = Date(); let api = AuthAPI(), storage = AuthStorage(); api.now = { clock }
        let auth = CoursePathAuth(api: api, storage: storage, now: { clock }, enabled: true)
        try await connected(auth, api: api); clock.addTimeInterval(601); api.hold = true
        let first = Task { try await auth.accessToken(server: .local) }
        while api.held == nil { await Task.yield() }
        let second = Task { try await auth.accessToken(server: .local) }; await Task.yield()
        api.held?.resume(returning: api.value("b"))
        let a = try await first.value, b = try await second.value
        XCTAssertEqual(a, b); XCTAssertEqual(api.renewals, 1); XCTAssertEqual(storage.writes, 2)
        XCTAssertEqual(auth.credential?.refreshToken, api.value("b").refreshToken)
    }
    func testAmbiguousRenewalFailureIsNotBlindlyRetried() async throws {
        var clock = Date(); let api = AuthAPI(), storage = AuthStorage(); api.now = { clock }
        let auth = CoursePathAuth(api: api, storage: storage, now: { clock }, enabled: true)
        try await connected(auth, api: api); clock.addTimeInterval(601); api.error = .offline
        for _ in 0..<2 { do { _ = try await auth.accessToken(server: .local); XCTFail() } catch {} }
        XCTAssertEqual(api.renewals, 1); XCTAssertEqual(storage.writes, 1)
    }
    func testDisconnectOrServerChangeCannotRestoreLateRenewal() async throws {
        var clock = Date(); let api = AuthAPI(), storage = AuthStorage(); api.now = { clock }
        let auth = CoursePathAuth(api: api, storage: storage, now: { clock }, enabled: true)
        try await connected(auth, api: api); clock.addTimeInterval(601); api.hold = true
        let request = Task { try await auth.accessToken(server: .local) }
        while api.held == nil { await Task.yield() }
        _ = try auth.remove(server: .local); api.held?.resume(returning: api.value("b"))
        do { _ = try await request.value; XCTFail() } catch {}
        XCTAssertNil(auth.credential); XCTAssertNil(storage.values[.local])
    }
    func testStoreCompletesAndRestoresAfterAutomaticRenewalWithoutSavingPairedTokensAsManual() async throws {
        var clock = Date(); let authAPI = AuthAPI(), paired = AuthStorage(), manual = AuthStorage(); authAPI.now = { clock }
        let auth = CoursePathAuth(api: authAPI, storage: paired, now: { clock }, enabled: true), api = PairedCalendarAPI()
        let suite = "dev.coursepath.notch.auth-store." + UUID().uuidString, prefs = UserDefaults(suiteName: suite)!
        defer { prefs.removePersistentDomain(forName: suite) }
        let store = CoursePathStore(api: api, credentials: manual, preferences: prefs, now: { clock }, auth: auth)
        let connected = await store.connectBrowser { _ in authAPI.callback() }
        XCTAssertTrue(connected); XCTAssertEqual(store.status, .connected); XCTAssertTrue(manual.values.isEmpty)
        clock.addTimeInterval(601)
        let completed = await store.setTaskCompletion("task", completed: true)
        XCTAssertTrue(completed); XCTAssertTrue(store.snapshot!.tasks[0].completed); XCTAssertEqual(authAPI.renewals, 1)
        XCTAssertEqual(api.tokens.suffix(2), [authAPI.value("b").accessToken, authAPI.value("b").accessToken])
        let restored = await store.setTaskCompletion("task", completed: false)
        XCTAssertTrue(restored); XCTAssertFalse(store.snapshot!.tasks[0].completed); XCTAssertTrue(manual.values.isEmpty)
        api.error = .offline; let offline = await store.refresh()
        XCTAssertFalse(offline); XCTAssertEqual(store.status, .offline); XCTAssertNotNil(store.snapshot)
        store.disconnect(); XCTAssertFalse(store.hasCredential); XCTAssertTrue(paired.values.isEmpty)
    }
    func testCanceledVisibilityReadStillPersistsAlreadyIssuedRotation() async throws {
        var clock = Date(); let authAPI = AuthAPI(), paired = AuthStorage(); authAPI.now = { clock }
        let auth = CoursePathAuth(api: authAPI, storage: paired, now: { clock }, enabled: true)
        try await connected(auth, api: authAPI)
        let suite = "dev.coursepath.notch.auth-cancel." + UUID().uuidString, prefs = UserDefaults(suiteName: suite)!
        defer { prefs.removePersistentDomain(forName: suite) }
        let store = CoursePathStore(api: PairedCalendarAPI(), credentials: AuthStorage(), preferences: prefs, now: { clock }, auth: auth)
        let initial = await store.refresh(); XCTAssertTrue(initial)
        let source = UUID(); store.setContentVisible(true, source: source)
        clock.addTimeInterval(601); authAPI.hold = true
        let read = Task { await store.refresh() }
        while authAPI.held == nil { await Task.yield() }
        store.setContentVisible(false, source: source)
        authAPI.held?.resume(returning: authAPI.value("b"))
        let canceled = await read.value; XCTAssertFalse(canceled)
        // A visibility poll can win the read race; await its independent rotation.
        let resumed = try await auth.accessToken(server: .local)
        XCTAssertEqual(resumed, authAPI.value("b").accessToken)
        XCTAssertEqual(auth.credential?.refreshToken, authAPI.value("b").refreshToken)
        XCTAssertEqual(paired.writes, 2); XCTAssertFalse(store.hasActivePolling)
        XCTAssertEqual(store.status, .ready); XCTAssertEqual(authAPI.renewals, 1)
    }
    func testRevokedRenewalExpiresStoreAndRemovesOnlyPairedCredential() async throws {
        var clock = Date(); let authAPI = AuthAPI(), paired = AuthStorage(); authAPI.now = { clock }
        let auth = CoursePathAuth(api: authAPI, storage: paired, now: { clock }, enabled: true)
        try await connected(auth, api: authAPI)
        let suite = "dev.coursepath.notch.auth-revoke." + UUID().uuidString, prefs = UserDefaults(suiteName: suite)!
        defer { prefs.removePersistentDomain(forName: suite) }
        let manual = AuthStorage(); manual.values[.local] = "cpn_" + String(repeating: "m", count: 43)
        let store = CoursePathStore(api: PairedCalendarAPI(), credentials: manual, preferences: prefs, now: { clock }, auth: auth)
        clock.addTimeInterval(601); authAPI.error = .unauthorized
        let rejected = await store.refresh(); XCTAssertFalse(rejected)
        XCTAssertEqual(store.status, .expired); XCTAssertFalse(store.hasCredential)
        XCTAssertNil(paired.values[.local]); XCTAssertNotNil(manual.values[.local])
    }
    func testExpiredPairedRecordIsClearedSoManualFallbackCanBeRestored() async throws {
        let api = AuthAPI(), paired = AuthStorage()
        paired.values[.local] = String(decoding: try JSONEncoder().encode(api.value()), as: UTF8.self)
        let auth = CoursePathAuth(api: api, storage: paired, now: { Date().addingTimeInterval(31 * 86400) }, enabled: true)
        XCTAssertThrowsError(try auth.load(server: .local))
        XCTAssertNil(paired.values[.local]); XCTAssertNil(auth.credential)
        XCTAssertNoThrow(try auth.load(server: .local))
    }

}
