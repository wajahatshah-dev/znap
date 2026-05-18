import AppKit

/// Borderless overlay window that refuses AppKit's automatic frame constraint.
///
/// macOS calls `constrainFrameRect(_:to:)` on every window to keep it within the
/// "usable" bounds of a screen (below menu bar, above Dock, etc.). For a full-screen
/// selection overlay we want to cover the *entire* screen — including menu bar and
/// Dock — on every display. Without this override, the overlay on secondary
/// displays gets silently clipped to a fraction of the actual screen.
final class OverlayWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class AreaSelectionController {
    private var windows: [NSWindow] = []
    private var continuation: CheckedContinuation<CGRect?, Never>?

    func selectArea() async -> CGRect? {
        if continuation != nil { return nil }
        return await withCheckedContinuation { cont in
            self.continuation = cont
            present()
        }
    }

    private func present() {
        windows.removeAll()
        NSApp.activate(ignoringOtherApps: true)

        for screen in NSScreen.screens {
            let w = OverlayWindow(contentRect: screen.frame,
                                  styleMask: .borderless,
                                  backing: .buffered,
                                  defer: false,
                                  screen: screen)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.level = .screenSaver
            w.ignoresMouseEvents = false
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            w.hasShadow = false
            w.acceptsMouseMovedEvents = true

            let view = AreaSelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.autoresizingMask = [.width, .height]
            view.screenOrigin = screen.frame.origin
            view.onComplete = { [weak self] rect in self?.finish(rect) }
            view.onCancel = { [weak self] in self?.finish(nil) }
            w.contentView = view

            // Force the frame after creation in case anything (display arrangement
            // change, Stage Manager, etc.) tries to renegotiate the size.
            w.setFrame(screen.frame, display: true)

            w.makeKeyAndOrderFront(nil)
            w.makeFirstResponder(view)
            windows.append(w)
        }
    }

    private func finish(_ rect: CGRect?) {
        for w in windows { w.orderOut(nil) }
        windows.removeAll()
        let cont = continuation
        continuation = nil
        cont?.resume(returning: rect)
    }
}

final class AreaSelectionView: NSView {
    var screenOrigin: CGPoint = .zero
    var onComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var startPoint: NSPoint?
    private var currentRect: NSRect = .zero
    private var mousePos: NSPoint = .zero
    private var hasMouse = false
    private var dragging = false

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        // Hide the system cursor — we draw our own crosshair.
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func draw(_ dirtyRect: NSRect) {
        // Dim everything by default…
        NSColor.black.withAlphaComponent(0.35).setFill()
        bounds.fill()

        // …punch out the selection so the live image shows through.
        if !currentRect.isEmpty {
            NSColor.clear.setFill()
            currentRect.fill(using: .copy)

            // Border
            NSColor.systemBlue.setStroke()
            let path = NSBezierPath(rect: currentRect.insetBy(dx: 0.5, dy: 0.5))
            path.lineWidth = 1.5
            path.stroke()

            // Corner ticks
            drawCornerTicks(in: currentRect)

            // Size badge above selection
            let badge = "\(Int(currentRect.width)) × \(Int(currentRect.height))"
            drawBadge(badge,
                      at: NSPoint(x: currentRect.midX,
                                  y: currentRect.maxY + 14),
                      anchor: .bottomCenter)
        }

        // Crosshair guides + coords when hovering (and during drag, for alignment).
        if hasMouse {
            drawCrosshair(at: mousePos)
            if !dragging {
                let global = NSPoint(x: mousePos.x + screenOrigin.x, y: mousePos.y + screenOrigin.y)
                let label = "\(Int(global.x)), \(Int(global.y))"
                drawBadge(label,
                          at: NSPoint(x: mousePos.x + 14, y: mousePos.y - 14),
                          anchor: .bottomLeft)
            }
        }
    }

