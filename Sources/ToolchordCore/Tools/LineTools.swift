import Foundation

/// Sorting, deduplicating, and reversing lines.
public enum LineTools {
    public static let commands: [ToolCommand] = [
        sortCommand,
        dedupeCommand,
        reverseCommand,
    ]

    // ─── Sort ────────────────────────────────────────────────────────────────

    private static let sortCommand = ToolCommand(
        id: "lines.sort",
        title: "Sort Lines",
        summary: "Alphabetical, numbers in natural order",
        group: .lines,
        icon: .symbol("arrow.up.arrow.down"),
        aliases: ["sort lines", "sort", "alphabetize", "order lines"],
        options: [
            .choice("order", "Order", [
                .init("asc", "A to Z"),
                .init("desc", "Z to A"),
            ], default: "asc"),
            .toggle("caseSensitive", "Case-sensitive", default: false),
        ],
        copyNoun: "lines",
        affinity: { profile in profile.has(.multiline) ? 35 : 0 },
        evaluate: { request in sortLines(request) }
    )

    static func sortLines(_ request: ToolRequest) -> ToolResult {
        guard let text = request.input.text else { return .needsInput("Paste text to sort.") }
        if text.isEmpty {
            return .success(ToolOutput(primaryText: "", status: "Sorted 0 lines"))
        }

        let (lines, lineBreak, hadTrailingBreak) = splitLines(text)
        let order = request.options.choice("order", default: "asc")
        let caseSensitive = request.options.flag("caseSensitive", default: false)
        var compareOptions: String.CompareOptions = [.numeric]
        if !caseSensitive {
            compareOptions.insert(.caseInsensitive)
        }

        // Stable sort: sort indices and break ties by original position
        let indices = Array(lines.indices)
        let sortedIndices = indices.sorted { a, b in
            let comparison = lines[a].compare(lines[b], options: compareOptions, range: nil, locale: nil)
            if comparison == .orderedSame {
                return a < b
            }
            if order == "desc" {
                return comparison == .orderedDescending
            }
            return comparison == .orderedAscending
        }

        let sortedLines = sortedIndices.map { lines[$0] }
        let output = joinLines(sortedLines, lineBreak: lineBreak, trailingBreak: hadTrailingBreak)
        let count = sortedLines.count

        return .success(ToolOutput(primaryText: output, status: count == 1 ? "Sorted 1 line" : "Sorted \(count) lines"))
    }

    // ─── Dedupe ──────────────────────────────────────────────────────────────

    private static let dedupeCommand = ToolCommand(
        id: "lines.dedupe",
        title: "Remove Duplicate Lines",
        summary: "Keep the first occurrence of each line",
        group: .lines,
        icon: .symbol("line.3.horizontal.decrease"),
        aliases: ["dedupe", "deduplicate", "unique lines", "uniq", "remove duplicates"],
        options: [
            .toggle("caseSensitive", "Case-sensitive", default: true),
            .toggle("trim", "Ignore surrounding spaces", default: false),
        ],
        copyNoun: "lines",
        affinity: { profile in profile.has(.multiline) ? 35 : 0 },
        evaluate: { request in dedupeLines(request) }
    )

    static func dedupeLines(_ request: ToolRequest) -> ToolResult {
        guard let text = request.input.text else { return .needsInput("Paste text to deduplicate.") }
        if text.isEmpty {
            return .success(ToolOutput(primaryText: "", status: "No duplicates"))
        }

        let (lines, lineBreak, hadTrailingBreak) = splitLines(text)
        let caseSensitive = request.options.flag("caseSensitive", default: true)
        let trim = request.options.flag("trim", default: false)

        // Compare bytes after the requested transformations. String equality
        // would also merge canonically equivalent but byte-distinct lines.
        var seen: Set<[UInt8]> = []
        var kept: [String] = []

        for line in lines {
            var key: String
            if trim {
                key = line.trimmingCharacters(in: .whitespaces)
            } else {
                key = line
            }
            if !caseSensitive {
                key = key.lowercased()
            }
            if seen.insert(Array(key.utf8)).inserted {
                kept.append(line)
            }
        }

        let removed = lines.count - kept.count
        let status: String
        if removed == 0 {
            status = "No duplicates"
        } else if removed == 1 {
            status = "Removed 1 duplicate"
        } else {
            status = "Removed \(removed) duplicates"
        }

        let output = joinLines(kept, lineBreak: lineBreak, trailingBreak: hadTrailingBreak)
        return .success(ToolOutput(primaryText: output, status: status))
    }

