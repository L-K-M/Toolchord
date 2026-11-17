import AppKit
import Foundation
import ToolchordSession

/// Palette actions that do nothing, for the snapshots and the theme
/// preview, which draw the palette without a panel behind it.
@MainActor
final class InertPaletteActions: PaletteActions {
    func openSelected() {}
    func back() {}
    func escape() {}
    func copyAndClose() {}
    func copyWithoutClosing() {}
    func copyField(_ id: String) {}
    func pasteFromClipboard() {}
    func showActions(from anchor: NSView?) {}
    func regenerate() {}
    func clearInput() {}
    func openSettings() {}
}

extension PaletteSession {
    /// A session for previews and snapshots: no system clipboard, no stored
    /// preferences, and a fixed clock and time zone, so the same input
    /// always shows the same result.
    @MainActor
    static func demo() -> PaletteSession {
        let session = PaletteSession(
            clipboard: MemoryClipboard(),
            preferences: MemoryPreferences(overrides: [:], recentCommandIDs: []),
            clock: { Date(timeIntervalSince1970: 1_700_000_000) },
            timeZone: { TimeZone(identifier: "Europe/Zurich") ?? .gmt }
        )
        session.activate()
        return session
    }
}
