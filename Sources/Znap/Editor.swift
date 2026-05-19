import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - Annotation model

enum AnnotationTool: Int, CaseIterable {
    case arrow, rectangle, ellipse, line, pen, highlight, text, blur

    var symbol: String {
        switch self {
        case .arrow:     return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse:   return "circle"
        case .line:      return "line.diagonal"
        case .pen:       return "pencil.tip"
        case .highlight: return "highlighter"
        case .text:      return "textformat"
        case .blur:      return "drop.fill"
        }
    }

    var name: String {
        switch self {
        case .arrow:     return "Arrow"
        case .rectangle: return "Rectangle"
        case .ellipse:   return "Ellipse"
        case .line:      return "Line"
        case .pen:       return "Pen"
        case .highlight: return "Highlight"
        case .text:      return "Text"
        case .blur:      return "Blur"
        }
    }
}

/// One drawn annotation. Coordinates are stored in **image pixel space**
/// (top-left origin) so they survive view resizing and can be re-rendered at full
/// resolution on flatten.
struct Annotation {
    let tool: AnnotationTool
    var points: [CGPoint]
    var color: NSColor
    var lineWidth: CGFloat
    var text: String = ""
}

// MARK: - Editor window

@MainActor
final class EditorWindowController: NSObject, NSWindowDelegate {
    private let original: CGImage
    private let onDone: (CGImage) -> Void
    private let onCancel: () -> Void

    private var window: NSWindow!
    private var canvas: EditorCanvasView!

    private var selectedTool: AnnotationTool = .arrow {
        didSet { canvas.currentTool = selectedTool; refreshToolHighlights() }
    }
    private var selectedColor: NSColor = .systemRed {
        didSet { canvas.currentColor = selectedColor; refreshColorHighlights() }
    }
    private var selectedWidth: CGFloat = 4 {
        didSet {
            canvas.currentLineWidth = selectedWidth
            widthSlider?.doubleValue = Double(selectedWidth)
            widthLabel?.stringValue = "\(Int(selectedWidth)) pt"
        }
    }

    private var toolButtons: [AnnotationTool: GlassIconButton] = [:]
    private var colorButtons: [(NSColor, NSView)] = []
    private var widthSlider: NSSlider?
    private var widthLabel: NSTextField?

    private let palette: [NSColor] = [
        .systemRed, .systemOrange, .systemYellow,
        .systemGreen, .systemBlue, .black, .white,
    ]
    private let widthRange: ClosedRange<CGFloat> = 1...16

    init(image: CGImage,
         onDone: @escaping (CGImage) -> Void,
         onCancel: @escaping () -> Void) {
        self.original = image
        self.onDone = onDone
        self.onCancel = onCancel
        super.init()
        setupWindow()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - Layout

    private func setupWindow() {
        let imgW = CGFloat(original.width)
        let imgH = CGFloat(original.height)
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let toolbarH: CGFloat = 56

        // Fit canvas into ~80% of the visible screen, never upscale past 1.0.
        let maxW = screen.width * 0.85
        let maxH = (screen.height - toolbarH - 40) * 0.85
        let scale = min(maxW / imgW, maxH / imgH, 1.0)
        let canvasW = max(imgW * scale, 480)
        let canvasH = max(imgH * scale, 320)

        // Toolbar needs ~920pt to fit everything; the window can grow but not
        // shrink below that or the right-side controls collide with Done.
        let minToolbarW: CGFloat = 920
        let totalW = max(canvasW, minToolbarW)
        let totalH = canvasH + toolbarH

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: totalW, height: totalH),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Edit Screenshot"
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.contentMinSize = NSSize(width: minToolbarW, height: 360)
        win.center()
        self.window = win

        let content = NSView(frame: NSRect(origin: .zero, size: NSSize(width: totalW, height: totalH)))
        content.autoresizesSubviews = true

        // Toolbar pinned to the top.
        let toolbar = NSView(frame: NSRect(x: 0, y: totalH - toolbarH, width: totalW, height: toolbarH))
        toolbar.autoresizingMask = [.width, .minYMargin]
        toolbar.wantsLayer = true
        toolbar.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        let divider = NSBox(frame: NSRect(x: 0, y: 0, width: totalW, height: 1))
        divider.boxType = .separator
        divider.autoresizingMask = [.width]
        toolbar.addSubview(divider)
        content.addSubview(toolbar)

        // Canvas container (dark backdrop, canvas centered inside).
        let canvasBg = NSView(frame: NSRect(x: 0, y: 0, width: totalW, height: totalH - toolbarH))
        canvasBg.autoresizingMask = [.width, .height]
        canvasBg.wantsLayer = true
        canvasBg.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.18).cgColor
        content.addSubview(canvasBg)

