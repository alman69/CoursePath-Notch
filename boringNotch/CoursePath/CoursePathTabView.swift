import SwiftUI
import Defaults

struct CoursePathTabView: View {
    @EnvironmentObject private var vm: BoringViewModel
    @Environment(\.openURL) private var openURL
    @ObservedObject private var store = CoursePathStore.shared
    @ObservedObject private var coordinator = BoringViewCoordinator.shared
    @ObservedObject private var completion = CoursePathCompletionController.shared
    @Default(.showFullEventTitles) private var showFullEventTitles
    @State private var visibilityID = UUID()
    @State private var calendarDay = CoursePathDate.key(.now)
    @State private var selection = CoursePathWeekSelection(today: CoursePathDate.key(.now))

    var body: some View {
        let today = store.currentDay
        let data = CoursePathWeekData(snapshot: store.snapshot, selection: selection, today: today)
        Group {
            if store.snapshot == nil {
                VStack(spacing: 8) {
                    CoursePathConnectionPrompt(store: store)
                    openCoursePathButton
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        Text("\(data.progress.completed)/\(data.progress.total) steps")
                        Text("·").foregroundColor(.gray)
                        Text("\(CoursePathTaskPresentation.duration(data.remainingMinutes)) left")
                        Text("·").foregroundColor(.gray)
                        Text("\(data.upcomingDeadlineCount) deadlines")
                        Spacer(minLength: 0)
                        if store.isCached && !store.isBusy { Text("Cached").foregroundColor(.gray) }
                    }
                    .font(.caption).foregroundColor(.white).lineLimit(1)
                    .help("Steps and remaining time cover the selected week. Deadlines include all upcoming assignments.")
                    ProgressView(value: data.progress.fraction)
                        .progressViewStyle(.linear).tint(Color(white: 0.65)).frame(height: 3)
                        .accessibilityLabel("Selected week's completed study steps")
                    if let notice = completion.notice {
                        Text(notice).font(.caption).foregroundColor(Color(white: 0.65))
                            .lineLimit(1).help(notice).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            weekHeader
                            workloadGraph(data.days, today: today)
                            Button {
                                withAnimation(.smooth(duration: 0.2)) { selection.toggleExpanded() }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: selection.isExpanded ? "chevron.down" : "chevron.right")
                                    Text(CoursePathDate.date(selection.selectedDay)?.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) ?? selection.selectedDay)
                                    Spacer(minLength: 0)
                                    Text("\(data.selectedTasks.count) steps").foregroundColor(.gray)
                                }
                                .font(.caption).foregroundColor(.white)
                                .frame(minHeight: 24).contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())
                            .accessibilityLabel("\(selection.isExpanded ? "Collapse" : "Expand") selected day's study steps")
                            if selection.isExpanded {
                                if data.selectedTasks.isEmpty {
                                    Text("No study steps this day").font(.caption).foregroundColor(.gray)
                                }
                                LazyVStack(spacing: 0) {
                                    ForEach(data.selectedTasks) { row in
                                        CoursePathStudyRow(row: row, showFullTitle: showFullEventTitles)
                                            .padding(.vertical, 4)
                                        Divider().opacity(0.2)
                                    }
                                }
                                .animation(.smooth(duration: 0.2), value: data.selectedTasks.map(\.id))
                            }
                            HStack {
                                Text("Upcoming deadlines").font(.caption).foregroundColor(.gray)
                                Spacer(minLength: 0)
                                openCoursePathButton
                            }
                            if data.deadlines.isEmpty {
                                Text("No upcoming deadlines").font(.caption).foregroundColor(.gray)
                            }
                            ForEach(data.deadlines) { deadline in
                                CalendarEntryRow(title: deadline.title, subtitle: deadline.course.isEmpty ? "Deadline" : deadline.course,
                                    color: deadline.colorHue.map { Color(hue: $0 / 360, saturation: 0.6, brightness: 0.8) } ?? .effectiveAccent,
                                    showFullTitle: showFullEventTitles, subtitleIcon: "calendar") {
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text(deadline.dateLabel).foregroundColor(deadline.dueToday ? .white : Color(white: 0.65))
                                        if let time = deadline.timeLabel { Text(time).foregroundColor(Color(white: 0.65)) }
                                    }
                                    .font(.caption)
                                }
                                Divider().opacity(0.2)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity).frame(height: 120, alignment: .top)
        .onAppear { advanceDay(store.currentDay); updateVisibility() }
        .onChange(of: store.currentDay) { _, current in advanceDay(current) }
        .onChange(of: vm.notchState) { _, _ in updateVisibility() }
        .onChange(of: coordinator.currentView) { _, _ in updateVisibility() }
        .onChange(of: store.server) { _, _ in completion.clearNotice() }
        .onChange(of: store.hasCredential) { _, credential in if !credential { completion.clearNotice() } }
        .onDisappear { store.setContentVisible(false, source: visibilityID) }
    }

    private var weekHeader: some View {
        HStack(spacing: 6) {
            Button {
                withAnimation(.smooth(duration: 0.2)) { selection.moveWeek(-1) }
            } label: { Image(systemName: "chevron.left").frame(width: 24, height: 24) }
            .accessibilityLabel("Previous week")
            Text(weekLabel).font(.caption).foregroundColor(.white)
            Button {
                withAnimation(.smooth(duration: 0.2)) { selection.moveWeek(1) }
            } label: { Image(systemName: "chevron.right").frame(width: 24, height: 24) }
            .accessibilityLabel("Next week")
            Spacer(minLength: 0)
        }
        .buttonStyle(PlainButtonStyle()).foregroundColor(.gray)
    }
    private var weekLabel: String {
        guard let first = CoursePathDate.date(selection.days[0]), let last = CoursePathDate.date(selection.days[6]) else { return "" }
        return first.formatted(.dateTime.month(.abbreviated).day()) + " – " + last.formatted(.dateTime.month(.abbreviated).day().year())
    }
    private func workloadGraph(_ days: [CoursePathDayWorkload], today: String) -> some View {
        let maximum = days.map(\.plannedMinutes).max() ?? 0
        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                let selected = day.id == selection.selectedDay
                Button {
                    withAnimation(.smooth(duration: 0.2)) { selection.select(day.id) }
                } label: {
                    VStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(day.plannedMinutes == 0 ? 0.1 : selected ? 0.75 : 0.35))
                            .frame(width: 14, height: maximum > 0 ? max(1, 22 * day.plannedMinutes / maximum) : 1)
                            .frame(height: 22, alignment: .bottom)
                        Text(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"][index])
                            .font(.caption2).foregroundColor(selected || day.id == today ? .white : .gray)
                        Text(String(day.id.suffix(2))).font(.caption2).foregroundColor(selected ? .white : .gray)
                        Rectangle().fill(selected ? Color.white.opacity(0.65) : .clear).frame(height: 2)
                    }
                    .frame(maxWidth: .infinity).contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel(day.id + (day.id == today ? ", today" : ""))
                .accessibilityValue(CoursePathTaskPresentation.duration(day.plannedMinutes) + " planned")
                .accessibilityAddTraits(selected ? .isSelected : [])
                .help(day.id + ": " + CoursePathTaskPresentation.duration(day.plannedMinutes) + " planned")
            }
        }
    }
    private func advanceDay(_ day: String) {
        selection.advanceToday(from: calendarDay, to: day)
        calendarDay = day
    }
    private func updateVisibility() {
        store.setContentVisible(vm.notchState == .open && coordinator.currentView == .coursePath, source: visibilityID)
    }
    private var openCoursePathButton: some View {
        Button { openURL(CoursePathServer.production.baseURL) } label: {
            Label("Open CoursePath", systemImage: "arrow.up.right.square")
                .font(.caption).foregroundColor(Color(white: 0.65))
        }
        .buttonStyle(PlainButtonStyle())
    }
}
