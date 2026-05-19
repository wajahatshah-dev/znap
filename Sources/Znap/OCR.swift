import Vision
import CoreGraphics

/// Vision-backed text recognition. Runs on a background queue and joins recognized
/// lines into a single string, preserving the visual top-to-bottom reading order.
enum OCR {
    static func recognize(in image: CGImage,
                          languages: [String] = ["en-US"]) async -> String {
        await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                if #available(macOS 13.0, *) {
                    request.automaticallyDetectsLanguage = true
                }
                request.recognitionLanguages = languages

                let handler = VNImageRequestHandler(cgImage: image, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    cont.resume(returning: "")
                    return
                }

                let observations = request.results ?? []

                // Sort observations top-to-bottom so the text reads naturally.
                // Vision uses normalized coords with (0,0) at bottom-left, so a higher
                // `boundingBox.maxY` means the line is higher on screen.
                let sorted = observations.sorted { lhs, rhs in
                    lhs.boundingBox.maxY > rhs.boundingBox.maxY
                }
                let lines = sorted.compactMap { $0.topCandidates(1).first?.string }
                cont.resume(returning: lines.joined(separator: "\n"))
            }
        }
    }
}
