import Foundation

struct CoursePathCalendarItem: Identifiable, Equatable {
    enum Kind { case study, deadline }
    let id: String
    let sourceID: String
    let kind: Kind
    let title: String
    let subtitle: String?
    let details: [String]
    let colorHue: Double?
    let completed: Bool
}

enum CoursePathCalendarAdapter {
    // The desktop snapshot already contains approved tasks and grouped, linked deadlines.
    // Keep study ordering separate from deadline times; a study duration is never a start time.
    static func items(in snapshot: CoursePathSnapshot?, on day: String) -> [CoursePathCalendarItem] {
        guard let snapshot else { return [] }
        let assignments = Dictionary(snapshot.assignments.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let tasks = CoursePathTaskPresentation.sorted(snapshot.tasks.filter { $0.date == day }).map { task in
            let assignment = assignments[task.assignmentId]
            let context = [assignment?.course, assignment?.title == task.title ? nil : assignment?.title]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            let duration = task.minutes.isFinite && task.minutes > 0
                ? [task.minutes.formatted(.number.precision(.fractionLength(0...2))) + " min"] : []
            return CoursePathCalendarItem(id: "study:" + task.id, sourceID: task.id, kind: .study, title: task.title,
                subtitle: context.isEmpty ? nil : context, details: duration,
                colorHue: assignment?.colorHue, completed: task.completed)
        }
        var seen = Set<String>()
        let deadlines = snapshot.deadlines.filter { $0.date == day && seen.insert($0.id).inserted }.sorted {
            // Unknown due times sort last; never substitute an invented end-of-day time.
            let left = $0.dueTime.isEmpty ? "~" : $0.dueTime
            let right = $1.dueTime.isEmpty ? "~" : $1.dueTime
            return left == right ? $0.id < $1.id : left < right
        }.map { deadline in
            CoursePathCalendarItem(id: "deadline:" + deadline.id, sourceID: deadline.id, kind: .deadline, title: deadline.title,
                subtitle: deadline.course.isEmpty ? nil : deadline.course,
                details: CoursePathDeadlineTime.display(deadline.dueTime).map { ["Due", $0] } ?? ["Due"],
                colorHue: deadline.colorHue, completed: deadline.completed)
        }
        // Keep active deadlines ahead of completed work without altering server order.
        return tasks.filter { !$0.completed } + deadlines.filter { !$0.completed }
            + tasks.filter(\.completed) + deadlines.filter(\.completed)
    }
}

enum CoursePathCalendarPlaceholder: Equatable {
    case empty, disconnected, loading, unavailable

    static func resolve(hasSnapshot: Bool, hasCredential: Bool, isBusy: Bool) -> Self {
        if hasSnapshot { return .empty }
        if isBusy { return .loading }
        return hasCredential ? .unavailable : .disconnected
    }
}
