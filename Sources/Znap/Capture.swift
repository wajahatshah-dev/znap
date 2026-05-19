import AppKit
import ScreenCaptureKit
import UniformTypeIdentifiers

@MainActor
final class CaptureManager {
    private let areaSelector = AreaSelectionController()
    private let windowPicker = WindowPickerController()
    private let scrollingCapture = ScrollingCaptureController()

    /// Start a scrolling capture session. The user selects an area, scrolls the
    /// content manually, and clicks Stop on the indicator panel — the result is
    /// stitched into a single tall image and shown in the preview panel.
    func captureScrolling() async {
        await scrollingCapture.start()
    }

    func captureFullScreen() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else { return }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
            config.width = Int(CGFloat(display.width) * scale)
            config.height = Int(CGFloat(display.height) * scale)
            config.showsCursor = true

            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config)
            present(image)
        } catch {
            showError(error, context: "Full screen capture failed")
        }
    }

    func captureArea() async {
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

            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config)
            present(image)
        } catch {
            showError(error, context: "Area capture failed")
        }
    }

    /// Capture an area and run Vision OCR on the result. Shows a panel with the
    /// recognized text and auto-copies it to the clipboard.
    func captureText() async {
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

            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config)

            playShutter()
            let text = await OCR.recognize(in: image)

            // Auto-copy when text was found, so the user can paste immediately.
            if !text.isEmpty {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(text, forType: .string)
            }
            OCRPanelController.show(text: text, thumbnail: image)
        } catch {
            showError(error, context: "Text capture failed")
        }
    }

    func captureWindow() async {
        guard let window = await windowPicker.pickWindow() else { return }
        do {
            // Bring the target window forward so it isn't occluded.
            if let app = window.owningApplication,
               let running = NSRunningApplication(processIdentifier: pid_t(app.processID)) {
                running.activate(options: [])
                try? await Task.sleep(nanoseconds: 200_000_000)
            }

            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
            config.width = max(2, Int((window.frame.width * scale).rounded()))
            config.height = max(2, Int((window.frame.height * scale).rounded()))
            config.showsCursor = false
            config.ignoreShadowsSingleWindow = false

            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config)
            present(image)
        } catch {
            showError(error, context: "Window capture failed")
        }
    }

    private func present(_ image: CGImage) {
        playShutter()
        PreviewPanelController.show(image: image)
    }
}
