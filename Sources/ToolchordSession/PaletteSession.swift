import Foundation
import Observation
import ToolchordCore

/// Text attached to the session, with where it came from and what it looks like.
public struct Payload: Sendable, Equatable {
    public enum Source: Sendable, Equatable {
        /// Pasted into search with ⌘V or the Paste action.
        case pasted
        /// Typed or edited in a tool's input editor.
        case edited
    }

    public var text: String
    public var source: Source
    public var profile: InputProfile

    public init(text: String, source: Source, limits: ToolLimits = .standard) {
        self.text = text
        self.source = source
        self.profile = InputDetector.profile(for: text, maxBytes: limits.maxInputBytes)
        self.exceedsLimit = profile.byteCount > limits.maxInputBytes
    }

    public var byteCount: Int { profile.byteCount }
    /// Larger than the input limit: shown as an error, not edited or evaluated.
    public let exceedsLimit: Bool
}

public enum PaletteMode: Sendable, Equatable {
    /// Search field and command list with a preview.
    case search
    /// The selected command opened with an input editor and full result.
    case tool(String)
}

/// What the preview shows for the selected command.
public enum PreviewState: Sendable, Equatable {
    /// No command is selected (for example, no search results).
    case none
    /// Evaluation is in flight. `previous` is the last result for the same
    /// command, which the UI may show dimmed. Copy is disabled.
    case pending(previous: ToolResult?)
    case ready(ToolResult)

    public var result: ToolResult? {
        switch self {
        case .ready(let result): result
        case .pending(let previous): previous
        case .none: nil
        }
    }

    public var isPending: Bool {
        if case .pending = self { return true }
        return false
    }
}

/// A short-lived message such as "Copied exp" or a paste problem.
public struct SessionNotice: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        case info
        case success
        case error
    }

    public let id: Int
    public let kind: Kind
    public let message: String
}

public enum CopyOutcome: Sendable, Equatable {
    case copied
    /// Nothing copyable: pending, invalid, or stale.
    case unavailable
    /// The clipboard write failed; the panel stays open.
    case failed
}

public enum EscapeOutcome: Sendable, Equatable {
    case closedActions
    case returnedToSearch
    /// Root Escape: the caller dismisses the panel and ends the session.
    case dismiss
}

/// The palette's in-memory draft and the single source of truth for the UI.
///
/// The draft holds the query, payload, selection, options, generated values,
/// result, and pending work. Back and the Actions menu preserve it; ``end()``
/// retires it (dismissal, Copy & Close, app switch, screen lock, quit).
/// Nothing in the draft is persisted.
///
/// Every change to input, command, options, or a generated value increments
/// the revision and disables copying before new work is scheduled. A
/// completion is published only if its session ID and revision are still
/// current, so stale results never appear and never reach the clipboard.
@MainActor
@Observable
public final class PaletteSession {
    public let catalog: [ToolCommand]
    public let limits: ToolLimits

    public private(set) var sessionID = UUID()
    public private(set) var query = ""
    public private(set) var payload: Payload?
    public private(set) var listing: CommandListing
    public private(set) var selectedID: String?
    public private(set) var mode: PaletteMode = .search
    public private(set) var preview: PreviewState = .none
    public private(set) var isActionsMenuOpen = false
    public private(set) var notice: SessionNotice?
    /// Per-command options chosen in this session.
    public private(set) var chosenOptions: [String: ToolOptions] = [:]
    /// Generated values, such as the UUID on screen, keyed by command ID.
    public private(set) var seeds: [String: String] = [:]

    @ObservationIgnored private let commandsByID: [String: ToolCommand]
    @ObservationIgnored private let evaluator: any ToolEvaluating
    @ObservationIgnored private let clipboard: any ClipboardWriting
    @ObservationIgnored private let preferences: any SessionPreferences
    @ObservationIgnored private let clock: @Sendable () -> Date
    @ObservationIgnored private let timeZone: @Sendable () -> TimeZone
    @ObservationIgnored private var selectionIsExplicit = false
    @ObservationIgnored private(set) var revision = 0
    @ObservationIgnored private var evaluationTask: Task<Void, Never>?
    @ObservationIgnored private var lastReady: (commandID: String, result: ToolResult)?
    @ObservationIgnored private var noticeCounter = 0
    /// Set after init and ``end()``; cleared by ``activate()`` or any change.
    @ObservationIgnored private var needsActivation = true
    /// Delay before evaluating edits typed in the input editor.
    @ObservationIgnored public var editDebounce: Duration = .milliseconds(60)

