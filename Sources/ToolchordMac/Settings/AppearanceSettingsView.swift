import AppKit
import SwiftUI
import ToolchordTheme

/// Settings ▸ Appearance: a live preview of the palette, the preset
/// gallery, and every theme setting. Each control writes straight through,
/// so the preview changes as you edit and the palette matches it the next
/// time it opens.
struct AppearanceSettingsView: View {
    @Bindable var preferences: AppPreferences
    let clipboard: SystemClipboard
    @State private var accessibility = DisplayAccessibility.shared
    @State private var scenario = ThemePreviewScenario.json
    @State private var backdrop = ThemePreviewBackdrop.wallpaper
    @State private var message: Message?
    @State private var fontFamilies: [String] = []

    private struct Message: Equatable {
        let text: String
        let isError: Bool
    }

    private var theme: PaletteTheme { preferences.theme }

    private var style: PaletteStyle {
        PaletteStyle(
            theme: theme,
            textSizes: preferences.textSizes,
            increaseContrast: accessibility.increaseContrast,
            reduceTransparency: accessibility.reduceTransparency
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            previewColumn
                .frame(width: ThemePreview.size.width + 40)
            Divider()
            Form {
                themeSection
                appearanceSection
                surfaceSection
                textSection
                codeSection
                statusSection
            }
            .formStyle(.grouped)
            .frame(width: 420)
        }
        .frame(height: 640)
        .onAppear { fontFamilies = CodeFonts.installedFamilies() }
    }

    // MARK: Preview

    private var previewColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Preview", selection: $scenario) {
                    ForEach(ThemePreviewScenario.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("What the preview shows")
                Spacer()
                Picker("Backdrop", selection: $backdrop) {
                    ForEach(ThemePreviewBackdrop.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("What the preview shows behind the palette")
            }
            ThemePreview(style: style, scenario: scenario, backdrop: backdrop)
                .frame(height: ThemePreview.size.height + 40)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            ContrastReport(theme: theme) {
                preferences.setTheme(ThemeAudit.raisingContrast(of: theme))
            }
            Spacer(minLength: 0)
        }
        .padding(20)
    }

    // MARK: Sections

