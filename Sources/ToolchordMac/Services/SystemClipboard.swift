import AppKit
import ToolchordCore
import ToolchordSession

/// The general pasteboard. Toolchord reads it only inside the user's Paste
/// command (⌘V or Edit › Paste), which macOS treats as user-initiated and
/// does not gate behind the "Paste from Other Apps" privacy alert. Opening,
/// navigating, and dismissing the palette never touch the pasteboard.
@MainActor
public final class SystemClipboard: ClipboardWriting {
    /// Marks content as confidential, following the nspasteboard.org
    /// convention: clipboard history tools that honor it skip such items or
    /// keep them hidden.
    static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    private let pasteboard: NSPasteboard

    /// - Parameter pasteboard: The pasteboard to use; tests pass a private one.
    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    public func writeText(_ text: String, sensitivity: ClipboardSensitivity) -> Bool {
        switch sensitivity {
        case .normal:
            pasteboard.clearContents()
            return pasteboard.setString(text, forType: .string)
        case .secret:
            // A generated secret stays on this Mac (no Universal Clipboard) and
            // is marked confidential for clipboard history tools.
            _ = pasteboard.prepareForNewContents(with: .currentHostOnly)
            let item = NSPasteboardItem()
            guard item.setString(text, forType: .string), item.setData(Data(), forType: Self.concealedType) else {
                return false
            }
            return pasteboard.writeObjects([item])
        }
    }

    /// Reads plain text. Call only in response to a paste command.
    public func readTextForPaste() -> String? {
        pasteboard.string(forType: .string)
    }
}
