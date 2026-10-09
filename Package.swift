// swift-tools-version: 5.9
import PackageDescription

// Test the isolated connection code without linking the notch's private system frameworks.
let package = Package(
    name: "CoursePathConnection",
    platforms: [.macOS(.v14)],
    products: [.library(name: "CoursePathConnection", targets: ["CoursePathConnection"])],
    targets: [
        .target(name: "CoursePathConnection", path: "boringNotch/CoursePath", exclude: ["CoursePathConnectionSettings.swift", "CoursePathCalendarView.swift", ".gitkeep"]),
        .testTarget(name: "CoursePathConnectionTests", dependencies: ["CoursePathConnection"], path: "Tests/CoursePathConnectionTests")
    ]
)
