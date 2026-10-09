import SwiftUI
import Defaults

extension Notification.Name {
    static let coursePathConnectionSettings = Notification.Name("CoursePath.connectionSettings")
}

struct CoursePathCalendarView: View {
    @EnvironmentObject private var vm: BoringViewModel
    @Environment(\.openURL) private var openURL
    @ObservedObject private var store = CoursePathStore.shared
    @ObservedObject private var coordinator = BoringViewCoordinator.shared
    @Default(.showFullEventTitles) private var showFullEventTitles
    @State private var selectedDate = Date()
    @State private var visibilityID = UUID()

    private var items: [CoursePathCalendarItem] {
        CoursePathCalendarAdapter.items(in: store.snapshot, on: CoursePathDate.key(selectedDate))
    }

    var body: some View {
        VStack(spacing: 0) {
            CalendarDateHeader(selectedDate: $selectedDate)
            if items.isEmpty {
                placeholder
                Spacer(minLength: 0)
            } else {
                ScrollViewReader { proxy in
                    List {
                        ForEach(items) { item in
                            Button {
                                // With a separate Vite/API server, open the website, not the API port.
                                openURL(store.server == .localAPI ? CoursePathServer.local.baseURL : store.server.baseURL)
                            } label: {
                                CalendarEntryRow(title: item.title, subtitle: item.subtitle,
                                    color: item.colorHue.map { Color(hue: $0 / 360, saturation: 0.6, brightness: 0.8) } ?? .effectiveAccent,
                                    showFullTitle: showFullEventTitles, completed: item.completed) {
                                    VStack(alignment: .trailing, spacing: 4) {
                                        ForEach(Array(item.details.enumerated()), id: \.offset) { index, detail in
                                            Text(detail).foregroundColor(index == 0 ? .white : Color(white: 0.65)).lineLimit(1)
                                        }
                                    }
                                    .font(.caption)
                                    .frame(minWidth: 44, alignment: .trailing)
                                }
                                .opacity(item.completed ? 0.4 : 1)
                            }
                            .accessibilityHint("Open in CoursePath")
                            .accessibilityValue(item.completed ? "Completed" : "Incomplete")
                            .id(item.id)
                            .padding(.leading, -5)
                            .buttonStyle(PlainButtonStyle())
                            .listRowSeparator(.automatic)
                            .listRowSeparatorTint(.gray.opacity(0.2))
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .scrollIndicators(.never)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .onChange(of: selectedDate) { _, _ in
                        if let first = items.first { withTransaction(Transaction(animation: nil)) { proxy.scrollTo(first.id, anchor: .top) } }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .listRowBackground(Color.clear)
        .frame(height: 120)
        .help(store.isCached ? "Showing the last fetched CoursePath calendar." : "CoursePath calendar")
        .onAppear { selectedDate = .now; updateVisibility() }
        .onChange(of: vm.notchState) { _, _ in selectedDate = .now; updateVisibility() }
        .onChange(of: coordinator.currentView) { _, _ in updateVisibility() }
        .onDisappear { store.setContentVisible(false, source: visibilityID) }
    }

    private func updateVisibility() {
        store.setContentVisible(vm.notchState == .open && coordinator.currentView == .home, source: visibilityID)
    }

    @ViewBuilder private var placeholder: some View {
        switch CoursePathCalendarPlaceholder.resolve(hasSnapshot: store.snapshot != nil, hasCredential: store.hasCredential, isBusy: store.isBusy) {
        case .empty:
            EmptyEventsView(selectedDate: selectedDate)
        case .disconnected, .loading, .unavailable:
            VStack {
                Image(systemName: "calendar.badge.clock").font(.title).foregroundColor(Color(white: 0.65))
                Text(store.isBusy ? "Loading calendar…" : store.hasCredential ? "Calendar unavailable" : "Connect CoursePath")
                    .font(.subheadline).foregroundColor(.white)
                Button("Open connection settings") {
                    SettingsWindowController.shared.showWindow()
                    DispatchQueue.main.async { NotificationCenter.default.post(name: .coursePathConnectionSettings, object: nil) }
                }
                .font(.caption).foregroundColor(Color(white: 0.65)).buttonStyle(PlainButtonStyle())
            }
        }
    }
}
