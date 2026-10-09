import XCTest
@testable import CoursePathConnection

final class CoursePathCalendarTests: XCTestCase {
    private let day = "2026-10-09"
    private func task(_ id: String, date: String = "2026-10-09", order: Double = 0, minutes: Double = 25, completed: Bool = false) -> CoursePathTask {
        CoursePathTask(id: id, assignmentId: "assignment", title: "Read notes", firstStep: "", date: date,
            minutes: minutes, order: order, completed: completed, completedAt: completed ? "2026-10-09T12:00:00Z" : nil)
    }
    private func deadline(_ id: String, date: String = "2026-10-09", dueTime: String = "23:59", completed: Bool = false) -> CoursePathDeadline {
        CoursePathDeadline(id: id, assignmentIds: ["assignment", "linked"], title: "Exam", course: "CS 101", kind: "exam",
            date: date, dueTime: dueTime, examMilestone: true, completed: completed, colorHue: 210)
    }
    private func snapshot(tasks: [CoursePathTask] = [], deadlines: [CoursePathDeadline] = []) -> CoursePathSnapshot {
        let assignment = CoursePathAssignment(id: "assignment", title: "Exam preparation", course: "CS 101", kind: "exam",
            deadline: day, dueTime: "23:59", deadlineOnly: false, completed: false, colorHue: 210)
        return CoursePathSnapshot(revision: 4, assignments: [assignment], tasks: tasks, deadlines: deadlines, upcomingDeadlines: deadlines)
    }
    func testApprovedTasksDateSwitchingAndDurationWithoutScheduledTimes() {
        let data = snapshot(tasks: [task("today", minutes: 15.5), task("tomorrow", date: "2026-10-10")])
        let today = CoursePathCalendarAdapter.items(in: data, on: day)
        XCTAssertEqual(today.map(\.id), ["study:today"])
        XCTAssertEqual(today[0].title, "Read notes")
        XCTAssertEqual(today[0].subtitle, "CS 101 · Exam preparation")
        XCTAssertEqual(today[0].details, [(15.5).formatted(.number.precision(.fractionLength(0...2))) + " min"])
        XCTAssertFalse(today[0].details.contains(where: { $0.contains(":") }))
        XCTAssertEqual(CoursePathCalendarAdapter.items(in: data, on: "2026-10-10").map(\.id), ["study:tomorrow"])
        XCTAssertTrue(CoursePathCalendarAdapter.items(in: data, on: "2026-10-11").isEmpty)
    }
    func testTaskOrderingAndCompletionArePreserved() {
        let data = snapshot(tasks: [task("last", order: 3), task("b", order: 0.5), task("a", order: 0.5, completed: true)])
        let rows = CoursePathCalendarAdapter.items(in: data, on: day)
        XCTAssertEqual(rows.map(\.id), ["study:b", "study:last", "study:a"])
        XCTAssertTrue(rows[2].completed); XCTAssertFalse(rows[0].completed)
        XCTAssertEqual(rows[0].colorHue, 210)
    }
    func testLinkedDeadlinesAreFilteredDeduplicatedAndChronological() {
        let later = deadline("late", dueTime: "23:59", completed: true)
        let early = deadline("early", dueTime: "09:15")
        let data = snapshot(tasks: [task("study")], deadlines: [later, deadline("other", date: "2026-10-10"), early, early])
        let rows = CoursePathCalendarAdapter.items(in: data, on: day)
        XCTAssertEqual(rows.map(\.id), ["study:study", "deadline:early", "deadline:late"])
        XCTAssertEqual(rows[1].details, ["Due", "9:15AM"])
        XCTAssertEqual(rows[1].subtitle, "CS 101")
        XCTAssertEqual(rows[2].details, ["Due", "11:59PM"])
        XCTAssertTrue(rows[2].completed)
        // The upcoming list and two linked assignment IDs must not create extra rows.
        XCTAssertEqual(rows.filter { $0.kind == .deadline }.count, 2)
    }
    func testUnknownDurationsAndDueTimesAreNotInvented() {
        let data = snapshot(tasks: [task("none", minutes: 0)], deadlines: [deadline("unknown", dueTime: ""), deadline("known", dueTime: "10:00")])
        let rows = CoursePathCalendarAdapter.items(in: data, on: day)
        XCTAssertEqual(rows[0].details, [])
        XCTAssertEqual(rows.map(\.id), ["study:none", "deadline:known", "deadline:unknown"])
        XCTAssertEqual(rows.last?.details, ["Due"])
    }
    func testEmptyAndDisconnectedCalendarStates() {
        XCTAssertTrue(CoursePathCalendarAdapter.items(in: nil, on: day).isEmpty)
        XCTAssertTrue(CoursePathCalendarAdapter.items(in: snapshot(), on: day).isEmpty)
        XCTAssertEqual(CoursePathCalendarPlaceholder.resolve(hasSnapshot: false, hasCredential: false, isBusy: false), .disconnected)
        XCTAssertEqual(CoursePathCalendarPlaceholder.resolve(hasSnapshot: false, hasCredential: true, isBusy: true), .loading)
        XCTAssertEqual(CoursePathCalendarPlaceholder.resolve(hasSnapshot: false, hasCredential: true, isBusy: false), .unavailable)
        XCTAssertEqual(CoursePathCalendarPlaceholder.resolve(hasSnapshot: true, hasCredential: true, isBusy: false), .empty)
    }
    func testDeadlineTimesUseTwelveHoursWithoutChangingStoredValues() {
        for (input, output) in [("23:59", "11:59PM"), ("09:00", "9:00AM"), ("00:00", "12:00AM"), ("12:00", "12:00PM"), ("12:15", "12:15PM"), ("13:05", "1:05PM")] {
            XCTAssertEqual(CoursePathDeadlineTime.display(input), output)
        }
        for input in [nil, "", "24:00", "12:60", "bad", "09:00:00", "-1:00"] as [String?] {
            XCTAssertNil(CoursePathDeadlineTime.display(input))
        }
        let data = snapshot(deadlines: [deadline("actual", dueTime: "23:59"), deadline("invalid", dueTime: "25:00")])
        let rows = CoursePathCalendarAdapter.items(in: data, on: day)
        XCTAssertEqual(rows[0].details, ["Due", "11:59PM"])
        XCTAssertEqual(rows[1].details, ["Due"])
        XCTAssertEqual(data.deadlines[0].dueTime, "23:59")
    }
}
