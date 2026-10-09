import Foundation

struct CoursePathWeekSelection: Equatable {
    private(set) var days: [String]
    private(set) var selectedDay: String
    private(set) var isExpanded = false
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }
    init(today: String) {
        let date = CoursePathDate.date(today) ?? Date()
        let offset = (Self.calendar.component(.weekday, from: date) + 5) % 7
        let monday = Self.calendar.date(byAdding: .day, value: -offset, to: date)!
        days = (0..<7).map { CoursePathDate.key(Self.calendar.date(byAdding: .day, value: $0, to: monday)!) }
        selectedDay = CoursePathDate.key(date)
    }
    mutating func moveWeek(_ delta: Int) {
        let index = days.firstIndex(of: selectedDay) ?? 0
        guard let date = CoursePathDate.date(days[0]), let shifted = Self.calendar.date(byAdding: .day, value: delta * 7, to: date) else { return }
        days = (0..<7).map { CoursePathDate.key(Self.calendar.date(byAdding: .day, value: $0, to: shifted)!) }
        selectedDay = days[index]; isExpanded = false
    }
    mutating func select(_ day: String) {
        guard days.contains(day) else { return }
        selectedDay = day; isExpanded = true
    }
    mutating func toggleExpanded() { isExpanded.toggle() }
}

struct CoursePathDayWorkload: Identifiable, Equatable {
    let id: String
    let plannedMinutes: Double
}

struct CoursePathWeekData {
    let days: [CoursePathDayWorkload]
    let progress: CoursePathTodayProgress
    let remainingMinutes: Double
    let upcomingDeadlineCount: Int
    let deadlines: [CoursePathUpcomingDeadline]
    let selectedTasks: [CoursePathCalendarItem]

    init(snapshot: CoursePathSnapshot?, selection: CoursePathWeekSelection, today: String) {
        let tasks = (snapshot?.tasks ?? []).filter { selection.days.contains($0.date) }
        progress = CoursePathTodayProgress(completed: tasks.filter(\.completed).count, total: tasks.count)
        remainingMinutes = tasks.filter { !$0.completed }.reduce(0) { $0 + CoursePathTaskPresentation.minutes($1) }
        days = selection.days.map { day in
            CoursePathDayWorkload(id: day, plannedMinutes: tasks.filter { $0.date == day }.reduce(0) { $0 + CoursePathTaskPresentation.minutes($1) })
        }
        let upcoming = CoursePathTabData(snapshot: snapshot, today: today)
        upcomingDeadlineCount = upcoming.upcomingDeadlineCount
        deadlines = upcoming.deadlines
        selectedTasks = CoursePathCalendarAdapter.items(in: snapshot, on: selection.selectedDay).filter { $0.kind == .study }
    }
}
