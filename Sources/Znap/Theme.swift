import AppKit

/// Shared visual language for Znap's floating panels. Mirrors the soft, glassy
/// look of recent iOS releases — translucent backdrop, continuous corner radius,
/// hairline edge highlight, pill-shaped icon-only controls.
enum Theme {
    static let cornerRadius: CGFloat = 18
    static let panelPadding: CGFloat = 10
    static let bottomBarHeight: CGFloat = 40
    static let iconButtonSize: CGFloat = 28
    static let iconButtonGap: CGFloat = 5
    static let thumbnailCornerRadius: CGFloat = 10

    /// Returns a container view filled with a translucent material and rounded
    /// corners, plus a transparent overlay (`content`) for adding child views.
    /// Set `panel.contentView = container`.
    @MainActor
    static func makeGlassContainer(size: NSSize) -> (container: NSView, content: NSView) {
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.cornerRadius = cornerRadius
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true

        // Apply the same rounded clip directly to the visual effect view so its
        // built-in edge highlight doesn't leak out as a hard rectangle behind the
        // parent's corner mask.
        let blur = NSVisualEffectView(frame: container.bounds)
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = cornerRadius
        blur.layer?.cornerCurve = .continuous
        blur.layer?.masksToBounds = true
        blur.autoresizingMask = [.width, .height]
        container.addSubview(blur)

        // Very subtle adaptive edge — barely-there hairline that follows the
        // rounded shape. Uses labelColor so it dims appropriately in dark mode.
        let edge = NSView(frame: container.bounds)
        edge.wantsLayer = true
        edge.layer?.cornerRadius = cornerRadius
        edge.layer?.cornerCurve = .continuous
        edge.layer?.borderWidth = 0.5
        edge.layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
        edge.autoresizingMask = [.width, .height]
        container.addSubview(edge)

        let content = NSView(frame: container.bounds)
        content.autoresizingMask = [.width, .height]
        container.addSubview(content)

        return (container, content)
    }

    @MainActor
    static func iconButton(symbol: String, tooltip: String,
                           target: AnyObject?, action: Selector) -> GlassIconButton {
        let b = GlassIconButton(frame: NSRect(x: 0, y: 0,
                                              width: iconButtonSize,
                                              height: iconButtonSize))
        let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            .applying(.init(scale: .medium))
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)?
            .withSymbolConfiguration(cfg)
        b.imagePosition = .imageOnly
        // Render the SF Symbol at its natural size — otherwise NSButton scales it
        // to fit the button bounds, which stretches the glyph.
        b.imageScaling = .scaleNone
        b.contentTintColor = .labelColor
        b.target = target
        b.action = action
        b.toolTip = tooltip
        return b
    }

    @MainActor
    static func primaryIconButton(symbol: String, tooltip: String,
                                  target: AnyObject?, action: Selector) -> GlassIconButton {
        let b = iconButton(symbol: symbol, tooltip: tooltip, target: target, action: action)
        b.isPrimary = true
        b.contentTintColor = .white
        return b
    }
}

/// Small borderless circle/pill button with a soft hover background. The primary
/// variant carries a filled accent tint at rest. The selected variant shows a
/// softer accent fill — used in the editor toolbar to mark the active tool.
@MainActor
final class GlassIconButton: NSButton {
    var isPrimary: Bool = false {
        didSet { updateBackground(); updateTint() }
    }
    var isSelected: Bool = false {
        didSet { updateBackground(); updateTint() }
    }
    /// Color used for the icon when the button is in its default (unselected,
    /// non-primary) state. Allows callers to keep their original tint.
    var defaultTintColor: NSColor = .labelColor {
        didSet { updateTint() }
    }
    private var isHovering = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    private func commonInit() {
        isBordered = false
        bezelStyle = .regularSquare
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        updateCornerRadius()
        updateBackground()
    }

    override func layout() {
        super.layout()
        updateCornerRadius()
    }

    private func updateCornerRadius() {
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.activeInActiveApp, .inVisibleRect, .mouseEnteredAndExited],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        updateBackground()
    }
    override func mouseExited(with event: NSEvent) {
        isHovering = false
        updateBackground()
    }

    private func updateBackground() {
        let bg: NSColor
        if isPrimary {
            bg = isHovering
                ? NSColor.controlAccentColor.withAlphaComponent(0.85)
                : NSColor.controlAccentColor
        } else if isSelected {
            // Softer accent fill — clearly marks selection without being as loud
            // as the primary CTA.
            bg = NSColor.controlAccentColor.withAlphaComponent(isHovering ? 0.35 : 0.22)
        } else {
            bg = isHovering
                ? NSColor.labelColor.withAlphaComponent(0.10)
                : .clear
        }
        layer?.backgroundColor = bg.cgColor
    }

    private func updateTint() {
        if isPrimary {
            contentTintColor = .white
        } else if isSelected {
            contentTintColor = .controlAccentColor
        } else {
            contentTintColor = defaultTintColor
        }
    }
}
