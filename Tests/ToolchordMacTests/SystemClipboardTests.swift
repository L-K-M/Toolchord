import AppKit
import Foundation
import Testing
import ToolchordCore
@testable import ToolchordMac

/// Review G1: generated secrets must not end up in clipboard history.
@MainActor
@Suite struct SystemClipboardTests {
    /// A private pasteboard, so tests never touch the user's clipboard.
    func withPasteboard(_ body: (NSPasteboard, SystemClipboard) -> Void) {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ch.lkmc.Toolchord.tests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        body(pasteboard, SystemClipboard(pasteboard: pasteboard))
    }

    func isConcealed(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.types?.contains(SystemClipboard.concealedType) == true
    }

    @Test func secretsAreMarkedConcealed() {
        withPasteboard { pasteboard, clipboard in
            #expect(clipboard.writeText("Pd4tJD1k6aLPzqlR", sensitivity: .secret))
            #expect(pasteboard.string(forType: .string) == "Pd4tJD1k6aLPzqlR")
            #expect(isConcealed(pasteboard))
            #expect(clipboard.readTextForPaste() == "Pd4tJD1k6aLPzqlR")
        }
    }

    @Test func ordinaryTextIsNotMarked() {
        withPasteboard { pasteboard, clipboard in
            #expect(clipboard.writeText("{\n  \"a\": 1\n}", sensitivity: .normal))
            #expect(pasteboard.string(forType: .string) == "{\n  \"a\": 1\n}")
            #expect(!isConcealed(pasteboard))
        }
    }

    @Test func eachWriteReplacesThePreviousContents() {
        withPasteboard { pasteboard, clipboard in
            #expect(clipboard.writeText("public", sensitivity: .normal))
            #expect(clipboard.writeText("secret", sensitivity: .secret))
            #expect(pasteboard.string(forType: .string) == "secret")
            #expect(isConcealed(pasteboard))
            #expect(clipboard.writeText("public again", sensitivity: .normal))
            #expect(pasteboard.string(forType: .string) == "public again")
            #expect(!isConcealed(pasteboard))
        }
    }
}
