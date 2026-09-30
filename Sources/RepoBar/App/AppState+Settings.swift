import AppKit
import RepoBarCore

struct SettingsUpdateEffects: OptionSet {
    let rawValue: Int

    static let launchAtLogin = Self(rawValue: 1 << 0)
    static let menuDiagnostics = Self(rawValue: 1 << 1)
    static let heatmapRange = Self(rawValue: 1 << 2)
    static let refresh = Self(rawValue: 1 << 3)
    static let cancelInFlightRefresh = Self(rawValue: 1 << 4)
    static let appAppearance = Self(rawValue: 1 << 5)
}

extension AppState {
    func updateSetting<Value>(
        _ keyPath: WritableKeyPath<UserSettings, Value>,
        to value: Value,
        effects: SettingsUpdateEffects = []
    ) {
        self.session.settings[keyPath: keyPath] = value
        self.persistSettings()

        if effects.contains(.launchAtLogin) {
            LaunchAtLoginHelper.set(enabled: self.session.settings.launchAtLogin)
        }
        if effects.contains(.appAppearance) {
            self.applyColorScheme()
        }
        if effects.contains(.heatmapRange) {
            self.updateHeatmapRange(now: Date())
        }
        if effects.contains(.menuDiagnostics) {
            NotificationCenter.default.post(name: .menuDiagnosticsDidChange, object: nil)
        }
        if effects.contains(.cancelInFlightRefresh) {
            self.requestRefresh(cancelInFlight: true)
        } else if effects.contains(.refresh) {
            self.requestRefresh()
        }
    }

    func applyColorScheme() {
        // NSApp is nil in unit tests that never create an NSApplication.
        guard let app = NSApp else { return }

        app.appearance = self.session.settings.appearance.colorScheme.nsAppearance
    }
}
