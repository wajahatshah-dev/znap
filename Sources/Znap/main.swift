import AppKit
import Carbon.HIToolbox

/// `⌃⌥⌘` — control + option + command. Rarely used by other macOS apps, so it
/// makes a safe modifier set for system-wide hotkeys.
private let hyperCarbon = controlKey | optionKey | cmdKey
private let hyperCocoa: NSEvent.ModifierFlags = [.control, .option, .command]

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var stopItem: NSMenuItem!

    let capture = CaptureManager()
    let recording = RecordingManager()
    let welcome = WelcomeWindowController()
    private let hotKeys = HotKeyManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildStatusItem()
        recording.onStateChange = { [weak self] isRecording in
            Task { @MainActor in self?.updateForRecording(isRecording) }
        }
        welcome.showIfFirstLaunch()
        registerGlobalHotKeys()
    }

    /// Wire each menu action to a global hotkey so it works from any app.
    /// The same shortcut appears next to its menu item, so users can discover it.
    private func registerGlobalHotKeys() {
        hotKeys.register(keyCode: kVK_ANSI_A, modifiers: hyperCarbon) { [weak self] in
            guard let self else { return }
            Task { @MainActor in await self.capture.captureArea() }
        }
        hotKeys.register(keyCode: kVK_ANSI_T, modifiers: hyperCarbon) { [weak self] in
            guard let self else { return }
            Task { @MainActor in await self.capture.captureText() }
        }
        hotKeys.register(keyCode: kVK_ANSI_F, modifiers: hyperCarbon) { [weak self] in
            guard let self else { return }
            Task { @MainActor in await self.capture.captureFullScreen() }
        }
        hotKeys.register(keyCode: kVK_ANSI_W, modifiers: hyperCarbon) { [weak self] in
            guard let self else { return }
            Task { @MainActor in await self.capture.captureWindow() }
        }
        hotKeys.register(keyCode: kVK_ANSI_L, modifiers: hyperCarbon) { [weak self] in
            guard let self else { return }
            Task { @MainActor in await self.capture.captureScrolling() }
        }
        hotKeys.register(keyCode: kVK_ANSI_R, modifiers: hyperCarbon) { [weak self] in
            guard let self else { return }
            Task { @MainActor in await self.recording.recordArea() }
        }
        hotKeys.register(keyCode: kVK_ANSI_V, modifiers: hyperCarbon) { [weak self] in
            guard let self else { return }
            Task { @MainActor in await self.recording.recordWindow() }
        }
        hotKeys.register(keyCode: kVK_ANSI_Period, modifiers: hyperCarbon) { [weak self] in
            guard let self else { return }
            Task { @MainActor in await self.recording.stop() }
        }
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = menuBarIcon()
        }

        let menu = NSMenu()
        menu.autoenablesItems = false

        menu.addItem(header("Capture"))
        menu.addItem(item("Capture Area",         #selector(captureArea),       key: "a", modifiers: hyperCocoa))
        menu.addItem(item("Capture Text (OCR)",   #selector(captureText),       key: "t", modifiers: hyperCocoa))
        menu.addItem(item("Capture Full Screen",  #selector(captureFullScreen), key: "f", modifiers: hyperCocoa))
        menu.addItem(item("Capture Window",       #selector(captureWindow),     key: "w", modifiers: hyperCocoa))
        menu.addItem(item("Capture Scrolling…",   #selector(captureScrolling),  key: "l", modifiers: hyperCocoa))

        menu.addItem(.separator())
        menu.addItem(header("Record"))
        menu.addItem(item("Record Area",   #selector(recordArea),   key: "r", modifiers: hyperCocoa))
        menu.addItem(item("Record Window", #selector(recordWindow), key: "v", modifiers: hyperCocoa))
        stopItem = item("Stop Recording", #selector(stopRecording), key: ".", modifiers: hyperCocoa)
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

    private func item(_ title: String, _ action: Selector, key: String,
                      modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.keyEquivalentModifierMask = modifiers
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
    @objc private func captureText()       { Task { await capture.captureText() } }
    @objc private func captureFullScreen() { Task { await capture.captureFullScreen() } }
    @objc private func captureWindow()     { Task { await capture.captureWindow() } }
    @objc private func captureScrolling()  { Task { await capture.captureScrolling() } }
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
