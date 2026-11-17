import AppKit
import SwiftUI

/// Sizes the palette is designed at: the standard text size and an
/// 18-point corner radius. `PaletteStyle` scales them for the chosen text
/// size and theme.
enum Theme {
    // MARK: Layout

    static let panelWidth: CGFloat = 760
    static let searchHeight: CGFloat = 460
    static let toolHeight: CGFloat = 600
    /// Below this width, editors and results stack vertically.
    static let narrowWidth: CGFloat = 640
    static let listWidth: CGFloat = 300
    static let rowHeight: CGFloat = 36
    static let codeLineHeight: CGFloat = 1.25

    // MARK: Settings colors

    // The Settings and welcome windows keep the system look whatever the
    // palette's theme, so they use the standard theme's status colors.
    static let success = PaletteStyle.standard.success
    static let warning = PaletteStyle.standard.warning
    static let failure = PaletteStyle.standard.failure
}

/// A small keycap label such as "⌘K" or "↵".
struct Keycap: View {
    let text: String
    @Environment(\.paletteStyle) private var style

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(style.font(10.5, weight: .medium, design: .rounded))
            .foregroundStyle(style.secondary)
            .padding(.horizontal, 5)
            .frame(minWidth: style.scaled(18), minHeight: style.scaled(18))
            .background(
                RoundedRectangle(cornerRadius: style.radius(4))
                    .strokeBorder(style.secondaryColor.opacity(style.showsBorders ? 0.9 : 0.45), lineWidth: style.showsBorders ? 1 : 0.8)
            )
            .accessibilityHidden(true)
    }
}
