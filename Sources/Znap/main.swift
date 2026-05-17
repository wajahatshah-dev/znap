import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var stopItem: NSMenuItem!

    let capture = CaptureManager()
    let recording = RecordingManager()
    let welcome = WelcomeWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildStatusItem()
        recording.onStateChange = { [weak self] isRecording in
            Task { @MainActor in self?.updateForRecording(isRecording) }
        }
        welcome.showIfFirstLaunch()
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = menuBarIcon()
        }

        let menu = NSMenu()
        menu.autoenablesItems = false

        menu.addItem(header("Capture"))
        menu.addItem(item("Capture Area",         #selector(captureArea),       key: "1"))
        menu.addItem(item("Capture Full Screen",  #selector(captureFullScreen), key: "3"))
        menu.addItem(item("Capture Window",       #selector(captureWindow),     key: "4"))

        menu.addItem(.separator())
        menu.addItem(header("Record"))
        menu.addItem(item("Record Area",   #selector(recordArea),   key: "5"))
        menu.addItem(item("Record Window", #selector(recordWindow), key: "6"))
        stopItem = item("Stop Recording", #selector(stopRecording), key: "s")
        stopItem.isEnabled = false
        menu.addItem(stopItem)

        menu.addItem(.separator())
        menu.addItem(item("Open Save Folder", #selector(openSaveFolder), key: ""))
        menu.addItem(item("About Znap", #selector(showWelcome), key: ""))
        menu.addItem(item("Quit Znap", #selector(quit), key: "q"))

        statusItem.menu = menu
    }

    private func header(_ title: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.isEnabled = false
        return i
    }

    private func item(_ title: String, _ action: Selector, key: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    private func updateForRecording(_ isRecording: Bool) {
        stopItem.isEnabled = isRecording
        if let button = statusItem.button {
            if isRecording {
                let img = NSImage(systemSymbolName: "record.circle.fill",
                                  accessibilityDescription: "Recording")
                img?.isTemplate = false
                button.image = img
                button.contentTintColor = .systemRed
            } else {
                button.image = menuBarIcon()
                button.contentTintColor = nil
            }
        }
    }

    private func menuBarIcon() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
              let img = NSImage(contentsOf: url) else {
            let fallback = NSImage(systemSymbolName: "camera.viewfinder",
                                    accessibilityDescription: "Znap")
            fallback?.isTemplate = true
            return fallback
        }
        img.size = NSSize(width: 18, height: 18)
        img.isTemplate = true
        return img
    }

    @objc private func captureArea()       { Task { await capture.captureArea() } }
    @objc private func captureFullScreen() { Task { await capture.captureFullScreen() } }
    @objc private func captureWindow()     { Task { await capture.captureWindow() } }
    @objc private func recordArea()        { Task { await recording.recordArea() } }
    @objc private func recordWindow()      { Task { await recording.recordWindow() } }
    @objc private func stopRecording()     { Task { await recording.stop() } }
    @objc private func openSaveFolder() {
        NSWorkspace.shared.open(SaveLocation.directory)
    }
    @objc private func showWelcome() {
        welcome.show()
    }
    @objc private func quit() {
        Task { await recording.stop() }
        NSApp.terminate(nil)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