    // ─── Reverse ─────────────────────────────────────────────────────────────

    private static let reverseCommand = ToolCommand(
        id: "lines.reverse",
        title: "Reverse Lines",
        summary: "Last line first",
        group: .lines,
        icon: .symbol("arrow.uturn.up"),
        aliases: ["reverse lines", "flip lines", "reverse order"],
        copyNoun: "lines",
        affinity: { profile in profile.has(.multiline) ? 20 : 0 },
        evaluate: { request in reverseLines(request) }
    )

    static func reverseLines(_ request: ToolRequest) -> ToolResult {
        guard let text = request.input.text else { return .needsInput("Paste text to reverse.") }
        if text.isEmpty {
            return .success(ToolOutput(primaryText: "", status: "Reversed 0 lines"))
        }

        let (lines, lineBreak, hadTrailingBreak) = splitLines(text)
        let reversed = Array(lines.reversed())
        let output = joinLines(reversed, lineBreak: lineBreak, trailingBreak: hadTrailingBreak)
        let count = reversed.count

        return .success(ToolOutput(primaryText: output, status: count == 1 ? "Reversed 1 line" : "Reversed \(count) lines"))
    }

    // ─── Line splitting and joining ──────────────────────────────────────────

    /// Splits text into lines on LF, CR, or CRLF. Returns the lines, the
    /// line-break sequence detected from the first line break (defaults to LF),
    /// and whether the input ended with a line break.
    static func splitLines(_ text: String) -> ([String], String, Bool) {
        var lines: [String] = []
        var lineBreak = "\n"
        var hadTrailingBreak = false
        var currentStart = text.utf8.startIndex
        var index = text.utf8.startIndex

        while index < text.utf8.endIndex {
            let byte = text.utf8[index]
            if byte == 0x0A {
                // LF (or second byte of CRLF)
                let lineEnd = index
                let line = String(bytes: text.utf8[currentStart..<lineEnd], encoding: .utf8)!
                lines.append(line)
                // Detect line break from first occurrence
                if lines.count == 1 {
                    // Check if previous byte was CR (CRLF)
                    if lineEnd > text.utf8.startIndex {
                        let prevIndex = text.utf8.index(before: lineEnd)
                        if text.utf8[prevIndex] == 0x0D {
                            lineBreak = "\r\n"
                            currentStart = text.utf8.index(after: lineEnd)
                            index = currentStart
                            continue
                        }
                    }
                    lineBreak = "\n"
                }
                currentStart = text.utf8.index(after: index)
                index = currentStart
            } else if byte == 0x0D {
                // CR (possibly followed by LF)
                let lineEnd = index
                let line = String(bytes: text.utf8[currentStart..<lineEnd], encoding: .utf8)!
                lines.append(line)
                let nextIndex = text.utf8.index(after: index)
                if nextIndex < text.utf8.endIndex && text.utf8[nextIndex] == 0x0A {
                    // CRLF
                    if lines.count == 1 {
                        lineBreak = "\r\n"
                    }
                    currentStart = text.utf8.index(after: nextIndex)
                    index = currentStart
                } else {
                    // CR only
                    if lines.count == 1 {
                        lineBreak = "\r"
                    }
                    currentStart = nextIndex
                    index = currentStart
                }
            } else {
                index = text.utf8.index(after: index)
            }
        }

        // Check if input ended with a line break
        if currentStart >= text.utf8.endIndex {
            hadTrailingBreak = true
            // The empty string after the trailing break is not a line
        } else {
            // Last line
            let line = String(bytes: text.utf8[currentStart..<text.utf8.endIndex], encoding: .utf8)!
            lines.append(line)
        }

        // If no line breaks were found, default to LF
        if lines.count > 0 && text.utf8.count > 0 {
            // Check if any line break was found
            var foundBreak = false
            var i = text.utf8.startIndex
            while i < text.utf8.endIndex {
                let b = text.utf8[i]
                if b == 0x0A || b == 0x0D {
                    foundBreak = true
                    break
                }
                i = text.utf8.index(after: i)
            }
            if !foundBreak {
                lineBreak = "\n"
            }
        }

        return (lines, lineBreak, hadTrailingBreak)
    }

    /// Joins lines with the specified line break, adding a trailing break if requested.
    static func joinLines(_ lines: [String], lineBreak: String, trailingBreak: Bool) -> String {
        var result = lines.joined(separator: lineBreak)
        if trailingBreak {
            result += lineBreak
        }
        return result
    }
}
