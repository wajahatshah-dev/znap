import AppKit
import ScreenCaptureKit
import UniformTypeIdentifiers

@MainActor
final class CaptureManager {
    private let areaSelector = AreaSelectionController()
    private let windowPicker = WindowPickerController()

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
