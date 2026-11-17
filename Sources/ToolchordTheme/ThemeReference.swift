/// Concrete stand-ins for what the system draws, where the contrast audit
/// and the snapshots need one color. The Mac layer draws the real thing.
public enum ThemeReference {
    /// The glass or vibrancy behind the panel. Window materials don't show
    /// in offscreen captures, so the snapshots draw this color instead, and
    /// the audit measures against the same color.
    public static func glass(_ tone: ThemeTone) -> ThemeColor {
        switch tone {
        case .light: ThemeColor(0xF2F2F5)
        case .dark: ThemeColor(0x292A2E)
        }
    }

    /// `NSColor.windowBackgroundColor`, measured on macOS 27: the automatic
    /// surface color, and what the panel shows under Reduce Transparency
    /// when the theme draws no surface.
    public static func windowBackground(_ tone: ThemeTone) -> ThemeColor {
        switch tone {
        case .light: ThemeColor(0xFFFFFF)
        case .dark: ThemeColor(0x1E1E1E)
        }
    }

    /// The automatic well: a faint wash of the label color over the panel.
    public static func wellWash(_ tone: ThemeTone) -> (color: ThemeColor, opacity: Double) {
        switch tone {
        case .light: (ThemeColor.black, 0.035)
        case .dark: (ThemeColor.white, 0.045)
        }
    }

    /// The default macOS accent (blue), for checking custom text on a
    /// selection drawn with the system accent.
    public static func systemAccent(_ tone: ThemeTone) -> ThemeColor {
        switch tone {
        case .light: ThemeColor(0x007AFF)
        case .dark: ThemeColor(0x0A84FF)
        }
    }

    /// The selected row is the accent at this opacity over the panel.
    public static let selectionOpacity = 0.22
}
