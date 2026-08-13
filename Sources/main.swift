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

// Renders the demo arrangement to a PNG for documentation. Drawn at `scale` through the
// same vector code the menu bar uses, so the result is genuinely sharp and always matches
// what the app actually looks like — never an upscaled screenshot.
if let index = CommandLine.arguments.firstIndex(of: "--export"),
   index + 1 < CommandLine.arguments.count {
    let path = CommandLine.arguments[index + 1]
    let scale = CommandLine.arguments.firstIndex(of: "--scale")
        .flatMap { $0 + 1 < CommandLine.arguments.count ? Double(CommandLine.arguments[$0 + 1]) : nil } ?? 4

    let image = RowRenderer().image(for: Demo.layout(),
                                    scale: CGFloat(scale),
                                    background: NSColor(white: 0.125, alpha: 1))
    guard let tiff = image.tiffRepresentation,
          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("Could not encode PNG\n".utf8))
        exit(1)
    }
    do {
        try png.write(to: URL(fileURLWithPath: path))
    } catch {
        FileHandle.standardError.write(Data("Write failed: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
    print("Wrote \(path) at \(Int(image.size.width))×\(Int(image.size.height))")
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu bar only: no Dock icon, no app menu
app.run()
