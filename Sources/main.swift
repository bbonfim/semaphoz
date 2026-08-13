import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = StatusBarController()
    }
}

// Non-interactive control of the login item, so install.sh can enable it without the
// user having to find the menu. The dropdown toggle does the same thing.
if CommandLine.arguments.contains("--enable-login-item") ||
   CommandLine.arguments.contains("--disable-login-item") {
    let enable = CommandLine.arguments.contains("--enable-login-item")
    if let failure = LoginItem.setEnabled(enable) {
        FileHandle.standardError.write(Data("Launch at Login failed: \(failure)\n".utf8))
        exit(1)
    }
    print("Launch at Login: \(LoginItem.isEnabled ? "enabled" : "disabled")")
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu bar only: no Dock icon, no app menu
app.run()
