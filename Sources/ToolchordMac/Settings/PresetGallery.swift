import AppKit
import SwiftUI
import ToolchordTheme

/// The preset tiles, each drawn in its own colors, corners, and
/// appearance. A Custom tile leads when there is a custom theme, so trying
/// presets never loses it.
struct PresetGallery: View {
    let current: PaletteTheme
    let custom: PaletteTheme?
    let onPick: (PaletteTheme) -> Void

    var body: some View {
        let selected = ThemePresets.matching(current)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 8)], alignment: .leading, spacing: 8) {
            if let custom, ThemePresets.matching(custom) == nil {
                PresetTile(name: "Custom", tagline: "Your most recent own theme", theme: custom, isSelected: selected == nil) {
                    onPick(custom)
                }
            }
            ForEach(ThemePresets.all) { preset in
                PresetTile(name: preset.name, tagline: preset.tagline, theme: preset.theme, isSelected: preset.id == selected?.id) {
                    onPick(preset.theme)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// A preset as a small picture of itself: its surface, accent, name in its
/// text color, and a row of its syntax and warning colors.
private struct PresetTile: View {
    let name: String
    let tagline: String
    let theme: PaletteTheme
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var systemScheme

    var body: some View {
        Button(action: action) {
            tile
        }
        .buttonStyle(.plain)
        .help("\(name): \(tagline)")
        .accessibilityLabel(name)
        .accessibilityHint(tagline)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var tile: some View {
        let style = PaletteStyle(theme: theme)
        let shape = RoundedRectangle(cornerRadius: max(3, style.radius(9)), style: .continuous)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Circle()
                    .fill(style.accent)
                    .frame(width: 9, height: 9)
                Text(name)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(style.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(style.accent)
                }
            }
            HStack(spacing: 3) {
                ForEach([ThemeColorRole.keys, .strings, .numbers, .literals, .warning], id: \.self) { role in
                    Capsule()
                        .fill(Color(nsColor: style.nsColor(role)))
                        .frame(height: 5)
                }
            }
        }
        .padding(8)
        .background(shape.fill(surface))
        .overlay(shape.strokeBorder(isSelected ? style.accent : Color(nsColor: .separatorColor), lineWidth: isSelected ? 2 : 1))
        .contentShape(shape)
        .environment(\.colorScheme, scheme)
    }

    /// The panel as it looks over the reference glass; the system window
    /// background for the standard theme.
    private var surface: Color {
        guard let tone = theme.appearance.pinnedTone else { return Color(nsColor: .windowBackgroundColor) }
        let fill = theme[.surface] ?? ThemeReference.windowBackground(tone)
        return Color(nsColor: NSColor(theme: fill.blended(over: ThemeReference.glass(tone), opacity: theme.surfaceOpacity)))
    }

    private var scheme: ColorScheme {
        switch theme.appearance {
        case .system: systemScheme
        case .light: .light
        case .dark: .dark
        }
    }
}
