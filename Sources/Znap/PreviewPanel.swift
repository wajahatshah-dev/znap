import AppKit

@MainActor
final class PreviewPanelController {
    private static var openPanels: [PreviewPanelController] = []

    /// Mutable so the editor can swap in an annotated version.
    private var image: CGImage
    private var panel: NSPanel?
    private var imageView: NSImageView?
    private var copyButton: GlassIconButton?
    private var editor: EditorWindowController?
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
        let maxDim: CGFloat = 200
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

        let pad = Theme.panelPadding
        let bottomBar = Theme.bottomBarHeight
        let panelW = w + pad * 2
        let panelH = h + bottomBar + pad * 2

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

        let (container, content) = Theme.makeGlassContainer(
            size: NSSize(width: panelW, height: panelH))

        // Image thumbnail
        let iv = NSImageView(frame: NSRect(x: pad, y: bottomBar + pad,
                                           width: w, height: h))
        iv.image = NSImage(cgImage: image, size: NSSize(width: imgW, height: imgH))
        iv.imageScaling = .scaleProportionallyUpOrDown
        iv.wantsLayer = true
        iv.layer?.cornerRadius = Theme.thumbnailCornerRadius
        iv.layer?.cornerCurve = .continuous
        iv.layer?.masksToBounds = true
        content.addSubview(iv)
        self.imageView = iv

        // Bottom: 4 icon-only buttons centered horizontally.
        let btnSize = Theme.iconButtonSize
        let btnGap = Theme.iconButtonGap
        let totalBtnW = btnSize * 4 + btnGap * 3
        let startX = (panelW - totalBtnW) / 2
        let btnY = (bottomBar - btnSize) / 2

        let editBtn = Theme.iconButton(
            symbol: "pencil.tip.crop.circle",
            tooltip: "Edit",
            target: self, action: #selector(editTapped))
        let copyBtn = Theme.iconButton(
            symbol: "doc.on.doc",
            tooltip: "Copy",
            target: self, action: #selector(copyImage))
        let saveBtn = Theme.primaryIconButton(
            symbol: "square.and.arrow.down",
            tooltip: "Save",
            target: self, action: #selector(saveImage))
        saveBtn.keyEquivalent = "\r"
        let closeBtn = Theme.iconButton(
            symbol: "xmark",
            tooltip: "Close",
            target: self, action: #selector(closeTapped))

        let buttons: [NSButton] = [editBtn, copyBtn, saveBtn, closeBtn]
        for (i, b) in buttons.enumerated() {
            b.frame = NSRect(x: startX + CGFloat(i) * (btnSize + btnGap),
                             y: btnY, width: btnSize, height: btnSize)
            content.addSubview(b)
        }
        self.copyButton = copyBtn

        panel.contentView = container
        panel.alphaValue = 0
        panel.orderFront(nil)
        self.panel = panel

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 1
        }
    }

    @objc private func editTapped() {
        // Hide while editing so the editor window has full focus.
        panel?.orderOut(nil)
        editor = EditorWindowController(
            image: image,
            onDone: { [weak self] edited in
                guard let self else { return }
                self.image = edited
                self.imageView?.image = NSImage(
                    cgImage: edited,
                    size: NSSize(width: edited.width, height: edited.height)
                )
                self.editor = nil
                self.panel?.orderFront(nil)
            },
            onCancel: { [weak self] in
                guard let self else { return }
                self.editor = nil
                self.panel?.orderFront(nil)
            }
        )
        editor?.show()
    }

    @objc private func copyImage() {
        let nsImage = NSImage(cgImage: image,
                              size: NSSize(width: image.width, height: image.height))
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([nsImage])
        flashCopyFeedback()
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

    private func flashCopyFeedback() {
        guard let btn = copyButton else { return }
        let originalImage = btn.image
        btn.image = NSImage(systemSymbolName: "checkmark",
                            accessibilityDescription: "Copied")?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak btn] in
            btn?.image = originalImage
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
