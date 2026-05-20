import AppKit
import ScreenCaptureKit
import Vision

/// Captures a scrollable region as one tall image. The user drag-selects a
/// viewport, then scrolls the content manually while we capture frames at ~3 fps
/// and stitch them together using Vision's image registration to detect how far
/// they've scrolled between frames.
@MainActor
final class ScrollingCaptureController {
    private let areaSelector = AreaSelectionController()

    private var captureTask: Task<Void, Never>?
    private var indicatorPanel: NSPanel?
    private var frameCountLabel: NSTextField?

    /// Latest stitched image. Grows as the user scrolls.
    private var accumulated: CGImage?
    /// The previous raw frame — used as the reference image for translation
    /// estimation against each new frame.
    private var previousFrame: CGImage?

    private var captureFilter: SCContentFilter?
    private var captureConfig: SCStreamConfiguration?
    private var frameCount: Int = 0
    private var isCapturing: Bool = false

    func start() async {
        guard !isCapturing else { return }
        guard let rect = await areaSelector.selectArea() else { return }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true)
            guard let (display, screen) = displayFor(rect: rect, in: content.displays) else { return }

            let source = toDisplayLocal(globalRect: rect, screen: screen)
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.sourceRect = source
            let scale = screen.backingScaleFactor
            config.width = max(2, Int((source.width * scale).rounded()))
            config.height = max(2, Int((source.height * scale).rounded()))
            config.showsCursor = false

            captureFilter = filter
            captureConfig = config
            isCapturing = true
            frameCount = 0
            accumulated = nil
            previousFrame = nil

            showIndicator()
            beginCaptureLoop()
        } catch {
            showError(error, context: "Scrolling capture failed to start")
        }
    }

    func stop() async {
        guard isCapturing else { return }
        isCapturing = false
        captureTask?.cancel()
        _ = await captureTask?.value
        captureTask = nil

        dismissIndicator()

        if let final = accumulated {
            playShutter()
            PreviewPanelController.show(image: final)
        }
        accumulated = nil
        previousFrame = nil
        captureFilter = nil
        captureConfig = nil
    }

    // MARK: - Capture loop

    private func beginCaptureLoop() {
        captureTask = Task { [weak self] in
            while let self, !Task.isCancelled, self.isCapturing {
                await self.captureOnce()
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }

    private func captureOnce() async {
        guard let filter = captureFilter, let config = captureConfig else { return }
        do {
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config)
            frameCount += 1
            frameCountLabel?.stringValue = "\(frameCount) frames · \(accumulated?.height ?? image.height) px tall"
            stitch(newFrame: image)
            previousFrame = image
        } catch {
            // Skip failed frames — keep the user's session alive.
        }
    }

    // MARK: - Stitching

    private func stitch(newFrame: CGImage) {
        guard let acc = accumulated, let prev = previousFrame else {
            accumulated = newFrame
            return
        }

        guard let ty = verticalOffset(reference: prev, floating: newFrame) else { return }

        // Vision returns the translation needed to align the *floating* (new)
        // frame onto the *reference* (previous) frame, in bottom-left pixel
        // coords. When the user scrolls DOWN by N pixels, the new frame shows
        // content from N pixels lower on the page; aligning it back onto the
        // previous frame requires shifting it DOWN — so `ty` comes back as
        // `-N` (negative). The actual scroll distance in screen pixels is `-ty`.
        let scrollPx = -ty
        let intDy = Int(scrollPx.rounded())

        // Skip frames that didn't scroll (intDy <= 1) or scrolled past the full
        // viewport (intDy >= height — Vision can't find overlap anyway).
        guard intDy > 1 && intDy < newFrame.height else { return }

        // The bottom `intDy` rows of the new frame are the freshly-revealed
        // content. CGImage uses top-left origin, so "bottom rows" are at high Y.
        guard let newContent = newFrame.cropping(to: CGRect(
            x: 0, y: newFrame.height - intDy,
            width: newFrame.width, height: intDy
        )) else { return }

        accumulated = appendBelow(newContent: newContent, base: acc)
    }

    private func verticalOffset(reference: CGImage, floating: CGImage) -> CGFloat? {
        // Reference and floating must be the same size for translation
        // registration — they always are in our pipeline (we crop with the same
        // sourceRect every frame).
        let request = VNTranslationalImageRegistrationRequest(targetedCGImage: floating)
        let handler = VNImageRequestHandler(cgImage: reference, options: [:])
        do {
            try handler.perform([request])
            guard let obs = request.results?.first as? VNImageTranslationAlignmentObservation else {
                return nil
            }
            return CGFloat(obs.alignmentTransform.ty)
        } catch {
            return nil
        }
    }

    private func appendBelow(newContent: CGImage, base: CGImage) -> CGImage {
        let w = max(base.width, newContent.width)
        let h = base.height + newContent.height
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: 0, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return base }

        // CGContext is bottom-left origin. The "top" of the visual image (where
        // `base` should go) corresponds to high Y; the "bottom" (where new
        // content goes) is low Y.
        ctx.draw(base, in: CGRect(x: 0, y: newContent.height,
                                  width: base.width, height: base.height))
        ctx.draw(newContent, in: CGRect(x: 0, y: 0,
                                        width: newContent.width, height: newContent.height))
        return ctx.makeImage() ?? base
    }

    // MARK: - Indicator panel

    private func showIndicator() {
        let panelW: CGFloat = 260
        let panelH: CGFloat = 96

        guard let screen = NSScreen.main else { return }
        // Top-right corner — far from where the user is most likely to be
        // selecting a scrolling region.
        let originX = screen.visibleFrame.maxX - panelW - 24
        let originY = screen.visibleFrame.maxY - panelH - 24

        let panel = NSPanel(
            contentRect: NSRect(x: originX, y: originY, width: panelW, height: panelH),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false

        let (container, content) = Theme.makeGlassContainer(
            size: NSSize(width: panelW, height: panelH))

        let title = NSTextField(labelWithString: "Scrolling Capture")
        title.frame = NSRect(x: 14, y: panelH - 30, width: panelW - 28, height: 18)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .labelColor
        content.addSubview(title)

        let subtitle = NSTextField(labelWithString: "Scroll the content, then tap Stop.")
        subtitle.frame = NSRect(x: 14, y: panelH - 48, width: panelW - 28, height: 14)
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        content.addSubview(subtitle)

        let count = NSTextField(labelWithString: "0 frames")
        count.frame = NSRect(x: 14, y: 12, width: panelW - 60, height: 14)
        count.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        count.textColor = .tertiaryLabelColor
        content.addSubview(count)
        self.frameCountLabel = count

        let stopBtn = Theme.primaryIconButton(
            symbol: "stop.fill",
            tooltip: "Stop and stitch",
            target: self, action: #selector(stopTapped)
        )
        stopBtn.frame = NSRect(x: panelW - 14 - 28, y: 8, width: 28, height: 28)
        content.addSubview(stopBtn)

        panel.contentView = container
        panel.alphaValue = 0
        panel.orderFront(nil)
        self.indicatorPanel = panel

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 1
        }
    }

    private func dismissIndicator() {
        guard let panel = indicatorPanel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
        indicatorPanel = nil
        frameCountLabel = nil
    }

    @objc private func stopTapped() {
        Task { await stop() }
    }
}
