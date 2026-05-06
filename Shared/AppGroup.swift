import Foundation

/// Single source of truth for the App Group identifier.
///
/// The host app and the two extensions all need this string to agree on
/// the same shared cache directory. Changing it requires updating all three
/// `.entitlements` files and any code-signing automation.
enum AppGroup {
    static let identifier = "group.io.github.saiahlee.EPSViewer"
}
