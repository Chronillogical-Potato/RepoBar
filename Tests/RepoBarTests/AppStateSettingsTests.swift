import AppKit
import Foundation
@testable import RepoBar
import RepoBarCore
import Testing

@MainActor
struct AppStateSettingsTests {
    @Test
    func `setting update persists nested value without starting runtime`() throws {
        let suiteName = "com.steipete.repobar.settings-update-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SettingsStore(defaults: defaults)
        let appState = AppState(settingsStore: store)

        appState.updateSetting(\.repoList.displayLimit, to: 12)

        #expect(appState.session.settings.repoList.displayLimit == 12)
        #expect(store.load().repoList.displayLimit == 12)
        #expect(appState.isStarted == false)
    }

    @Test
    func `heatmap setting effect updates derived range`() throws {
        let suiteName = "com.steipete.repobar.settings-update-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let appState = AppState(settingsStore: SettingsStore(defaults: defaults))
        let previousRange = appState.session.heatmapRange

        appState.updateSetting(\.heatmap.span, to: .oneMonth, effects: .heatmapRange)

        #expect(appState.session.heatmapRange != previousRange)
        #expect(appState.session.settings.heatmap.span == .oneMonth)
    }

    @Test
    func `color scheme setting persists without starting runtime`() throws {
        let suiteName = "com.steipete.repobar.settings-update-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SettingsStore(defaults: defaults)
        let appState = AppState(settingsStore: store)

        appState.updateSetting(\.appearance.colorScheme, to: .dark, effects: .appAppearance)

        #expect(appState.session.settings.appearance.colorScheme == .dark)
        #expect(store.load().appearance.colorScheme == .dark)
        #expect(appState.isStarted == false)
    }

    @Test
    func `color scheme maps to AppKit appearance`() {
        #expect(AppColorScheme.system.nsAppearance == nil)
        #expect(AppColorScheme.light.nsAppearance?.name == .aqua)
        #expect(AppColorScheme.dark.nsAppearance?.name == .darkAqua)
    }

    @Test
    func `bootstrap restores persisted login after restart`() async throws {
        let suiteName = "com.steipete.repobar.login-restore-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let authDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("repobar-login-restore-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: authDirectory) }

        let tokenStore = TokenStore(
            service: "com.steipete.repobar.login-restore-tests",
            storage: .file(authDirectory)
        )
        let account = try Account(
            username: "restart-user",
            host: #require(URL(string: "https://github.com")),
            authMethod: .pat
        )
        try tokenStore.savePAT("persisted-token", accountID: account.id)
        var settings = UserSettings()
        settings.accounts = [account]
        settings.activeAccountID = account.id
        let settingsStore = SettingsStore(defaults: defaults)
        settingsStore.save(settings)

        let restarted = AppState(
            settingsStore: settingsStore,
            accountManager: AccountManager(tokenStore: tokenStore)
        )
        await restarted.bootstrapAccounts()

        #expect(restarted.session.account == .loggedIn(UserIdentity(username: account.username, host: account.host)))
        #expect(restarted.session.hasStoredTokens)
        #expect(restarted.accountManager.activeAccountID == account.id)
        #expect(restarted.session.settings.resolvedActiveAccount()?.id == account.id)
    }
}
