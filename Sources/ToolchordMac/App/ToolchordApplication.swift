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
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let preferences = AppPreferences()
    private let clipboard = SystemClipboard()
    private lazy var model = AppModel(preferences: preferences)
    private let customTools = CustomToolLibrary()
    private lazy var session = PaletteSession(catalog: ToolCatalog.commands + [CustomToolCatalog.maker], clipboard: clipboard, preferences: preferences)
    private lazy var panelController = PanelController(session: session, clipboard: clipboard)
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var welcomeWindow: NSWindow?
    private var customToolWindow: NSWindow?
    private var customToolEditor: CustomToolEditorModel?
    private var preferencesObservation: Any?

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

        if !preferences.hasCompletedWelcome {
            showWelcome()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Opening the app again (Finder, Spotlight) shows Settings, which is
        // the way back when the menu bar icon is hidden.
        showSettings()
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
            let image = NSImage(systemSymbolName: "command.square", accessibilityDescription: "Toolchord")
            image?.isTemplate = true
            button.image = image
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
                string: "Developer tools a shortcut away. Everything runs on this Mac.",
                attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
            ),
        ])
    }

    // MARK: - Windows

    func showCustomToolEditor(editing id: String? = nil) {
        customTools.reload()
        if let editor = customToolEditor {
            editor.selectDocument(id ?? "new")
            editor.refreshAvailability()
        } else {
            let editor = CustomToolEditorModel(library: customTools, editing: id)
            let window = makeWindow(title: "Make Custom Tool", content: CustomToolEditorView(model: editor))
            window.styleMask.insert(.resizable)
            window.setContentSize(NSSize(width: 1020, height: 780))
            window.contentMinSize = NSSize(width: 820, height: 620)
            customToolEditor = editor
            customToolWindow = window
        }
        present(customToolWindow)
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
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === customToolWindow {
            customToolEditor?.clearSample()
            customToolEditor = nil
            customToolWindow = nil
        }
        if (notification.object as? NSWindow) === welcomeWindow {
            preferences.hasCompletedWelcome = true
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === customToolWindow, customToolEditor?.isDirty == true else { return true }
        let alert = NSAlert()
        alert.messageText = "Discard your custom tool changes?"
        alert.informativeText = "Your saved tool stays unchanged. Keep editing to save this draft."
        alert.addButton(withTitle: "Keep Editing")
        alert.addButton(withTitle: "Discard Changes")
        return alert.runModal() == .alertSecondButtonReturn
    }
}

/// The main menu, used while Settings or the welcome window is active, so
/// standard editing shortcuts work in their text fields.
@MainActor
enum MainMenu {
    static func make(target: AppDelegate) -> NSMenu {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Toolchord")
        let about = NSMenuItem(title: "About Toolchord", action: #selector(AppDelegate.showAbout), keyEquivalent: "")
        about.target = target
        appMenu.addItem(about)
        appMenu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(AppDelegate.showSettingsAction), keyEquivalent: ",")
        settings.target = target
        appMenu.addItem(settings)
        let makeTool = NSMenuItem(title: "Make Custom Tool…", action: #selector(AppDelegate.showCustomToolEditorAction), keyEquivalent: "")
        makeTool.target = target
        appMenu.addItem(makeTool)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Hide Toolchord", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(NSMenuItem(title: "Quit Toolchord", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = editMenu
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        return main
    }
}
