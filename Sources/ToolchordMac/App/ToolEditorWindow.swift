import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ToolchordCore

extension UTType {
    static let toolchordTool = UTType(exportedAs: "ch.lkmc.toolchord.tool", conformingTo: .json)
}

/// One authoring workspace for the local library. Imported files are working
/// copies. Only an explicit export writes a portable file.
@MainActor
final class ToolEditorWindow: NSWindowController, NSWindowDelegate, NSToolbarDelegate, NSToolbarItemValidation, NSMenuItemValidation {
    let editor: CustomToolEditorModel
    private let workspace = CustomToolWorkspace()
    private let didClose: () -> Void

    init(library: CustomToolLibrary, didClose: @escaping () -> Void) {
        editor = CustomToolEditorModel(library: library)
        self.didClose = didClose
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        super.init(window: window)
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.tabbingMode = .disallowed
        window.contentMinSize = NSSize(width: 820, height: 540)
        window.contentViewController = NSHostingController(rootView:
            CustomToolEditorView(model: editor, workspace: workspace, onSelect: { [weak self] id in
                self?.select(id)
            }, onOpenFile: { [weak self] url in self?.open(url) }))
        window.toolbarStyle = .unified
        let toolbar = NSToolbar(identifier: "Toolchord.ToolLibrary")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame.size ?? NSSize(width: 1120, height: 800)
        window.setContentSize(NSSize(width: min(1120, visible.width), height: min(720, visible.height - 64)))
        window.center()
        window.setFrameAutosaveName("Toolchord.ToolLibrary")
        _ = editor.restoreRecoveryIfAvailable()
        observeEditor()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func windowWillClose(_ notification: Notification) {
        editor.flushRecovery()
        editor.clearSample()
        didClose()
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { editor.undoManager }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard editor.isDirty else { return true }
        confirmLeaving { if $0 { sender.close() } }
        return false
    }

    func select(_ id: String, forceNew: Bool = false) {
        guard forceNew || id != editor.documentID else { return }
        confirmLeaving { [weak self] proceed in
            guard proceed, let self else { return }
            editor.cancelWork()
            if forceNew && editor.documentID == "new" { editor.discardDraft() }
            editor.selectDocument(id)
        }
    }

    func confirmLeaving(_ completion: @escaping (Bool) -> Void) {
        guard editor.isDirty else { completion(true); return }
        guard let window, window.attachedSheet == nil else { completion(false); return }
        let alert = NSAlert()
        alert.messageText = "Save changes to “\(editor.definition.title)”?"
        alert.informativeText = editor.hasPendingDescription
            ? "There is an unused description. Keep editing to generate it, or discard it with the draft."
            : "Save adds the tested tool to your library. Run the current sample before saving."
        let canSave = editor.canSave && !editor.hasPendingDescription
        let positive = alert.addButton(withTitle: canSave ? "Save" : "Keep Editing")
        if !canSave { positive.keyEquivalent = "\u{1b}" }
        alert.addButton(withTitle: "Discard Changes").hasDestructiveAction = true
        if canSave { alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}" }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { completion(false); return }
            switch response {
            case .alertFirstButtonReturn where canSave: completion(editor.save())
            case .alertSecondButtonReturn:
                editor.discardDraft()
                completion(true)
            default: completion(false)
            }
        }
    }

    func chooseFile() {
        guard let window, window.attachedSheet == nil else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.toolchordTool, .json]
        panel.prompt = "Open Tool"
        panel.beginSheetModal(for: window) { [weak self] response in
            if response == .OK, let url = panel.url { self?.open(url) }
        }
    }

    func open(_ url: URL) {
        confirmLeaving { [weak self] proceed in
            guard proceed, let self else { return }
            do {
                editor.cancelWork()
                try editor.openTool(from: url)
                NSDocumentController.shared.noteNewRecentDocumentURL(url)
            } catch { showFileError(error) }
        }
    }

    func showFileError(_ error: any Error) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "Couldn’t complete the file operation"
        alert.informativeText = (error as? ToolDiagnostic)?.description ?? error.localizedDescription
        alert.beginSheetModal(for: window)
    }

    @objc func exportTool() {
        guard let window, window.attachedSheet == nil else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.toolchordTool]
        panel.nameFieldStringValue = editor.definition.title + ".toolchord"
        panel.prompt = "Export"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                try editor.exportTool(to: url)
                NSDocumentController.shared.noteNewRecentDocumentURL(url)
            } catch { showFileError(error) }
        }
    }

    @objc func runSample() { workspace.showsInspector = true; editor.runSample() }
    @objc func saveTool() { _ = editor.save() }
    @objc func generateTool() {
        guard canPerform(#selector(generateTool)) else { return }
        editor.generate()
    }
    @objc func revertTool() { editor.revert() }
    @objc func cancelOperationInEditor() { editor.cancelWork() }
    @objc func toggleInspector() { workspace.showsInspector.toggle() }
    @objc func toggleLibrary() { workspace.showsSidebar.toggle() }

    private func observeEditor() {
        withObservationTracking {
            window?.title = editor.definition.title.isEmpty ? "Untitled Tool" : editor.definition.title
            window?.subtitle = "Tool Library"
            window?.isDocumentEdited = editor.isDirty
            _ = editor.canSave
            _ = editor.isBusy
            _ = workspace.hasPendingProviderEdits
            _ = workspace.showsInspector
            _ = workspace.showsSidebar
            window?.toolbar?.validateVisibleItems()
        } onChange: { [weak self] in Task { @MainActor in self?.observeEditor() } }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(toggleLibrary): item.title = workspace.showsSidebar ? "Hide Tool Library" : "Show Tool Library"
        case #selector(toggleInspector): item.title = workspace.showsInspector ? "Hide Sample Inspector" : "Show Sample Inspector"
        default: break
        }
        return canPerform(item.action)
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool { canPerform(item.action) }

    private func canPerform(_ action: Selector?) -> Bool {
        guard window?.attachedSheet == nil else { return false }
        switch action {
        case #selector(saveTool): return editor.canSave
        case #selector(cancelOperationInEditor): return editor.isBusy
        case #selector(revertTool): return editor.isDirty
        case #selector(generateTool): return !workspace.hasPendingProviderEdits && !editor.isBusy && editor.hasPendingDescription && editor.unavailableReason == nil
        case #selector(exportTool), #selector(runSample): return !editor.isBusy
        default: return true
        }
    }

    private static let toolbarCommands: [(id: NSToolbarItem.Identifier, label: String, symbol: String, action: Selector)] = [
        (.init("library"), "Tool Library", "sidebar.left", #selector(toggleLibrary)),
        (.init("run"), "Run Sample", "play.fill", #selector(runSample)),
        (.init("save"), "Save to Tool Library", "tray.and.arrow.down", #selector(saveTool)),
        (.init("inspector"), "Sample Inspector", "sidebar.right", #selector(toggleInspector)),
        (.init("export"), "Export Tool", "square.and.arrow.up", #selector(exportTool)),
    ]

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Self.toolbarCommands.map(\.id) + [.space, .flexibleSpace]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.init("library"), .flexibleSpace, .init("run"), .init("save"), .space, .init("inspector")]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let command = Self.toolbarCommands.first(where: { $0.id == id }) else { return nil }
        let item = NSToolbarItem(itemIdentifier: id)
        item.label = command.label
        item.paletteLabel = command.label
        item.toolTip = command.label
        item.image = NSImage(systemSymbolName: command.symbol, accessibilityDescription: command.label)
        item.target = self
        item.action = command.action
        return item
    }
}
