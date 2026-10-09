import XCTest
@testable import CoursePathConnection

final class CoursePathInstallationTests: XCTestCase {
    func testLocationRegistrationIsRetriedOnFailureAndNotRepeatedForRebuilds() throws {
        let suite = "dev.coursepath.notch.install-test." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        preferences.set(true, forKey: "openLastTabByDefault")
        preferences.set("production", forKey: "CoursePath.server")
        enum Failure: Error { case unavailable }
        XCTAssertThrowsError(try CoursePathInstallation.refresh(path: "/Applications/CoursePath Notch.app", preferences: preferences) { throw Failure.unavailable })
        XCTAssertNil(preferences.string(forKey: "CoursePath.registeredInstallation"))
        var registrations = 0
        for _ in 0..<3 {
            try CoursePathInstallation.refresh(path: "/Applications/CoursePath Notch.app", preferences: preferences) { registrations += 1 }
        }
        XCTAssertEqual(registrations, 1)
        try CoursePathInstallation.refresh(path: "/Users/test/Applications/CoursePath Notch.app", preferences: preferences) { registrations += 1 }
        XCTAssertEqual(registrations, 2)
        XCTAssertTrue(preferences.bool(forKey: "openLastTabByDefault"))
        XCTAssertEqual(preferences.string(forKey: "CoursePath.server"), "production")
    }
}
