import AppKit
import SwiftUI

/// The Settings window's content: General and Appearance as toolbar tabs.
/// The window takes each tab's size, keeping its top edge, as macOS
/// Settings windows do.
@MainActor
final class SettingsTabViewController: NSTabViewController {
    init(model: AppModel, clipboard: SystemClipboard) {
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        addTab(GeneralSettingsView(model: model), label: "General", symbol: "gearshape")
        addTab(AppearanceSettingsView(preferences: model.preferences, clipboard: clipboard), label: "Appearance", symbol: "paintpalette")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func addTab<Content: View>(_ content: Content, label: String, symbol: String) {
        let controller = NSHostingController(rootView: content)
        controller.sizingOptions = [.preferredContentSize]
        controller.title = label
        let item = NSTabViewItem(viewController: controller)
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        addTabViewItem(item)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        fitWindow(animated: false)
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        fitWindow(animated: true)
    }

    override func preferredContentSizeDidChange(for viewController: NSViewController) {
        super.preferredContentSizeDidChange(for: viewController)
        guard viewController === tabViewItems[safe: selectedTabViewItemIndex]?.viewController else { return }
        fitWindow(animated: false)
    }

    /// Sizes the window to the selected tab, keeping its top edge.
    private func fitWindow(animated: Bool) {
        guard let window = view.window,
              let size = tabViewItems[safe: selectedTabViewItemIndex]?.viewController?.preferredContentSize,
              size.width > 0, size.height > 0 else { return }
        let content = window.contentRect(forFrameRect: window.frame)
        guard abs(content.width - size.width) > 0.5 || abs(content.height - size.height) > 0.5 else { return }
        let target = NSRect(x: content.minX, y: content.maxY - size.height, width: size.width, height: size.height)
        let frame = window.frameRect(forContentRect: target)
        window.setFrame(frame, display: true, animate: animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