        let initialCanvasFrame = NSRect(
            x: (totalW - imgW * scale) / 2,
            y: (canvasBg.frame.height - imgH * scale) / 2,
            width: imgW * scale,
            height: imgH * scale
        )
        canvas = EditorCanvasView(frame: initialCanvasFrame)
        canvas.baseImage = original
        canvas.currentTool = selectedTool
        canvas.currentColor = selectedColor
        canvas.currentLineWidth = selectedWidth
        canvas.onTextNeeded = { [weak self] callback in
            self?.promptForText(completion: callback)
        }
        canvas.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        canvasBg.addSubview(canvas)

        layoutToolbar(in: toolbar, width: totalW)
        win.contentView = content
        refreshAllHighlights()
    }

    private func layoutToolbar(in toolbar: NSView, width totalW: CGFloat) {
        let padding: CGFloat = 12
        let btnH: CGFloat = 30
        let btnW: CGFloat = 34
        let y: CGFloat = (toolbar.frame.height - btnH) / 2

        var x: CGFloat = padding

        // Cancel button (left)
        let cancelBtn = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancelBtn.frame = NSRect(x: x, y: y, width: 72, height: btnH)
        cancelBtn.bezelStyle = .rounded
        toolbar.addSubview(cancelBtn)
        x = cancelBtn.frame.maxX + 16

        // Tool buttons
        for tool in AnnotationTool.allCases {
            let b = GlassIconButton(frame: NSRect(x: x, y: y, width: btnW, height: btnH))
            let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            b.image = NSImage(systemSymbolName: tool.symbol, accessibilityDescription: tool.name)?
                .withSymbolConfiguration(cfg)
            b.imagePosition = .imageOnly
            b.imageScaling = .scaleNone
            b.target = self
            b.action = #selector(toolTapped(_:))
            b.tag = tool.rawValue
            b.toolTip = tool.name
            toolbar.addSubview(b)
            toolButtons[tool] = b
            x += btnW + 4
        }

        x += 12

        // Color swatches
        let swatchSize: CGFloat = 22
        let swatchY = (toolbar.frame.height - swatchSize) / 2
        for (idx, c) in palette.enumerated() {
            let dot = ColorSwatchView(frame: NSRect(x: x, y: swatchY, width: swatchSize, height: swatchSize))
            dot.color = c
            dot.onClick = { [weak self] in self?.selectedColor = c }
            toolbar.addSubview(dot)
            colorButtons.append((c, dot))
            x += swatchSize + 4
            _ = idx
        }

        x += 14

        // Width: continuous slider with a small "Npt" indicator so the user can
        // dial in any thickness, not just the three presets we used to ship.
        let sliderW: CGFloat = 96
        let slider = NSSlider(value: Double(selectedWidth),
                              minValue: Double(widthRange.lowerBound),
                              maxValue: Double(widthRange.upperBound),
                              target: self,
                              action: #selector(widthSliderChanged(_:)))
        slider.frame = NSRect(x: x, y: y, width: sliderW, height: btnH)
        slider.controlSize = .small
        slider.toolTip = "Stroke width"
        toolbar.addSubview(slider)
        self.widthSlider = slider
        x += sliderW + 6

        let label = NSTextField(labelWithString: "\(Int(selectedWidth)) pt")
        label.frame = NSRect(x: x, y: y + 7, width: 36, height: 16)
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .left
        toolbar.addSubview(label)
        self.widthLabel = label
        x += 40

        x += 8

        // Undo / Redo
        let undoBtn = NSButton(frame: NSRect(x: x, y: y, width: btnW, height: btnH))
        undoBtn.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: "Undo")
        undoBtn.bezelStyle = .texturedRounded
        undoBtn.target = self
        undoBtn.action = #selector(undoTapped)
        undoBtn.toolTip = "Undo (⌘Z)"
        undoBtn.keyEquivalent = "z"
        undoBtn.keyEquivalentModifierMask = .command
        toolbar.addSubview(undoBtn)
        x += btnW + 2

        let redoBtn = NSButton(frame: NSRect(x: x, y: y, width: btnW, height: btnH))
        redoBtn.image = NSImage(systemSymbolName: "arrow.uturn.forward", accessibilityDescription: "Redo")
        redoBtn.bezelStyle = .texturedRounded
        redoBtn.target = self
        redoBtn.action = #selector(redoTapped)
        redoBtn.toolTip = "Redo (⇧⌘Z)"
        redoBtn.keyEquivalent = "Z"
        redoBtn.keyEquivalentModifierMask = [.command, .shift]
        toolbar.addSubview(redoBtn)
        x += btnW + 2

        // Clear all
        let clearBtn = NSButton(frame: NSRect(x: x, y: y, width: btnW, height: btnH))
        clearBtn.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Clear all")
        clearBtn.bezelStyle = .texturedRounded
        clearBtn.target = self
        clearBtn.action = #selector(clearTapped)
        clearBtn.toolTip = "Clear all annotations"
        toolbar.addSubview(clearBtn)

        // Done (right side, pinned)
        let doneW: CGFloat = 88
        let doneBtn = NSButton(title: "Done", target: self, action: #selector(doneTapped))
        doneBtn.frame = NSRect(x: totalW - padding - doneW, y: y, width: doneW, height: btnH)
        doneBtn.bezelStyle = .rounded
        doneBtn.keyEquivalent = "\r"
        doneBtn.autoresizingMask = [.minXMargin]
        toolbar.addSubview(doneBtn)
    }

    // MARK: - Highlights

    private func refreshAllHighlights() {
        refreshToolHighlights()
        refreshColorHighlights()
    }
    private func refreshToolHighlights() {
        for (tool, btn) in toolButtons {
            btn.isSelected = (tool == selectedTool)
        }
    }
    private func refreshColorHighlights() {
        for (color, view) in colorButtons {
            (view as? ColorSwatchView)?.isSelected = (color == selectedColor)
        }
    }

    // MARK: - Actions

    @objc private func toolTapped(_ sender: NSButton) {
        if let t = AnnotationTool(rawValue: sender.tag) { selectedTool = t }
    }
    @objc private func widthSliderChanged(_ sender: NSSlider) {
        let rounded = CGFloat(sender.doubleValue.rounded())
        // Avoid firing didSet (and re-setting the slider) when value is unchanged.
        if rounded != selectedWidth { selectedWidth = rounded }
    }
    @objc private func undoTapped() { canvas.undo() }
    @objc private func redoTapped() { canvas.redo() }
    @objc private func clearTapped() { canvas.clearAll() }

    @objc private func cancelTapped() {
        window.orderOut(nil)
        onCancel()
    }

    @objc private func doneTapped() {
        let result = canvas.flatten()
        window.orderOut(nil)
        onDone(result)
    }

    func windowWillClose(_ notification: Notification) {
        // Treat the red close button as Cancel.
        onCancel()
    }

    private func promptForText(completion: @escaping (String) -> Void) {
        let alert = NSAlert()
        alert.messageText = "Add text"
        alert.informativeText = "Type the text to place on the screenshot."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 22))
        field.placeholderString = "Your text"
        alert.accessoryView = field
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        let response = alert.runModal()
        completion(response == .alertFirstButtonReturn ? field.stringValue : "")
    }
}

