import AppKit
import SwiftUI
import ToolchordCore
import ToolchordSession

/// Shows, focuses, and dismisses the palette, and connects the session to
/// the clipboard, menus, and window.
///
/// Dismissal (Escape at the root, Copy & Close, switching apps, screen lock,
/// sleep, user switching, quit) ends the session, which clears the draft and
/// retires pending work. Back and the Actions menu keep the draft.
@MainActor
public final class PanelController: NSObject, PaletteActions, PaletteCommandHandling {
    public enum DismissReason {
        /// Copy & Close or root Escape: return focus to the originating app.
        case completed
        /// The user moved focus elsewhere: leave it where they put it.
        case focusLost
        /// Lock, sleep, user switch, or quit.
        case system
    }

    let session: PaletteSession
    private let clipboard: SystemClipboard
    private let panel = PalettePanel()
    private let focus = PaletteFocus()
    private var hostingView: NSHostingView<PaletteView>!
    private var originApplication: NSRunningApplication?
    private var suppressResignDismissal = 0
    private var observers: [NSObjectProtocol] = []
    private var isNarrow = false

    /// Opens Settings; set by the app delegate.
    public var settingsHandler: (() -> Void)?

    public var isVisible: Bool { panel.isVisible }

    public init(session: PaletteSession, clipboard: SystemClipboard) {
        self.session = session
        self.clipboard = clipboard
        super.init()
        panel.commandHandler = self
        installContent()
        observeSystemEvents()
    }

    // MARK: - Showing

