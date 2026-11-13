import AppKit
import SwiftUI
import ToolchordCore
import ToolchordSession

/// App-level actions the palette views trigger. Implemented by the panel
/// controller, which owns the clipboard, menus, and window.
@MainActor
protocol PaletteActions: AnyObject {
    func openSelected()
    func back()
    func escape()
    func copyAndClose()
    func copyWithoutClosing()
    func copyField(_ id: String)
    func pasteFromClipboard()
    func showActions(from anchor: NSView?)
    func regenerate()
    func clearInput()
    func openSettings()
}

/// The palette: search with a live preview, or one tool expanded.
struct PaletteView: View {
    let session: PaletteSession
    let actions: PaletteActions
    let focus: PaletteFocus
    var isNarrow = false

    var body: some View {
        VStack(spacing: 0) {
            if session.isInTool, let command = session.selectedCommand {
                ToolHeader(session: session, command: command, actions: actions)
                Divider()
                ToolBody(session: session, command: command, actions: actions, focus: focus, isNarrow: isNarrow)
            } else {
                SearchHeader(session: session, actions: actions, focus: focus)
                if let payload = session.payload {
                    Divider()
                    AttachmentBar(payload: payload, onClear: actions.clearInput)
                }
                Divider()
                SearchBody(session: session, actions: actions, isNarrow: isNarrow)
            }
            Divider()
            FooterBar(session: session, actions: actions)
        }
        .overlay(alignment: .bottom) {
            NoticeView(session: session)
                .padding(.bottom, 58)
        }
        .onChange(of: session.preview) { _, preview in
            Announcer.announce(preview: preview, session: session)
        }
    }
}

// MARK: - Search mode

private struct SearchHeader: View {
    let session: PaletteSession
    let actions: PaletteActions
    let focus: PaletteFocus

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            SearchField(session: session, focus: focus, onOpen: actions.openSelected, onEscape: actions.escape)
                .frame(height: 28)
            Button(action: actions.pasteFromClipboard) {
                Keycap("⌘V")
            }
            .buttonStyle(.plain)
            .help("Attach the clipboard as input (⌘V)")
            .accessibilityLabel("Paste clipboard as input")
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
    }
}

private struct AttachmentBar: View {
    let payload: Payload
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: payload.source == .pasted ? "doc.on.clipboard" : "pencil")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            // Metadata only: the pasted text itself may be a secret (for
            // example a token being hashed), so it appears only in the editor.
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize()
            Spacer(minLength: 0)
            Button(action: onClear) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Clear input (⇧⌘⌫)")
            .accessibilityLabel("Clear input")
        }
        .padding(.horizontal, 18)
        .frame(height: 38)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    private var label: String {
        let source = payload.source == .pasted ? "Pasted" : "Edited"
        return "\(source) · \(payload.profile.label) · \(ByteCountText.string(payload.byteCount))"
    }
}

private struct SearchBody: View {
    let session: PaletteSession
    let actions: PaletteActions
    let isNarrow: Bool

    var body: some View {
        if isNarrow {
            VStack(spacing: 0) {
                CommandList(session: session, actions: actions)
                    .frame(height: 150)
                Divider()
                PreviewPane(session: session, actions: actions)
                    .frame(maxHeight: .infinity)
            }
        } else {
            HStack(spacing: 0) {
                CommandList(session: session, actions: actions)
                    .frame(width: Theme.listWidth)
                Divider()
                PreviewPane(session: session, actions: actions)
            }
        }
    }
}

private struct CommandList: View {
    let session: PaletteSession
    let actions: PaletteActions

