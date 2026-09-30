import Foundation
@testable import RepoBar
@testable import RepoBarCore
import Testing

@MainActor
struct RepoSubmenuCacheTests {
    @Test
    func `heatmap color change rebuilds cached submenu without repository changes`() throws {
        let suiteName = "com.steipete.repobar.submenu-cache-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let appState = AppState(settingsStore: SettingsStore(defaults: defaults))
        appState.session.settings.heatmap.display = .submenu
        appState.session.settings.appearance.accentTone = .githubGreen
        let now = Date(timeIntervalSinceReferenceDate: 1_500_000)
        appState.session.heatmapRange = HeatmapRange(start: now.addingTimeInterval(-86400), end: now)
        let repo = Repository(
            id: "synthetic", name: "Repo", owner: "example", sortOrder: 0,
            error: nil, rateLimitedUntil: nil, ciStatus: .unknown,
            openIssues: 0, openPulls: 0, latestRelease: nil, latestActivity: nil,
            traffic: nil, heatmap: [HeatmapCell(date: now, count: 4)]
        )
        let manager = StatusBarMenuManager(appState: appState)
        let builder = StatusBarMenuBuilder(appState: appState, target: manager)
        let display = RepositoryDisplayModel(repo: repo, now: now)
        let greenMenu = builder.repoSubmenu(for: display, isPinned: false)
        #expect(builder.repoSubmenu(for: display, isPinned: false) === greenMenu)

        appState.session.settings.appearance.accentTone = .system
        let systemMenu = builder.repoSubmenu(for: display, isPinned: false)

        #expect(systemMenu !== greenMenu)
        #expect(builder.repoSubmenu(for: display, isPinned: false) === systemMenu)
        appState.session.settings.appearance.accentTone = .githubGreen
        #expect(builder.repoSubmenu(for: display, isPinned: false) !== systemMenu)
    }
}
