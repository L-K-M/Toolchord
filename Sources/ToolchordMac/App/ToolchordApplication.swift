import AppKit
import SwiftUI
import ToolchordCore
import ToolchordSession

/// Entry point for the app target.
@MainActor
public enum ToolchordApplication {
    private static var delegate: AppDelegate?

    public static func run() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        Self.delegate = delegate
        application.delegate = delegate
        application.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private let preferences = AppPreferences()
    private let clipboard = SystemClipboard()
    private lazy var model = AppModel(preferences: preferences)
    private let customTools = CustomToolLibrary()
    private lazy var session = PaletteSession(catalog: ToolCatalog.commands + [CustomToolCatalog.maker], clipboard: clipboard, preferences: preferences)
    private lazy var panelController = PanelController(session: session, clipboard: clipboard)
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var welcomeWindow: NSWindow?
    private var workspace: ToolEditorWindow?
    private var pendingFile: URL?
    private var finishedLaunching = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Launch without taking focus from the frontmost app (for example at login).
        NSApp.setActivationPolicy(.prohibited)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = MainMenu.make(target: self)

        customTools.onChange = { [weak self] commands in self?.session.replaceCatalog(commands) }
        customTools.reload()
        HotKeyCenter.shared.onPress = { [weak self] in
            guard let self else { return }
            self.panelController.showOrFocus()
        }
        panelController.settingsHandler = { [weak self] in self?.showSettings() }
        panelController.customToolHandler = { [weak self] id in self?.showCustomToolEditor(editing: id) }
        model.onShortcutChange = { [weak self] in self?.updateStatusItem() }
        model.registerStoredShortcut()
        model.refreshLoginItem()

        updateStatusItem()
        observePreferences()
        observeTheme()

        finishedLaunching = true
        if let pendingFile {
            self.pendingFile = nil
            openFile(pendingFile)
        } else if let journal = customTools.recoveryURL, FileManager.default.fileExists(atPath: journal.path) {
            showCustomToolEditor()
        } else if !preferences.hasCompletedWelcome {
            showWelcome()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let window = workspace?.window {
            present(window)
        } else if welcomeWindow?.isVisible == true {
            present(welcomeWindow)
        } else if settingsWindow?.isVisible == true || !preferences.showsMenuBarIcon {
            showSettings()
        } else {
            openPalette()
        }
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: - Menu bar

    private func observePreferences() {
        withObservationTracking {
            _ = preferences.showsMenuBarIcon
            _ = preferences.shortcut
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateStatusItem()
                self?.observePreferences()
            }
        }
    }

