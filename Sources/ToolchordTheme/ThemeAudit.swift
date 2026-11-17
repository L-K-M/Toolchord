/// WCAG 2.x contrast rules for the colors Toolchord draws: a theme's custom
/// colors and Toolchord's own defaults. System colors (label, accent,
/// window background) are the system's to keep legible and are not checked.
///
/// Every shipped preset passes with no issues and no problems (see the unit
/// tests). A custom theme isn't held to the rules: the editor lists what
/// fails and offers to raise it.
///
/// The panel may be translucent, so each color is checked against every
/// background it can sit on: the surface over the reference glass, the
/// opaque surface Reduce Transparency shows, the wells on both, and the
/// selection. Translucent panels over busy wallpapers are approximated by
/// the reference glass; Reduce Transparency makes the check exact.
public enum ThemeAudit {
    /// Text, including code tokens and status labels.
    public static let textMinimum = 4.5
    /// Structural glyphs (punctuation) and components (the accent).
    public static let graphicMinimum = 3.0
    /// Under Increase Contrast, text is raised to WCAG AAA...
    public static let increasedTextMinimum = 7.0
    /// ...and glyphs and components to the normal text minimum.
    public static let increasedGraphicMinimum = 4.5

    /// System controls (buttons, pickers, scroll bars) draw for the pinned
    /// appearance, so the panel's lightness has to agree with it.
    static let darkPanelMaximumLuminance = 0.2
    static let lightPanelMinimumLuminance = 0.4

    /// The minimum for a kind of role; nil for backgrounds.
    public static func minimum(for kind: ThemeColorRole.Kind, increasedContrast: Bool) -> Double? {
        switch kind {
        case .background: nil
        case .text: increasedContrast ? increasedTextMinimum : textMinimum
        case .graphic, .component: increasedContrast ? increasedGraphicMinimum : graphicMinimum
        }
    }

    // MARK: Checks

    /// Every role that misses its minimum, in every tone the theme draws.
    public static func issues(in theme: PaletteTheme) -> [ContrastIssue] {
        theme.tones.flatMap { issues(in: theme, tone: $0) }
    }

    /// Every role that misses its minimum in `tone`, once each, against its
    /// worst background, in role order.
    public static func issues(in theme: PaletteTheme, tone: ThemeTone) -> [ContrastIssue] {
        let backdrop = Backdrop(theme: theme, tone: tone, increasedContrast: false, accent: theme[.accent])
        var found: [ContrastIssue] = []
        for role in ThemeColorRole.allCases {
            guard let check = check(role, in: theme, tone: tone) else { continue }
            let backgrounds = backdrop.backgrounds(for: role)
            guard let worst = backgrounds.min(by: { check.ratio(on: $0) < check.ratio(on: $1) }) else { continue }
            let ratio = check.ratio(on: worst)
            // A hair of tolerance: a ratio computed at exactly the minimum passes.
            if ratio + 1e-9 < check.minimum {
                found.append(ContrastIssue(role: role, tone: tone, foreground: check.foreground(on: worst), background: worst, ratio: ratio, minimum: check.minimum))
            }
        }
        return found
    }

    /// Rules the contrast math can't see, as sentences for the editor.
    public static func problems(in theme: PaletteTheme) -> [String] {
        guard let tone = theme.appearance.pinnedTone else {
            return theme.colors.isEmpty ? [] : ["Custom colors need the Light or Dark appearance; the System appearance uses the standard colors."]
        }
        let backdrop = Backdrop(theme: theme, tone: tone, increasedContrast: false, accent: theme[.accent])
        let luminances = backdrop.panels.map(\.relativeLuminance)
        switch tone {
        case .dark where luminances.contains(where: { $0 > darkPanelMaximumLuminance }):
            return ["The surface is too light for the Dark appearance: buttons and menus would draw light text on it. Choose Light or a darker surface."]
        case .light where luminances.contains(where: { $0 < lightPanelMinimumLuminance }):
            return ["The surface is too dark for the Light appearance: buttons and menus would draw dark text on it. Choose Dark or a lighter surface."]
        default:
            return []
        }
    }

