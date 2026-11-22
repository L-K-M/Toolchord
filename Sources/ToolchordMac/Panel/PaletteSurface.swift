import AppKit

/// The palette and the Settings preview share the same Liquid Glass surface.
/// The theme's colors are drawn over the system material by PaletteView.
@MainActor
final class PaletteSurface {
    let view = NSGlassEffectView()

    init(content: NSView) {
        content.translatesAutoresizingMaskIntoConstraints = false
        view.style = .regular
        view.contentView = content
        apply(.standard)
    }

    func apply(_ style: PaletteStyle) {
        view.appearance = style.appearance
        view.cornerRadius = style.cornerRadius
    }
}