    public init(
        catalog: [ToolCommand] = ToolCatalog.commands,
        evaluator: any ToolEvaluating = BackgroundEvaluator(),
        clipboard: any ClipboardWriting,
        preferences: any SessionPreferences,
        limits: ToolLimits = .standard,
        clock: @escaping @Sendable () -> Date = { Date() },
        timeZone: @escaping @Sendable () -> TimeZone = { TimeZone.current }
    ) {
        self.catalog = catalog
        self.commandsByID = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.evaluator = evaluator
        self.clipboard = clipboard
        self.preferences = preferences
        self.limits = limits
        self.clock = clock
        self.timeZone = timeZone
        self.listing = CommandListing(sections: [])
        rebuildListing(.reset, evaluate: false)
    }

    /// Starts work for a fresh session (for example when the panel opens):
    /// generates values for and evaluates the initial selection. Does
    /// nothing if the session already has work or results.
    public func activate() {
        guard needsActivation else { return }
        needsActivation = false
        selectionDidChange()
    }

    // MARK: - Derived state

    public var selectedCommand: ToolCommand? { selectedID.flatMap { commandsByID[$0] } }

    public func command(_ id: String) -> ToolCommand? { commandsByID[id] }

    public var profile: InputProfile { payload?.profile ?? .none }

    public var isInTool: Bool {
        if case .tool = mode { return true }
        return false
    }

    /// Resolved options for a command: session choices over preferences over built-in defaults.
    public func options(for commandID: String) -> ToolOptions {
        guard let command = commandsByID[commandID] else { return ToolOptions() }
        if let chosen = chosenOptions[commandID] { return chosen.resolved(for: command.options) }
        return preferences.defaultOptions(for: command).resolved(for: command.options)
    }

    /// The successful output that Copy & Close would copy, if any.
    public var copyableOutput: ToolOutput? {
        if case .ready(let result) = preview { return result.output }
        return nil
    }

    public var canCopy: Bool { copyableOutput != nil }

    /// "Copy JSON & Close" for the selected command and its options.
    public var copyTitle: String {
        guard let command = selectedCommand else { return "Copy & Close" }
        return command.copyAndCloseTitle(options: options(for: command.id))
    }

    /// Short single-line pasted text that names a command can move into search.
    public var canUseAsSearchText: Bool {
        guard let text = payload?.text else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 80, !trimmed.contains(where: \.isNewline) else { return false }
        return CommandSearch.plausiblyNamesCommand(trimmed, in: catalog)
    }

    /// Whether a command needs input that is not attached.
    public func isWaitingForInput(_ command: ToolCommand) -> Bool {
        command.input == .text && payload == nil
    }

    // MARK: - Search and selection

    public func setQuery(_ text: String) {
        guard text != query else { return }
        query = text
        rebuildListing(.query)
    }

    /// Moves the selection by `delta` rows, clamped to the list.
    public func moveSelection(by delta: Int) {
        let ids = listing.orderedIDs
        guard !ids.isEmpty else { return }
        let current = selectedID.flatMap { ids.firstIndex(of: $0) }
        let target: Int
        if let current {
            target = min(max(current + delta, 0), ids.count - 1)
        } else {
            target = delta >= 0 ? 0 : ids.count - 1
        }
        select(ids[target])
    }

    public func selectFirst() {
        if let first = listing.orderedIDs.first { select(first) }
    }

    public func selectLast() {
        if let last = listing.orderedIDs.last { select(last) }
    }

    /// Selects a listed command explicitly (arrow keys or a click).
    public func select(_ commandID: String) {
        guard listing.contains(commandID) else { return }
        selectionIsExplicit = true
        guard commandID != selectedID else { return }
        selectedID = commandID
        selectionDidChange()
    }

    /// Opens the selected command in the expanded tool view (Return).
    public func openSelected() {
        guard let id = selectedID else { return }
        isActionsMenuOpen = false
        mode = .tool(id)
    }

    /// Returns from the tool view to search with the draft intact.
    public func back() {
        isActionsMenuOpen = false
        mode = .search
    }

    // MARK: - Input

    /// Attaches pasted text, replacing any attachment and keeping the query.
    public func attach(_ text: String) {
        payload = Payload(text: text, source: .pasted, limits: limits)
        if !rebuildListing(.payload) { scheduleEvaluation() }
    }

