import Foundation

enum CoursePathServer: String, CaseIterable, Identifiable {
    case local, localAPI, production
    static var defaultServer: CoursePathServer {
        #if COURSEPATH_MVP_RELEASE
        .production
        #else
        .local
        #endif
    }
    var id: String { rawValue }
    var label: String {
        switch self {
        case .local: return "Local backend (5173)"
        case .localAPI: return "Local API with Vite (5174)"
        case .production: return "Production"
        }
    }
    var baseURL: URL {
        switch self {
        case .local: return URL(string: "http://127.0.0.1:5173")!
        case .localAPI: return URL(string: "http://127.0.0.1:5174")!
        case .production: return URL(string: "https://app.coursepath.dev")!
        }
    }
}

struct CoursePathAssignment: Codable, Identifiable, Equatable {
    let id, title, course, kind, deadline, dueTime: String
    let deadlineOnly, completed: Bool
    let colorHue: Double?
}

struct CoursePathTask: Codable, Identifiable, Equatable {
    let id, assignmentId, title, firstStep, date: String
    let minutes, order: Double
    let completed: Bool
    let completedAt: String?
}

struct CoursePathDeadline: Codable, Identifiable, Equatable {
    let id: String
    let assignmentIds: [String]
    let title, course, kind, date, dueTime: String
    let examMilestone, completed: Bool
    let colorHue: Double?
}

struct CoursePathSnapshot: Codable, Equatable {
    let revision: Int
    let assignments: [CoursePathAssignment]
    let tasks: [CoursePathTask]
    let deadlines, upcomingDeadlines: [CoursePathDeadline]
}

struct CoursePathCompletion: Codable, Equatable {
    let revision: Int
    let taskId: String
    let completed: Bool
    let completedAt: String?
    let assignmentId: String
    let assignmentCompleted: Bool
}

enum CoursePathDate {
    // Date-only schedule values use the user's local Gregorian day, never session start times.
    static func key(_ date: Date, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
    static func date(_ key: String, timeZone: TimeZone = .autoupdatingCurrent) -> Date? {
        guard key.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
        let values = key.split(separator: "-").compactMap { Int($0) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let date = calendar.date(from: DateComponents(year: values[0], month: values[1], day: values[2], hour: 12)), self.key(date, timeZone: timeZone) == key else { return nil }
        return date
    }
}

enum CoursePathError: Error, LocalizedError, Equatable {
    case unauthorized, conflict, invalidToken, invalidResponse, offline, timeout, http(Int), keychain(Int32)
    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Connection expired or was revoked. Connect CoursePath again."
        case .conflict: return "The calendar changed. Refresh before updating this task."
        case .invalidToken: return "Paste a valid CoursePath desktop token."
        case .invalidResponse: return "CoursePath returned an invalid response."
        case .offline: return "CoursePath is unavailable. Check your connection and backend."
        case .timeout: return "The CoursePath request timed out. Try refreshing."
        case .http(let status): return "CoursePath request failed (HTTP \(status))."
        case .keychain: return "The credential could not be accessed securely in Keychain."
        }
    }
}
