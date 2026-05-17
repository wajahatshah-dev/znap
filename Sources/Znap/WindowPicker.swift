import AppKit
import ScreenCaptureKit

@MainActor
final class WindowPickerController {
    func pickWindow() async -> SCWindow? {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                true, onScreenWindowsOnly: true)
        } catch {
            showError(error, context: "Could not load windows")
            return nil
        }

        let myPID = ProcessInfo.processInfo.processIdentifier
        let windows = content.windows
            .filter { w in
                guard let app = w.owningApplication else { return false }
                if app.processID == myPID { return false }
                if w.frame.width < 60 || w.frame.height < 60 { return false }
                return true
            }
            .sorted { ($0.owningApplication?.applicationName ?? "") < ($1.owningApplication?.applicationName ?? "") }

        guard !windows.isEmpty else { return nil }

        let alert = NSAlert()
        alert.messageText = "Select a window"
        alert.informativeText = "Choose which window to capture."
        alert.addButton(withTitle: "Capture")
        alert.addButton(withTitle: "Cancel")

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 420, height: 26), pullsDown: false)
        for w in windows {
            let app = w.owningApplication?.applicationName ?? "Unknown"
            let title = (w.title?.isEmpty == false) ? w.title! : "Untitled"
            let label = "\(app) — \(title)"
            popup.addItem(withTitle: "")
            popup.lastItem?.title = label
        }
        alert.accessoryView = popup

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }
        let idx = popup.indexOfSelectedItem
        return (idx >= 0 && idx < windows.count) ? windows[idx] : nil
    }
}