    // MARK: Drawing

    /// The colors Toolchord draws itself for `theme` in `tone`: the theme's
    /// custom colors and Toolchord's defaults. Roles the system draws are
    /// absent. Under Increase Contrast every foreground is raised to its
    /// increased minimum against the opaque panel Reduce Transparency
    /// shows, keeping its hue, so a custom theme honors the setting too.
    public static func drawnColors(for theme: PaletteTheme, tone: ThemeTone, increasedContrast: Bool) -> [ThemeColorRole: ThemeColor] {
        var drawn: [ThemeColorRole: ThemeColor] = [:]
        drawn[.surface] = theme[.surface]
        drawn[.well] = theme[.well]
        var accent = theme[.accent]
        if increasedContrast, let custom = accent {
            let panels = Backdrop(theme: theme, tone: tone, increasedContrast: true, accent: custom).backgrounds(for: .accent)
            accent = custom.raisingContrast(to: increasedGraphicMinimum, against: panels)
        }
        drawn[.accent] = accent
        let backdrop = Backdrop(theme: theme, tone: tone, increasedContrast: increasedContrast, accent: accent)
        for role in ThemeColorRole.allCases where role.kind == .text || role.kind == .graphic {
            guard let color = checkedColor(role, in: theme, tone: tone) else { continue }
            if increasedContrast, let minimum = minimum(for: role.kind, increasedContrast: true) {
                drawn[role] = color.raisingContrast(to: minimum, against: backdrop.backgrounds(for: role))
            } else {
                drawn[role] = color
            }
        }
        return drawn
    }

    /// `theme` with every failing color moved the least distance toward
    /// black or white that passes, keeping its hue. A failing automatic
    /// syntax or status color becomes a custom one. The system appearance
    /// can't hold custom colors and is returned unchanged.
    public static func raisingContrast(of theme: PaletteTheme) -> PaletteTheme {
        guard let tone = theme.appearance.pinnedTone else { return theme }
        var result = theme
        if let accent = result[.accent] {
            let panels = Backdrop(theme: result, tone: tone, increasedContrast: false, accent: accent).backgrounds(for: .accent)
            if accent.worstContrast(against: panels) < graphicMinimum {
                result[.accent] = raised(accent, to: graphicMinimum, against: panels)
            }
        }
        let backdrop = Backdrop(theme: result, tone: tone, increasedContrast: false, accent: result[.accent])
        for role in ThemeColorRole.allCases where role.kind == .text || role.kind == .graphic {
            guard let check = check(role, in: result, tone: tone),
                  let minimum = minimum(for: role.kind, increasedContrast: false) else { continue }
            let backgrounds = backdrop.backgrounds(for: role)
            guard backgrounds.contains(where: { check.ratio(on: $0) < check.minimum }) else { continue }
            // A failing system color becomes a custom one, starting from its
            // opaque stand-in and held to the custom minimum from then on,
            // so it is raised that far at once.
            let start = check.opacity < 1 ? result.startingColor(for: role, tone: tone) : check.color
            result[role] = raised(start, to: minimum, against: backgrounds)
        }
        return result
    }

    // MARK: Helpers

    /// The color the audit holds Toolchord to: the theme's own, or
    /// Toolchord's default. Nil when the system draws the role.
    static func checkedColor(_ role: ThemeColorRole, in theme: PaletteTheme, tone: ThemeTone) -> ThemeColor? {
        theme[role] ?? ThemeDefaults.color(role, tone: tone)
    }

    /// A color the audit checks, drawn at `opacity` over each background
    /// (1 for a theme's opaque colors), and its minimum.
    struct Check {
        let color: ThemeColor
        let opacity: Double
        let minimum: Double

        func foreground(on background: ThemeColor) -> ThemeColor {
            opacity >= 1 ? color : color.blended(over: background, opacity: opacity)
        }

        func ratio(on background: ThemeColor) -> Double {
            foreground(on: background).contrast(with: background)
        }
    }

