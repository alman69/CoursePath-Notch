import SwiftUI
import AppKit

struct CoursePathConnectionSettings: View {
    @ObservedObject private var store = CoursePathStore.shared
    @State private var browser = CoursePathBrowserSession()
    @State private var pairingTask: Task<Void, Never>?
    @State private var pastedToken = ""
    @State private var visibilityID = UUID()

    var body: some View {
        Form {
            Section("CoursePath connection") {
                Picker("Server", selection: Binding(get: { store.server }, set: {
                    pairingTask?.cancel(); browser.cancel(); pastedToken = ""; store.selectServer($0)
                })) {
                    ForEach(CoursePathServer.allCases) { server in Text(server.label).tag(server) }
                }
                Text(store.server.baseURL.absoluteString).font(.caption).foregroundStyle(.secondary)
                if !store.hasCredential {
                    if store.browserPairingEnabled {
                        Button("Connect CoursePath") {
                            pairingTask = Task { _ = await store.connectBrowser(browser: browser.open) }
                        }.disabled(store.isBusy)
                        if let code = store.pairingConfirmation {
                            Text("Confirmation code: " + code).monospaced().textSelection(.enabled)
                            Button("Cancel connection") { pairingTask?.cancel(); browser.cancel() }
                        }
                    }
                    SecureField("Desktop access token", text: $pastedToken)
                        .textContentType(.password)
                    Button("Connect") {
                        let token = pastedToken; pastedToken = ""
                        Task { await store.connect(token) }
                    }
                    .disabled(store.isBusy || pastedToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                HStack {
                    Button("Refresh") { Task { await store.refresh() } }
                        .disabled(store.isBusy || !store.hasCredential)
                    Button("Disconnect") { pairingTask?.cancel(); browser.cancel(); pastedToken = ""; store.disconnect() }
                        .disabled(store.status == .disconnected)
                    if store.isBusy { ProgressView().controlSize(.small) }
                }
                Text(store.message).foregroundStyle(.secondary).accessibilityLabel("CoursePath status: " + store.message)
                if let snapshot = store.snapshot {
                    Text("\(snapshot.tasks.count) study tasks · \(snapshot.upcomingDeadlines.count) upcoming deadlines")
                    if let updated = store.lastUpdated {
                        Text("Last refreshed \(updated.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if store.isCached { Text("Showing cached data. Refresh before updating progress.").font(.caption).foregroundStyle(.secondary) }
                }
            }
            .settingsSearchSection("coursepath.connection")
            Section {
                Text(store.browserPairingEnabled ? "Connect through your browser and confirm the code shown here. Manual desktop tokens remain available as a development fallback. Credentials stay in this Mac’s Keychain." : "Generate a desktop token in CoursePath Settings → CoursePath Notch. Credentials stay in this Mac’s Keychain. Each server uses its own credential.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("CoursePath")
        .background(CoursePathSettingsVisibility { visible in store.setContentVisible(visible, source: visibilityID) })
        .onDisappear { pairingTask?.cancel(); browser.cancel(); pastedToken = ""; store.setContentVisible(false, source: visibilityID) }
    }
}

// A closed/minimized/inactive Settings window can keep its hosting view alive.
// Observe the real window rather than relying only on SwiftUI onDisappear.
private struct CoursePathSettingsVisibility: NSViewRepresentable {
    let changed: (Bool) -> Void
    func makeNSView(context: Context) -> Monitor { Monitor(changed: changed) }
    func updateNSView(_ view: Monitor, context: Context) { view.changed = changed }
    static func dismantleNSView(_ view: Monitor, coordinator: ()) { view.stop() }

    final class Monitor: NSView {
        var changed: (Bool) -> Void
        private var observers: [NSObjectProtocol] = []
        private var visible = false
        init(changed: @escaping (Bool) -> Void) { self.changed = changed; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow(); stop()
            guard let window else { return }
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification, NSWindow.didChangeOcclusionStateNotification, NSWindow.willCloseNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] notification in
                    guard let self else { return }
                    self.updateVisible(notification.name != NSWindow.willCloseNotification && window.isVisible && window.isKeyWindow && window.occlusionState.contains(.visible))
                })
            }
            updateVisible(window.isVisible && window.isKeyWindow && window.occlusionState.contains(.visible))
        }
        private func updateVisible(_ value: Bool) { if value != visible { visible = value; changed(value) } }
        func stop() { observers.forEach(NotificationCenter.default.removeObserver); observers.removeAll(); updateVisible(false) }
        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }
}
