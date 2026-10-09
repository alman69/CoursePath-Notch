import Combine

@MainActor
final class CoursePathCompletionController: ObservableObject {
    static let shared = CoursePathCompletionController(store: .shared)
    @Published private(set) var isSubmitting = false
    @Published private(set) var notice: String?
    private let store: CoursePathStore
    init(store: CoursePathStore) { self.store = store }
    var canUpdate: Bool { !isSubmitting && !store.isBusy && store.status == .connected }
    func clearNotice() { notice = nil }
    @discardableResult
    func setCompletion(_ id: String, completed: Bool) async -> Bool {
        guard canUpdate else { return false }
        isSubmitting = true; notice = nil
        defer { isSubmitting = false }
        let confirmed = await store.setTaskCompletion(id, completed: completed)
        if !confirmed {
            notice = store.status == .connected
                ? "Calendar changed. Latest progress loaded; review before trying again."
                : "Progress may have changed. Refresh in connection settings before trying again."
        }
        return confirmed
    }
}
