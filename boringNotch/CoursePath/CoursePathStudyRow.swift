import SwiftUI

struct CoursePathStudyRow: View {
    let row: CoursePathCalendarItem
    let showFullTitle: Bool
    @ObservedObject private var store = CoursePathStore.shared
    @ObservedObject private var completion = CoursePathCompletionController.shared
    private var color: Color {
        row.colorHue.map { Color(hue: $0 / 360, saturation: 0.6, brightness: 0.8) } ?? .effectiveAccent
    }
    var body: some View {
        HStack(spacing: 4) {
            ReminderToggle(isOn: Binding(get: { row.completed }, set: { update($0) }), color: color)
                .accessibilityLabel((row.completed ? "Restore " : "Complete ") + row.title)
            Button { update(!row.completed) } label: {
                CalendarEntryRow(title: row.title, subtitle: row.subtitle ?? "Study step", color: color,
                    showFullTitle: showFullTitle, subtitleIcon: "checklist", strikethrough: row.completed) {
                    if let duration = row.details.first {
                        Text(duration).font(.caption).foregroundColor(.white).lineLimit(1)
                            .frame(minWidth: 44, alignment: .trailing)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel((row.completed ? "Restore study step: " : "Complete study step: ") + row.title)
        }
        .disabled(!completion.canUpdate)
        .opacity(row.completed ? 0.4 : 1)
    }
    private func update(_ desired: Bool) {
        Task { await completion.setCompletion(row.sourceID, completed: desired) }
    }
}