    /// Keeps the palette drawn in the current theme and text sizes.
    private func observeTheme() {
        withObservationTracking {
            panelController.applyTheme(preferences.theme, textSizes: preferences.textSizes)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeTheme() }
        }
    }

    private func updateStatusItem() {
        guard preferences.showsMenuBarIcon else {
            if let statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
                self.statusItem = nil
            }
            return
        }
        let item = statusItem ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        if let button = item.button {
            let image = Bundle.module.url(forResource: "Wrench", withExtension: "svg").flatMap(NSImage.init(contentsOf:))
                ?? NSImage(systemSymbolName: "wrench.fill", accessibilityDescription: "Toolchord")
            image?.size = NSSize(width: 18, height: 18)
            image?.isTemplate = true
            button.image = image
            button.setAccessibilityLabel("Toolchord")
            button.toolTip = "Toolchord (\(preferences.shortcut.displayString))"
        }
        let menu = NSMenu()
        let open = NSMenuItem(title: "Open Toolchord", action: #selector(openPalette), keyEquivalent: "")
        open.target = self
        if model.isShortcutActive {
            open.title = "Open Toolchord   \(preferences.shortcut.displayString)"
        }
        menu.addItem(open)
        let makeTool = NSMenuItem(title: "Make Custom Tool…", action: #selector(showCustomToolEditorAction), keyEquivalent: "")
        makeTool.target = self
        menu.addItem(makeTool)
        if !model.isShortcutActive {
            let warning = NSMenuItem(title: "Shortcut not active — fix in Settings", action: #selector(showSettingsAction), keyEquivalent: "")
            warning.target = self
            menu.addItem(warning)
        }
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettingsAction), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let about = NSMenuItem(title: "About Toolchord", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Toolchord", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
    }

    @objc func openPalette() {
        // Let the status menu close before the panel takes key status.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.panelController.showOrFocus()
        }
    }

    @objc func showCustomToolEditorAction() { showCustomToolEditor() }

    @objc func showSettingsAction() {
        showSettings()
    }

    @objc func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(
                string: "Developer tools a shortcut away.",
                attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
            ),
        ])
    }

    // MARK: - Windows

    func showCustomToolEditor(editing id: String? = nil) {
        let controller = openWorkspace()
        if let id { controller.select(id) }
    }

    private func openWorkspace() -> ToolEditorWindow {
        customTools.reload()
        let controller = workspace ?? ToolEditorWindow(library: customTools) { [weak self] in
            self?.workspace = nil
            self?.updateActivationAfterClosing()
        }
        workspace = controller
        present(controller.window)
        controller.editor.refreshAvailability()
        return controller
    }

    @objc func newTool() { openWorkspace().select("new", forceNew: true) }
    @objc func openTool() { openWorkspace().chooseFile() }

    // Finder, Open Recent, and drag and drop all edit library working copies.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        guard urls.count == 1 else {
            DispatchQueue.main.async { [weak self] in
                self?.openWorkspace().showFileError(ToolDiagnostic("Choose one tool at a time to review it before adding it to your library."))
            }
            return
        }
        if finishedLaunching { openFile(url) }
        else { pendingFile = url }
    }

    private func openFile(_ url: URL) { openWorkspace().open(url) }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let urls = NSDocumentController.shared.recentDocumentURLs
        for url in urls {
            let item = menu.addItem(withTitle: url.lastPathComponent, action: #selector(openRecent(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = url
            item.toolTip = url.path
        }
        if !urls.isEmpty { menu.addItem(.separator()) }
        let clear = menu.addItem(withTitle: "Clear Menu", action: #selector(NSDocumentController.clearRecentDocuments(_:)), keyEquivalent: "")
        clear.target = NSDocumentController.shared
    }

    @objc private func openRecent(_ item: NSMenuItem) {
        if let url = item.representedObject as? URL { openFile(url) }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let workspace, workspace.editor.isDirty else { return .terminateNow }
        guard workspace.window?.attachedSheet == nil else {
            workspace.window?.attachedSheet?.makeKeyAndOrderFront(nil)
            return .terminateCancel
        }
        present(workspace.window)
        workspace.confirmLeaving { proceed in sender.reply(toApplicationShouldTerminate: proceed) }
        return .terminateLater
    }

    func showSettings() {
        if settingsWindow == nil {
            let tabs = SettingsTabViewController(model: model, clipboard: clipboard)
            let window = NSWindow(contentViewController: tabs)
            window.styleMask = [.titled, .closable]
            window.toolbarStyle = .preference
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            settingsWindow = window
        }
        present(settingsWindow)
    }

    private func showWelcome() {
        if welcomeWindow == nil {
            let view = WelcomeView(
                model: model,
                onTry: { [weak self] in
                    // Trying it counts as finishing onboarding; the window
                    // would otherwise be unreachable after the palette closes.
                    self?.finishWelcome()
                    self?.panelController.showOrFocus()
                },
                onDone: { [weak self] in self?.finishWelcome() }
            )
            welcomeWindow = makeWindow(title: "Welcome to Toolchord", content: view)
        }
        present(welcomeWindow)
    }

    private func finishWelcome() {
        preferences.hasCompletedWelcome = true
        welcomeWindow?.close()
    }

    private func makeWindow<Content: View>(title: String, content: Content) -> NSWindow {
        let controller = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: controller)
        window.title = title
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }

    private func present(_ window: NSWindow?) {
        guard let window else { return }
        if panelController.isVisible { panelController.dismiss(.system) }
        NSApp.setActivationPolicy(.regular)
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === welcomeWindow {
            preferences.hasCompletedWelcome = true
            welcomeWindow = nil
        }
        updateActivationAfterClosing()
    }

    private func updateActivationAfterClosing() {
        // AppKit sends willClose before removing the window from the screen.
        DispatchQueue.main.async { [weak self] in
            guard let self, workspace == nil,
                  settingsWindow?.isVisible != true, welcomeWindow?.isVisible != true else { return }
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
