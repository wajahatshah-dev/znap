import AppKit

@MainActor
final class WelcomeWindowController {
    static let hasShownKey = "Znap.HasShownWelcome"

    private var window: NSWindow?

    static var hasShown: Bool {
        UserDefaults.standard.bool(forKey: hasShownKey)
    }

    func showIfFirstLaunch() {
        guard !Self.hasShown else { return }
        show()
        UserDefaults.standard.set(true, forKey: Self.hasShownKey)
    }

    func show() {
        if let w = window {
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
            return
        }

        let size = NSSize(width: 520, height: 560)
        let w = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        w.title = "Welcome to Znap"
        w.titlebarAppearsTransparent = true
        w.isMovableByWindowBackground = true
        w.center()
        w.level = .floating
        w.isReleasedWhenClosed = false

        let root = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        root.material = .underWindowBackground
        root.blendingMode = .behindWindow
        root.state = .active
        root.autoresizingMask = [.width, .height]

        // Icon — use the bundle's app icon
        let iconSize: CGFloat = 96
        let icon = NSImageView(frame: NSRect(x: (size.width - iconSize) / 2,
                                             y: size.height - 130,
                                             width: iconSize, height: iconSize))
        icon.image = NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        root.addSubview(icon)

        // Title
        let title = label("Znap",
                          font: .systemFont(ofSize: 26, weight: .semibold),
                          color: .labelColor,
                          frame: NSRect(x: 0, y: size.height - 178,
                                        width: size.width, height: 32))
        title.alignment = .center
        root.addSubview(title)

        // Subtitle
        let subtitle = label("A lightweight screen capture & recorder, living in your menu bar.",
                             font: .systemFont(ofSize: 13),
                             color: .secondaryLabelColor,
                             frame: NSRect(x: 24, y: size.height - 206,
                                           width: size.width - 48, height: 20))
        subtitle.alignment = .center
        root.addSubview(subtitle)

        // Feature rows
        let features: [(String, String, String)] = [
            ("rectangle.dashed",     "Capture Area",      "Drag to select a region of the screen."),
            ("rectangle.on.rectangle", "Capture Window",  "Pick any window and snap a clean shot."),
            ("display",              "Capture Full Screen", "One click — your whole display."),
            ("record.circle",        "Record Area / Window", "Record video to .mov. Click Stop when done."),
        ]
        var y = size.height - 252
        for (sym, name, desc) in features {
            let row = featureRow(symbol: sym, name: name, desc: desc,
                                 frame: NSRect(x: 36, y: y - 44,
                                               width: size.width - 72, height: 44))
            root.addSubview(row)
            y -= 56
        }

        // Hint
        let hint = label("Click the Znap icon in your menu bar to get started.",
                         font: .systemFont(ofSize: 12),
                         color: .tertiaryLabelColor,
                         frame: NSRect(x: 24, y: 64,
                                       width: size.width - 48, height: 18))
        hint.alignment = .center
        root.addSubview(hint)

        // Button
        let button = NSButton(title: "Get Started",
                              target: self,
                              action: #selector(close))
        button.bezelStyle = .rounded
        button.keyEquivalent = "\r"
        button.controlSize = .large
        button.sizeToFit()
        var bf = button.frame
        bf.size.width = max(bf.size.width, 140)
        bf.size.height = 32
        bf.origin = NSPoint(x: (size.width - bf.width) / 2, y: 20)
        button.frame = bf
        root.addSubview(button)

        w.contentView = root
        self.window = w

        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    @objc private func close() {
        window?.orderOut(nil)
    }

    private func label(_ text: String, font: NSFont, color: NSColor, frame: NSRect) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = font
        f.textColor = color
        f.frame = frame
        f.isBezeled = false
        f.drawsBackground = false
        f.isEditable = false
        f.isSelectable = false
        return f
    }

    private func featureRow(symbol: String, name: String, desc: String, frame: NSRect) -> NSView {
        let view = NSView(frame: frame)

        let icon = NSImageView(frame: NSRect(x: 0, y: 6, width: 28, height: 28))
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        let cfg = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        icon.image = img?.withSymbolConfiguration(cfg)
        icon.contentTintColor = .controlAccentColor
        view.addSubview(icon)

        let title = label(name,
                          font: .systemFont(ofSize: 13, weight: .semibold),
                          color: .labelColor,
                          frame: NSRect(x: 40, y: 22, width: frame.width - 40, height: 18))
        view.addSubview(title)

        let detail = label(desc,
                           font: .systemFont(ofSize: 12),
                           color: .secondaryLabelColor,
                           frame: NSRect(x: 40, y: 4, width: frame.width - 40, height: 16))
        view.addSubview(detail)

        return view
    }
}
