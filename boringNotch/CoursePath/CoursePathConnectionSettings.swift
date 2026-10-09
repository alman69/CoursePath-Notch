import SwiftUI
import AppKit

struct CoursePathConnectionSettings: View {
    @ObservedObject private var store = CoursePathStore.shared
    @State private var pastedToken = ""
    @State private var visibilityID = UUID()

    var body: some View {
        Form {
            Section("CoursePath connection") {
                Picker("Server", selection: Binding(get: { store.server }, set: {
                    pastedToken = ""; store.selectServer($0)
                })) {
                    ForEach(CoursePathServer.allCases) { server in Text(server.label).tag(server) }
                }
                Text(store.server.baseURL.absoluteString).font(.caption).foregroundStyle(.secondary)
                if !store.hasCredential {
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
                    Button("Disconnect") { pastedToken = ""; store.disconnect() }
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
            Section {
                Text("Generate a desktop token in CoursePath Settings → CoursePath Notch. Credentials stay in this Mac’s Keychain. Each server uses its own credential.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Calendar and task views will be connected in a later phase.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("CoursePath")
        .background(CoursePathSettingsVisibility { visible in store.setContentVisible(visible, source: visibilityID) })
        .onDisappear { pastedToken = ""; store.setContentVisible(false, source: visibilityID) }
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
