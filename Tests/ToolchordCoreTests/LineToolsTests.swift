import Foundation
import Testing
@testable import ToolchordCore

@Suite struct LineToolsTests {

    // ─── Helpers ─────────────────────────────────────────────────────────────

    private func run(_ id: String, _ text: String, options: [String: String] = [:]) throws -> ToolOutput {
        let command = try #require(LineTools.commands.first { $0.id == id })
        let result = command.run(ToolRequest(input: .text(text), options: ToolOptions(options)))
        return try #require(result.output, "Expected success, got \(result)")
    }

    // ─── Sort ────────────────────────────────────────────────────────────────

    @Test func sortBasic() throws {
        let output = try run("lines.sort", "b\na\nC")
        #expect(output.primaryText == "a\nb\nC")
        #expect(output.status == "Sorted 3 lines")
    }

    @Test func sortCaseSensitive() throws {
        let output = try run("lines.sort", "b\na\nC", options: ["caseSensitive": "true"])
        #expect(output.primaryText == "C\na\nb")
    }

    @Test func sortNaturalNumbers() throws {
        let output = try run("lines.sort", "item10\nitem2\nitem1")
        #expect(output.primaryText == "item1\nitem2\nitem10")
    }

    @Test func sortDescending() throws {
        let output = try run("lines.sort", "a\nc\nb", options: ["order": "desc"])
        #expect(output.primaryText == "c\nb\na")
    }

    @Test func sortTrailingNewline() throws {
        let output = try run("lines.sort", "b\na\n")
        #expect(output.primaryText == "a\nb\n")
    }

    @Test func sortCRLF() throws {
        let output = try run("lines.sort", "b\r\na")
        #expect(output.primaryText == "a\r\nb")
    }

    @Test func sortEmptyLine() throws {
        let output = try run("lines.sort", "b\n\na")
        #expect(output.primaryText == "\na\nb")
    }

    @Test func sortStability() throws {
        // B and b are equal case-insensitively; A and a are equal.
        // Original order: B(0), b(1), A(2). Stable sort: A(2) < B(0) < b(1)
        let output = try run("lines.sort", "B\nb\nA")
        #expect(output.primaryText == "A\nB\nb")
    }

    @Test func sortSingleLine() throws {
        let output = try run("lines.sort", "single")
        #expect(output.primaryText == "single")
        #expect(output.status == "Sorted 1 line")
    }

    @Test func sortEmptyInput() throws {
        let output = try run("lines.sort", "")
        #expect(output.primaryText == "")
    }

    // ─── Dedupe ──────────────────────────────────────────────────────────────

    @Test func dedupeBasic() throws {
        let output = try run("lines.dedupe", "a\nb\na\nB")
        #expect(output.primaryText == "a\nb\nB")
        #expect(output.status == "Removed 1 duplicate")
    }

    @Test func dedupeCaseInsensitive() throws {
        let output = try run("lines.dedupe", "a\nb\na\nB", options: ["caseSensitive": "false"])
        #expect(output.primaryText == "a\nb")
    }

    @Test func dedupeTrim() throws {
        let output = try run("lines.dedupe", "a\n a \nb", options: ["trim": "true"])
        #expect(output.primaryText == "a\nb")
    }

    @Test func dedupeEmptyInput() throws {
        let output = try run("lines.dedupe", "")
        #expect(output.primaryText == "")
    }

    @Test(arguments: ["\n", "\r", "\r\n"])
    func dedupePreservesDistinctUnicodeBytes(lineBreak: String) throws {
        let composed = "é"
        let decomposed = "e\u{301}"
        let input = [composed, decomposed, composed, decomposed].joined(separator: lineBreak) + lineBreak
        let output = try run("lines.dedupe", input)
        let expected = [composed, decomposed].joined(separator: lineBreak) + lineBreak
        #expect(output.primaryText.utf8.elementsEqual(expected.utf8))
        #expect(output.status == "Removed 2 duplicates")
    }

    @Test func dedupeAppliesOnlyRequestedNormalizations() throws {
        let input = " É \n E\u{301} \né\ne\u{301}"
        let expected = " É \n E\u{301} "
        let output = try run("lines.dedupe", input, options: ["caseSensitive": "false", "trim": "true"])
        #expect(output.primaryText.utf8.elementsEqual(expected.utf8))
        #expect(output.status == "Removed 2 duplicates")
    }

    // ─── Reverse ─────────────────────────────────────────────────────────────

    @Test func reverseBasic() throws {
        let output = try run("lines.reverse", "1\n2\n3")
        #expect(output.primaryText == "3\n2\n1")
        #expect(output.status == "Reversed 3 lines")
    }

    @Test func reverseTrailingNewline() throws {
        let output = try run("lines.reverse", "1\n2\n")
        #expect(output.primaryText == "2\n1\n")
    }

    @Test func reverseEmptyInput() throws {
        let output = try run("lines.reverse", "")
        #expect(output.primaryText == "")
    }

    // ─── Empty input for all commands ────────────────────────────────────────

    @Test func allCommandsHandleEmptyInput() throws {
        #expect(try run("lines.sort", "").primaryText == "")
        #expect(try run("lines.dedupe", "").primaryText == "")
        #expect(try run("lines.reverse", "").primaryText == "")
    }

    // ─── Affinity ────────────────────────────────────────────────────────────

    @Test func sortAffinity() throws {
        let command = try #require(LineTools.commands.first { $0.id == "lines.sort" })
        let multiline = InputProfile(isAttached: true, kinds: [.multiline], primaryKind: .multiline, byteCount: 10, lineCount: 3, isBlank: false)
        let singleLine = InputProfile(isAttached: true, kinds: [.text], primaryKind: .text, byteCount: 10, lineCount: 1, isBlank: false)
        #expect(command.affinity(multiline) == 35)
        #expect(command.affinity(singleLine) == 0)
    }

    @Test func dedupeAffinity() throws {
        let command = try #require(LineTools.commands.first { $0.id == "lines.dedupe" })
        let multiline = InputProfile(isAttached: true, kinds: [.multiline], primaryKind: .multiline, byteCount: 10, lineCount: 3, isBlank: false)
        #expect(command.affinity(multiline) == 35)
    }

    @Test func reverseAffinity() throws {
        let command = try #require(LineTools.commands.first { $0.id == "lines.reverse" })
        let multiline = InputProfile(isAttached: true, kinds: [.multiline], primaryKind: .multiline, byteCount: 10, lineCount: 3, isBlank: false)
        #expect(command.affinity(multiline) == 20)
    }
}
