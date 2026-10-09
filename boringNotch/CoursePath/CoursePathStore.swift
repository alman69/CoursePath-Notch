import Foundation
import Combine
import AppKit

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
    @Published private(set) var currentDay: String
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
    private var isMutationInFlight = false
    private var pollingTask: Task<Void, Never>?
    var hasActivePolling: Bool { pollingTask != nil }
    private var visibleSources = Set<UUID>()
    private var lastRequestStarted: Date?
    private let visibilityRefreshInterval: TimeInterval = 5
    private let workspaceNotifications = NSWorkspace.shared.notificationCenter
    private var workspaceObservers: [NSObjectProtocol] = []
    private var dayObservers: [NSObjectProtocol] = []
    private var isAsleep = false
    private var lastSnapshotDay: String?

    init(api: CoursePathAPI = CoursePathAPIClient(), credentials: CoursePathCredentialStorage = CoursePathKeychain(), preferences: UserDefaults = .standard, now: @escaping () -> Date = Date.init, pollInterval: TimeInterval = 20) {
        self.api = api; self.credentials = credentials; self.preferences = preferences; self.now = now; self.pollInterval = pollInterval
        currentDay = CoursePathDate.key(now())
        server = CoursePathServer(rawValue: preferences.string(forKey: "CoursePath.server") ?? "") ?? .local
        restoreCredential()
        workspaceObservers.append(workspaceNotifications.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleSleep() }
        })
        workspaceObservers.append(workspaceNotifications.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleWake() }
        })
        for name in [Notification.Name.NSCalendarDayChanged, .NSSystemTimeZoneDidChange] {
            dayObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.updateCurrentDay()
                    await self?.refreshVisibleContent()
                }
            })
        }
    }
    deinit {
        workspaceObservers.forEach(workspaceNotifications.removeObserver)
        dayObservers.forEach(NotificationCenter.default.removeObserver)
        pollingTask?.cancel()
        requestTask?.cancel()
    }
    private func updateCurrentDay() {
        let day = CoursePathDate.key(now())
        if day != currentDay { currentDay = day }
    }
    private func handleSleep() {
        isAsleep = true
        restartPolling()
    }
    private func handleWake() {
        isAsleep = false
        updateCurrentDay()
        restartPolling()
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
        cancelRequests(); token = nil; hasCredential = false; snapshot = nil; lastUpdated = nil; lastRequestStarted = nil; lastSnapshotDay = nil
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
        updateCurrentDay()
        let version = generation, server = server, today = currentDay, api = api
        lastRequestStarted = now()
        isBusy = true; isMutationInFlight = mutation != nil; status = .connecting; message = "Connecting…"
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
        defer {
            if generation == version {
                isBusy = false; isMutationInFlight = false; requestTask = nil
                if pollingTask == nil && hasCredential && !visibleSources.isEmpty && !isAsleep { restartPolling() }
            }
        }
        do {
            let result = try await request.value
            guard generation == version, !request.isCancelled else { return false }
            guard result.revision >= (self.snapshot?.revision ?? 0) else { throw CoursePathError.invalidResponse }
            if token != candidate || !hasCredential { try credentials.save(candidate, server: server) }
            token = candidate; hasCredential = true; self.snapshot = result; lastUpdated = now(); lastSnapshotDay = today; status = .connected
            updateCurrentDay()
            if today != currentDay { Task { [weak self] in await self?.refreshVisibleContent() } }
            message = conflicted ? "The calendar changed. Latest progress loaded; review before trying again." : "Connected."
            return !conflicted
        } catch {
            guard generation == version, !request.isCancelled else { return false }
            if error as? CoursePathError == .unauthorized {
                token = nil; hasCredential = false; self.snapshot = nil; lastUpdated = nil; lastSnapshotDay = nil; status = .expired
                pollingTask?.cancel(); pollingTask = nil
                do { try credentials.delete(server: server) }
                catch { message = "Access expired. Disconnect to remove the stored credential."; return false }
            } else { status = hasCredential ? .offline : .failed }
            message = (error as? CoursePathError)?.localizedDescription ?? "CoursePath could not be reached."
            if mutation != nil && status == .offline { message += " Progress may be stale. Refresh before another update." }
            return false
        }
    }
    func disconnect() {
        cancelRequests(); token = nil; hasCredential = false; snapshot = nil; lastUpdated = nil; lastRequestStarted = nil; lastSnapshotDay = nil
        do { try credentials.delete(server: server); status = .disconnected; message = "Disconnected. Revoke the device in CoursePath Settings to also remove server access." }
        catch { status = .failed; message = error.localizedDescription }
        restartPolling()
    }
    private func cancelRequests() {
        generation = UUID(); requestTask?.cancel(); requestTask = nil; isBusy = false; isMutationInFlight = false
    }
    func tasks(on day: String) -> [CoursePathTask] {
        CoursePathTaskPresentation.sorted((snapshot?.tasks ?? []).filter { $0.date == day })
    }
    func setContentVisible(_ visible: Bool, source: UUID) {
        updateCurrentDay()
        let changed = visible ? visibleSources.insert(source).inserted : visibleSources.remove(source) != nil
        guard changed else { return }
        // A newly visible tab/display shares the same throttle and polling loop.
        if visibleSources.isEmpty || pollingTask == nil { restartPolling() }
        else if visible { Task { [weak self] in await self?.refreshVisibleContent() } }
    }
    // Used for opening, tab changes and wake. Explicit refreshes and post-mutation
    // snapshots remain immediate; failed lifecycle reads are also rate limited.
    private var visibilityRefreshDelay: TimeInterval? {
        guard !visibleSources.isEmpty, !isAsleep, !isBusy else { return nil }
        let dayChanged = lastSnapshotDay.map { $0 != currentDay } ?? false
        guard dayChanged || (lastUpdated.map({ now().timeIntervalSince($0) >= visibilityRefreshInterval }) ?? true) else { return nil }
        guard let lastRequestStarted, CoursePathDate.key(lastRequestStarted) == currentDay else { return 0 }
        return max(0, visibilityRefreshInterval - now().timeIntervalSince(lastRequestStarted))
    }
    @discardableResult
    func refreshVisibleContent() async -> Bool {
        updateCurrentDay()
        guard visibilityRefreshDelay == 0 else { return false }
        return await refresh()
    }
    private func restartPolling() {
        pollingTask?.cancel(); pollingTask = nil
        guard !visibleSources.isEmpty, hasCredential, !isAsleep else {
            // Hidden/asleep reads are dispensable. Already-issued user writes must finish.
            if requestTask != nil && !isMutationInFlight {
                cancelRequests(); status = hasCredential ? .ready : .disconnected
                message = hasCredential ? "Ready to refresh connection." : "Not connected."
            }
            return
        }
        let interval = pollInterval
        pollingTask = Task { [weak self] in
            guard !Task.isCancelled else { return }
            // A canceled first read must retry after the shared throttle, rather
            // than waiting a whole polling interval after a rapid close/reopen.
            if let delay = self?.visibilityRefreshDelay {
                do { if delay > 0 { try await Task.sleep(for: .seconds(delay)) } } catch { return }
                guard !Task.isCancelled else { return }
                _ = await self?.refreshVisibleContent()
            }
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000)) } catch { return }
                // Do not hold a strong store reference across the timer's suspension.
                guard !Task.isCancelled, let store = self else { return }
                _ = await store.refresh()
            }
        }
    }
}
