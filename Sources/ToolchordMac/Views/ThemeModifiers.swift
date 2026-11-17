import SwiftUI

extension View {
    /// The theme's text color for everything that doesn't set its own. Only
    /// a custom text color is applied: setting even `.primary` here would
    /// override the system's own colors for controls such as borderless
    /// buttons, which the standard theme keeps.
    @ViewBuilder
    func themedForeground(_ style: PaletteStyle) -> some View {
        if let text = style.customText {
            foregroundStyle(text)
        } else {
            self
        }
    }

    /// The rounded box behind input, results, and fields: the theme's well
    /// color, outlined under Increase Contrast. `radius` is designed for the
    /// standard 18-point panel and follows the theme's corners.
    func wellBackground(radius: CGFloat = 10) -> some View {
        modifier(WellBackground(radius: radius))
    }
}

private struct WellBackground: ViewModifier {
    let radius: CGFloat
    @Environment(\.paletteStyle) private var style

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: style.radius(radius), style: .continuous)
        content
            .background(shape.fill(style.well))
            .overlay {
                if style.showsBorders {
                    shape.strokeBorder(style.border, lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
    }
}