    /// Reports a paste that contained no text; the current payload is kept.
    public func rejectPaste(reason: String = "The clipboard doesn’t contain text. Your input is unchanged.") {
        post(.error, reason)
    }

    /// Replaces the payload with text edited in the tool's input editor.
    public func editInput(_ text: String) {
        // Compare bytes: canonically equivalent edits can change tool output.
        if let current = payload?.text, current.hasSameUTF8(as: text) { return }
        payload = Payload(text: text, source: .edited, limits: limits)
        if !rebuildListing(.payload) { scheduleEvaluation(after: editDebounce) }
    }

    /// Removes the attachment and immediately invalidates its result.
    public func clearInput() {
        guard payload != nil else { return }
        payload = nil
        isActionsMenuOpen = false
        if !rebuildListing(.payload) { scheduleEvaluation() }
    }

    /// Moves short pasted text that names a command into search.
    public func useAsSearchText() {
        guard canUseAsSearchText, let text = payload?.text else { return }
        payload = nil
        isActionsMenuOpen = false
        mode = .search
        query = text.trimmingCharacters(in: .whitespaces)
        if !rebuildListing(.query) { scheduleEvaluation() }
    }

    // MARK: - Options and generated values

    public func setOption(_ optionID: String, to value: String, for commandID: String) {
        guard let command = commandsByID[commandID], let option = command.options.first(where: { $0.id == optionID }), option.accepts(value) else {
            return
        }
        var options = self.options(for: commandID)
        guard options.values[optionID] != value else { return }
        options = ToolOptions(options.values.merging([optionID: value]) { _, new in new })
        chosenOptions[commandID] = options
        if commandID == selectedID { scheduleEvaluation() }
    }

    /// Replaces the selected generator's value, such as a new UUID.
    public func regenerate() {
        guard let command = selectedCommand, let makeSeed = command.makeSeed else { return }
        isActionsMenuOpen = false
        seeds[command.id] = makeSeed(SeedContext(now: clock(), options: options(for: command.id)))
        scheduleEvaluation()
    }

    // MARK: - Actions menu

    public func toggleActionsMenu() { isActionsMenuOpen.toggle() }

    public func closeActionsMenu() { isActionsMenuOpen = false }

    /// Escape: close Actions, else leave the tool, else ask to dismiss.
    public func escape() -> EscapeOutcome {
        if isActionsMenuOpen {
            isActionsMenuOpen = false
            return .closedActions
        }
        if isInTool {
            back()
            return .returnedToSearch
        }
        return .dismiss
    }

    // MARK: - Copy

    /// Copies the visible successful primary result. The caller closes the
    /// panel and ends the session after `.copied` when the user chose
    /// Copy & Close; Copy without closing keeps the draft.
    @discardableResult
    public func copyPrimary() -> CopyOutcome {
        guard let output = copyableOutput, let command = selectedCommand else { return .unavailable }
        isActionsMenuOpen = false
        guard clipboard.writeText(output.primaryText, sensitivity: output.sensitivity) else {
            post(.error, "Couldn’t copy to the clipboard. Try again.")
            return .failed
        }
        preferences.recordUse(of: command.id)
        return .copied
    }

    /// Copies one result field and keeps the panel open.
    @discardableResult
    public func copyField(_ fieldID: String) -> CopyOutcome {
        guard let output = copyableOutput, let field = output.fields.first(where: { $0.id == fieldID && $0.isCopyable }) else {
            return .unavailable
        }
        guard clipboard.writeText(field.value, sensitivity: output.sensitivity) else {
            post(.error, "Couldn’t copy to the clipboard. Try again.")
            return .failed
        }
        if let id = selectedID { preferences.recordUse(of: id) }
        post(.success, "Copied \(field.label)")
        return .copied
    }

    /// Shows a confirmation after Copy without closing.
    public func confirmCopiedWithoutClosing() {
        post(.success, "Copied \(selectedCommand.map { $0.copyNoun(options(for: $0.id)) } ?? "result")")
    }

    // MARK: - Notices

    public func dismissNotice(_ id: Int) {
        if notice?.id == id { notice = nil }
    }

    private func post(_ kind: SessionNotice.Kind, _ message: String) {
        noticeCounter += 1
        notice = SessionNotice(id: noticeCounter, kind: kind, message: message)
    }

    /// Waits until the evaluation scheduled most recently has finished or
    /// been cancelled. For tests and snapshot rendering.
    public func waitForIdle() async {
        while let task = evaluationTask {
            await task.value
            if evaluationTask == task { break }
        }
    }