    var body: some View {
        if session.listing.isEmpty {
            VStack(spacing: 10) {
                Text("No tools found")
                    .font(.system(size: 13, weight: .medium))
                Button("Clear search") { session.setQuery("") }
                    .controlSize(.small)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(session.listing.sections) { section in
                            Text(section.title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.top, 10)
                                .padding(.bottom, 4)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(section.commandIDs, id: \.self) { id in
                                if let command = session.command(id) {
                                    CommandRow(command: command, isSelected: id == session.selectedID)
                                        .id(id)
                                        .contentShape(Rectangle())
                                        // One tap selects; a second tap on the already-selected row
                                        // opens it. A double-tap gesture would hold every single
                                        // tap for the double-tap timeout, so it is not used.
                                        .onTapGesture {
                                            if session.selectedID == id {
                                                actions.openSelected()
                                            } else {
                                                session.select(id)
                                            }
                                        }
                                        .accessibilityAction {
                                            session.select(id)
                                        }
                                        .accessibilityAction(named: "Open") {
                                            session.select(id)
                                            actions.openSelected()
                                        }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
                .onChange(of: session.selectedID) { _, id in
                    guard let id else { return }
                    proxy.scrollTo(id)
                }
            }
        }
    }
}

private struct CommandRow: View {
    let command: ToolCommand
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            CommandIconView(icon: command.icon, isSelected: isSelected)
            Text(command.title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                .lineLimit(1)
            Spacer(minLength: 4)
            if isSelected {
                Keycap("↵")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: Theme.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isSelected ? Theme.selection : Color.clear)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(command.title)
        .accessibilityHint(command.summary)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

struct CommandIconView: View {
    let icon: CommandIcon
    var isSelected = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Theme.chip)
            switch icon {
            case .glyph(let glyph):
                Text(glyph)
                    .font(.system(size: glyph.count > 2 ? 9 : 11, weight: .semibold, design: .monospaced))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            case .symbol(let name):
                Image(systemName: name)
                    .font(.system(size: 11, weight: .semibold))
            }
        }
        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        .frame(width: 26, height: 26)
        .accessibilityHidden(true)
    }
}

private struct PreviewPane: View {
    let session: PaletteSession
    let actions: PaletteActions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let command = session.selectedCommand {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(command.title)
                            .font(.system(size: 13, weight: .semibold))
                        Text(command.summary)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    StatusBadge(preview: session.preview)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)
                OptionsBar(session: session, command: command)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                ResultContent(session: session, command: command, actions: actions, focus: nil)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            } else {
                EmptyState(symbol: "magnifyingglass", title: "No tool selected", message: "Type to search, or clear the search to see every tool.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Tool mode

private struct ToolHeader: View {
    let session: PaletteSession
    let command: ToolCommand
    let actions: PaletteActions

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                title
                Spacer(minLength: 8)
                OptionsBar(session: session, command: command)
            }
            // Measure the whole row before allowing the title or option
            // labels to compress. Dense options get their own row below.
            .fixedSize(horizontal: true, vertical: false)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    title
                    Spacer(minLength: 0)
                }
                OptionsBar(session: session, command: command)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 58)
    }

    private var title: some View {
        Group {
            Button(action: actions.back) {
                Label("Tools", systemImage: "chevron.left")
                    .font(.system(size: 12.5))
            }
            .buttonStyle(.borderless)
            .help("Back to tools (Esc)")
            CommandIconView(icon: command.icon, isSelected: true)
            Text(command.title)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
        }
    }
}

private struct ToolBody: View {
    let session: PaletteSession
    let command: ToolCommand
    let actions: PaletteActions
    let focus: PaletteFocus
    let isNarrow: Bool

