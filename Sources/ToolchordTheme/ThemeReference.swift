/// Concrete stand-ins for what the system draws, where the contrast audit
/// and the snapshots need one color. The Mac layer draws the real thing.
public enum ThemeReference {
    /// The glass or vibrancy behind the panel. Window materials don't show
    /// in offscreen captures, so the snapshots draw this color instead, and
    /// the audit measures against the same color.
    public static func glass(_ tone: ThemeTone) -> ThemeColor {
        switch tone {
        case .light: ThemeColor(0xF2F2F5)
        case .dark: ThemeColor(0x29292E)
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

    /// `NSColor.labelColor` as measured on macOS 27: translucent black or
    /// white, so it changes with the background it is drawn on.
    public static func systemLabel(_ tone: ThemeTone) -> (color: ThemeColor, opacity: Double) {
        switch tone {
        case .light: (ThemeColor.black, 0.85)
        case .dark: (ThemeColor.white, 0.85)
        }
    }

    /// `NSColor.secondaryLabelColor` as measured on macOS 27.
    public static func systemSecondaryLabel(_ tone: ThemeTone) -> (color: ThemeColor, opacity: Double) {
        switch tone {
        case .light: (ThemeColor.black, 0.5)
        case .dark: (ThemeColor.white, 0.55)
        }
    }

    /// An opaque stand-in for the system label color, where the editor
    /// needs a concrete starting color.
    public static func label(_ tone: ThemeTone) -> ThemeColor {
        switch tone {
        case .light: ThemeColor(0x1D1D1F)
        case .dark: ThemeColor(0xF5F5F7)
        }
    }

    /// An opaque stand-in for the secondary label color that still reads
    /// at 4.5:1 on the window background.
    public static func secondaryLabel(_ tone: ThemeTone) -> ThemeColor {
        switch tone {
        case .light: ThemeColor(0x6E6E73)
        case .dark: ThemeColor(0xA1A1A6)
        }
    }
}