    // MARK: - Session lifetime

    /// Retires the draft: cancels pending work, clears every value, and
    /// starts a fresh session ID so no earlier completion can publish.
    public func end() {
        evaluationTask?.cancel()
        evaluationTask = nil
        sessionID = UUID()
        revision += 1
        query = ""
        payload = nil
        mode = .search
        isActionsMenuOpen = false
        notice = nil
        chosenOptions = [:]
        seeds = [:]
        lastReady = nil
        selectionIsExplicit = false
        preview = .none
        rebuildListing(.reset, evaluate: false)
    }

    // MARK: - Internals

    private enum ListingChange {
        case reset
        case query
        case payload
    }

    /// Rebuilds the list and updates the selection. Returns whether it
    /// scheduled an evaluation, so callers never schedule the same work twice.
    @discardableResult
    private func rebuildListing(_ change: ListingChange, evaluate: Bool = true) -> Bool {
        listing = CommandListing.make(query: query, profile: profile, catalog: catalog, recentIDs: preferences.recentCommandIDs)
        let previous = selectedID

        if isInTool {
            // The open tool keeps its command while its input is edited.
        } else {
            switch change {
            case .reset, .query:
                selectedID = listing.first
                selectionIsExplicit = false
            case .payload:
                let hasQuery = !CommandSearch.normalize(query).isEmpty
                if let previous, listing.contains(previous), hasQuery || (selectionIsExplicit && isCompatible(previous)) {
                    // Keep the user's choice.
                } else {
                    selectedID = listing.first
                    selectionIsExplicit = false
                }
            }
        }

        guard evaluate else {
            needsActivation = true
            return false
        }
        if selectedID != previous || change == .reset || needsActivation {
            selectionDidChange()
            return true
        }
        return false
    }

    /// An explicit selection survives new input unless that input has
    /// suggestions and the selection is not one of them.
    private func isCompatible(_ commandID: String) -> Bool {
        guard let command = commandsByID[commandID] else { return false }
        let hasSuggestions = listing.sections.first?.id == "suggested"
        return !hasSuggestions || command.affinity(profile) >= CommandListing.suggestionThreshold
    }

    private func selectionDidChange() {
        needsActivation = false
        isActionsMenuOpen = false
        if let command = selectedCommand, let makeSeed = command.makeSeed, seeds[command.id] == nil {
            seeds[command.id] = makeSeed(SeedContext(now: clock(), options: options(for: command.id)))
        }
        scheduleEvaluation()
    }

    private func makeRequest(for command: ToolCommand) -> ToolRequest {
        let input: ToolInput = command.input == .none ? .none : (payload.map { .text($0.text) } ?? .none)
        return ToolRequest(
            input: input,
            options: options(for: command.id),
            seed: seeds[command.id],
            now: clock(),
            timeZone: timeZone(),
            limits: limits
        )
    }

    private func scheduleEvaluation(after delay: Duration? = nil) {
        if needsActivation {
            // First work in a fresh session: evaluate (and seed) the selection.
            needsActivation = false
            if let command = selectedCommand, let makeSeed = command.makeSeed, seeds[command.id] == nil {
                seeds[command.id] = makeSeed(SeedContext(now: clock(), options: options(for: command.id)))
            }
        }
        // Disable copy before scheduling new work.
        revision += 1
        evaluationTask?.cancel()
        evaluationTask = nil

        guard let command = selectedCommand else {
            preview = .none
            return
        }

        let identity = (session: sessionID, revision: revision)
        let request = makeRequest(for: command)

        // Missing input needs no background work.
        if command.input == .text && request.input == .none {
            publish(command.id, command.run(request))
            return
        }

        let previous = lastReady?.commandID == command.id ? lastReady?.result : nil
        preview = .pending(previous: previous)

        let evaluator = self.evaluator
        evaluationTask = Task { [weak self] in
            if let delay {
                try? await Task.sleep(for: delay)
            }
            // Superseded before it started: never hand stale work to the evaluator.
            if Task.isCancelled { return }
            let result = await evaluator.evaluate(command, request)
            guard !Task.isCancelled, let self else { return }
            guard self.sessionID == identity.session, self.revision == identity.revision else { return }
            self.publish(command.id, result)
        }
    }

    private func publish(_ commandID: String, _ result: ToolResult) {
        lastReady = (commandID, result)
        preview = .ready(result)
    }
}