    /// Opens the palette, or refocuses it (keeping the draft) when it is already open.
    public func showOrFocus() {
        if panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
            focusCurrentView()
            return
        }
        let frontmost = NSWorkspace.shared.frontmostApplication
        originApplication = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : frontmost
        let screen = ScreenLocator.targetScreen(for: originApplication)
        let size = CGSize(width: Theme.panelWidth, height: session.isInTool ? Theme.toolHeight : Theme.searchHeight)
        let frame = ScreenLocator.frame(for: size, on: screen)
        updateLayout(width: frame.width)
        panel.setFrame(frame, display: false)
        panel.animationBehavior = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? .none : .utilityWindow
        session.activate()
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
        focusCurrentView()
    }

    public func dismiss(_ reason: DismissReason) {
        let wasVisible = panel.isVisible
        if wasVisible {
            suppressResignDismissal += 1
            panel.orderOut(nil)
            suppressResignDismissal -= 1
        }
        session.end()
        syncPanelSize()
        // A non-activating panel normally leaves the originating app active,
        // so focus returns by itself. Reactivate it only if Toolchord became
        // active meanwhile (for example through Settings).
        if wasVisible, reason == .completed, NSApp.isActive, let origin = originApplication, !origin.isTerminated {
            origin.activate()
        }
        originApplication = nil
    }

    private func installContent() {
        hostingView = NSHostingView(rootView: makeRootView())
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        let container: NSView
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = Theme.cornerRadius
            glass.style = .regular
            glass.contentView = hostingView
            container = glass
        } else {
            let effect = NSVisualEffectView()
            effect.material = .popover
            effect.state = .active
            effect.blendingMode = .behindWindow
            effect.maskImage = Self.roundedMask(radius: Theme.cornerRadius)
            effect.addSubview(hostingView)
            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: effect.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
            ])
            container = effect
        }
        panel.contentView = container
    }

    private func makeRootView() -> PaletteView {
        PaletteView(session: session, actions: self, focus: focus, isNarrow: isNarrow)
    }

    private func updateLayout(width: CGFloat) {
        let narrow = width < Theme.narrowWidth
        if narrow != isNarrow {
            isNarrow = narrow
            hostingView.rootView = makeRootView()
        }
    }

    static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    /// Grows or shrinks the panel for the current mode, keeping its top edge.
    private func syncPanelSize() {
        let height = session.isInTool ? Theme.toolHeight : Theme.searchHeight
        var frame = panel.frame
        guard abs(frame.height - height) > 0.5 else { return }
        let top = frame.maxY
        let visible = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? frame
        frame.size.height = min(height, visible.height - 32)
        frame.origin.y = max(visible.minY + 16, top - frame.height)
        let animate = panel.isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.setFrame(frame, display: panel.isVisible, animate: animate)
        panel.invalidateShadow()
    }

    private func focusCurrentView() {
        // Let SwiftUI create the views for the current mode first.
        DispatchQueue.main.async { [self] in
            if session.isInTool {
                if session.selectedCommand?.isGenerator == true {
                    focus.focusResult()
                } else {
                    focus.focusEditor()
                }
            } else {
                focus.focusSearch()
            }
        }
    }

    // MARK: - PaletteActions

    func openSelected() {
        guard session.selectedCommand != nil else {
            NSSound.beep()
            return
        }
        session.openSelected()
        syncPanelSize()
        focusCurrentView()
    }

    func back() {
        session.back()
        syncPanelSize()
        focusCurrentView()
    }

    func escape() {
        switch session.escape() {
        case .closedActions:
            break
        case .returnedToSearch:
            syncPanelSize()
            focusCurrentView()
        case .dismiss:
            dismiss(.completed)
        }
    }

    func copyAndClose() {
        switch session.copyPrimary() {
        case .copied:
            dismiss(.completed)
        case .failed:
            break
        case .unavailable:
            NSSound.beep()
        }
    }

    func copyWithoutClosing() {
        switch session.copyPrimary() {
        case .copied: session.confirmCopiedWithoutClosing()
        case .failed: break
        case .unavailable: NSSound.beep()
        }
    }

    func copyField(_ id: String) {
        session.copyField(id)
    }

    /// The ⌘V button: send a real paste command to the search field so the
    /// read goes through the same path as typing ⌘V.
    func pasteFromClipboard() {
        if session.isInTool {
            focus.focusEditor()
        } else {
            focus.focusSearch()
        }
        NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self)
    }

    func pasteIntoSearch() {
        guard let text = clipboard.readTextForPaste() else {
            session.rejectPaste()
            return
        }
        session.attach(text)
    }

    func regenerate() {
        guard session.selectedCommand?.makeSeed != nil else {
            NSSound.beep()
            return
        }
        session.regenerate()
    }

    func clearInput() {
        session.clearInput()
        if session.isInTool { focus.focusEditor() } else { focus.focusSearch() }
    }

    func openSettings() {
        dismiss(.system)
        settingsHandler?()
    }

    func dismissPanel() {
        dismiss(.completed)
    }

    func showActions() {
        showActions(from: nil)
    }

    func showActions(from anchor: NSView?) {
        let menu = makeActionsMenu()
        session.toggleActionsMenu()
        suppressResignDismissal += 1
        let view = anchor ?? panel.contentView
        if let view {
            let origin = anchor != nil ? NSPoint(x: 0, y: view.bounds.height + 4) : NSPoint(x: view.bounds.maxX - 240, y: 60)
            menu.popUp(positioning: nil, at: origin, in: view)
        }
        suppressResignDismissal -= 1
        session.closeActionsMenu()
        guard panel.isVisible else { return }
        if anotherAppIsActive {
            // The user switched apps while the menu was open.
            dismiss(.focusLost)
        } else if !panel.isKeyWindow {
            panel.makeKey()
        }
    }

    /// Whether an app other than Toolchord and the one the palette was opened over is now active.
    private var anotherAppIsActive: Bool {
        guard let active = NSWorkspace.shared.frontmostApplication else { return false }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return active.processIdentifier != ownPID && active.processIdentifier != originApplication?.processIdentifier
    }

    // MARK: - Actions menu

    private func makeActionsMenu() -> NSMenu {
        let menu = NSMenu(title: "Actions")
        menu.autoenablesItems = false
        let command = session.selectedCommand
        let canCopy = session.canCopy

        menu.addItem(item(session.copyTitle, key: "\r", modifiers: [.command], enabled: canCopy) { [weak self] in self?.copyAndClose() })
        let noun = command.map { $0.copyNoun(session.options(for: $0.id)) } ?? "result"
        menu.addItem(item("Copy \(noun) without closing", key: "\r", modifiers: [.command, .shift], enabled: canCopy) { [weak self] in self?.copyWithoutClosing() })
        menu.addItem(.separator())

        if session.isInTool {
            menu.addItem(item("Back to Tools", key: "\u{1b}", modifiers: [], enabled: true) { [weak self] in self?.back() })
        } else {
            menu.addItem(item("Open \(command?.title ?? "Tool")", key: "\r", modifiers: [], enabled: command != nil) { [weak self] in self?.openSelected() })
            menu.addItem(item("Paste Clipboard as Input", key: "v", modifiers: [.command], enabled: true) { [weak self] in self?.pasteFromClipboard() })
        }
        if session.canUseAsSearchText {
            menu.addItem(item("Use Input as Search Text", key: "", modifiers: [], enabled: true) { [weak self] in
                self?.session.useAsSearchText()
                self?.syncPanelSize()
                self?.focusCurrentView()
            })
        }
        menu.addItem(item("Clear Input", key: "\u{8}", modifiers: [.command, .shift], enabled: session.payload != nil) { [weak self] in self?.clearInput() })
        if let command, let title = command.regenerateTitle {
            menu.addItem(item(title, key: "r", modifiers: [.command], enabled: true) { [weak self] in self?.regenerate() })
        }

        if let command, !command.options.isEmpty {
            menu.addItem(.separator())
            let options = session.options(for: command.id)
            for option in command.options {
                switch option.kind {
                case .choice(let choices, let defaultID):
                    let parent = NSMenuItem(title: option.label, action: nil, keyEquivalent: "")
                    let submenu = NSMenu(title: option.label)
                    let current = options.choice(option.id, default: defaultID)
                    for choice in choices {
                        let entry = item(choice.label, key: "", modifiers: [], enabled: true) { [weak self] in
                            self?.session.setOption(option.id, to: choice.id, for: command.id)
                        }
                        entry.state = choice.id == current ? .on : .off
                        submenu.addItem(entry)
                    }
                    parent.submenu = submenu
                    menu.addItem(parent)
                case .toggle(let defaultValue):
                    let isOn = options.flag(option.id, default: defaultValue)
                    let entry = item(option.label, key: "", modifiers: [], enabled: true) { [weak self] in
                        self?.session.setOption(option.id, to: isOn ? "false" : "true", for: command.id)
                    }
                    entry.state = isOn ? .on : .off
                    menu.addItem(entry)
                }
            }
        }

        menu.addItem(.separator())
        menu.addItem(item("Settings…", key: ",", modifiers: [.command], enabled: true) { [weak self] in self?.openSettings() })
        menu.addItem(item("Close Panel", key: "w", modifiers: [.command], enabled: true) { [weak self] in self?.dismiss(.completed) })
        return menu
    }

    private func item(_ title: String, key: String, modifiers: NSEvent.ModifierFlags, enabled: Bool, action: @escaping @MainActor () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, action: action)
        item.keyEquivalent = key
        item.keyEquivalentModifierMask = modifiers
        item.isEnabled = enabled
        return item
    }

    // MARK: - System events

    private func observeSystemEvents() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.suppressResignDismissal == 0, self.panel.isVisible else { return }
                // Another app or window took focus: leave focus where the user moved it.
                self.dismiss(.focusLost)
            }
        })
        let workspace = NSWorkspace.shared.notificationCenter
        // A switch to a third app always ends the session, even if AppKit
        // does not deliver a resign-key notification (for example during menu tracking).
        observers.append(workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.panel.isVisible, self.anotherAppIsActive else { return }
                self.dismiss(.focusLost)
            }
        })
        for name in [NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.dismiss(.system) }
            })
        }
        // Not a documented constant, so it is a best-effort signal alongside the documented ones above.
        observers.append(DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss(.system) }
        })
        observers.append(center.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss(.system) }
        })
    }
}

/// A menu item that runs a closure.
@MainActor
final class ClosureMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(title: String, action handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func run() {
        handler()
    }
}
