import Foundation

struct CoursePathTodayProgress: Equatable {
    let completed: Int
    let total: Int
    var fraction: Double { total == 0 ? 0 : Double(completed) / Double(total) }
}

struct CoursePathUpcomingDeadline: Identifiable, Equatable {
    let id, title, course, dateLabel: String
    let timeLabel: String?
    let dueToday: Bool
    let colorHue: Double?
}

struct CoursePathTabData {
    let tasks: [CoursePathCalendarItem]
    let progress: CoursePathTodayProgress
    let deadlines: [CoursePathUpcomingDeadline]
    let upcomingDeadlineCount: Int

    init(snapshot: CoursePathSnapshot?, today: String, deadlineLimit: Int = 3) {
        tasks = CoursePathCalendarAdapter.items(in: snapshot, on: today).filter { $0.kind == .study }
        progress = CoursePathTodayProgress(completed: tasks.filter(\.completed).count, total: tasks.count)
        var seen = Set<String>()
        // Reuse the server's grouped upcoming markers. Do not expand linked assignments.
        let markers = (snapshot?.upcomingDeadlines ?? []).filter {
            !$0.completed && $0.date >= today && seen.insert($0.id).inserted
        }.sorted {
            let left = $0.date + " " + ($0.dueTime.isEmpty ? "~" : $0.dueTime)
            let right = $1.date + " " + ($1.dueTime.isEmpty ? "~" : $1.dueTime)
            return left == right ? $0.id < $1.id : left < right
        }
        upcomingDeadlineCount = markers.count
        deadlines = markers.prefix(max(0, deadlineLimit)).map { deadline in
            let dateLabel = deadline.date == today ? "Today" : CoursePathDate.date(deadline.date)?.formatted(.dateTime.month(.abbreviated).day()) ?? deadline.date
            return CoursePathUpcomingDeadline(id: deadline.id, title: deadline.title, course: deadline.course,
                dateLabel: dateLabel, timeLabel: CoursePathDeadlineTime.display(deadline.dueTime),
                dueToday: deadline.date == today, colorHue: deadline.colorHue)
        }
    }
}
