// Shared navigation identities used by the existing header and content switch.
public enum NotchViews: CaseIterable, Hashable {
    case home, shelf, coursePath

    var label: String {
        switch self {
        case .home: return "Home"
        case .shelf: return "Shelf"
        case .coursePath: return "CoursePath"
        }
    }
    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .shelf: return "tray.fill"
        case .coursePath: return "calendar"
        }
    }
    static func tabOnClose(current: Self, rememberLastTab: Bool, shelfHasItems: Bool, openShelfByDefault: Bool) -> Self {
        if rememberLastTab { return current }
        return shelfHasItems && openShelfByDefault ? .shelf : .home
    }
    static func visibleTabs(shelfEnabled: Bool) -> [Self] {
        allCases.filter { shelfEnabled || $0 != .shelf }
    }
}
