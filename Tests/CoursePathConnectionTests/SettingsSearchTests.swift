import XCTest
@testable import CoursePathConnection

final class SettingsSearchTests: XCTestCase {
    func testTitlesCaseWhitespaceAndSynonyms() {
        let tab = SettingsSearchIndex.search("  REMEMBER last TAB \n")
        XCTAssertEqual(tab.map(\.id), ["general.openLastTabByDefault"])
        XCTAssertEqual(tab.first?.category, "General")
        XCTAssertEqual(tab.first?.section, "Notch behavior")
        XCTAssertEqual(tab.first?.sectionID, "general.behavior")
        XCTAssertTrue(SettingsSearchIndex.search("startup").contains { $0.title == "Launch at login" })
        XCTAssertTrue(SettingsSearchIndex.search("swipe").contains { $0.title == "Close gesture" })
        XCTAssertTrue(SettingsSearchIndex.search("camera").contains { $0.title == "Enable boring mirror" })
        XCTAssertTrue(SettingsSearchIndex.search("CoursePath").contains { $0.category == "CoursePath" && $0.title == "Server" })
        XCTAssertTrue(SettingsSearchIndex.search("music source").contains { $0.category == "Media" })
    }
    func testTypingClearingAndNoMatches() {
        let partial = SettingsSearchIndex.search("rem")
        let full = SettingsSearchIndex.search("remember last")
        XCTAssertGreaterThan(partial.count, full.count)
        XCTAssertEqual(full.map(\.id), ["general.openLastTabByDefault"])
        XCTAssertTrue(SettingsSearchIndex.search("").isEmpty)
        XCTAssertTrue(SettingsSearchIndex.search(" \n ").isEmpty)
        XCTAssertTrue(SettingsSearchIndex.search("nonexistent control xyz").isEmpty)
        XCTAssertTrue(SettingsSearchIndex.search("check for updates").isEmpty)
    }
    func testConditionalResultsRouteToRealParentAndExplainAvailability() throws {
        let delay = try XCTUnwrap(SettingsSearchIndex.search("hover delay").first)
        XCTAssertEqual(delay.reason(enabled: []), "Enable Open notch on hover first.")
        XCTAssertNil(delay.reason(enabled: ["hover"]))
        XCTAssertEqual(delay.sectionID, "general.behavior")
        let unavailable = try XCTUnwrap(SettingsSearchIndex.search("horizontal gestures").first)
        XCTAssertNotNil(unavailable.reason(enabled: ["gestures"]))
        let token = try XCTUnwrap(SettingsSearchIndex.search("desktop access token").first)
        XCTAssertNotNil(token.reason(enabled: ["credential"]))
        XCTAssertNil(token.reason(enabled: ["needsCredential"]))
        let customSize = SettingsSearchIndex.search("custom notch size")
        XCTAssertEqual(customSize.count, 2) // Two genuine controls, on distinct display types.
        XCTAssertNotEqual(customSize[0].id, customSize[1].id)
        XCTAssertNotEqual(customSize[0].requirement, customSize[1].requirement)
    }
    func testCatalogHasUniqueIdentitiesExactLabelsAndRealAnchors() throws {
        let entries = SettingsSearchIndex.entries
        XCTAssertEqual(Set(entries.map(\.id)).count, entries.count)
        XCTAssertEqual(Set(entries.map(\.category)), Set(["General", "Appearance", "Media", "CoursePath", "HUD", "Battery", "Shelf", "Shortcuts", "Advanced", "About"]))
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let settings = try String(contentsOf: root.appendingPathComponent("boringNotch/components/Settings/SettingsView.swift"))
        let connection = try String(contentsOf: root.appendingPathComponent("boringNotch/CoursePath/CoursePathConnectionSettings.swift"))
        let slots = try String(contentsOf: root.appendingPathComponent("boringNotch/components/Settings/MusicSlotConfigurationView.swift"))
        let source = settings + connection + slots
        for entry in entries {
            XCTAssertTrue(source.contains(".settingsSearchSection(\"" + entry.sectionID + "\")"), entry.id + " has no real anchor")
            XCTAssertTrue(source.contains(entry.title), entry.id + " label no longer exists")
            XCTAssertFalse(entry.id.contains("Downloads")); XCTAssertFalse(entry.id.contains("Extensions"))
        }
    }
    func testPublicCatalogExcludesRetiredCalendarAndDeveloperConnections() {
        XCTAssertFalse(SettingsSearchIndex.entries.contains { $0.category == "Calendar" || $0.id.hasPrefix("calendar.") })
        let entries = SettingsSearchIndex.publicEntries
        XCTAssertFalse(entries.contains { ["coursepath.server", "coursepath.desktopToken", "coursepath.connect"].contains($0.id) })
        XCTAssertTrue(entries.contains { $0.id == "coursepath.browserConnect" && $0.title == "Connect CoursePath" && $0.sectionID == "coursepath.connection" })
        XCTAssertTrue(entries.contains { $0.id == "coursepath.disconnect" })
    }
    func testRememberAllTabsAndOriginalDefaults() {
        for tab in NotchViews.allCases {
            for items in [true, false] {
                for shelfDefault in [true, false] {
                    XCTAssertEqual(NotchViews.tabOnClose(current: tab, rememberLastTab: true, shelfHasItems: items, openShelfByDefault: shelfDefault), tab)
                    XCTAssertEqual(NotchViews.tabOnClose(current: tab, rememberLastTab: false, shelfHasItems: items, openShelfByDefault: shelfDefault), items && shelfDefault ? .shelf : .home)
                }
            }
        }
    }
}
