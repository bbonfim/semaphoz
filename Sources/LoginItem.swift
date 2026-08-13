import Foundation
import ServiceManagement

/// Launch-at-login, via the modern `SMAppService` registration (macOS 13+).
///
/// This is preferred over dropping a LaunchAgent plist into `~/Library/LaunchAgents`:
/// the registration shows up in System Settings → General → Login Items, so it can be
/// found and revoked there rather than being an invisible file the user has to know about.
///
/// Registration follows the app bundle's *path*, so moving the bundle after enabling this
/// silently breaks it. See `install.sh`, which puts the app somewhere stable first.
enum LoginItem {

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns nil on success, or a human-readable reason on failure.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