    var body: some View {
        if command.isGenerator {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    PanelLabel("Result")
                    Spacer()
                    StatusBadge(preview: session.preview)
                }
                ResultContent(session: session, command: command, actions: actions, focus: focus)
                if let title = command.regenerateTitle {
                    Button {
                        actions.regenerate()
                    } label: {
                        Label(title, systemImage: "arrow.clockwise")
                    }
                    .keyboardShortcut("r", modifiers: .command)
                }
            }
            .padding(16)
        } else {
            let layout = isNarrow ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
            layout {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        PanelLabel("Input")
                        Spacer()
                        if let payload = session.payload {
                            Text(ByteCountText.string(payload.byteCount))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let payload = session.payload, payload.exceedsLimit {
                        EmptyState(
                            symbol: "exclamationmark.triangle",
                            title: "Input too large to edit",
                            message: "\(ByteCountText.string(payload.byteCount)) is over the \(ByteCountText.string(session.limits.maxInputBytes)) limit. Clear it and paste a smaller selection.",
                            tint: Theme.warning
                        )
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.well))
                    } else {
                        InputEditor(
                            text: session.payload?.text ?? "",
                            accessibilityLabel: "Input for \(command.title)",
                            focus: focus,
                            onChange: { session.editInput($0) }
                        )
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.well))
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        PanelLabel("Result")
                        Spacer()
                        StatusBadge(preview: session.preview)
                    }
                    ResultContent(session: session, command: command, actions: actions, focus: focus)
                }
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private struct PanelLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Results

private struct ResultContent: View {
    let session: PaletteSession
    let command: ToolCommand
    let actions: PaletteActions
    let focus: PaletteFocus?

    var body: some View {
        // One branch for ready results and pending ones that still show the
        // previous result, so re-evaluation updates the same views instead of
        // replacing them (which lost the result's scroll position). New input
        // (not an edit) gets new views, which start at the top.
        if let shown = shownResult {
            content(for: shown.result, dimmed: shown.dimmed)
                .id(session.inputGeneration)
        } else if session.preview.isPending {
            DelayedProgress()
        } else {
            EmptyState(symbol: "questionmark", title: "No result", message: "")
        }
    }

    private var shownResult: (result: ToolResult, dimmed: Bool)? {
        switch session.preview {
        case .ready(let result): (result, false)
        case .pending(let previous?): (previous, true)
        case .pending(nil), .none: nil
        }
    }

    @ViewBuilder
    private func content(for result: ToolResult, dimmed: Bool) -> some View {
        switch result {
        case .needsInput(let message):
            EmptyState(
                symbol: "doc.on.clipboard",
                title: session.isInTool ? "Type or paste input" : "Paste input to preview",
                message: session.isInTool ? message : "\(message) Press ⌘V to attach the clipboard, or ↵ to open the editor."
            )
        case .success(let output):
            SuccessView(output: output, command: command, dimmed: dimmed, actions: actions, focus: focus, isTool: session.isInTool)
                .id(command.id)
        case .invalid(let diagnostic):
            ErrorView(diagnostic: diagnostic, input: session.payload?.text)
        case .unsupported(let message):
            EmptyState(symbol: "nosign", title: "Not supported", message: message, tint: Theme.warning)
        case .tooLarge(let message):
            EmptyState(symbol: "exclamationmark.triangle", title: "Too large", message: message, tint: Theme.warning)
        }
    }
}

