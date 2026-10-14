import Foundation

// Maintenance: add controls here using their preference/action identity, exact UI label,
// real category route and an existing settingsSearchSection anchor. Keep availability
// keys in SettingsSearchSidebar in sync. Never index values, tokens or calendar names.
struct SettingsSearchEntry: Identifiable, Equatable {
    let id: String
    let title: String
    let category: String
    let categoryTitle: String
    let section: String
    let sectionID: String
    let keywords: String
    let requirement: String?
    let unavailableReason: String?
    var destinationLabel: String {
        let context: String
        switch id {
        case "general.notchHeight": context = " (notch displays)"
        case "general.nonNotchHeight": context = " (non-notch displays)"
        default: context = ""
        }
        return categoryTitle + " → " + section + context
    }
    func reason(enabled: Set<String>) -> String? {
        guard let requirement, !enabled.contains(requirement) else { return nil }
        return unavailableReason
    }
}

enum SettingsSearchIndex {
    static var entries: [SettingsSearchEntry] {
#if COURSEPATH_MVP_RELEASE
        publicEntries
#else
        developerEntries
#endif
    }
    // Use the same public catalog in release builds and isolated regression tests.
    static var publicEntries: [SettingsSearchEntry] {
        developerEntries.filter { !["coursepath.server", "coursepath.desktopToken", "coursepath.connect"].contains($0.id) }
    }
    static let developerEntries: [SettingsSearchEntry] = [
        SettingsSearchEntry(id: "general.menubarIcon", title: "Show menu bar icon", category: "General", categoryTitle: "General", section: "System features", sectionID: "general.system", keywords: "status tray", requirement: nil, unavailableReason: nil),
        SettingsSearchEntry(id: "general.launchAtLogin", title: "Launch at login", category: "General", categoryTitle: "General", section: "System features", sectionID: "general.system", keywords: "startup start login", requirement: nil, unavailableReason: nil),
        SettingsSearchEntry(id: "general.showOnAllDisplays", title: "Show on all displays", category: "General", categoryTitle: "General", section: "System features", sectionID: "general.system", keywords: "monitor screen", requirement: nil, unavailableReason: nil),
        SettingsSearchEntry(id: "general.preferredScreenUUID", title: "Preferred display", category: "General", categoryTitle: "General", section: "System features", sectionID: "general.system", keywords: "monitor screen", requirement: "singleDisplay", unavailableReason: "Turn off Show on all displays first."),
        SettingsSearchEntry(id: "general.automaticallySwitchDisplay", title: "Automatically switch displays", category: "General", categoryTitle: "General", section: "System features", sectionID: "general.system", keywords: "monitor screen", requirement: "singleDisplay", unavailableReason: "Turn off Show on all displays first."),
        SettingsSearchEntry(id: "general.notchHeightMode", title: "Notch height on notch displays", category: "General", categoryTitle: "General", section: "Notch sizing", sectionID: "general.sizing", keywords: "size", requirement: nil, unavailableReason: nil),
        SettingsSearchEntry(id: "general.notchHeight", title: "Custom notch size", category: "General", categoryTitle: "General", section: "Notch sizing", sectionID: "general.sizing", keywords: "height", requirement: "customNotch", unavailableReason: "Choose Custom height for notch displays first."),
        SettingsSearchEntry(id: "general.nonNotchHeightMode", title: "Notch height on non-notch displays", category: "General", categoryTitle: "General", section: "Notch sizing", sectionID: "general.sizing", keywords: "size", requirement: nil, unavailableReason: nil),
        SettingsSearchEntry(id: "general.nonNotchHeight", title: "Custom notch size", category: "General", categoryTitle: "General", section: "Notch sizing", sectionID: "general.sizing", keywords: "height", requirement: "customNonNotch", unavailableReason: "Choose Custom height for non-notch displays first."),
        SettingsSearchEntry(id: "general.openNotchOnHover", title: "Open notch on hover", category: "General", categoryTitle: "General", section: "Notch behavior", sectionID: "general.behavior", keywords: "mouse", requirement: nil, unavailableReason: nil),
        SettingsSearchEntry(id: "general.enableHaptics", title: "Enable haptic feedback", category: "General", categoryTitle: "General", section: "Notch behavior", sectionID: "general.behavior", keywords: "vibration", requirement: nil, unavailableReason: nil),
        SettingsSearchEntry(id: "general.openLastTabByDefault", title: "Remember last tab", category: "General", categoryTitle: "General", section: "Notch behavior", sectionID: "general.behavior", keywords: "home shelf CoursePath", requirement: nil, unavailableReason: nil),
        SettingsSearchEntry(id: "general.minimumHoverDuration", title: "Hover delay", category: "General", categoryTitle: "General", section: "Notch behavior", sectionID: "general.behavior", keywords: "mouse", requirement: "hover", unavailableReason: "Enable Open notch on hover first."),
        SettingsSearchEntry(id: "general.enableGestures", title: "Enable gestures", category: "General", categoryTitle: "General", section: "Gesture control", sectionID: "general.gestures", keywords: "swipe", requirement: "hover", unavailableReason: "Enabled automatically when Open notch on hover is off."),
        SettingsSearchEntry(id: "general.horizontalGestures", title: "Change media with horizontal gestures", category: "General", categoryTitle: "General", section: "Gesture control", sectionID: "general.gestures", keywords: "swipe music", requirement: "never", unavailableReason: "This existing control is not yet available."),
        SettingsSearchEntry(id: "general.closeGestureEnabled", title: "Close gesture", category: "General", categoryTitle: "General", section: "Gesture control", sectionID: "general.gestures", keywords: "swipe scrolling", requirement: "gestures", unavailableReason: "Enable gestures first."),
        SettingsSearchEntry(id: "general.gestureSensitivity", title: "Gesture sensitivity", category: "General", categoryTitle: "General", section: "Gesture control", sectionID: "general.gestures", keywords: "swipe", requirement: "gestures", unavailableReason: "Enable gestures first."),
        SettingsSearchEntry(id: "appearance.alwaysShowTabs", title: "Always show tabs", category: "Appearance", categoryTitle: "Appearance", section: "General", sectionID: "appearance.general", keywords: "home shelf CoursePath", requirement: nil, unavailableReason: nil),
        SettingsSearchEntry(id: "appearance.settingsIconInNotch", title: "Show settings icon in notch", category: "Appearance", categoryTitle: "Appearance", section: "General", sectionID: "appearance.general", keywords: "gear", requirement: nil, unavailableReason: nil),
        SettingsSearchEntry(id: "appearance.coloredSpectrogram", title: "Colored spectrogram", category: "Appearance", categoryTitle: "Appearance", section: "Media", sectionID: "appearance.media", keywords: "music", requirement: nil, unavailableReason: nil),
        SettingsSearchEntry(id: "appearance.playerColorTinting", title: "Player tinting", category: "Appearance", categoryTitle: "Appearance", section: "Media", sectionID: "appearance.media", keywords: "music color", requirement: nil, unavailableReason: nil),
        SettingsSearchEntry(id: "appearance.lightingEffect", title: "Enable blur effect behind album art", category: "Appearance", categoryTitle: "Appearance", section: "Media", sectionID: "appearance.media", keywords: "music", requirement: nil, unavailableReason: nil),
        SettingsSearchEntry(id: "appearance.sliderColor", title: "Slider color", category: "Appearance", categoryTitle: "Appearance", section: "Media", sectionID: "appearance.media", keywords: "music progress", requirement: nil, unavailableReason: nil),
        SettingsSearchEntry(id: "appearance.useMusicVisualizer", title: "Use music visualizer spectrogram", category: "Appearance", categoryTitle: "Appearance", section: "Custom music live activity animation", sectionID: "appearance.animation", keywords: "music", requirement: "never", unavailableReason: "This existing control is marked Coming soon."),
        SettingsSearchEntry(id: "appearance.selectedVisualizer", title: "Selected animation", category: "Appearance", categoryTitle: "Appearance", section: "Custom music live activity animation", sectionID: "appearance.animation", keywords: "music", requirement: "animationSelection", unavailableReason: "Turn off Use music visualizer spectrogram and add a custom animation first."),
        SettingsSearchEntry(id: "appearance.customVisualizers", title: "Custom vizualizers (Lottie)", category: "Appearance", categoryTitle: "Appearance", section: "Custom vizualizers (Lottie)", sectionID: "appearance.visualizers", keywords: "animation Lottie add remove", requirement: nil, unavailableReason: nil),
        SettingsSearchEntry(id: "appearance.showMirror", title: "Enable boring mirror", category: "Appearance", categoryTitle: "Appearance", section: "Additional features", sectionID: "appearance.features", keywords: "camera webcam", requirement: "camera", unavailableReason: "No video input device is available."),
        SettingsSearchEntry(id: "appearance.mirrorShape", title: "Mirror shape", category: "Appearance", categoryTitle: "Appearance", section: "Additional features", sectionID: "appearance.features", keywords: "camera webcam", requirement: nil, unavailableReason: nil),
        SettingsSearchEntry(id: "appearance.showNotHumanFace", title: "Show cool face animation while inactive", category: "Appearance", categoryTitle: "Appearance", section: "Additional features", sectionID: "appearance.features", keywords: "camera mirror", requirement: nil, unavailableReason: nil),
        SettingsSearchEntry(id: "media.mediaController", title: "Music Source", category: "Media", categoryTitle: "Media", section: "Media Source", sectionID: "media.source", keywords: "playback spotify apple youtube", requirement: nil, unavailableReason: nil),
        SettingsSearchEntry(id: "media.musicLiveActivityEnabled", title: "Show music live activity", category: "Media", categoryTitle: "Media", section: "Media playback live activity", sectionID: "media.activity", keywords: "playback", requirement: nil, unavailableReason: nil),
        SettingsSearchEntry(id: "media.enableSneakPeek", title: "Show sneak peek on playback changes", category: "Media", categoryTitle: "Media", section: "Media playback live activity", sectionID: "media.activity", keywords: "music", requirement: nil, unavailableReason: nil),
        SettingsSearchEntry(id: "media.sneakPeekStyles", title: "Sneak Peek Style", category: "Media", categoryTitle: "Media", section: "Media playback live activity", sectionID: "media.activity", keywords: "music", requirement: nil, unavailableReason: nil),
        SettingsSearchEntry(id: "media.waitInterval", title: "Media inactivity timeout", category: "Media", categoryTitle: "Media", section: "Media playback live activity", sectionID: "media.activity", keywords: "music delay", requirement: nil, unavailableReason: nil),
        SettingsSearchEntry(id: "media.hideNotchOption", title: "Full screen behavior", category: "Media", categoryTitle: "Media", section: "Media playback live activity", sectionID: "media.activity", keywords: "music fullscreen", requirement: nil, unavailableReason: nil),
        SettingsSearchEntry(id: "media.musicControlSlots", title: "Layout Preview", category: "Media", categoryTitle: "Media", section: "Media controls", sectionID: "media.controls", keywords: "music buttons reorder volume shuffle repeat favorite", requirement: nil, unavailableReason: nil),
        SettingsSearchEntry(id: "media.resetMusicControls", title: "Reset to Defaults", category: "Media", categoryTitle: "Media", section: "Media controls", sectionID: "media.controls", keywords: "music buttons", requirement: nil, unavailableReason: nil),
        SettingsSearchEntry(id: "media.enableLyrics", title: "Show lyrics below artist name", category: "Media", categoryTitle: "Media", section: "Media controls", sectionID: "media.controls", keywords: "music", requirement: nil, unavailableReason: nil),
        SettingsSearchEntry(id: "coursepath.browserConnect", title: "Connect CoursePath", category: "CoursePath", categoryTitle: "CoursePath", section: "CoursePath connection", sectionID: "coursepath.connection", keywords: "connection browser sign in calendar tasks", requirement: "needsCredential", unavailableReason: "Already connected. Use Refresh or Disconnect."),
        SettingsSearchEntry(id: "coursepath.server", title: "Server", category: "CoursePath", categoryTitle: "CoursePath", section: "CoursePath connection", sectionID: "coursepath.connection", keywords: "connection local production", requirement: nil, unavailableReason: nil),
        SettingsSearchEntry(id: "coursepath.desktopToken", title: "Desktop access token", category: "CoursePath", categoryTitle: "CoursePath", section: "CoursePath connection", sectionID: "coursepath.connection", keywords: "connection authentication", requirement: "needsCredential", unavailableReason: "A credential is already stored. Disconnect to connect with another token."),
        SettingsSearchEntry(id: "coursepath.connect", title: "Connect", category: "CoursePath", categoryTitle: "CoursePath", section: "CoursePath connection", sectionID: "coursepath.connection", keywords: "connection", requirement: "needsCredential", unavailableReason: "Already connected. Use Refresh or Disconnect."),
        SettingsSearchEntry(id: "coursepath.refresh", title: "Refresh", category: "CoursePath", categoryTitle: "CoursePath", section: "CoursePath connection", sectionID: "coursepath.connection", keywords: "sync connection", requirement: "credential", unavailableReason: "Connect to CoursePath first."),
        SettingsSearchEntry(id: "coursepath.disconnect", title: "Disconnect", category: "CoursePath", categoryTitle: "CoursePath", section: "CoursePath connection", sectionID: "coursepath.connection", keywords: "connection", requirement: "disconnect", unavailableReason: "No CoursePath connection to disconnect."),
        SettingsSearchEntry(id: "hud.hudReplacement", title: "Replace system HUD", category: "HUD", categoryTitle: "HUDs", section: "Replace system HUD", sectionID: "hud.system", keywords: "volume brightness", requirement: "accessibility", unavailableReason: "Accessibility access is required. Use Request Accessibility in HUDs."),
        SettingsSearchEntry(id: "hud.optionKeyAction", title: "Option key behaviour", category: "HUD", categoryTitle: "HUDs", section: "General", sectionID: "hud.general", keywords: "volume brightness", requirement: "hud", unavailableReason: "Enable Replace system HUD first."),
        SettingsSearchEntry(id: "hud.enableGradient", title: "Progress bar style", category: "HUD", categoryTitle: "HUDs", section: "General", sectionID: "hud.general", keywords: "volume brightness gradient", requirement: "hud", unavailableReason: "Enable Replace system HUD first."),
        SettingsSearchEntry(id: "hud.systemEventIndicatorShadow", title: "Enable glowing effect", category: "HUD", categoryTitle: "HUDs", section: "General", sectionID: "hud.general", keywords: "volume brightness", requirement: "hud", unavailableReason: "Enable Replace system HUD first."),
        SettingsSearchEntry(id: "hud.systemEventIndicatorUseAccent", title: "Tint progress bar with accent color", category: "HUD", categoryTitle: "HUDs", section: "General", sectionID: "hud.general", keywords: "volume brightness", requirement: "hud", unavailableReason: "Enable Replace system HUD first."),
        SettingsSearchEntry(id: "hud.showOpenNotchHUD", title: "Show HUD in open notch", category: "HUD", categoryTitle: "HUDs", section: "Open Notch", sectionID: "hud.open", keywords: "volume brightness", requirement: "hud", unavailableReason: "Enable Replace system HUD first."),
        SettingsSearchEntry(id: "hud.showOpenNotchHUDPercentage", title: "Show percentage", category: "HUD", categoryTitle: "HUDs", section: "Open Notch", sectionID: "hud.open", keywords: "volume brightness", requirement: "openHUD", unavailableReason: "Enable Replace system HUD and Show HUD in open notch first."),
        SettingsSearchEntry(id: "hud.inlineHUD", title: "HUD style", category: "HUD", categoryTitle: "HUDs", section: "Closed Notch", sectionID: "hud.closed", keywords: "volume brightness", requirement: "hud", unavailableReason: "Enable Replace system HUD first."),
        SettingsSearchEntry(id: "hud.showClosedNotchHUDPercentage", title: "Show percentage", category: "HUD", categoryTitle: "HUDs", section: "Closed Notch", sectionID: "hud.closed", keywords: "volume brightness", requirement: "hud", unavailableReason: "Enable Replace system HUD first."),
        SettingsSearchEntry(id: "battery.showBatteryIndicator", title: "Show battery indicator", category: "Battery", categoryTitle: "Battery", section: "General", sectionID: "battery.general", keywords: "power charge", requirement: nil, unavailableReason: nil),
        SettingsSearchEntry(id: "battery.showPowerStatusNotifications", title: "Show power status notifications", category: "Battery", categoryTitle: "Battery", section: "General", sectionID: "battery.general", keywords: "charge", requirement: nil, unavailableReason: nil),
        SettingsSearchEntry(id: "battery.showBatteryPercentage", title: "Show battery percentage", category: "Battery", categoryTitle: "Battery", section: "Battery Information", sectionID: "battery.information", keywords: "power charge", requirement: nil, unavailableReason: nil),
        SettingsSearchEntry(id: "battery.showPowerStatusIcons", title: "Show power status icons", category: "Battery", categoryTitle: "Battery", section: "Battery Information", sectionID: "battery.information", keywords: "charge", requirement: nil, unavailableReason: nil),
        SettingsSearchEntry(id: "shelf.boringShelf", title: "Enable shelf", category: "Shelf", categoryTitle: "Shelf", section: "General", sectionID: "shelf.general", keywords: "files", requirement: nil, unavailableReason: nil),
        SettingsSearchEntry(id: "shelf.openShelfByDefault", title: "Open shelf by default if items are present", category: "Shelf", categoryTitle: "Shelf", section: "General", sectionID: "shelf.general", keywords: "tab files", requirement: nil, unavailableReason: nil),
        SettingsSearchEntry(id: "shelf.expandedDragDetection", title: "Expanded drag detection area", category: "Shelf", categoryTitle: "Shelf", section: "General", sectionID: "shelf.general", keywords: "files drop", requirement: nil, unavailableReason: nil),
        SettingsSearchEntry(id: "shelf.copyOnDrag", title: "Copy items on drag", category: "Shelf", categoryTitle: "Shelf", section: "General", sectionID: "shelf.general", keywords: "files drop", requirement: nil, unavailableReason: nil),
        SettingsSearchEntry(id: "shelf.autoRemoveShelfItems", title: "Remove from shelf after dragging", category: "Shelf", categoryTitle: "Shelf", section: "General", sectionID: "shelf.general", keywords: "files drop", requirement: nil, unavailableReason: nil),
        SettingsSearchEntry(id: "shelf.quickShareProvider", title: "Quick Share Service", category: "Shelf", categoryTitle: "Shelf", section: "Quick Share", sectionID: "shelf.share", keywords: "files airdrop", requirement: nil, unavailableReason: nil),
        SettingsSearchEntry(id: "shortcuts.toggleSneakPeek", title: "Toggle Sneak Peek:", category: "Shortcuts", categoryTitle: "Shortcuts", section: "Media", sectionID: "shortcuts.media", keywords: "keyboard music", requirement: nil, unavailableReason: nil),
        SettingsSearchEntry(id: "shortcuts.toggleNotchOpen", title: "Toggle Notch Open:", category: "Shortcuts", categoryTitle: "Shortcuts", section: "Shortcuts", sectionID: "shortcuts.notch", keywords: "keyboard", requirement: nil, unavailableReason: nil),
        SettingsSearchEntry(id: "advanced.useCustomAccentColor", title: "Accent color", category: "Advanced", categoryTitle: "Advanced", section: "Accent color", sectionID: "advanced.accent", keywords: "theme appearance", requirement: nil, unavailableReason: nil),
        SettingsSearchEntry(id: "advanced.colorPresets", title: "Color Presets", category: "Advanced", categoryTitle: "Advanced", section: "Accent color", sectionID: "advanced.accent", keywords: "theme appearance", requirement: "customAccent", unavailableReason: "Choose Custom accent color first."),
        SettingsSearchEntry(id: "advanced.customAccentColorData", title: "Pick a Color", category: "Advanced", categoryTitle: "Advanced", section: "Accent color", sectionID: "advanced.accent", keywords: "theme appearance", requirement: "customAccent", unavailableReason: "Choose Custom accent color first."),
        SettingsSearchEntry(id: "advanced.enableShadow", title: "Enable window shadow", category: "Advanced", categoryTitle: "Advanced", section: "Window Appearance", sectionID: "advanced.appearance", keywords: "appearance", requirement: nil, unavailableReason: nil),
        SettingsSearchEntry(id: "advanced.cornerRadiusScaling", title: "Corner radius scaling", category: "Advanced", categoryTitle: "Advanced", section: "Window Appearance", sectionID: "advanced.appearance", keywords: "appearance", requirement: nil, unavailableReason: nil),
        SettingsSearchEntry(id: "advanced.appIcon", title: "Default", category: "Advanced", categoryTitle: "Advanced", section: "App icon", sectionID: "advanced.icon", keywords: "icon", requirement: "never", unavailableReason: "App icon selection is marked Coming soon."),
        SettingsSearchEntry(id: "advanced.extendHoverArea", title: "Extend hover area", category: "Advanced", categoryTitle: "Advanced", section: "Window Behavior", sectionID: "advanced.behavior", keywords: "mouse", requirement: nil, unavailableReason: nil),
        SettingsSearchEntry(id: "advanced.hideTitleBar", title: "Hide title bar", category: "Advanced", categoryTitle: "Advanced", section: "Window Behavior", sectionID: "advanced.behavior", keywords: "window", requirement: nil, unavailableReason: nil),
        SettingsSearchEntry(id: "advanced.showOnLockScreen", title: "Show notch on lock screen", category: "Advanced", categoryTitle: "Advanced", section: "Window Behavior", sectionID: "advanced.behavior", keywords: "window", requirement: nil, unavailableReason: nil),
        SettingsSearchEntry(id: "advanced.hideFromScreenRecording", title: "Hide from screen recording", category: "Advanced", categoryTitle: "Advanced", section: "Window Behavior", sectionID: "advanced.behavior", keywords: "privacy capture", requirement: nil, unavailableReason: nil),
        SettingsSearchEntry(id: "about.releaseName", title: "Release name", category: "About", categoryTitle: "About", section: "Version info", sectionID: "about.version", keywords: "build", requirement: nil, unavailableReason: nil),
        SettingsSearchEntry(id: "about.version", title: "Version", category: "About", categoryTitle: "About", section: "Version info", sectionID: "about.version", keywords: "build", requirement: nil, unavailableReason: nil),
        SettingsSearchEntry(id: "about.github", title: "GitHub", category: "About", categoryTitle: "About", section: "About", sectionID: "about.links", keywords: "source license attribution", requirement: nil, unavailableReason: nil),
        SettingsSearchEntry(id: "general.quit", title: "Quit app", category: "General", categoryTitle: "General", section: "System features", sectionID: "general.system", keywords: "exit", requirement: nil, unavailableReason: nil),
        SettingsSearchEntry(id: "hud.requestAccessibility", title: "Request Accessibility", category: "HUD", categoryTitle: "HUDs", section: "Replace system HUD", sectionID: "hud.system", keywords: "permission volume brightness", requirement: "needsAccessibility", unavailableReason: "Accessibility access is already granted."),
    ]
    static func search(_ query: String) -> [SettingsSearchEntry] {
        let terms = normalized(query).split(whereSeparator: \.isWhitespace)
        guard !terms.isEmpty else { return [] }
        return entries.filter { entry in
            let text = normalized([entry.title, entry.categoryTitle, entry.section, entry.keywords].joined(separator: " "))
            return terms.allSatisfy { text.contains($0) }
        }
    }
    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}