// MARK: - Color swatch view

final class ColorSwatchView: NSView {
    var color: NSColor = .systemRed { didSet { needsDisplay = true } }
    var isSelected: Bool = false { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 2, dy: 2)
        let path = NSBezierPath(ovalIn: r)
        color.setFill()
        path.fill()
        if isSelected {
            NSColor.controlAccentColor.setStroke()
            let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5))
            ring.lineWidth = 2.5
            ring.stroke()
        } else {
            NSColor.separatorColor.setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}

// MARK: - Canvas

final class EditorCanvasView: NSView {
    var baseImage: CGImage? { didSet { needsDisplay = true } }
    var currentTool: AnnotationTool = .arrow
    var currentColor: NSColor = .systemRed
    var currentLineWidth: CGFloat = 4

    /// Callback fired when the user clicks with the text tool. Pass the typed
    /// string back via the completion handler (empty string = cancelled).
    var onTextNeeded: ((@escaping (String) -> Void) -> Void)?

    private var annotations: [Annotation] = []
    private var redoStack: [Annotation] = []
    private var inProgress: Annotation?

    /// Top-left origin matches image pixel coordinates — keeps the math trivial.
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let img = baseImage else { return }

        // Pin global rendering quality up-front so the base image and every
        // annotation rasterize with antialiasing and high interpolation.
        NSGraphicsContext.current?.shouldAntialias = true
        NSGraphicsContext.current?.imageInterpolation = .high