    /// What to check for `role`, or nil when there is nothing to check.
    ///
    /// Automatic text and secondary text draw the system's label colors,
    /// which stay legible on the backgrounds the system pairs them with but
    /// not on a surface or wells the theme draws itself, such as black
    /// wells in the Light appearance. On such a theme they are checked as
    /// what the system draws, translucent black or white, at the text
    /// minimum for text and the graphic minimum for secondary text, since
    /// Apple designs that near 4:1. Code text, punctuation, and comments
    /// follow these two and are covered by them. The automatic accent is
    /// the person's own and can't be known here.
    static func check(_ role: ThemeColorRole, in theme: PaletteTheme, tone: ThemeTone) -> Check? {
        guard let minimum = minimum(for: role.kind, increasedContrast: false) else { return nil }
        if let color = checkedColor(role, in: theme, tone: tone) {
            return Check(color: color, opacity: 1, minimum: minimum)
        }
        guard drawsOwnBackground(theme) else { return nil }
        switch role {
        case .text:
            let label = ThemeReference.systemLabel(tone)
            return Check(color: label.color, opacity: label.opacity, minimum: textMinimum)
        case .secondaryText:
            let label = ThemeReference.systemSecondaryLabel(tone)
            return Check(color: label.color, opacity: label.opacity, minimum: graphicMinimum)
        default:
            return nil
        }
    }

    /// Whether text sits on a background the theme chose: a surface color
    /// that is drawn, or wells.
    static func drawsOwnBackground(_ theme: PaletteTheme) -> Bool {
        (theme[.surface] != nil && theme.surfaceOpacity > 0) || theme[.well] != nil
    }

    /// Raised past `minimum` and rounded to the 8 bits a theme stores, with
    /// a margin so the rounding can't land it back under.
    private static func raised(_ color: ThemeColor, to minimum: Double, against backgrounds: [ThemeColor]) -> ThemeColor {
        var target = minimum
        for _ in 0..<10 {
            let candidate = color.raisingContrast(to: target, against: backgrounds).rounded
            if candidate.worstContrast(against: backgrounds) >= minimum { return candidate }
            target += 0.05
        }
        return color.raisingContrast(to: 21, against: backgrounds).rounded
    }

    /// The colors a theme's foregrounds are drawn on in one tone.
    struct Backdrop {
        /// The panel: the surface over the reference glass, and the opaque
        /// panel Reduce Transparency shows (only that one under Increase
        /// Contrast, which turns Reduce Transparency on).
        let panels: [ThemeColor]
        /// The wells on each panel.
        let wells: [ThemeColor]
        /// The selected row on each panel.
        let selections: [ThemeColor]

        init(theme: PaletteTheme, tone: ThemeTone, increasedContrast: Bool, accent: ThemeColor?) {
            let fill = theme[.surface] ?? ThemeReference.windowBackground(tone)
            let normal = fill.blended(over: ThemeReference.glass(tone), opacity: theme.surfaceOpacity)
            // With no surface fill, Reduce Transparency turns the glass into
            // the system's opaque material.
            let opaque = theme.surfaceOpacity > 0 ? fill : ThemeReference.windowBackground(tone)
            let panels = increasedContrast || normal == opaque ? [opaque] : [normal, opaque]
            self.panels = panels
            if let well = theme[.well] {
                wells = [well]
            } else {
                let wash = ThemeReference.wellWash(tone)
                wells = panels.map { wash.color.blended(over: $0, opacity: wash.opacity) }
            }
            let selection = accent ?? ThemeReference.systemAccent(tone)
            selections = panels.map { selection.blended(over: $0, opacity: ThemeReference.selectionOpacity) }
        }

        /// Where `role` is drawn.
        func backgrounds(for role: ThemeColorRole) -> [ThemeColor] {
            switch role {
            case .surface, .well: []
            case .accent: panels
            case .text, .secondaryText: panels + wells + selections
            case .code, .keys, .strings, .numbers, .literals, .punctuation, .comments: wells
            case .success, .warning, .failure: panels + wells
            }
        }
    }
}