    private func drawCrosshair(at p: NSPoint) {
        NSColor.white.withAlphaComponent(0.55).setStroke()
        let line = NSBezierPath()
        line.lineWidth = 1
        line.move(to: NSPoint(x: bounds.minX, y: p.y))
        line.line(to: NSPoint(x: bounds.maxX, y: p.y))
        line.move(to: NSPoint(x: p.x, y: bounds.minY))
        line.line(to: NSPoint(x: p.x, y: bounds.maxY))
        let pattern: [CGFloat] = [4, 3]
        line.setLineDash(pattern, count: 2, phase: 0)
        line.stroke()

        // Solid + marker right at the cursor.
        NSColor.white.setStroke()
        let plus = NSBezierPath()
        plus.lineWidth = 1.5
        plus.move(to: NSPoint(x: p.x - 8, y: p.y))
        plus.line(to: NSPoint(x: p.x + 8, y: p.y))
        plus.move(to: NSPoint(x: p.x, y: p.y - 8))
        plus.line(to: NSPoint(x: p.x, y: p.y + 8))
        plus.setLineDash(nil, count: 0, phase: 0)
        plus.stroke()
    }

    private func drawCornerTicks(in rect: NSRect) {
        let len: CGFloat = 10
        NSColor.systemBlue.setStroke()
        let corners: [(NSPoint, NSPoint, NSPoint)] = [
            (NSPoint(x: rect.minX, y: rect.minY),
             NSPoint(x: rect.minX + len, y: rect.minY),
             NSPoint(x: rect.minX, y: rect.minY + len)),
            (NSPoint(x: rect.maxX, y: rect.minY),
             NSPoint(x: rect.maxX - len, y: rect.minY),
             NSPoint(x: rect.maxX, y: rect.minY + len)),
            (NSPoint(x: rect.minX, y: rect.maxY),
             NSPoint(x: rect.minX + len, y: rect.maxY),
             NSPoint(x: rect.minX, y: rect.maxY - len)),
            (NSPoint(x: rect.maxX, y: rect.maxY),
             NSPoint(x: rect.maxX - len, y: rect.maxY),
             NSPoint(x: rect.maxX, y: rect.maxY - len)),
        ]
        let path = NSBezierPath()
        path.lineWidth = 2.5
        for (c, a, b) in corners {
            path.move(to: a); path.line(to: c); path.line(to: b)
        }
        path.stroke()
    }

    private enum BadgeAnchor { case bottomLeft, bottomCenter }
    private func drawBadge(_ text: String, at point: NSPoint, anchor: BadgeAnchor) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let str = text as NSString
        let textSize = str.size(withAttributes: attrs)
        let padX: CGFloat = 6, padY: CGFloat = 3
        var origin = point
        switch anchor {
        case .bottomLeft:
            break
        case .bottomCenter:
            origin.x -= (textSize.width + padX * 2) / 2
        }
        let bg = NSRect(x: origin.x, y: origin.y,
                        width: textSize.width + padX * 2,
                        height: textSize.height + padY * 2)
        let bgPath = NSBezierPath(roundedRect: bg, xRadius: 4, yRadius: 4)
        NSColor.black.withAlphaComponent(0.75).setFill()
        bgPath.fill()
        str.draw(at: NSPoint(x: origin.x + padX, y: origin.y + padY), withAttributes: attrs)
    }

    // MARK: - Mouse

    override func mouseEntered(with event: NSEvent) {
        hasMouse = true
        mousePos = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hasMouse = false
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        mousePos = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        mousePos = startPoint ?? .zero
        currentRect = .zero
        dragging = true
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let s = startPoint else { return }
        let p = convert(event.locationInWindow, from: nil)
        mousePos = p
        currentRect = NSRect(x: min(s.x, p.x),
                             y: min(s.y, p.y),
                             width: abs(p.x - s.x),
                             height: abs(p.y - s.y))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        dragging = false
        guard currentRect.width >= 4, currentRect.height >= 4 else {
            onCancel?()
            return
        }
        let global = CGRect(x: currentRect.minX + screenOrigin.x,
                            y: currentRect.minY + screenOrigin.y,
                            width: currentRect.width,
                            height: currentRect.height)
        onComplete?(global)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() } // Esc
    }
}
