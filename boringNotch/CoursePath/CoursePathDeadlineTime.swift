import Foundation

enum CoursePathDeadlineTime {
    // A deadline is a local wall-clock value, not a timezone-converted study start.
    // Match h:mma with a fixed AM/PM spelling and no locale-dependent spacing.
    static func display(_ value: String?) -> String? {
        guard let value, value.range(of: #"^[0-9]{1,2}:[0-9]{2}$"#, options: .regularExpression) != nil else { return nil }
        let parts = value.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) else { return nil }
        let hour = parts[0] % 12 == 0 ? 12 : parts[0] % 12
        return String(format: "%d:%02d%@", hour, parts[1], parts[0] < 12 ? "AM" : "PM")
    }
}
