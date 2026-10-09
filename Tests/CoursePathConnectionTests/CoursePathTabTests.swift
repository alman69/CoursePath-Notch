import XCTest
@testable import CoursePathConnection

final class CoursePathTabTests: XCTestCase {
    private let today = "2026-10-09"
    private func task(_ id: String, order: Double, completed: Bool = false, date: String = "2026-10-09") -> CoursePathTask {
        CoursePathTask(id: id, assignmentId: "a", title: id, firstStep: "", date: date, minutes: 25, order: order,
            completed: completed, completedAt: completed ? "2026-10-09T12:00:00Z" : nil)
    }
    private func deadline(_ id: String, date: String, time: String, completed: Bool = false) -> CoursePathDeadline {
        CoursePathDeadline(id: id, assignmentIds: ["a", "linked"], title: id, course: "CS", kind: "exam",
            date: date, dueTime: time, examMilestone: true, completed: completed, colorHue: nil)
    }
    private func snapshot(tasks: [CoursePathTask] = [], deadlines: [CoursePathDeadline] = []) -> CoursePathSnapshot {
        CoursePathSnapshot(revision: 10, assignments: [], tasks: tasks, deadlines: deadlines, upcomingDeadlines: deadlines)
    }
    func testNavigationRetainsHomeShelfAndAddsCoursePath() {
        let tabs = NotchViews.visibleTabs(shelfEnabled: true)
        XCTAssertEqual(tabs, [.home, .shelf, .coursePath])
        XCTAssertEqual(tabs.map(\.label), ["Home", "Shelf", "CoursePath"])
        XCTAssertEqual(tabs.map(\.icon), ["house.fill", "tray.fill", "calendar"])
        XCTAssertEqual(NotchViews.visibleTabs(shelfEnabled: false), [.home, .coursePath])
        XCTAssertEqual(Set(tabs).count, 3)
    }
    func testTodayProgressUsesOnlyTodaysStepsAndRetainsStableIdsAndOrder() {
        let data = CoursePathTabData(snapshot: snapshot(tasks: [task("last", order: 2), task("task:original-id", order: 0, completed: true), task("tomorrow", order: -1, completed: true, date: "2026-10-10")]), today: today)
        XCTAssertEqual(data.tasks.map(\.sourceID), ["last", "task:original-id"])
        XCTAssertEqual(data.progress, CoursePathTodayProgress(completed: 1, total: 2))
        XCTAssertEqual(data.progress.fraction, 0.5)
        XCTAssertEqual(data.tasks[0].details, ["25 min"])
        XCTAssertTrue(data.tasks[1].completed)
    }
    func testUpcomingDeadlinesAreGroupedIncompleteChronologicalAndLimited() {
        let early = deadline("early", date: today, time: "09:00")
        let data = CoursePathTabData(snapshot: snapshot(deadlines: [
            deadline("later", date: "2026-10-10", time: "00:00"),
            deadline("past", date: "2026-10-08", time: "23:59"),
            deadline("done", date: today, time: "08:00", completed: true),
            deadline("night", date: today, time: "23:59"), early, early]), today: today, deadlineLimit: 2)
        XCTAssertEqual(data.deadlines.map(\.id), ["early", "night"])
        XCTAssertEqual(data.deadlines.map(\.timeLabel), ["9:00AM", "11:59PM"])
        XCTAssertEqual(data.deadlines.map(\.dateLabel), ["Today", "Today"])
        XCTAssertTrue(data.deadlines.allSatisfy(\.dueToday))
        XCTAssertEqual(data.progress.total, 0) // Deadlines are not study steps.
    }
    func testEmptySchedulesAndDisconnectedDataHaveZeroProgress() {
        for source in [nil, snapshot()] as [CoursePathSnapshot?] {
            let data = CoursePathTabData(snapshot: source, today: today)
            XCTAssertTrue(data.tasks.isEmpty); XCTAssertTrue(data.deadlines.isEmpty)
            XCTAssertEqual(data.progress, CoursePathTodayProgress(completed: 0, total: 0))
            XCTAssertEqual(data.progress.fraction, 0)
        }
    }
    func testMissingDeadlineTimeDoesNotInventATimeAndMidnightIsFormatted() {
        let source = snapshot(deadlines: [deadline("missing", date: "2026-10-10", time: ""), deadline("midnight", date: "2026-10-10", time: "00:00")])
        let data = CoursePathTabData(snapshot: source, today: today)
        XCTAssertEqual(data.deadlines.map(\.id), ["midnight", "missing"])
        XCTAssertEqual(data.deadlines[0].timeLabel, "12:00AM")
        XCTAssertNil(data.deadlines[1].timeLabel)
        XCTAssertFalse(data.deadlines[0].dueToday)
        XCTAssertEqual(source.upcomingDeadlines[0].dueTime, "")
    }
}