        NSImage(cgImage: img, size: bounds.size).draw(in: bounds)

        let scale = CGSize(
            width: bounds.width / CGFloat(img.width),
            height: bounds.height / CGFloat(img.height)
        )
        for ann in annotations { renderAnnotation(ann, scale: scale, source: img) }
        if let ip = inProgress { renderAnnotation(ip, scale: scale, source: img) }
    }

    private func renderAnnotation(_ ann: Annotation, scale: CGSize, source: CGImage) {
        let s: (CGPoint) -> CGPoint = { p in
            CGPoint(x: p.x * scale.width, y: p.y * scale.height)
        }
        let lw = ann.lineWidth * max(scale.width, 0.5)

        // Force the highest-quality rasterization for every shape — antialiasing
        // and high-quality interpolation aren't guaranteed across all contexts.
        NSGraphicsContext.current?.shouldAntialias = true
        NSGraphicsContext.current?.imageInterpolation = .high
        NSGraphicsContext.current?.cgContext.setAllowsAntialiasing(true)
        NSGraphicsContext.current?.cgContext.setShouldAntialias(true)

        ann.color.setStroke()
        ann.color.setFill()

        switch ann.tool {
        case .arrow:
            guard ann.points.count >= 2 else { return }
            drawArrow(from: s(ann.points.first!), to: s(ann.points.last!),
                      lineWidth: lw, color: ann.color)
        case .rectangle:
            guard ann.points.count >= 2 else { return }
            let r = boxRect(from: s(ann.points.first!), to: s(ann.points.last!))
            // Inset by half the line width so the stroke stays fully inside the
            // bounding box, and round the corners slightly for a modern look.
            let inset = lw / 2
            let insetRect = r.insetBy(dx: inset, dy: inset)
            let radius = max(2, min(insetRect.width, insetRect.height) * 0.04)
            let path = NSBezierPath(roundedRect: insetRect, xRadius: radius, yRadius: radius)
            path.lineWidth = lw
            path.lineJoinStyle = .round
            path.stroke()
        case .ellipse:
            guard ann.points.count >= 2 else { return }
            let r = boxRect(from: s(ann.points.first!), to: s(ann.points.last!))
            let inset = lw / 2
            let path = NSBezierPath(ovalIn: r.insetBy(dx: inset, dy: inset))
            path.lineWidth = lw
            path.stroke()
        case .line:
            guard ann.points.count >= 2 else { return }
            let p = NSBezierPath()
            p.move(to: s(ann.points.first!))
            p.line(to: s(ann.points.last!))
            p.lineWidth = lw
            p.lineCapStyle = .round
            p.stroke()
        case .pen:
            guard ann.points.count >= 2 else { return }
            let p = NSBezierPath()
            p.move(to: s(ann.points[0]))
            for pt in ann.points.dropFirst() { p.line(to: s(pt)) }
            p.lineWidth = lw
            p.lineCapStyle = .round
            p.lineJoinStyle = .round
            p.stroke()
        case .highlight:
            guard ann.points.count >= 2 else { return }
            ann.color.withAlphaComponent(0.35).setStroke()
            let p = NSBezierPath()
            p.move(to: s(ann.points[0]))
            for pt in ann.points.dropFirst() { p.line(to: s(pt)) }
            p.lineWidth = lw * 3
            p.lineCapStyle = .round
            p.stroke()
        case .text:
            guard !ann.text.isEmpty, let first = ann.points.first else { return }
            let fontSize = max(14, ann.lineWidth * 4) * max(scale.width, 0.5)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
                .foregroundColor: ann.color,
            ]
            (ann.text as NSString).draw(at: s(first), withAttributes: attrs)
        case .blur:
            guard ann.points.count >= 2 else { return }
            let imageRect = boxRect(from: ann.points.first!, to: ann.points.last!)
            let displayRect = boxRect(from: s(ann.points.first!), to: s(ann.points.last!))
            if let blurred = blurredRegion(of: source, rect: imageRect, radius: 18) {
                NSImage(cgImage: blurred, size: displayRect.size).draw(in: displayRect)
            }
        }
    }

    private func boxRect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
               width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    /// Draws an arrow as a single filled polygon — tapered head with barbs that
    /// flare out from a rectangular shaft. Avoids the visible seam you get when
    /// stroking a shaft and then drawing a separate filled triangle.
    private func drawArrow(from a: CGPoint, to b: CGPoint, lineWidth: CGFloat, color: NSColor) {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let len = sqrt(dx * dx + dy * dy)
        guard len > 1 else { return }

        let angle = atan2(dy, dx)
        let cosA = cos(angle)
        let sinA = sin(angle)
        // Perpendicular axis (90° CCW from direction of travel).
        let perpCos = -sinA
        let perpSin = cosA

        // Proportions scale linearly with line width so the arrow stays balanced
        // across the full 1–16 pt range:
        //   shaft total = lineWidth (matches the slider value exactly)
        //   head width  ≈ 5× lineWidth   (head is wider than the shaft)
        //   head length ≈ 5.5× lineWidth (slightly longer than wide → directional)
        // The min clamps keep very thin arrows from disappearing.
        let shaftHalf = max(0.6, lineWidth / 2)
        let headHalf = max(5, lineWidth * 2.5)
        let headLen = min(len * 0.5, max(10, lineWidth * 5.5))
        let headStart = max(0, len - headLen)

        func point(along: CGFloat, perp: CGFloat) -> CGPoint {
            CGPoint(
                x: a.x + cosA * along + perpCos * perp,
                y: a.y + sinA * along + perpSin * perp
            )
        }

        let tip = point(along: len, perp: 0)

        let path = NSBezierPath()
        path.move(to: tip)
        path.line(to: point(along: headStart, perp: -headHalf))   // right barb
        path.line(to: point(along: headStart, perp: -shaftHalf))  // right notch
        path.line(to: point(along: 0,         perp: -shaftHalf))  // right tail
        path.line(to: point(along: 0,         perp:  shaftHalf))  // left tail
        path.line(to: point(along: headStart, perp:  shaftHalf))  // left notch
        path.line(to: point(along: headStart, perp:  headHalf))   // left barb
        path.close()
        path.lineJoinStyle = .round

        color.setFill()
        path.fill()
    }

    private func blurredRegion(of source: CGImage, rect: CGRect, radius: CGFloat) -> CGImage? {
        // CIImage uses bottom-left coords — convert from our top-left rect.
        let h = CGFloat(source.height)
        let ciRect = CGRect(x: rect.minX, y: h - rect.maxY,
                            width: rect.width, height: rect.height)
        let ci = CIImage(cgImage: source)
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = ci.clampedToExtent()
        filter.radius = Float(radius)
        guard let out = filter.outputImage?.cropped(to: ciRect) else { return nil }
        let ctx = CIContext()
        return ctx.createCGImage(out, from: ciRect)
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        guard let img = baseImage else { return }
        let p = imagePoint(from: convert(event.locationInWindow, from: nil), image: img)

        if currentTool == .text {
            onTextNeeded? { [weak self] str in
                guard let self, !str.isEmpty else { return }
                let ann = Annotation(tool: .text, points: [p],
                                     color: self.currentColor,
                                     lineWidth: self.currentLineWidth,
                                     text: str)
                self.commit(ann)
            }
            return
        }

        inProgress = Annotation(tool: currentTool, points: [p, p],
                                color: currentColor, lineWidth: currentLineWidth)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard var ip = inProgress, let img = baseImage else { return }
        let p = imagePoint(from: convert(event.locationInWindow, from: nil), image: img)
        if ip.tool == .pen || ip.tool == .highlight {
            ip.points.append(p)
        } else {
            ip.points = [ip.points.first ?? p, p]
        }
        inProgress = ip
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let ip = inProgress else { return }
        inProgress = nil
        let first = ip.points.first ?? .zero
        let last = ip.points.last ?? .zero
        if ip.tool != .pen && ip.tool != .highlight {
            if abs(last.x - first.x) < 4 && abs(last.y - first.y) < 4 {
                needsDisplay = true
                return
            }
        }
        commit(ip)
    }

    private func commit(_ ann: Annotation) {
        annotations.append(ann)
        redoStack.removeAll()
        needsDisplay = true
    }

    private func imagePoint(from viewPoint: NSPoint, image: CGImage) -> CGPoint {
        CGPoint(
            x: viewPoint.x * CGFloat(image.width) / bounds.width,
            y: viewPoint.y * CGFloat(image.height) / bounds.height
        )
    }

    // MARK: Public

    func undo() {
        guard let last = annotations.popLast() else { return }
        redoStack.append(last)
        needsDisplay = true
    }

    func redo() {
        guard let last = redoStack.popLast() else { return }
        annotations.append(last)
        needsDisplay = true
    }

    func clearAll() {
        if annotations.isEmpty { return }
        redoStack.append(contentsOf: annotations.reversed())
        annotations.removeAll()
        needsDisplay = true
    }

    /// Render the image with all annotations to a new CGImage at full resolution.
    func flatten() -> CGImage {
        guard let img = baseImage else { return baseImage ?? CGImage.empty }
        let w = img.width, h = img.height
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: 0, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return img }

        // Use a flipped NSGraphicsContext so AppKit drawing uses top-left coords —
        // identical to how the on-screen canvas renders.
        let ns = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns

        NSImage(cgImage: img, size: NSSize(width: w, height: h))
            .draw(in: CGRect(x: 0, y: 0, width: w, height: h))
        for ann in annotations {
            renderAnnotation(ann, scale: CGSize(width: 1, height: 1), source: img)
        }

        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage() ?? img
    }
}

// Tiny fallback so the `flatten()` guard doesn't crash. In practice baseImage is
// always set by the controller before the user can hit Done.
private extension CGImage {
    static var empty: CGImage {
        let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }
}