private struct SuccessView: View {
    let output: ToolOutput
    let command: ToolCommand
    let dimmed: Bool
    let actions: PaletteActions
    let focus: PaletteFocus?
    var isTool = false
    @State private var warningsExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let swatch = output.swatch {
                SwatchView(swatch: swatch, label: output.primaryText)
            }
            if output.presentation == .fields {
                FieldsList(fields: output.fields, actions: actions)
                    .frame(maxHeight: FieldsList.idealHeight(for: output.fields))
                    .opacity(dimmed ? 0.45 : 1)
                Spacer(minLength: 0)
            } else if isShortResult {
                // One or two short lines: a compact well, fields below at their natural size.
                resultText
                    .frame(height: lineCount == 1 ? 46 : 66)
                if !output.fields.isEmpty {
                    FieldsList(fields: output.fields, actions: actions)
                        .frame(maxHeight: FieldsList.idealHeight(for: output.fields))
                        .opacity(dimmed ? 0.45 : 1)
                }
                Spacer(minLength: 0)
            } else {
                resultText
                    .frame(minHeight: 60, maxHeight: .infinity)
                if !output.fields.isEmpty {
                    FieldsList(fields: output.fields, actions: actions)
                        .frame(height: fieldsHeight)
                        .opacity(dimmed ? 0.45 : 1)
                }
            }
            WarningsView(warnings: output.warnings, isExpanded: $warningsExpanded)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: output.warnings) { _, _ in warningsExpanded = false }
        .onChange(of: dimmed) { _, pending in
            if pending { warningsExpanded = false }
        }
    }

    private var resultText: some View {
        ResultTextView(
            text: output.primaryText,
            syntax: output.syntax,
            identity: command.id,
            sensitivity: output.sensitivity,
            dimmed: dimmed,
            accessibilityLabel: "Result of \(command.title)",
            focus: focus
        )
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.well))
    }

    /// Lines in the primary text, counted in the first few kilobytes only.
    private var lineCount: Int {
        var lines = 1
        for unit in output.primaryText.utf8.prefix(4096) where unit == 0x0A { lines += 1 }
        return lines
    }

    private var isShortResult: Bool {
        lineCount <= 2 && output.primaryText.utf8.count <= 240
    }

    /// Room for a few field rows below a long result, more in the tool view.
    private var fieldsHeight: CGFloat {
        min(FieldsList.idealHeight(for: output.fields), isTool ? 230 : 118)
    }
}

private struct FieldsList: View {
    let fields: [ResultField]
    let actions: PaletteActions

    /// Approximate content height, so short lists don't stretch to fill the pane.
    static func idealHeight(for fields: [ResultField]) -> CGFloat {
        var height: CGFloat = 8
        for field in fields {
            let lines = min(4, field.value.reduce(1) { $1 == "\n" ? $0 + 1 : $0 })
            height += 33 + CGFloat(lines - 1) * 16 + (field.note == nil ? 0 : 15)
        }
        return height
    }

    var body: some View {
        if fields.isEmpty {
            EmptyState(symbol: "list.bullet", title: "Nothing to show", message: "")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(fields) { field in
                        FieldRow(field: field, actions: actions)
                        if field.id != fields.last?.id {
                            Divider().opacity(0.5)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.well))
        }
    }
}

private struct FieldRow: View {
    let field: ResultField
    let actions: PaletteActions

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            // Combine only the text so the Copy button stays a separate
            // accessibility element with its own label and action.
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(field.label)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 112, alignment: .leading)
                    .lineLimit(2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(field.value.isEmpty ? "(empty)" : field.value)
                        .font(field.isMonospaced ? .system(size: 12, design: .monospaced) : .system(size: 12.5))
                        .foregroundStyle(field.value.isEmpty ? Color.secondary : toneColor)
                        .lineLimit(4)
                        .textSelection(.enabled)
                    if let note = field.note {
                        Text(note)
                            .font(.system(size: 11))
                            .foregroundStyle(field.tone == .warning ? Theme.warning : Color.secondary)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 4)
            if field.isCopyable {
                Button {
                    actions.copyField(field.id)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .help("Copy \(field.label)")
                .accessibilityLabel("Copy \(field.label)")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var toneColor: Color {
        switch field.tone {
        case .normal: .primary
        case .success: Theme.success
        case .warning: Theme.warning
        }
    }
}

private struct SwatchView: View {
    let swatch: ColorSwatch
    let label: String

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(.sRGB, red: swatch.red, green: swatch.green, blue: swatch.blue, opacity: swatch.alpha))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.hairline))
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .accessibilityElement(children: .ignore)
        .accessibilityLabel("Color swatch \(label)")
    }
}

