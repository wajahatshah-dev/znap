import AppKit
import AVFoundation

/// Floating preview panel for a freshly recorded video. Mirrors the screenshot
/// preview: bottom-left glass panel with a static first-frame thumbnail, then
/// commits to Desktop on Save or deletes the temp file on Discard.
@MainActor
final class VideoPreviewPanelController {
    private static var openPanels: [VideoPreviewPanelController] = []

    private let tempURL: URL
    private var panel: NSPanel?
    private var copyButton: GlassIconButton?
    private var stackIndex: Int = 0
    private var didCommit = false

    static func show(tempURL: URL) {
        let controller = VideoPreviewPanelController(tempURL: tempURL)
        controller.stackIndex = openPanels.count
        openPanels.append(controller)
        controller.present()
    }

    private init(tempURL: URL) {
        self.tempURL = tempURL
    }

    private func present() {
        // Pull the first frame as a static thumbnail. `firstFrame` applies the
        // preferred track transform, so the thumbnail's own dimensions already
        // reflect the video's display aspect — no need to load tracks separately.
        let asset = AVURLAsset(url: tempURL)
        let thumbnail = Self.firstFrame(of: asset)
        let videoW = CGFloat(thumbnail?.width ?? 16)
        let videoH = CGFloat(thumbnail?.height ?? 9)

        let maxDim: CGFloat = 220
        let ratio = videoW / max(videoH, 1)

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

        // Static thumbnail of the first frame.
        let thumbFrame = NSRect(x: pad, y: bottomBar + pad, width: w, height: h)
        let imageView = NSImageView(frame: thumbFrame)
        if let thumbnail {
            imageView.image = NSImage(cgImage: thumbnail,
                                      size: NSSize(width: thumbnail.width,
                                                   height: thumbnail.height))
        }
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = Theme.thumbnailCornerRadius
        imageView.layer?.cornerCurve = .continuous
        imageView.layer?.masksToBounds = true
        imageView.layer?.backgroundColor = NSColor.black.cgColor
        content.addSubview(imageView)

        // Small video badge so it's recognizable as a recording.
        let badgeSize: CGFloat = 22
        let badge = NSImageView(frame: NSRect(x: thumbFrame.maxX - badgeSize - 6,
                                              y: thumbFrame.maxY - badgeSize - 6,
                                              width: badgeSize, height: badgeSize))
        badge.image = NSImage(systemSymbolName: "video.fill",
                              accessibilityDescription: "Video")?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .semibold))
        badge.contentTintColor = .white
        badge.wantsLayer = true
        badge.layer?.cornerRadius = badgeSize / 2
        badge.layer?.cornerCurve = .continuous
        badge.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        content.addSubview(badge)

        // Bottom: 4 icon-only buttons (Play, Copy, Save, Discard).
        let btnSize = Theme.iconButtonSize
        let btnGap = Theme.iconButtonGap
        let totalBtnW = btnSize * 4 + btnGap * 3
        let startX = (panelW - totalBtnW) / 2
        let btnY = (bottomBar - btnSize) / 2

        let playBtn = Theme.iconButton(
            symbol: "play.fill",
            tooltip: "Preview in QuickTime",
            target: self, action: #selector(playTapped))
        let copyBtn = Theme.iconButton(
            symbol: "doc.on.doc",
            tooltip: "Copy file",
            target: self, action: #selector(copyFile))
        let saveBtn = Theme.primaryIconButton(
            symbol: "square.and.arrow.down",
            tooltip: "Save",
            target: self, action: #selector(saveVideo))
        saveBtn.keyEquivalent = "\r"
        let closeBtn = Theme.iconButton(
            symbol: "xmark",
            tooltip: "Discard",
            target: self, action: #selector(closeTapped))

        let buttons: [NSButton] = [playBtn, copyBtn, saveBtn, closeBtn]
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

    /// Grab a single frame near the start of the clip for the thumbnail.
    private static func firstFrame(of asset: AVAsset) -> CGImage? {
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 60)
        return try? gen.copyCGImage(at: .zero, actualTime: nil)
    }

    @objc private func playTapped() {
        NSWorkspace.shared.open(tempURL)
    }

    @objc private func copyFile() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([tempURL as NSURL])
        flashCopyFeedback()
    }

    @objc private func saveVideo() {
        let dest = SaveLocation.newURL(prefix: "Znap Recording", ext: "mov")
        do {
            try FileManager.default.moveItem(at: tempURL, to: dest)
            didCommit = true
            NSWorkspace.shared.activateFileViewerSelecting([dest])
            dismiss()
        } catch {
            showError(error, context: "Could not save recording")
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
        // If the user didn't Save, the temp file is theirs to lose.
        if !didCommit {
            try? FileManager.default.removeItem(at: tempURL)
        }
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
        self.panel = nil
        VideoPreviewPanelController.openPanels.removeAll { $0 === self }
    }
}
