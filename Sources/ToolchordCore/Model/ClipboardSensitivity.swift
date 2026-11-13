import Foundation

/// How a result should be treated once it is copied.
public enum ClipboardSensitivity: Sendable, Hashable {
    /// Ordinary text.
    case normal
    /// A generated secret, such as a random password or API key. Copies stay
    /// on this Mac and are marked as confidential for clipboard history tools.
    case secret
}
