import AppKit
import AVFoundation
import ScreenCaptureKit

final class RecordingManager: NSObject, @unchecked Sendable {
    private let lock = NSLock()
    private var stream: SCStream?
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var outputURL: URL?
    private var sessionStarted = false
    private let sampleQueue = DispatchQueue(label: "znap.sample")

    /// Called on the main thread when recording starts/stops.
    var onStateChange: ((Bool) -> Void)?

    @MainActor
    private let areaSelector = AreaSelectionController()
    @MainActor
    private let windowPicker = WindowPickerController()

    var isRecording: Bool {
        lock.lock(); defer { lock.unlock() }
        return stream != nil
    }

    @MainActor
    func recordArea() async {
        if isRecording { return }
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
            let (w, h) = CGSize(width: source.width * scale, height: source.height * scale).evenInts
            config.width = max(2, w)
            config.height = max(2, h)
            config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
            config.queueDepth = 6
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.showsCursor = true

            try await start(filter: filter, config: config)
        } catch {
            await MainActor.run { showError(error, context: "Could not start area recording") }
        }
    }

    @MainActor
    func recordWindow() async {
        if isRecording { return }
        guard let window = await windowPicker.pickWindow() else { return }
        do {
            if let app = window.owningApplication,
               let running = NSRunningApplication(processIdentifier: pid_t(app.processID)) {
                running.activate(options: [])
                try? await Task.sleep(nanoseconds: 200_000_000)
            }

            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
            let (w, h) = CGSize(width: window.frame.width * scale,
                                height: window.frame.height * scale).evenInts
            config.width = max(2, w)
            config.height = max(2, h)
            config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
            config.queueDepth = 6
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.showsCursor = true

            try await start(filter: filter, config: config)
        } catch {
            await MainActor.run { showError(error, context: "Could not start window recording") }
        }
    }

    private func start(filter: SCContentFilter, config: SCStreamConfiguration) async throws {
        let url = SaveLocation.newURL(prefix: "Znap Recording", ext: "mov")
        try? FileManager.default.removeItem(at: url)

        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: config.width,
            AVVideoHeightKey: config.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: Int(Double(config.width * config.height) * 6.0),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        if writer.canAdd(input) { writer.add(input) }

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)

        lock.lock()
        self.stream = stream
        self.assetWriter = writer
        self.videoInput = input
        self.outputURL = url
        self.sessionStarted = false
        lock.unlock()

        try await stream.startCapture()

        DispatchQueue.main.async { [weak self] in self?.onStateChange?(true) }
    }

    func stop() async {
        lock.lock()
        let s = stream
        let writer = assetWriter
        let input = videoInput
        let url = outputURL
        stream = nil
        lock.unlock()

        guard let s else { return }

        do { try await s.stopCapture() } catch { /* already stopped */ }

        input?.markAsFinished()
        if let writer, writer.status == .writing {
            await writer.finishWriting()
        } else {
            writer?.cancelWriting()
        }

        lock.lock()
        assetWriter = nil
        videoInput = nil
        outputURL = nil
        sessionStarted = false
        lock.unlock()

        await MainActor.run { [weak self] in
            self?.onStateChange?(false)
            if let url, FileManager.default.fileExists(atPath: url.path) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
    }
}

extension RecordingManager: SCStreamOutput {
    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid else { return }

        guard let array = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let info = array.first,
              let raw = info[.status] as? Int,
              let status = SCFrameStatus(rawValue: raw),
              status == .complete else { return }

        lock.lock()
        let writer = assetWriter
        let input = videoInput
        let started = sessionStarted
        lock.unlock()

        guard let writer, let input else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if !started {
            guard writer.status == .unknown else { return }
            writer.startWriting()
            writer.startSession(atSourceTime: pts)
            lock.lock(); sessionStarted = true; lock.unlock()
        }

        if writer.status == .writing && input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        }
    }
}
