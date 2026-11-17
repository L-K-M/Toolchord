import AppKit
import Observation

/// The accessibility display settings the palette honors, kept current
/// while Toolchord runs: Increase Contrast and Reduce Transparency.
@MainActor
@Observable
final class DisplayAccessibility {
    static let shared = DisplayAccessibility()

    private(set) var increaseContrast: Bool
    private(set) var reduceTransparency: Bool
    @ObservationIgnored private let workspace: NSWorkspace
    @ObservationIgnored private var observer: NSObjectProtocol?

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
        increaseContrast = workspace.accessibilityDisplayShouldIncreaseContrast
        reduceTransparency = workspace.accessibilityDisplayShouldReduceTransparency
        observer = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    private func refresh() {
        let contrast = workspace.accessibilityDisplayShouldIncreaseContrast
        let transparency = workspace.accessibilityDisplayShouldReduceTransparency
        if increaseContrast != contrast { increaseContrast = contrast }
        if reduceTransparency != transparency { reduceTransparency = transparency }
    }
}
