import AppKit
import RepoBarCore

extension AppColorScheme {
    /// `nil` lets the app follow the macOS appearance.
    var nsAppearance: NSAppearance? {
        switch self {
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        case .system: nil
        }
    }
}
