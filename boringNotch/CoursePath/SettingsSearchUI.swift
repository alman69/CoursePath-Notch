import SwiftUI
import Defaults
import AVFoundation

private struct SettingsSearchHighlightKey: EnvironmentKey {
    static let defaultValue: String? = nil
}
extension EnvironmentValues {
    var settingsSearchHighlight: String? {
        get { self[SettingsSearchHighlightKey.self] }
        set { self[SettingsSearchHighlightKey.self] = newValue }
    }
}
private struct SettingsSearchSection: ViewModifier {
    let section: String
    @Environment(\.settingsSearchHighlight) private var highlighted
    func body(content: Content) -> some View {
        content.id(section)
            .listRowBackground(highlighted == section ? Color.effectiveAccent.opacity(0.12) : nil)
            .background(highlighted == section ? Color.effectiveAccent.opacity(0.08) : Color.clear)
            .animation(.easeInOut(duration: 0.2), value: highlighted)
    }
}
extension View {
    func settingsSearchSection(_ id: String) -> some View { modifier(SettingsSearchSection(section: id)) }
}

struct SettingsSearchSidebar: View {
    @Binding var query: String
    let navigate: (SettingsSearchEntry, String?) -> Void
    @State private var selectedResult: String?
    @State private var accessibilityAuthorized = false
    @FocusState private var searchFocused: Bool
    @ObservedObject private var store = CoursePathStore.shared
    @Default(.showOnAllDisplays) private var allDisplays
    @Default(.notchHeightMode) private var notchHeightMode
    @Default(.nonNotchHeightMode) private var nonNotchHeightMode
    @Default(.openNotchOnHover) private var hover
    @Default(.enableGestures) private var gestures
    @Default(.useMusicVisualizer) private var musicVisualizer
    @Default(.customVisualizers) private var visualizers
    @Default(.hudReplacement) private var hud
    @Default(.showOpenNotchHUD) private var openHUD
    @Default(.useCustomAccentColor) private var customAccent

    private var results: [SettingsSearchEntry] { SettingsSearchIndex.search(query) }
    private var enabled: Set<String> {
        var flags = Set<String>()
        if !allDisplays { flags.insert("singleDisplay") }
        if notchHeightMode == .custom { flags.insert("customNotch") }
        if nonNotchHeightMode == .custom { flags.insert("customNonNotch") }
        if hover { flags.insert("hover") }
        if gestures { flags.insert("gestures") }
        if !musicVisualizer && !visualizers.isEmpty { flags.insert("animationSelection") }
        if AVCaptureDevice.default(for: .video) != nil { flags.insert("camera") }
        if !store.hasCredential { flags.insert("needsCredential") }
        if store.hasCredential && !store.isBusy { flags.insert("credential") }
        if store.status != .disconnected { flags.insert("disconnect") }
        if accessibilityAuthorized { flags.insert("accessibility") }
        else { flags.insert("needsAccessibility") }
        if hud { flags.insert("hud") }
        if hud && openHUD { flags.insert("openHUD") }
        if customAccent { flags.insert("customAccent") }
        return flags
    }
    private func reason(_ entry: SettingsSearchEntry) -> String? {
        if entry.category == "CoursePath", store.isBusy, ["connect", "refresh"].contains(entry.id.components(separatedBy: ".").last ?? "") {
            return "A CoursePath request is in progress. Wait for it to finish."
        }
        if entry.id == "coursepath.browserConnect", !store.browserPairingEnabled { return "Browser pairing is disabled in this development build." }
        if entry.id == "coursepath.connect", !store.hasCredential { return "Enter a desktop access token in CoursePath to enable Connect." }
        return entry.reason(enabled: enabled)
    }
    private func open(_ entry: SettingsSearchEntry) {
        searchFocused = false
        navigate(entry, reason(entry))
        query = ""
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search settings…", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onSubmit { if let entry = results.first(where: { $0.id == selectedResult }) ?? results.first { open(entry) } }
                    .onExitCommand { query = "" }
                    .onMoveCommand { direction in
                        guard !results.isEmpty, direction == .up || direction == .down else { return }
                        let current = results.firstIndex(where: { $0.id == selectedResult }) ?? -1
                        let index = max(0, min(results.count - 1, current + (direction == .down ? 1 : -1)))
                        selectedResult = results[index].id
                    }
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain).accessibilityLabel("Clear search")
                }
            }
            .padding(7)
            .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            .padding(10)
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if results.isEmpty {
                    Text("No matching settings").font(.callout).foregroundStyle(.secondary).padding()
                } else {
                    List(selection: $selectedResult) {
                        ForEach(results) { entry in
                            Button { open(entry) } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(entry.title).foregroundStyle(.primary)
                                    Text(entry.destinationLabel)
                                        .font(.caption).foregroundStyle(.secondary)
                                    if let reason = reason(entry) { Text(reason).font(.caption2).foregroundStyle(.secondary) }
                                }
                                .lineLimit(nil)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain).tag(entry.id)
                            .help([entry.title, entry.destinationLabel, reason(entry)].compactMap { $0 }.joined(separator: "\n"))
                        }
                    }
                    .listStyle(.sidebar).frame(maxHeight: 240)
                    .onKeyPress(.return) {
                        guard let entry = results.first(where: { $0.id == selectedResult }) else { return .ignored }
                        open(entry); return .handled
                    }
                    .onExitCommand { query = "" }
                }
                Divider()
            }
        }
        .onChange(of: query) { _, _ in selectedResult = nil }
        .task(id: query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
            guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            accessibilityAuthorized = await XPCHelperClient.shared.isAccessibilityAuthorized()
        }
        .onReceive(NotificationCenter.default.publisher(for: .accessibilityAuthorizationChanged)) { notification in
            if let granted = notification.userInfo?["granted"] as? Bool { accessibilityAuthorized = granted }
        }
    }
}
