import AppKit

@MainActor
final class PreviewPanelController {
    private static var openPanels: [PreviewPanelController] = []

    private let image: CGImage
    private var panel: NSPanel?
    private var stackIndex: Int = 0

    static func show(image: CGImage) {
        let controller = PreviewPanelController(image: image)
        controller.stackIndex = openPanels.count
        openPanels.append(controller)
        controller.present()
    }

    private init(image: CGImage) {
        self.image = image
    }

    private func present() {
        let maxDim: CGFloat = 280
        let imgW = CGFloat(image.width)
        let imgH = CGFloat(image.height)
        let ratio = imgW / imgH

        var w: CGFloat
        var h: CGFloat
        if ratio >= 1 {
            w = maxDim
            h = maxDim / ratio
        } else {
            h = maxDim
            w = maxDim * ratio
        }

        let bottomBar: CGFloat = 44
        let padding: CGFloat = 8
        let panelW = w + padding * 2
        let panelH = h + bottomBar + padding

        guard let screen = NSScreen.main else { return }
        let originX = screen.visibleFrame.minX + 20
        let originY = screen.visibleFrame.minY + 20 + CGFloat(stackIndex) * (panelH + 12)

        let panel = NSPanel(
            contentRect: NSRect(x: originX, y: originY, width: panelW, height: panelH),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false

        // Container with rounded corners + subtle border.
        let container = NSView(frame: NSRect(origin: .zero,
                                             size: NSSize(width: panelW, height: panelH)))
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.masksToBounds = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor

        // Image
        let imageView = NSImageView(frame: NSRect(x: padding, y: bottomBar,
                                                  width: w, height: h))
        imageView.image = NSImage(cgImage: image, size: NSSize(width: imgW, height: imgH))
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 6
        imageView.layer?.masksToBounds = true
        container.addSubview(imageView)

        // Buttons
        let btnH: CGFloat = 26
        let gap: CGFloat = 8
        let btnW: CGFloat = (panelW - padding * 2 - gap * 2) / 3
        let btnY: CGFloat = (bottomBar - btnH) / 2

        let copyBtn = makeButton(title: "Copy",
                                 symbol: "doc.on.doc",
                                 selector: #selector(copyImage),
                                 frame: NSRect(x: padding, y: btnY, width: btnW, height: btnH))
        let saveBtn = makeButton(title: "Save",
                                 symbol: "square.and.arrow.down",
                                 selector: #selector(saveImage),
                                 frame: NSRect(x: padding + btnW + gap, y: btnY, width: btnW, height: btnH))
        let closeBtn = makeButton(title: "Close",
                                  symbol: "xmark",
                                  selector: #selector(closeTapped),
                                  frame: NSRect(x: padding + (btnW + gap) * 2,
                                                y: btnY, width: btnW, height: btnH))
        saveBtn.bezelColor = .controlAccentColor
        saveBtn.keyEquivalent = "\r"

        container.addSubview(copyBtn)
        container.addSubview(saveBtn)
        container.addSubview(closeBtn)

        panel.contentView = container
        panel.alphaValue = 0
        panel.orderFront(nil)
        self.panel = panel

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 1
        }
    }

    private func makeButton(title: String, symbol: String, selector: Selector, frame: NSRect) -> NSButton {
        let b = NSButton(frame: frame)
        b.title = " " + title
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        b.imagePosition = .imageLeft
        b.bezelStyle = .rounded
        b.controlSize = .small
        b.font = .systemFont(ofSize: 12, weight: .medium)
        b.target = self
        b.action = selector
        return b
    }

    @objc private func copyImage() {
        let nsImage = NSImage(cgImage: image,
                              size: NSSize(width: image.width, height: image.height))
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([nsImage])
        flashButtonTitle("Copied")
    }

    @objc private func saveImage() {
        let url = SaveLocation.newURL(prefix: "Znap Screenshot", ext: "png")
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = NSSize(width: image.width, height: image.height)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        do {
            try data.write(to: url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            dismiss()
        } catch {
            showError(error, context: "Could not save screenshot")
        }
    }

    @objc private func closeTapped() {
        dismiss()
    }

    private func flashButtonTitle(_ text: String) {
        guard let container = panel?.contentView else { return }
        for case let btn as NSButton in container.subviews where btn.action == #selector(copyImage) {
            let originalTitle = btn.title
            let originalImage = btn.image
            btn.title = " " + text
            btn.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak btn] in
                btn?.title = originalTitle
                btn?.image = originalImage
            }
            break
        }
    }

    private func dismiss() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
        self.panel = nil
        PreviewPanelController.openPanels.removeAll { $0 === self }
    }
}
