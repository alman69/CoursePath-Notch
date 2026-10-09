import Foundation
import Combine

@MainActor
final class CoursePathStore: ObservableObject {
    static let shared = CoursePathStore()
    enum Status: String { case disconnected, ready, connecting, connected, offline, expired, failed }
    @Published private(set) var server: CoursePathServer
    @Published private(set) var snapshot: CoursePathSnapshot?
    @Published private(set) var status: Status = .disconnected
    @Published private(set) var message = "Not connected."
    @Published private(set) var isBusy = false
    @Published private(set) var hasCredential = false
    @Published private(set) var lastUpdated: Date?
    var isCached: Bool { snapshot != nil && status != .connected }
    var upcomingDeadlines: [CoursePathDeadline] { snapshot?.upcomingDeadlines ?? [] }
    private let api: CoursePathAPI
    private let credentials: CoursePathCredentialStorage
    private let preferences: UserDefaults
    private let now: () -> Date
    private let pollInterval: TimeInterval
    private var token: String?
    private var generation = UUID()
    private var requestTask: Task<CoursePathSnapshot, Error>?
    private var pollingTask: Task<Void, Never>?
    private var visibleSources = Set<UUID>()

    init(api: CoursePathAPI = CoursePathAPIClient(), credentials: CoursePathCredentialStorage = CoursePathKeychain(), preferences: UserDefaults = .standard, now: @escaping () -> Date = Date.init, pollInterval: TimeInterval = 20) {
        self.api = api; self.credentials = credentials; self.preferences = preferences; self.now = now; self.pollInterval = pollInterval
        server = CoursePathServer(rawValue: preferences.string(forKey: "CoursePath.server") ?? "") ?? .local
        restoreCredential()
    }
    private func restoreCredential() {
        do {
            token = try credentials.read(server: server); hasCredential = token != nil
            status = hasCredential ? .ready : .disconnected
            message = hasCredential ? "Ready to verify connection." : "Not connected."
        } catch { status = .failed; message = error.localizedDescription }
    }
    func selectServer(_ server: CoursePathServer) {
        guard server != self.server else { return }
        cancelRequests(); token = nil; hasCredential = false; snapshot = nil; lastUpdated = nil
        self.server = server; preferences.set(server.rawValue, forKey: "CoursePath.server")
        restoreCredential(); restartPolling()
    }
    @discardableResult
    func connect(_ input: String) async -> Bool {
        guard !isBusy else { return false }
        let candidate = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard candidate.range(of: #"^cpn_[A-Za-z0-9_-]{43}$"#, options: .regularExpression) != nil else {
            status = .failed; message = CoursePathError.invalidToken.localizedDescription; return false
        }
        return await perform(candidate: candidate)
    }
    @discardableResult
    func refresh() async -> Bool {
        guard let token, !isBusy else { return false }
        return await perform(candidate: token)
    }
    @discardableResult
    func setTaskCompletion(_ id: String, completed: Bool) async -> Bool {
        guard let token, let snapshot, status == .connected, !isBusy, snapshot.tasks.contains(where: { $0.id == id }) else { return false }
        return await perform(candidate: token, mutation: (id, completed, snapshot.revision))
    }
    // In-memory, authoritative data only; no speculative completion toggles or calendar disk cache.
    private func perform(candidate: String, mutation: (String, Bool, Int)? = nil) async -> Bool {
        let version = generation, server = server, today = CoursePathDate.key(now()), api = api
        isBusy = true; status = .connecting; message = "Connecting…"
        var conflicted = false
        let request = Task<CoursePathSnapshot, Error> {
            try Task.checkCancellation()
            if let mutation {
                do { _ = try await api.complete(server: server, token: candidate, taskId: mutation.0, completed: mutation.1, revision: mutation.2) }
                catch CoursePathError.conflict { conflicted = true }
                try Task.checkCancellation()
            }
            return try await api.snapshot(server: server, token: candidate, today: today)
        }
        requestTask = request
        defer { if generation == version { isBusy = false; requestTask = nil } }
        do {
            let result = try await request.value
            guard generation == version, !request.isCancelled else { return false }
            guard result.revision >= (self.snapshot?.revision ?? 0) else { throw CoursePathError.invalidResponse }
            if token != candidate || !hasCredential { try credentials.save(candidate, server: server) }
            token = candidate; hasCredential = true; self.snapshot = result; lastUpdated = now(); status = .connected
            message = conflicted ? "The calendar changed. Latest progress loaded; review before trying again." : "Connected."
            return !conflicted
        } catch {
            guard generation == version, !request.isCancelled else { return false }
            if error as? CoursePathError == .unauthorized {
                token = nil; hasCredential = false; self.snapshot = nil; lastUpdated = nil; status = .expired
                do { try credentials.delete(server: server) }
                catch { message = "Access expired. Disconnect to remove the stored credential."; return false }
            } else { status = hasCredential ? .offline : .failed }
            message = (error as? CoursePathError)?.localizedDescription ?? "CoursePath could not be reached."
            if mutation != nil && status == .offline { message += " Progress may be stale. Refresh before another update." }
            return false
        }
    }
    func disconnect() {
        cancelRequests(); token = nil; hasCredential = false; snapshot = nil; lastUpdated = nil
        do { try credentials.delete(server: server); status = .disconnected; message = "Disconnected. Revoke the device in CoursePath Settings to also remove server access." }
        catch { status = .failed; message = error.localizedDescription }
    }
    private func cancelRequests() {
        generation = UUID(); requestTask?.cancel(); requestTask = nil; isBusy = false
    }
    func tasks(on day: String) -> [CoursePathTask] {
        (snapshot?.tasks ?? []).filter { $0.date == day }.sorted { $0.order == $1.order ? $0.id < $1.id : $0.order < $1.order }
    }
    func setContentVisible(_ visible: Bool, source: UUID) {
        if visible { visibleSources.insert(source) } else { visibleSources.remove(source) }
        restartPolling()
    }
    private func restartPolling() {
        pollingTask?.cancel(); pollingTask = nil
        guard !visibleSources.isEmpty else {
            // Cancel reads when all CoursePath surfaces leave view; disconnect also invalidates writes.
            if requestTask != nil { cancelRequests(); status = hasCredential ? .ready : .disconnected }
            return
        }
        pollingTask = Task { [weak self] in
            guard let self else { return }
            guard !Task.isCancelled, !self.visibleSources.isEmpty else { return }
            _ = await self.refresh()
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: UInt64(self.pollInterval * 1_000_000_000)) } catch { return }
                guard !Task.isCancelled else { return }
                _ = await self.refresh()
            }
        }
    }
}