    private var themeSection: some View {
        Section {
            PresetGallery(current: theme, custom: preferences.customTheme) { preferences.setTheme($0) }
            HStack {
                Button("Copy Theme", action: copyTheme)
                    .help("Copy this theme as JSON text to share it")
                Button("Paste Theme", action: pasteTheme)
                    .help("Use a theme someone copied with Copy Theme")
                Spacer()
                Button("Reset to Default") { preferences.resetAppearance() }
                    .disabled(theme == .standard && preferences.textSizes == .standard)
            }
            if let message {
                Text(message.text)
                    .font(.system(size: 12))
                    .foregroundStyle(message.isError ? Theme.failure : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Theme")
        } footer: {
            Text("A preset sets every look below at once and keeps your text sizes. Custom keeps your most recent own theme. Reset to Default restores Toolchord's look and text sizes.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var appearanceSection: some View {
        Section {
            Picker("Appearance", selection: themeBinding(\.appearance)) {
                ForEach(ThemeAppearance.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
        } footer: {
            Text(theme.appearance == .system
                ? "System follows your Mac in light and dark with the standard colors. To pick colors, choose Light or Dark: a fixed color can't stay legible in both."
                : "The palette stays \(theme.appearance.label.lowercased()), so its colors stay legible. Colors left on Automatic use the standard ones.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var surfaceSection: some View {
        Section("Surface") {
            colorRow(.surface)
            sliderRow("Opacity", value: themeBinding(\.surfaceOpacity), in: PaletteTheme.Limit.surfaceOpacity, label: opacityLabel)
            colorRow(.well)
            sliderRow("Corners", value: themeBinding(\.cornerRadius), in: PaletteTheme.Limit.cornerRadius, label: "\(Int(theme.cornerRadius)) pt")
        }
    }

    private var textSection: some View {
        Section("Text") {
            colorRow(.accent)
            colorRow(.text)
            colorRow(.secondaryText)
            Picker("Text size", selection: $preferences.textSizes.interface) {
                ForEach(InterfaceTextSize.allCases) { Text($0.label).tag($0) }
            }
        }
    }

    private var codeSection: some View {
        Section("Code") {
            Picker("Typeface", selection: themeBinding(\.codeFontFamily)) {
                Text("System (SF Mono)").tag(String?.none)
                ForEach(typefaceChoices, id: \.self) { family in
                    Text(fontFamilies.contains(family) ? family : "\(family) (not installed)")
                        .tag(String?.some(family))
                }
            }
            Stepper(value: $preferences.textSizes.codeFontSize, in: ThemeTextSizes.codeFontSizes, step: 1) {
                HStack {
                    Text("Size")
                    Spacer()
                    Text("\(Int(preferences.textSizes.codeFontSize)) pt")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            ForEach([ThemeColorRole.code, .keys, .strings, .numbers, .literals, .punctuation, .comments]) { role in
                colorRow(role)
            }
        }
    }

    private var statusSection: some View {
        Section("Status") {
            ForEach([ThemeColorRole.success, .warning, .failure]) { role in
                colorRow(role)
            }
        }
    }

    // MARK: Controls

    private func colorRow(_ role: ThemeColorRole) -> some View {
        // Under System the rows are disabled and show the current tone's colors.
        let tone = theme.appearance.pinnedTone ?? (NSApp.effectiveAppearance.isDarkAppearance ? .dark : .light)
        return ThemeColorRow(
            role: role,
            color: colorBinding(role),
            startingColor: theme.startingColor(for: role, tone: tone),
            isEditable: theme.appearance != .system
        )
    }

    /// A continuous slider: the theme rounds what it stores (whole points,
    /// hundredths), and a stepped slider would draw a tick for every step.
    private func sliderRow(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, label: String) -> some View {
        HStack {
            Text(title)
            Slider(value: value, in: range)
                .accessibilityLabel(title)
                .accessibilityValue(label)
            Text(label)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 52, alignment: .trailing)
        }
    }

    private var opacityLabel: String {
        switch theme.surfaceOpacity {
        case 0: "Glass"
        case 1: "Solid"
        default: "\(Int((theme.surfaceOpacity * 100).rounded()))%"
        }
    }

    /// Installed monospaced families, plus the theme's own when this Mac
    /// doesn't have it, so the picker never shows an empty selection.
    private var typefaceChoices: [String] {
        guard let family = theme.codeFontFamily, !fontFamilies.contains(family) else { return fontFamilies }
        return fontFamilies + [family]
    }

    // MARK: Bindings

    private func themeBinding<Value>(_ keyPath: WritableKeyPath<PaletteTheme, Value>) -> Binding<Value> {
        Binding(
            get: { preferences.theme[keyPath: keyPath] },
            set: { newValue in
                var edited = preferences.theme
                edited[keyPath: keyPath] = newValue
                preferences.setTheme(edited)
            }
        )
    }

    /// A color that may be automatic. Giving the surface a color while it
    /// is pure glass also makes it solid, so the color shows.
    private func colorBinding(_ role: ThemeColorRole) -> Binding<ThemeColor?> {
        Binding(
            get: { preferences.theme[role] },
            set: { newValue in
                var edited = preferences.theme
                edited[role] = newValue
                if role == .surface, newValue != nil, edited.surfaceOpacity == 0 {
                    edited.surfaceOpacity = 1
                }
                preferences.setTheme(edited)
            }
        )
    }

    // MARK: Sharing

    private func copyTheme() {
        if clipboard.writeText(theme.jsonText, sensitivity: .normal) {
            message = Message(text: "Copied the theme as JSON text.", isError: false)
        } else {
            message = Message(text: "Couldn't copy the theme to the clipboard.", isError: true)
        }
    }

    /// Reads the clipboard only now, on the person's request, like the
    /// palette's own Paste.
    private func pasteTheme() {
        guard let text = clipboard.readTextForPaste() else {
            message = Message(text: PaletteTheme.ImportError.notATheme.description, isError: true)
            return
        }
        switch PaletteTheme.imported(from: text) {
        case .success(let pasted):
            preferences.setTheme(pasted)
            let name = ThemePresets.matching(pasted)?.name ?? "custom theme"
            message = Message(text: "Applied the pasted \(name). Text sizes stay as they were.", isError: false)
        case .failure(let error):
            message = Message(text: error.description, isError: true)
        }
    }
}

/// One color setting: its name, whether it is automatic, and a color well.
/// Picking a color turns Automatic off; turning Automatic off starts from
/// the color the palette draws now, so the first change is an adjustment.
private struct ThemeColorRow: View {
    let role: ThemeColorRole
    @Binding var color: ThemeColor?
    let startingColor: ThemeColor
    let isEditable: Bool

    var body: some View {
        HStack {
            Text(role.label)
                .help(role.summary)
            Spacer()
            Toggle("Automatic", isOn: Binding(
                get: { color == nil },
                set: { automatic in color = automatic ? nil : (color ?? startingColor) }
            ))
            .toggleStyle(.checkbox)
            .accessibilityLabel("\(role.label) automatic")
            ColorPicker(role.label, selection: Binding(
                get: { Color(nsColor: NSColor(theme: color ?? startingColor)) },
                set: { picked in
                    if let value = ThemeColor(nsColor: NSColor(picked)) { color = value }
                }
            ), supportsOpacity: false)
            .labelsHidden()
        }
        .disabled(!isEditable)
    }
}

/// Which of the theme's colors miss their WCAG contrast minimum, and a way
/// to raise them.
private struct ContrastReport: View {
    let theme: PaletteTheme
    let onRaise: () -> Void

    var body: some View {
        let issues = ThemeAudit.issues(in: theme)
        let problems = ThemeAudit.problems(in: theme)
        VStack(alignment: .leading, spacing: 6) {
            if issues.isEmpty && problems.isEmpty {
                Label("The theme's colors meet WCAG contrast minimums on the panel, in wells, and on the selection.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
            } else {
                Label("Some colors may be hard to read.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.warning)
                ForEach(problems, id: \.self) { problem in
                    Text(problem)
                }
                if !issues.isEmpty {
                    Text(issues.map(\.summary).joined(separator: "; "))
                    Button("Raise Contrast", action: onRaise)
                        .help("Move each color that fails toward black or white until it passes, keeping its hue")
                }
            }
        }
        .font(.system(size: 12))
        .fixedSize(horizontal: false, vertical: true)
    }
}
