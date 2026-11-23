import AppKit

/// The palette's window material with its SwiftUI content inside: Liquid
/// Glass on macOS 26 and later, rounded popover vibrancy before. The panel
/// and the theme preview in Settings both draw through it, so the preview
/// shows the same glass, corners, and pinned appearance.
///
/// The theme's surface color is drawn by `PaletteView` over this material;
/// the material itself stays the system's, which follows Reduce
/// Transparency and Increase Contrast on its own.
@MainActor
final class PaletteSurface {
    /// The view to install as the window's content.
    let view: NSView

    init(content: NSView, blending: NSVisualEffectView.BlendingMode) {
        content.translatesAutoresizingMaskIntoConstraints = false
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.contentView = content
            view = glass
        } else {
            let effect = NSVisualEffectView()
            effect.material = .popover
            effect.state = .active
            effect.blendingMode = blending
            effect.addSubview(content)
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
                content.topAnchor.constraint(equalTo: effect.topAnchor),
                content.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
            ])
            view = effect
        }
        apply(.standard)
    }

    /// Pins the style's appearance (nil follows the system) and rounds the
    /// material to the theme's corners.
    func apply(_ style: PaletteStyle) {
        view.appearance = style.appearance
        if #available(macOS 26.0, *), let glass = view as? NSGlassEffectView {
            glass.cornerRadius = style.cornerRadius
        } else if let effect = view as? NSVisualEffectView {
            effect.maskImage = Self.roundedMask(radius: style.cornerRadius)
        }
    }

    static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
