import XCTest
import Foundation
import AppKit
@testable import CoursePathConnection

private let testToken = "cpn_" + String(repeating: "a", count: 43)
private let sampleJSON = #"{"revision":4,"assignments":[{"id":"a","title":"Synthetic work","course":"TEST","kind":"assignment","deadline":"2026-12-01","dueTime":"23:59","deadlineOnly":false,"completed":false}],"tasks":[{"id":"second","assignmentId":"a","title":"Second","firstStep":"Open notes","date":"2026-10-09","minutes":30,"order":1,"completed":false,"completedAt":null},{"id":"first","assignmentId":"a","title":"First","firstStep":"","date":"2026-10-09","minutes":15.5,"order":0,"completed":false,"completedAt":null}],"deadlines":[{"id":"a","assignmentIds":["a"],"title":"Synthetic work","course":"TEST","kind":"assignment","date":"2026-12-01","dueTime":"23:59","examMilestone":false,"completed":false}],"upcomingDeadlines":[{"id":"a","assignmentIds":["a"],"title":"Synthetic work","course":"TEST","kind":"assignment","date":"2026-12-01","dueTime":"23:59","examMilestone":false,"completed":false}]}"#
private func sample(_ revision: Int = 4, completed: Bool = false) -> CoursePathSnapshot {
    let decoded = try! JSONDecoder().decode(CoursePathSnapshot.self, from: Data(sampleJSON.utf8))
    let tasks = decoded.tasks.map { CoursePathTask(id: $0.id, assignmentId: $0.assignmentId, title: $0.title, firstStep: $0.firstStep, date: $0.date, minutes: $0.minutes, order: $0.order, completed: completed, completedAt: completed ? "2026-10-09T12:00:00.000Z" : nil) }
    return CoursePathSnapshot(revision: revision, assignments: decoded.assignments, tasks: tasks, deadlines: decoded.deadlines, upcomingDeadlines: decoded.upcomingDeadlines)
}

private final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

private final class MemoryCredentials: CoursePathCredentialStorage {
    var values: [CoursePathServer: String] = [:]
    var saves = 0
    func read(server: CoursePathServer) throws -> String? { values[server] }
    func save(_ token: String, server: CoursePathServer) throws { values[server] = token; saves += 1 }
    func delete(server: CoursePathServer) throws { values.removeValue(forKey: server) }
}

@MainActor private final class MockAPI: CoursePathAPI {
    var result = sample()
    var error: CoursePathError?
    var mutationError: CoursePathError?
    var reads = 0
    var writes: [(String, Bool, Int)] = []
    var hold = false
    var held: CheckedContinuation<CoursePathSnapshot, Error>?
    var holdMutation = false
    var heldMutation: CheckedContinuation<Void, Never>?
    func snapshot(server: CoursePathServer, token: String, today: String) async throws -> CoursePathSnapshot {
        reads += 1
        if let error { throw error }
        if hold { return try await withCheckedThrowingContinuation { held = $0 } }
        return result
    }
    func complete(server: CoursePathServer, token: String, taskId: String, completed: Bool, revision: Int) async throws -> CoursePathCompletion {
        writes.append((taskId, completed, revision))
        if holdMutation { await withCheckedContinuation { heldMutation = $0 } }
        if let mutationError { throw mutationError }
        let tasks = result.tasks.map { task in
            task.id == taskId ? CoursePathTask(id: task.id, assignmentId: task.assignmentId, title: task.title, firstStep: task.firstStep,
                date: task.date, minutes: task.minutes, order: task.order, completed: completed,
                completedAt: completed ? "2026-10-09T12:00:00.000Z" : nil) : task
        }
        result = CoursePathSnapshot(revision: revision + 1, assignments: result.assignments, tasks: tasks, deadlines: result.deadlines, upcomingDeadlines: result.upcomingDeadlines)
        return CoursePathCompletion(revision: result.revision, taskId: taskId, completed: completed, completedAt: completed ? "2026-10-09T12:00:00.000Z" : nil, assignmentId: "a", assignmentCompleted: tasks.allSatisfy(\.completed))
    }
}

