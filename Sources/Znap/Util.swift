import AppKit
import ScreenCaptureKit

enum SaveLocation {
    static var directory: URL {
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    static func newURL(prefix: String, ext: String) -> URL {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let name = "\(prefix) \(f.string(from: Date())).\(ext)"
        return directory.appendingPathComponent(name)
    }
}

func playShutter() {
    NSSound(contentsOfFile: "/System/Library/Sounds/Grab.aiff", byReference: true)?.play()
}

@MainActor
func showError(_ error: Error, context: String = "") {
    if isScreenRecordingPermissionError(error) {
        showPermissionAlert()
        return
    }
    NSSound.beep()
    let alert = NSAlert()
    alert.messageText = context.isEmpty ? "Error" : context
    alert.informativeText = error.localizedDescription
    alert.alertStyle = .warning
    NSApp.activate(ignoringOtherApps: true)
    alert.runModal()
}

private func isScreenRecordingPermissionError(_ error: Error) -> Bool {
    let ns = error as NSError
    // SCStreamErrorDomain code -3801 = userDeclined; -3812 also seen for missing entitlement.
    if ns.domain == "com.apple.ScreenCaptureKit.SCStreamErrorDomain" {
        return ns.code == -3801 || ns.code == -3812 || ns.code == -3802
    }
    return ns.localizedDescription.range(of: "TCC", options: .caseInsensitive) != nil
        || ns.localizedDescription.range(of: "declined", options: .caseInsensitive) != nil
}

@MainActor
private func showPermissionAlert() {
    let alert = NSAlert()
    alert.messageText = "Znap needs Screen Recording permission"
    alert.informativeText = """
    Open System Settings → Privacy & Security → Screen Recording, then toggle Znap on.
    After granting, quit Znap (menu bar → Quit Znap) and relaunch it.
    """
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Open Settings")
    alert.addButton(withTitle: "Cancel")
    NSApp.activate(ignoringOtherApps: true)
    if alert.runModal() == .alertFirstButtonReturn {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}

func displayFor(rect: CGRect, in displays: [SCDisplay]) -> (SCDisplay, NSScreen)? {
    let center = CGPoint(x: rect.midX, y: rect.midY)
    guard let screen = NSScreen.screens.first(where: { $0.frame.contains(center) })
            ?? NSScreen.main else { return nil }
    let screenID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    let display = displays.first(where: { $0.displayID == screenID }) ?? displays.first
    guard let display else { return nil }
    return (display, screen)
}

/// Convert a global (bottom-left origin) rect to a display-local top-left-origin rect in points.
func toDisplayLocal(globalRect: CGRect, screen: NSScreen) -> CGRect {
    let local = globalRect.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
    return CGRect(x: local.minX,
                  y: screen.frame.height - local.maxY,
                  width: local.width,
                  height: local.height)
}

extension CGSize {
    var evenInts: (Int, Int) {
        let w = Int(width.rounded()); let h = Int(height.rounded())
        return (w - (w % 2), h - (h % 2))
    }
}
