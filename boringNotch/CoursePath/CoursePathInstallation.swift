import Foundation
import ServiceManagement

enum CoursePathInstallation {
    // Register only a user-enabled item, once when its installed location changes.
    // Running an Xcode build must never take the login item back from the installed app.
    static func refreshEnabledLoginItem() {
        let url = Bundle.main.bundleURL.standardizedFileURL
        let roots = [URL(fileURLWithPath: "/Applications"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        guard Bundle.main.bundleIdentifier == "dev.coursepath.notch",
              roots.contains(url.deletingLastPathComponent()), SMAppService.mainApp.status == .enabled else { return }
        try? refresh(path: url.path, preferences: .standard) {
            try SMAppService.mainApp.unregister()
            try SMAppService.mainApp.register()
        }
    }

    static func refresh(path: String, preferences: UserDefaults, register: () throws -> Void) throws {
        let key = "CoursePath.registeredInstallation"
        guard preferences.string(forKey: key) != path else { return }
        // Rebuilds at the same location need no registration changes.
        try register()
        preferences.set(path, forKey: key)
    }
}