@MainActor
final class CoursePathConnectionTests: XCTestCase {
    private func client() -> CoursePathAPIClient {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockURLProtocol.self]
        return CoursePathAPIClient(session: URLSession(configuration: config))
    }
    private func store(_ api: MockAPI, credentials: MemoryCredentials = MemoryCredentials(), pollInterval: TimeInterval = 20, now: @escaping () -> Date = { Date(timeIntervalSince1970: 1791547200) }) -> CoursePathStore {
        let name = "dev.coursepath.notch.tests." + UUID().uuidString
        let preferences = UserDefaults(suiteName: name)!
        addTeardownBlock { preferences.removePersistentDomain(forName: name) }
        return CoursePathStore(api: api, credentials: credentials, preferences: preferences, now: now, pollInterval: pollInterval)
    }
    func testSnapshotRequestAndDecoding() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:5173/api/desktop/snapshot?today=2026-10-09")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer " + testToken)
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-CoursePath"), "1")
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            XCTAssertEqual(request.timeoutInterval, 15)
            return (200, Data(sampleJSON.utf8))
        }
        let result = try await client().snapshot(server: .local, token: testToken, today: "2026-10-09")
        XCTAssertEqual(result, sample()); XCTAssertEqual(result.tasks[1].minutes, 15.5)
        XCTAssertEqual(result.upcomingDeadlines[0].dueTime, "23:59")
    }
    func testDesiredCompletionAndRestorationPayloads() async throws {
        for desired in [true, false] {
            MockURLProtocol.handler = { request in
                XCTAssertEqual(request.url?.absoluteString, "https://app.coursepath.dev/api/desktop/task-completion")
                XCTAssertEqual(request.httpMethod, "POST")
                var data = request.httpBody ?? Data()
                if let stream = request.httpBodyStream {
                    stream.open(); defer { stream.close() }
                    var buffer = [UInt8](repeating: 0, count: 4096)
                    while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; data.append(buffer, count: count) }
                }
                let body = try JSONSerialization.jsonObject(with: data) as! [String: Any]
                XCTAssertEqual(body["taskId"] as? String, "first"); XCTAssertEqual(body["completed"] as? Bool, desired); XCTAssertEqual(body["revision"] as? Int, 4)
                let response = CoursePathCompletion(revision: 5, taskId: "first", completed: desired, completedAt: desired ? "2026-10-09T12:00:00.000Z" : nil, assignmentId: "a", assignmentCompleted: desired)
                return (200, try JSONEncoder().encode(response))
            }
            let response = try await client().complete(server: .production, token: testToken, taskId: "first", completed: desired, revision: 4)
            XCTAssertEqual(response.completed, desired)
        }
    }
    func testHTTPErrorsRevocationAndInvalidData() async {
        for (status, expected) in [(401, CoursePathError.unauthorized), (403, .unauthorized), (409, .conflict), (500, .http(500)), (302, .http(302))] {
            MockURLProtocol.handler = { _ in (status, Data()) }
            do { _ = try await client().snapshot(server: .localAPI, token: testToken, today: "2026-10-09"); XCTFail("Expected error") }
            catch { XCTAssertEqual(error as? CoursePathError, expected) }
        }
        MockURLProtocol.handler = { _ in (200, Data("{}".utf8)) }
        do { _ = try await client().snapshot(server: .local, token: testToken, today: "2026-10-09"); XCTFail("Expected decoding error") }
        catch { XCTAssertEqual(error as? CoursePathError, .invalidResponse) }
    }
    func testOfflineAndTimeoutErrors() async {
        for (code, expected) in [(URLError.notConnectedToInternet, CoursePathError.offline), (.timedOut, .timeout)] {
            MockURLProtocol.handler = { _ in throw URLError(code) }
            do { _ = try await client().snapshot(server: .local, token: testToken, today: "2026-10-09"); XCTFail("Expected network error") }
            catch { XCTAssertEqual(error as? CoursePathError, expected) }
        }
    }
    func testLocalDatesAndValidation() {
        let instant = Date(timeIntervalSince1970: 1791505800) // Oct 9, 00:30 UTC; Oct 8 in New York.
        XCTAssertEqual(CoursePathDate.key(instant, timeZone: TimeZone(secondsFromGMT: 0)!), "2026-10-09")
        XCTAssertEqual(CoursePathDate.key(instant, timeZone: TimeZone(identifier: "America/New_York")!), "2026-10-08")
        XCTAssertNotNil(CoursePathDate.date("2028-02-29")); XCTAssertNil(CoursePathDate.date("2026-02-29")); XCTAssertNil(CoursePathDate.date("2026-2-9"))
    }
    func testAuthenticationOrderingOfflineCacheAndRevocation() async {
        let api = MockAPI(), credentials = MemoryCredentials(), store = store(api, credentials: credentials)
        let invalid = await store.connect("invalid"); XCTAssertFalse(invalid); XCTAssertEqual(api.reads, 0)
        let connected = await store.connect(testToken); XCTAssertTrue(connected); XCTAssertEqual(store.status, .connected)
        XCTAssertEqual(credentials.values[.local], testToken); XCTAssertEqual(store.tasks(on: "2026-10-09").map(\.id), ["first", "second"])
        XCTAssertTrue(store.tasks(on: "2026-10-10").isEmpty)
        api.error = .offline; let refreshed = await store.refresh(); XCTAssertFalse(refreshed); XCTAssertTrue(store.isCached); XCTAssertNotNil(store.snapshot)
        api.error = .unauthorized; _ = await store.refresh(); XCTAssertEqual(store.status, .expired); XCTAssertNil(store.snapshot); XCTAssertNil(credentials.values[.local]); XCTAssertFalse(store.hasCredential)
    }
    func testCompletionConflictRestorationAndNoOptimisticFailures() async {
        let api = MockAPI(), store = store(api); _ = await store.connect(testToken)
        let complete = await store.setTaskCompletion("first", completed: true); XCTAssertTrue(complete); XCTAssertTrue(store.snapshot!.tasks.first(where: { $0.id == "first" })!.completed)
        XCTAssertFalse(store.snapshot!.tasks.first(where: { $0.id == "second" })!.completed)
        let restored = await store.setTaskCompletion("first", completed: false); XCTAssertTrue(restored); XCTAssertFalse(store.snapshot!.tasks.first(where: { $0.id == "first" })!.completed)
        XCTAssertEqual(api.writes.map { $0.1 }, [true, false]); XCTAssertEqual(api.writes.map { $0.2 }, [4, 5])
        api.mutationError = .conflict; api.result = sample(9, completed: true)
        let conflict = await store.setTaskCompletion("first", completed: true); XCTAssertFalse(conflict); XCTAssertEqual(store.snapshot?.revision, 9); XCTAssertEqual(api.writes.count, 3)
        api.mutationError = .offline
        _ = await store.setTaskCompletion("first", completed: false); XCTAssertTrue(store.snapshot!.tasks[0].completed); XCTAssertTrue(store.isCached)
        let again = await store.setTaskCompletion("first", completed: false); XCTAssertFalse(again); XCTAssertEqual(api.writes.count, 4)
    }
    func testDisconnectServerIsolationAndStaleResponses() async {
        let api = MockAPI(), credentials = MemoryCredentials(), store = store(api, credentials: credentials)
        _ = await store.connect(testToken); store.selectServer(.production); XCTAssertFalse(store.hasCredential); XCTAssertNil(store.snapshot)
        XCTAssertNotNil(credentials.values[.local]); store.selectServer(.local); XCTAssertTrue(store.hasCredential)
        api.hold = true; let read = Task { await store.refresh() }
        while api.held == nil { await Task.yield() }
        let repeatRead = await store.refresh(); XCTAssertFalse(repeatRead)
        let repeatWrite = await store.setTaskCompletion("first", completed: true); XCTAssertFalse(repeatWrite)
        store.disconnect(); XCTAssertNil(credentials.values[.local]); XCTAssertFalse(store.hasCredential)
        api.held?.resume(returning: sample(50)); _ = await read.value; XCTAssertNil(store.snapshot); XCTAssertEqual(store.status, .disconnected)
    }
    func testVisibleOnlyPollingAndOlderRevisionProtection() async throws {
        let api = MockAPI(), store = store(api, pollInterval: 0.03); _ = await store.connect(testToken)
        try await Task.sleep(nanoseconds: 80_000_000); XCTAssertEqual(api.reads, 1)
        let source = UUID(); store.setContentVisible(true, source: source)
        try await Task.sleep(nanoseconds: 100_000_000); XCTAssertGreaterThan(api.reads, 2)
        store.setContentVisible(false, source: source); let count = api.reads
        try await Task.sleep(nanoseconds: 80_000_000); XCTAssertEqual(api.reads, count)
        api.result = sample(1); let older = await store.refresh(); XCTAssertFalse(older); XCTAssertEqual(store.snapshot?.revision, 4)
    }
    func testStaleReopeningTabSwitchesAndWakeShareThrottle() async throws {
        let api = MockAPI()
        var clock = Date(timeIntervalSince1970: 1791547200)
        let store = store(api, now: { clock })
        _ = await store.connect(testToken)
        let home = UUID(), weekly = UUID()
        store.setContentVisible(true, source: home)
        try await Task.sleep(for: .milliseconds(10))
        XCTAssertEqual(api.reads, 1) // Fresh connect is reused.
        store.setContentVisible(false, source: home)
        clock.addTimeInterval(6)
        api.result = sample(5, completed: true)
        store.setContentVisible(true, source: home)
        try await Task.sleep(for: .milliseconds(10))
        XCTAssertEqual(api.reads, 2)
        XCTAssertEqual(store.snapshot?.revision, 5)
        XCTAssertTrue(store.tasks(on: "2026-10-09").allSatisfy(\.completed))
        for _ in 0..<5 {
            store.setContentVisible(true, source: weekly)
            store.setContentVisible(false, source: home)
            store.setContentVisible(true, source: home)
            store.setContentVisible(false, source: weekly)
        }
        try await Task.sleep(for: .milliseconds(10))
        XCTAssertEqual(api.reads, 2)
        clock.addTimeInterval(6)
        api.result = sample(6) // External restoration while the Mac slept.
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        try await Task.sleep(for: .milliseconds(10))
        XCTAssertEqual(api.reads, 3)
        XCTAssertFalse(store.tasks(on: "2026-10-09")[0].completed)
        store.setContentVisible(false, source: home)
        clock.addTimeInterval(60)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        try await Task.sleep(for: .milliseconds(10))
        XCTAssertEqual(api.reads, 3) // Closed wake does not fetch.
    }
    func testLifecycleFailuresAreThrottledAndConcurrentReadsAreSkipped() async throws {
        let api = MockAPI()
        var clock = Date(timeIntervalSince1970: 1791547200)
        let store = store(api, now: { clock })
        _ = await store.connect(testToken)
        let source = UUID(), second = UUID()
        clock.addTimeInterval(6); api.error = .offline
        store.setContentVisible(true, source: source)
        try await Task.sleep(for: .milliseconds(10))
        XCTAssertEqual(api.reads, 2); XCTAssertEqual(store.status, .offline)
        for _ in 0..<5 { _ = await store.refreshVisibleContent() }
        XCTAssertEqual(api.reads, 2); XCTAssertEqual(store.snapshot?.revision, 4)
        clock.addTimeInterval(6); api.error = nil; api.hold = true
        let read = Task { await store.refreshVisibleContent() }
        while api.held == nil { await Task.yield() }
        store.setContentVisible(true, source: second)
        let duplicate = await store.refreshVisibleContent()
        XCTAssertFalse(duplicate); XCTAssertEqual(api.reads, 3)
        api.held?.resume(returning: sample(7)); _ = await read.value
        store.setContentVisible(false, source: source); store.setContentVisible(false, source: second)
        XCTAssertEqual(store.snapshot?.revision, 7)
    }
    func testRealKeychainLifecycle() throws {
        // Isolated temporary service, never the user's actual CoursePath credential.
        let keychain = CoursePathKeychain(service: "dev.coursepath.notch.tests." + UUID().uuidString)
        defer { try? keychain.delete(server: .local); try? keychain.delete(server: .production) }
        XCTAssertNil(try keychain.read(server: .local))
        try keychain.save(testToken, server: .local); XCTAssertEqual(try keychain.read(server: .local), testToken)
        XCTAssertNil(try keychain.read(server: .production))
        try keychain.save(testToken + "replacement", server: .local); XCTAssertEqual(try keychain.read(server: .local), testToken + "replacement")
        try keychain.delete(server: .local); try keychain.delete(server: .local); XCTAssertNil(try keychain.read(server: .local))
    }
    func testHomeAndSettingsSharePollingAndKeepOfflineRows() async throws {
        let api = MockAPI(), store = store(api, pollInterval: 0.03)
        _ = await store.connect(testToken)
        let home = UUID(), settings = UUID()
        store.setContentVisible(true, source: home)
        try await Task.sleep(nanoseconds: 10_000_000)
        let initialReads = api.reads
        store.setContentVisible(true, source: home)
        store.setContentVisible(true, source: settings)
        try await Task.sleep(nanoseconds: 5_000_000)
        XCTAssertEqual(api.reads, initialReads)
        store.setContentVisible(false, source: home)
        try await Task.sleep(nanoseconds: 70_000_000)
        XCTAssertGreaterThan(api.reads, initialReads)
        api.error = .offline
        _ = await store.refresh()
        XCTAssertEqual(store.status, .offline)
        XCTAssertEqual(CoursePathCalendarAdapter.items(in: store.snapshot, on: "2026-10-09").map(\.id), ["study:first", "study:second"])
        store.setContentVisible(false, source: settings)
        let finalReads = api.reads
        try await Task.sleep(nanoseconds: 70_000_000)
        XCTAssertEqual(api.reads, finalReads)
        api.error = .unauthorized
        _ = await store.refresh()
        XCTAssertTrue(CoursePathCalendarAdapter.items(in: store.snapshot, on: "2026-10-09").isEmpty)
        XCTAssertEqual(CoursePathCalendarPlaceholder.resolve(hasSnapshot: store.snapshot != nil, hasCredential: store.hasCredential, isBusy: store.isBusy), .disconnected)
    }
    func testCompletionFinishesWhenLeavingTabWithoutDuplicateWrites() async {
        let api = MockAPI(), store = store(api)
        _ = await store.connect(testToken)
        let source = UUID(); store.setContentVisible(true, source: source)
        // A just-connected snapshot is fresh; opening must not duplicate that read.
        await Task.yield()
        while store.isBusy { await Task.yield() }
        api.holdMutation = true
        let mutation = Task { await store.setTaskCompletion("first", completed: true) }
        while api.heldMutation == nil { await Task.yield() }
        let duplicate = await store.setTaskCompletion("first", completed: true)
        XCTAssertFalse(duplicate); XCTAssertEqual(api.writes.count, 1)
        XCTAssertFalse(store.snapshot!.tasks.first(where: { $0.id == "first" })!.completed)
        store.setContentVisible(false, source: source)
        XCTAssertTrue(store.isBusy)
        api.heldMutation?.resume()
        let confirmed = await mutation.value
        XCTAssertTrue(confirmed); XCTAssertEqual(store.status, .connected)
        let data = CoursePathTabData(snapshot: store.snapshot, today: "2026-10-09")
        XCTAssertEqual(data.progress, CoursePathTodayProgress(completed: 1, total: 2))
        XCTAssertEqual(store.snapshot?.revision, 5)
        XCTAssertEqual(api.writes.count, 1)
    }
    func testConfirmedWriteWithFailedRefreshKeepsCacheAndBlocksRepeatUntilRefresh() async {
        let api = MockAPI(), store = store(api); _ = await store.connect(testToken)
        api.error = .offline // The POST succeeds, but its following snapshot read fails.
        let result = await store.setTaskCompletion("first", completed: true)
        XCTAssertFalse(result); XCTAssertEqual(store.status, .offline)
        XCTAssertEqual(store.snapshot?.revision, 4)
        XCTAssertFalse(store.snapshot!.tasks.first(where: { $0.id == "first" })!.completed)
        let repeatWrite = await store.setTaskCompletion("first", completed: true)
        XCTAssertFalse(repeatWrite); XCTAssertEqual(api.writes.count, 1)
        api.error = nil
        let refreshed = await store.refresh()
        XCTAssertTrue(refreshed); XCTAssertEqual(store.snapshot?.revision, 5)
        XCTAssertTrue(store.snapshot!.tasks.first(where: { $0.id == "first" })!.completed)
        XCTAssertEqual(api.writes.count, 1)
    }
    func testSharedHomeAndWeeklyCompletionAndRestorationUseOneAuthoritativeStore() async {
        let api = MockAPI(), store = store(api); _ = await store.connect(testToken)
        let controller = CoursePathCompletionController(store: store)
        let confirmed = await controller.setCompletion("first", completed: true)
        XCTAssertTrue(confirmed); XCTAssertNil(controller.notice)
        let home = CoursePathCalendarAdapter.items(in: store.snapshot, on: "2026-10-09")
        let weekly = CoursePathWeekData(snapshot: store.snapshot, selection: CoursePathWeekSelection(today: "2026-10-09"), today: "2026-10-09")
        XCTAssertEqual(home.map(\.sourceID), ["second", "first"])
        XCTAssertEqual(weekly.selectedTasks.map(\.sourceID), home.map(\.sourceID))
        XCTAssertEqual(weekly.progress.completed, 1); XCTAssertEqual(store.tasks(on: "2026-10-09").map(\.id), ["second", "first"])
        let restored = await controller.setCompletion("first", completed: false)
        XCTAssertTrue(restored); XCTAssertEqual(store.tasks(on: "2026-10-09").map(\.id), ["first", "second"])
        XCTAssertEqual(api.writes.map { $0.2 }, [4, 5]); XCTAssertEqual(api.writes.count, 2)
    }
    func testSharedCompletionFailureConflictAndExternalChanges() async {
        let api = MockAPI(), store = store(api); _ = await store.connect(testToken)
        let controller = CoursePathCompletionController(store: store)
        api.mutationError = .offline
        let failed = await controller.setCompletion("first", completed: true)
        XCTAssertFalse(failed); XCTAssertNotNil(controller.notice); XCTAssertFalse(controller.canUpdate)
        XCTAssertTrue(store.snapshot!.tasks.allSatisfy { !$0.completed })
        _ = await controller.setCompletion("first", completed: true); XCTAssertEqual(api.writes.count, 1)
        api.mutationError = nil; _ = await store.refresh()
        api.mutationError = .conflict; api.result = sample(9, completed: true)
        let conflicted = await controller.setCompletion("first", completed: true)
        XCTAssertFalse(conflicted); XCTAssertEqual(store.snapshot?.revision, 9)
        XCTAssertTrue(controller.notice?.contains("Calendar changed") == true); XCTAssertEqual(api.writes.count, 2)
        api.mutationError = nil; api.result = sample(10)
        _ = await store.refresh()
        let data = CoursePathWeekData(snapshot: store.snapshot, selection: CoursePathWeekSelection(today: "2026-10-09"), today: "2026-10-09")
        XCTAssertEqual(data.progress.completed, 0); XCTAssertEqual(data.selectedTasks.map(\.sourceID), ["first", "second"])
    }
}
