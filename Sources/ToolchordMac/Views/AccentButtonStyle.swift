import SwiftUI

/// The Copy button in a theme's own accent. The system's prominent button
/// always draws white text, which a light accent such as yellow can't
/// carry, so this one picks black or white for the label, whichever reads
/// better on the fill.
struct AccentButtonStyle: ButtonStyle {
    let fill: Color
    let label: Color

    func makeBody(configuration: Configuration) -> some View {
        AccentButton(configuration: configuration, fill: fill, label: label)
    }

    private struct AccentButton: View {
        let configuration: ButtonStyleConfiguration
        let fill: Color
        let label: Color
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.paletteStyle) private var style

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: style.radius(7), style: .continuous)
            configuration.label
                .foregroundStyle(label)
                .padding(.horizontal, style.scaled(10))
                .frame(minHeight: style.scaled(28))
                .background(shape.fill(fill))
                .overlay {
                    if configuration.isPressed {
                        shape.fill(Color.black.opacity(0.15))
                    }
                }
                .overlay {
                    if style.showsBorders {
                        shape.strokeBorder(label.opacity(0.6), lineWidth: 1)
                    }
                }
                .contentShape(shape)
                .opacity(isEnabled ? 1 : 0.4)
        }
    }
}