private struct ErrorView: View {
    let diagnostic: ToolDiagnostic
    let input: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(diagnostic.message)
                    .font(.system(size: 13, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "xmark.octagon.fill").foregroundStyle(Theme.failure)
            }
            if let location = diagnostic.location {
                Text("Line \(location.line), column \(location.column)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                if let input, let context = ErrorContext(text: input, location: location) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(context.line)
                        Text(context.caret).foregroundStyle(Theme.failure)
                    }
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.well))
                    .accessibilityHidden(true)
                }
            }
            Text("Copy is unavailable until the input is fixed.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
}

/// The input line containing an error, windowed around the column, with a caret.
struct ErrorContext: Equatable {
    let line: String
    let caret: String

    init?(text: String, location: TextLocation, width: Int = 64) {
        var currentLine = 1
        var lineScalars: [Unicode.Scalar] = []
        var previousWasCR = false
        for scalar in text.unicodeScalars {
            if scalar == "\n" && previousWasCR {
                previousWasCR = false
                continue
            }
            previousWasCR = scalar == "\r"
            if scalar == "\n" || scalar == "\r" {
                if currentLine == location.line { break }
                currentLine += 1
                continue
            }
            if currentLine == location.line {
                lineScalars.append(scalar == "\t" ? " " : scalar)
            } else if currentLine > location.line {
                break
            }
        }
        guard currentLine == location.line else { return nil }
        let column = max(0, location.column - 1)
        let start = max(0, min(column - width / 2, lineScalars.count - width))
        let end = min(lineScalars.count, start + width)
        var visible = String(String.UnicodeScalarView(lineScalars[start..<max(start, end)]))
        var caretOffset = column - start
        if start > 0 {
            visible = "…" + visible
            caretOffset += 1
        }
        if end < lineScalars.count { visible += "…" }
        line = visible.isEmpty ? " " : visible
        caret = String(repeating: " ", count: max(0, caretOffset)) + "^"
    }
}

private struct StatusBadge: View {
    let preview: PreviewState

