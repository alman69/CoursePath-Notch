import XCTest
@testable import CoursePathConnection

final class CoursePathWeekTests: XCTestCase {
    private func task(_ id: String, day: String, minutes: Double, order: Double = 0, completed: Bool = false) -> CoursePathTask {
        CoursePathTask(id: id, assignmentId: "a", title: id, firstStep: "", date: day, minutes: minutes,
            order: order, completed: completed, completedAt: completed ? "2026-10-09T12:00:00Z" : nil)
    }
    private func snapshot(_ tasks: [CoursePathTask], deadlines: [CoursePathDeadline] = []) -> CoursePathSnapshot {
        CoursePathSnapshot(revision: 10, assignments: [], tasks: tasks, deadlines: deadlines, upcomingDeadlines: deadlines)
    }
    func testMondaySundayWeeksNavigateAcrossYearsLeapDaysAndDST() {
        var week = CoursePathWeekSelection(today: "2026-01-01")
        XCTAssertEqual(week.days.first, "2025-12-29"); XCTAssertEqual(week.days.last, "2026-01-04")
        week.moveWeek(1)
        XCTAssertEqual(week.days.first, "2026-01-05"); XCTAssertEqual(week.selectedDay, "2026-01-08")
        week.moveWeek(-1); XCTAssertEqual(week.selectedDay, "2026-01-01")
        let leap = CoursePathWeekSelection(today: "2028-02-29")
        XCTAssertEqual(leap.days.first, "2028-02-28"); XCTAssertEqual(leap.days.last, "2028-03-05")
        var spring = CoursePathWeekSelection(today: "2026-03-08")
        XCTAssertEqual(spring.days.first, "2026-03-02"); XCTAssertEqual(spring.days.last, "2026-03-08")
        spring.moveWeek(1); XCTAssertEqual(spring.days.last, "2026-03-15")
        XCTAssertEqual(Set(spring.days).count, 7)
        XCTAssertEqual(CoursePathWeekSelection(today: "2026-11-01").days.last, "2026-11-01")
    }
    func testMidnightFollowsTodayAcrossWeekBoundaryButKeepsBrowsedDates() {
        var current = CoursePathWeekSelection(today: "2026-10-11")
        current.toggleExpanded()
        current.advanceToday(from: "2026-10-11", to: "2026-10-12")
        XCTAssertEqual(current.selectedDay, "2026-10-12"); XCTAssertEqual(current.days.first, "2026-10-12")
        XCTAssertTrue(current.isExpanded)
        current.select("2026-10-14")
        let browsed = current
        current.advanceToday(from: "2026-10-12", to: "2026-10-13")
        XCTAssertEqual(current, browsed)
        current.moveWeek(-1)
        let olderWeek = current
        current.advanceToday(from: "2026-10-13", to: "2026-10-14")
        XCTAssertEqual(current, olderWeek)
    }
    func testDailyBreakdownStartsCollapsedSelectsAndCollapsesOnWeekNavigation() {
        var week = CoursePathWeekSelection(today: "2026-10-09")
        XCTAssertFalse(week.isExpanded)
        week.select("2026-10-10"); XCTAssertTrue(week.isExpanded); XCTAssertEqual(week.selectedDay, "2026-10-10")
        week.toggleExpanded(); XCTAssertFalse(week.isExpanded)
        week.select("2026-10-11"); week.moveWeek(-1)
        XCTAssertFalse(week.isExpanded); XCTAssertEqual(week.selectedDay, "2026-10-04")
        week.select("2026-11-01"); XCTAssertEqual(week.selectedDay, "2026-10-04")
    }
    func testPlannedWorkloadIncludesCompletedStepsWhileRemainingTimeDoesNot() {
        let tasks = [task("done", day: "2026-10-09", minutes: 60, completed: true),
            task("left", day: "2026-10-09", minutes: 30, order: 1),
            task("saturday", day: "2026-10-10", minutes: 90, completed: true),
            task("sunday", day: "2026-10-11", minutes: 45),
            task("next-week", day: "2026-10-12", minutes: 500)]
        let data = CoursePathWeekData(snapshot: snapshot(tasks), selection: CoursePathWeekSelection(today: "2026-10-09"), today: "2026-10-09")
        XCTAssertEqual(data.progress, CoursePathTodayProgress(completed: 2, total: 4))
        XCTAssertEqual(data.remainingMinutes, 75)
        XCTAssertEqual(data.days.map(\.plannedMinutes), [0, 0, 0, 0, 90, 90, 45])
        XCTAssertEqual(data.selectedTasks.map(\.sourceID), ["left", "done"])
        XCTAssertEqual(CoursePathTaskPresentation.duration(data.remainingMinutes), "1h 15m")
        XCTAssertEqual(tasks.map(\.order), [0, 1, 0, 0, 0])
    }
    func testUnfinishedGroupsPreserveOrderAndRestorationReturnsOriginalPosition() {
        let original = [task("a", day: "2026-10-09", minutes: 15, order: 0, completed: true),
            task("b", day: "2026-10-09", minutes: 15, order: 1),
            task("c", day: "2026-10-09", minutes: 15, order: 2, completed: true),
            task("d", day: "2026-10-09", minutes: 15, order: 3)]
        XCTAssertEqual(CoursePathTaskPresentation.sorted(original).map(\.id), ["b", "d", "a", "c"])
        let restored = [task("a", day: "2026-10-09", minutes: 15, order: 0)] + original.dropFirst()
        XCTAssertEqual(CoursePathTaskPresentation.sorted(restored).map(\.id), ["a", "b", "d", "c"])
        XCTAssertEqual(original.map(\.id), ["a", "b", "c", "d"])
    }
    func testIncompleteDeadlinePrecedesCompletedStudySteps() {
        let deadline = CoursePathDeadline(id: "linked", assignmentIds: ["a", "b"], title: "Exam", course: "CS", kind: "exam",
            date: "2026-10-09", dueTime: "23:59", examMilestone: true, completed: false, colorHue: nil)
        let source = snapshot([task("done", day: "2026-10-09", minutes: 20, completed: true)], deadlines: [deadline, deadline])
        let home = CoursePathCalendarAdapter.items(in: source, on: "2026-10-09")
        XCTAssertEqual(home.map(\.id), ["deadline:linked", "study:done"])
        XCTAssertEqual(home[0].details, ["Due", "11:59PM"])
        let week = CoursePathWeekData(snapshot: source, selection: CoursePathWeekSelection(today: "2026-10-09"), today: "2026-10-09")
        XCTAssertEqual(week.upcomingDeadlineCount, 1); XCTAssertEqual(week.deadlines.count, 1)
    }
    func testSelectedDaysAndEmptyDisconnectedWeeks() {
        var selection = CoursePathWeekSelection(today: "2026-10-09")
        selection.select("2026-10-10")
        let source = snapshot([task("friday", day: "2026-10-09", minutes: 25), task("saturday", day: "2026-10-10", minutes: 40)])
        XCTAssertEqual(CoursePathWeekData(snapshot: source, selection: selection, today: "2026-10-09").selectedTasks.map(\.sourceID), ["saturday"])
        for source in [nil, snapshot([])] as [CoursePathSnapshot?] {
            let empty = CoursePathWeekData(snapshot: source, selection: selection, today: "2026-10-09")
            XCTAssertEqual(empty.progress.total, 0); XCTAssertEqual(empty.remainingMinutes, 0)
            XCTAssertTrue(empty.days.allSatisfy { $0.plannedMinutes == 0 })
            XCTAssertTrue(empty.selectedTasks.isEmpty); XCTAssertEqual(empty.upcomingDeadlineCount, 0)
        }
    }
    func testInvalidDurationsDoNotBecomeWorkload() {
        let data = CoursePathWeekData(snapshot: snapshot([task("missing", day: "2026-10-09", minutes: 0),
            task("invalid", day: "2026-10-09", minutes: -20), task("nan", day: "2026-10-09", minutes: .nan)]),
            selection: CoursePathWeekSelection(today: "2026-10-09"), today: "2026-10-09")
        XCTAssertEqual(data.remainingMinutes, 0); XCTAssertTrue(data.days.allSatisfy { $0.plannedMinutes == 0 })
        XCTAssertEqual(CoursePathTaskPresentation.duration(.nan), "0 min")
    }
    func testUpcomingMetricCountsAllMarkersWhileOnlyThreeNearestAreShown() {
        let markers = (0..<5).map { index in
            CoursePathDeadline(id: "deadline\(index)", assignmentIds: ["a", "linked"], title: "Exam", course: "CS", kind: "exam",
                date: "2026-10-\(10 + index)", dueTime: "23:59", examMilestone: true, completed: false, colorHue: nil)
        }
        let data = CoursePathWeekData(snapshot: snapshot([], deadlines: markers + [markers[0]]),
            selection: CoursePathWeekSelection(today: "2026-10-09"), today: "2026-10-09")
        XCTAssertEqual(data.upcomingDeadlineCount, 5)
        XCTAssertEqual(data.deadlines.map(\.id), ["deadline0", "deadline1", "deadline2"])
    }
}
