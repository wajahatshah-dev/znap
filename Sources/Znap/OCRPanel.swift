import AppKit

/// Floating result panel for "Capture Text". Shows the source thumbnail, the
/// recognized text in a scrollable text view, and Copy / Close icon buttons.
@MainActor
final class OCRPanelController {
    private static var openPanels: [OCRPanelController] = []

    private let text: String
    private let thumbnail: CGImage
    private var panel: NSPanel?
    private var copyButton: GlassIconButton?
    private var stackIndex: Int = 0

    static func show(text: String, thumbnail: CGImage) {
        let controller = OCRPanelController(text: text, thumbnail: thumbnail)
        controller.stackIndex = openPanels.count
        openPanels.append(controller)
        controller.present()
    }

    private init(text: String, thumbnail: CGImage) {
        self.text = text
        self.thumbnail = thumbnail
    }

    private func present() {
        let panelW: CGFloat = 300
        let pad = Theme.panelPadding
        let thumbH: CGFloat = 56
        let textH: CGFloat = 150
        let bottomBar = Theme.bottomBarHeight
        let panelH: CGFloat = thumbH + textH + bottomBar + pad * 3

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

        // Top: source thumbnail with an OCR badge.
        let thumbFrame = NSRect(x: pad, y: panelH - pad - thumbH,
                                width: panelW - pad * 2, height: thumbH)
        let thumb = NSImageView(frame: thumbFrame)
        thumb.image = NSImage(cgImage: thumbnail,
                              size: NSSize(width: thumbnail.width, height: thumbnail.height))
        thumb.imageScaling = .scaleProportionallyUpOrDown
        thumb.wantsLayer = true
        thumb.layer?.cornerRadius = Theme.thumbnailCornerRadius
        thumb.layer?.cornerCurve = .continuous
        thumb.layer?.masksToBounds = true
        thumb.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.06).cgColor
        content.addSubview(thumb)

        let badgeSize: CGFloat = 22
        let badge = NSImageView(frame: NSRect(x: thumbFrame.maxX - badgeSize - 6,
                                              y: thumbFrame.maxY - badgeSize - 6,
                                              width: badgeSize, height: badgeSize))
        badge.image = NSImage(systemSymbolName: "text.viewfinder",
                              accessibilityDescription: "Recognized text")?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .semibold))
        badge.contentTintColor = .white
        badge.wantsLayer = true
        badge.layer?.cornerRadius = badgeSize / 2
        badge.layer?.cornerCurve = .continuous
        badge.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        content.addSubview(badge)

        // Middle: scrollable, selectable text view.
        let textFrame = NSRect(x: pad,
                               y: bottomBar + pad,
                               width: panelW - pad * 2,
                               height: textH)
        let scroll = NSScrollView(frame: textFrame)
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.wantsLayer = true
        scroll.layer?.cornerRadius = Theme.thumbnailCornerRadius
        scroll.layer?.cornerCurve = .continuous
        scroll.layer?.masksToBounds = true
        scroll.drawsBackground = false

        let textView = NSTextView(frame: NSRect(origin: .zero, size: textFrame.size))
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.font = .systemFont(ofSize: 12)
        textView.string = text.isEmpty ? "(No text recognized)" : text
        if text.isEmpty {
            textView.textColor = .secondaryLabelColor
        }
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: textFrame.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        scroll.documentView = textView
        content.addSubview(scroll)

        // Bottom: Copy (primary) + Close icon buttons, centered.
        let btnSize = Theme.iconButtonSize
        let btnGap = Theme.iconButtonGap
        let totalBtnW = btnSize * 2 + btnGap
        let startX = (panelW - totalBtnW) / 2
        let btnY = (bottomBar - btnSize) / 2

        let copyBtn = Theme.primaryIconButton(
            symbol: "doc.on.doc",
            tooltip: "Copy text",
            target: self, action: #selector(copyText))
        copyBtn.frame = NSRect(x: startX, y: btnY, width: btnSize, height: btnSize)
        copyBtn.keyEquivalent = "\r"
        copyBtn.isEnabled = !text.isEmpty

        let closeBtn = Theme.iconButton(
            symbol: "xmark",
            tooltip: "Close",
            target: self, action: #selector(closeTapped))
        closeBtn.frame = NSRect(x: startX + btnSize + btnGap, y: btnY,
                                width: btnSize, height: btnSize)

        content.addSubview(copyBtn)
        content.addSubview(closeBtn)
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

    @objc private func copyText() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        flashCopyFeedback()
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
        OCRPanelController.openPanels.removeAll { $0 === self }
    }
}