    var body: some View {
        Group {
            switch preview {
            case .none:
                EmptyView()
            case .pending:
                HStack(spacing: 5) {
                    ProgressView().controlSize(.mini)
                    Text("Working…")
                }
                .foregroundStyle(.secondary)
            case .ready(let result):
                switch result {
                case .success(let output):
                    switch output.statusTone {
                    case .success:
                        Label(output.status, systemImage: "checkmark.circle.fill").foregroundStyle(Theme.success)
                    case .warning:
                        Label(output.status, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
                    case .normal:
                        Text(output.status).foregroundStyle(.secondary)
                    }
                case .invalid:
                    Label("Can’t copy", systemImage: "xmark.circle.fill").foregroundStyle(Theme.failure)
                case .needsInput:
                    Text("Needs input").foregroundStyle(.secondary)
                case .unsupported:
                    Label("Unsupported", systemImage: "nosign").foregroundStyle(Theme.warning)
                case .tooLarge:
                    Label("Too large", systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
                }
            }
        }
        .font(.system(size: 11.5, weight: .medium))
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Options

private struct OptionsBar: View {
    let session: PaletteSession
    let command: ToolCommand

    var body: some View {
        if !command.options.isEmpty {
            ViewThatFits(in: .horizontal) {
                optionRow(presentation: .segments)
                optionRow(presentation: .menus)
            }
        }
    }

    private enum Presentation { case segments, menus }

    private func optionRow(presentation: Presentation) -> some View {
        let options = session.options(for: command.id)
        return HStack(spacing: 12) {
            ForEach(command.options) { option in
                switch option.kind {
                case .choice(let choices, let defaultID):
                    let picker = Picker(option.label, selection: Binding(
                        get: { options.choice(option.id, default: defaultID) },
                        set: { session.setOption(option.id, to: $0, for: command.id) }
                    )) {
                        ForEach(choices) { choice in
                            Text(choice.label).tag(choice.id)
                        }
                    }
                    .controlSize(.small)
                    .help(option.label)
                    .accessibilityLabel(option.label)

                    switch presentation {
                    case .segments: picker.pickerStyle(.segmented)
                    case .menus: picker.pickerStyle(.menu)
                    }
                case .toggle(let defaultValue):
                    Toggle(option.label, isOn: Binding(
                        get: { options.flag(option.id, default: defaultValue) },
                        set: { session.setOption(option.id, to: $0 ? "true" : "false", for: command.id) }
                    ))
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .font(.system(size: 11.5))
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - Footer and notices

private struct FooterBar: View {
    let session: PaletteSession
    let actions: PaletteActions
    @State private var anchor = AnchorBox()

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                if session.isInTool {
                    hint("esc", "Back")
                } else {
                    hint("↑↓", "Navigate")
                    hint("↵", "Open")
                    hint("esc", "Close")
                }
            }
            .accessibilityHidden(true)
            Spacer(minLength: 8)
            Button {
                actions.showActions(from: anchor.view)
            } label: {
                HStack(spacing: 6) {
                    Text("Actions")
                    Keycap("⌘K")
                }
            }
            .buttonStyle(.borderless)
            .background(AnchorView(box: anchor))
            .help("More actions (⌘K)")
            .accessibilityLabel("Actions")
            Button(action: actions.copyAndClose) {
                HStack(spacing: 8) {
                    Text(session.copyTitle)
                    Text("⌘↵").font(.system(size: 11, weight: .medium)).opacity(0.8)
                }
                .padding(.horizontal, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!session.canCopy)
            .accessibilityLabel(session.copyTitle)
            .accessibilityHint(session.canCopy ? "Copies the result and returns to your previous app" : "Unavailable until there is a valid result")
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Keycap(key)
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
    }
}

/// Holds a reference to an AppKit view so menus can be positioned at it.
@MainActor
final class AnchorBox {
    weak var view: NSView?
}

private struct AnchorView: NSViewRepresentable {
    let box: AnchorBox

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        box.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        box.view = view
    }
}

private struct NoticeView: View {
    let session: PaletteSession

    var body: some View {
        if let notice = session.notice {
            Label(notice.message, systemImage: symbol(for: notice.kind))
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(.regularMaterial))
                .overlay(Capsule().strokeBorder(Theme.hairline))
                .foregroundStyle(notice.kind == .error ? Theme.failure : Color.primary)
                .transition(.opacity)
                .task(id: notice.id) {
                    try? await Task.sleep(for: .seconds(notice.kind == .error ? 4 : 2))
                    session.dismissNotice(notice.id)
                }
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    private func symbol(for kind: SessionNotice.Kind) -> String {
        switch kind {
        case .info: "info.circle"
        case .success: "checkmark.circle.fill"
        case .error: "exclamationmark.circle.fill"
        }
    }
}

// MARK: - Small pieces

struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var tint: Color = .secondary

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 13, weight: .medium))
            if !message.isEmpty {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Shows a spinner only if evaluation takes longer than a moment, to avoid flicker.
private struct DelayedProgress: View {
    @State private var visible = false

    var body: some View {
        ProgressView()
            .controlSize(.small)
            .opacity(visible ? 1 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task {
                try? await Task.sleep(for: .milliseconds(150))
                visible = true
            }
    }
}

/// Speaks result changes once evaluation settles.
@MainActor
enum Announcer {
    static func announce(preview: PreviewState, session: PaletteSession) {
        guard case .ready(let result) = preview else { return }
        let message: String
        switch result {
        case .success(let output): message = output.status
        case .invalid(let diagnostic): message = "Error. \(diagnostic.description)"
        case .needsInput: return
        case .unsupported(let text), .tooLarge(let text): message = text
        }
        guard let window = NSApp.windows.first(where: { $0 is PalettePanel && $0.isVisible }) else { return }
        NSAccessibility.post(element: window, notification: .announcementRequested, userInfo: [
            .announcement: message,
            .priority: NSAccessibilityPriorityLevel.medium.rawValue,
        ])
    }
}
