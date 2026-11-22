import Foundation

/// One attributed run of inline content.
struct MarkdownInline {
    var text: String
    var link: String?
    var image: String?
    /// Formatting around the run (and around its link, if any).
    var emphasis: Bool
    var strong: Bool
    var strike: Bool
    var code: Bool
    var soft: Bool
    var hard: Bool
    var html: Bool
    /// Formatting inside the link text, restored from the source; it nests
    /// inside the link element.
    var linkEmphasis = false
    var linkStrong = false
    var linkStrike = false
}

/// A block in the rebuilt Markdown tree; leaf blocks hold their inline runs.
final class MarkdownBlock {
    enum Kind {
        case root, paragraph, header(Int), orderedList, unorderedList, item(Int), code(String?), quote, thematic
        case table(Int), headerRow, row, cell(Int), html
    }
    let identity: Int
    let kind: Kind
    var children: [MarkdownBlock] = []
    var runs: [MarkdownInline] = []
    var start: Int?
    var end: Int?
    var loose = false
    /// For a list item: `false` for `[ ] `, `true` for `[x] ` or `[X] `, `nil` if not a task.
    var task: Bool?
    /// Where a leaf's first run starts in the source (1-based line, UTF-8 column).
    var firstSource: (line: Int, column: Int)?
    var alignments: [String?] = []
    /// A table's column alignments as Foundation reports them; it reports
    /// unspecified columns as left, so left counts as unspecified here.
    var reportedAlignments: [String?] = []
    init(_ kind: Kind, identity: Int = -1) { self.kind = kind; self.identity = identity }
}

/// Parses Markdown with Foundation and rebuilds the block tree from the
/// attributed runs' presentation intents, then marks loose lists (from blank
/// source lines) and table alignments (from the delimiter row).
enum MarkdownDocument {
    static func lines(_ text: String) -> [String] {
        let b = Array(text.utf8); var start = 0; var i = 0; var result: [String] = []
        while i < b.count {
            if b[i] == 10 || b[i] == 13 {
                result.append(String(decoding: b[start..<i], as: UTF8.self))
                if b[i] == 13 && i+1 < b.count && b[i+1] == 10 { i += 1 }
                start = i + 1
            }
            i += 1
        }
        result.append(String(decoding: b[start...], as: UTF8.self)); return result
    }

    /// Re-parses at most this many link texts per document (see
    /// ``restoreLinkFormatting(_:position:lines:)``); later links keep
    /// Foundation's flattened text, so pathological input stays fast.
    static let maxRestoredLinks = 1_000

    /// Foundation drops all formatting inside link text — emphasis, code, and
    /// images, so a README badge `[![Build](b.svg)](ci)` arrives as a plain
    /// link "Build". The run's source position still spans the original
    /// markup, so when that source differs from the run's text,
    /// parse it again as inline Markdown and keep the result, inside the
    /// outer link, if it yields the same text. Foundation also drops line
    /// endings inside link labels, so a recovered multiline label may add
    /// those separators back. Source positions may include quote/list prefixes;
    /// remove them only when the decoded text still matches. Otherwise keep
    /// the flat run.
    static func restoreLinkFormatting(_ inline: MarkdownInline, position: AttributedString.MarkdownSourcePosition, lines: [[UInt8]]) -> [MarkdownInline]? {
        guard position.startLine >= 1, position.endLine >= position.startLine, position.endLine <= lines.count else { return nil }
        let firstLine = lines[position.startLine - 1]
        let lastLine = lines[position.endLine - 1]
        let multiline = position.startLine != position.endLine
        var start = position.startColumn - 1
        var end = position.endColumn
        guard start >= 0, start <= firstLine.count, end >= 0, end <= lastLine.count,
              multiline || start < end else { return nil }
        // A code span's position excludes its backticks.
        while start > 0, firstLine[start - 1] == 0x60 { start -= 1 }
        while end < lastLine.count, lastLine[end] == 0x60 { end += 1 }
        var markup: [UInt8]
        if multiline {
            markup = Array(firstLine[start...])
            for line in lines[position.startLine..<(position.endLine - 1)] {
                markup.append(0x0A)
                markup.append(contentsOf: line)
            }
            markup.append(0x0A)
            markup.append(contentsOf: lastLine[..<end])
        } else {
            markup = Array(firstLine[start..<end])
        }
        func restore(_ markup: [UInt8]) -> [MarkdownInline]? {
            // Also re-parse text with `<`: Foundation flattens inline HTML in link
        // text to plain text, where cmark passes it through.
        guard !markup.elementsEqual(inline.text.utf8) || markup.contains(0x3C) else { return nil }
            let options = AttributedString.MarkdownParsingOptions(
                allowsExtendedAttributes: false,
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible,
                languageCode: nil
            )
            guard let parsed = try? AttributedString(markdown: String(decoding: markup, as: UTF8.self), options: options) else { return nil }
            var restored: [MarkdownInline] = []
            var combined = ""
            for run in parsed.runs {
                let text = String(parsed.characters[run.range])
                let intent = run.inlinePresentationIntent ?? []
                combined += text
                restored.append(MarkdownInline(
                    text: text, link: inline.link, image: run.imageURL?.absoluteString,
                    emphasis: inline.emphasis, strong: inline.strong, strike: inline.strike,
                    code: intent.contains(.code), soft: intent.contains(.softBreak), hard: intent.contains(.lineBreak), html: intent.contains(.inlineHTML),
                    linkEmphasis: intent.contains(.emphasized),
                    linkStrong: intent.contains(.stronglyEmphasized),
                    linkStrike: intent.contains(.strikethrough)
                ))
            }
            let restoresLineEndings = multiline && combined.replacingOccurrences(of: "\n", with: "") == inline.text
            return combined == inline.text || restoresLineEndings ? restored : nil
        }
        if let restored = restore(markup) { return restored }
        guard multiline else { return nil }
        // Source spans inside block quotes/lists include continuation prefixes.
        // Try removing only their ASCII prefix characters, retaining this
        // candidate only when the same decoded-text safeguard succeeds.
        var unprefixed: [UInt8] = []
        for (index, line) in markup.split(separator: 0x0A, omittingEmptySubsequences: false).enumerated() {
            if index > 0 { unprefixed.append(0x0A) }
            let content = index == 0 ? line : line.drop(while: { $0 == 32 || $0 == 9 || $0 == 62 })
            unprefixed.append(contentsOf: content)
        }
        return unprefixed.elementsEqual(markup) ? nil : restore(unprefixed)
    }

    /// Foundation's parser takes quadratic time to attach source positions to
    /// GitHub autolinks (bare `https://…` URLs and email addresses): 8,000 of
    /// them take over 3 s, against 0.35 s without positions. Above this many
    /// candidates (`://` and `@`), parse without positions: lists are then
    /// loose only when an item holds two paragraphs, table alignment comes
    /// from Foundation, and link text keeps Foundation's flat text (including
    /// its loss of separators inside multiline link labels).
    static let maxAutolinkCandidatesWithPositions = 1_000

    static func autolinkCandidates(in text: String, upTo limit: Int) -> Int {
        var count = 0
        var previous: UInt8 = 0
        var beforePrevious: UInt8 = 0
        for byte in text.utf8 {
            if byte == 0x40 || (byte == 0x2F && previous == 0x2F && beforePrevious == 0x3A) {
                count += 1
                if count > limit { break }
            }
            beforePrevious = previous
            previous = byte
        }
        return count
    }

    /// GitHub task list items: the item's first paragraph starts with
    /// `[ ] `, `[x] `, or `[X] `, written literally in the source (so an
    /// escaped `\[x\]` is ordinary text). Without source positions the
    /// decoded text decides.
    static func taskState(of item: MarkdownBlock, lines: [[UInt8]], usesPositions: Bool) -> Bool? {
        // The marker is plain text at the start of the first run (not code,
        // a link, an image, or HTML).
        guard let first = item.children.first, case .paragraph = first.kind, let run = first.runs.first,
              !run.code, !run.html, run.link == nil, run.image == nil else { return nil }
        let prefix = String(run.text.prefix(4))
        let checked: Bool
        switch prefix {
        case "[ ] ": checked = false
        case "[x] ", "[X] ": checked = true
        default: return nil
        }
        guard usesPositions else { return checked }
        guard let source = first.firstSource, source.line >= 1, source.line <= lines.count else { return nil }
        let line = lines[source.line - 1]
        let start = source.column - 1
        guard start >= 0, start + 4 <= line.count, line[start..<(start + 4)].elementsEqual(prefix.utf8) else { return nil }
        return checked
    }

    static func parse(_ text: String, request: ToolRequest) throws -> MarkdownBlock {
        if request.cancellation.isCancelled { throw MarkupFailure.cancelled }
        var options = AttributedString.MarkdownParsingOptions(allowsExtendedAttributes: false, interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible, languageCode: nil)
        let usesPositions = autolinkCandidates(in: text, upTo: maxAutolinkCandidatesWithPositions) <= maxAutolinkCandidatesWithPositions
        options.appliesSourcePositionAttributes = usesPositions
        let attributed = try AttributedString(markdown: text, options: options)
        let source = lines(text)
        let sourceBytes = source.map { Array($0.utf8) }
        var restoredLinks = 0
        let root = MarkdownBlock(.root)
        var path: [MarkdownBlock] = []
        for (index, run) in attributed.runs.enumerated() {
            if index % 2048 == 0, request.cancellation.isCancelled { throw MarkupFailure.cancelled }
            let components = run.presentationIntent?.components ?? []
            if components.count > request.limits.maxNestingDepth { throw MarkupFailure.nesting }
            var common = 0
            while common < path.count && common < components.count && path[common].identity == components[components.count - common - 1].identity { common += 1 }
            path.removeSubrange(common...)
            for level in common..<components.count {
                let component = components[components.count - level - 1]
                let kind: MarkdownBlock.Kind
                switch component.kind {
                case .paragraph: kind = .paragraph
                case .header(let level): kind = .header(level)
                case .orderedList: kind = .orderedList
                case .unorderedList: kind = .unorderedList
                case .listItem(let ordinal): kind = .item(ordinal)
                case .codeBlock(let language): kind = .code(language)
                case .blockQuote: kind = .quote
                case .thematicBreak: kind = .thematic
                case .table(let columns): kind = .table(columns.count)
                case .tableHeaderRow: kind = .headerRow
                case .tableRow: kind = .row
                case .tableCell(let column): kind = .cell(column)
                @unknown default: kind = .paragraph
                }
                let node = MarkdownBlock(kind, identity: component.identity)
                if case .table(let columns) = component.kind {
                    node.reportedAlignments = columns.map { column in
                        switch column.alignment {
                        case .center: "center"
                        case .right: "right"
                        default: nil
                        }
                    }
                }
                (path.last ?? root).children.append(node); path.append(node)
            }
            let intent = run.inlinePresentationIntent ?? []
            let inline = MarkdownInline(text: String(attributed.characters[run.range]), link: run.link?.absoluteString, image: run.imageURL?.absoluteString, emphasis: intent.contains(.emphasized), strong: intent.contains(.stronglyEmphasized), strike: intent.contains(.strikethrough), code: intent.contains(.code), soft: intent.contains(.softBreak), hard: intent.contains(.lineBreak), html: intent.contains(.inlineHTML))
            var leaf = path.last ?? root
            if intent.contains(.blockHTML) {
                leaf = MarkdownBlock(.html); (path.last ?? root).children.append(leaf)
            }
            if leaf.runs.isEmpty, let position = run.markdownSourcePosition {
                leaf.firstSource = (position.startLine, position.startColumn)
            }
            if inline.link != nil, inline.image == nil, restoredLinks < maxRestoredLinks,
               let position = run.markdownSourcePosition,
               let restored = restoreLinkFormatting(inline, position: position, lines: sourceBytes) {
                restoredLinks += 1
                leaf.runs.append(contentsOf: restored)
            } else {
                leaf.runs.append(inline)
            }
            if let position = run.markdownSourcePosition {
                leaf.start = min(leaf.start ?? position.startLine, position.startLine)
                leaf.end = max(leaf.end ?? position.endLine, position.endLine)
            }
        }
        var blanks = [0]; blanks.reserveCapacity(source.count + 1)
        for line in source { blanks.append(blanks.last! + (line.utf8.allSatisfy { $0 == 32 || $0 == 9 || $0 == 62 } ? 1 : 0)) }
        func blankBetween(_ a: MarkdownBlock, _ b: MarkdownBlock) -> Bool {
            guard let end = a.end, let start = b.start, start > end + 1, end >= 0, start - 1 < blanks.count else { return false }
            return blanks[start - 1] > blanks[end]
        }
        // A script calls this parser from inside a JavaScriptCore stack.
        // Carry the postorder traversal on the heap, including at maximum depth.
        var pending: [(MarkdownBlock, Bool)] = [(root, false)]
        while let (block, visited) = pending.popLast() {
            if !visited {
                pending.append((block, true))
                for child in block.children.reversed() { pending.append((child, false)) }
                continue
            }
            if request.cancellation.isCancelled { throw MarkupFailure.cancelled }
            for child in block.children {
                if let start = child.start { block.start = min(block.start ?? start, start) }
                if let end = child.end { block.end = max(block.end ?? end, end) }
            }
            switch block.kind {
            case .item:
                block.task = taskState(of: block, lines: sourceBytes, usesPositions: usesPositions)
            case .orderedList, .unorderedList:
                // Two paragraphs in one item always have a blank line between them.
                for item in block.children {
                    for (first, second) in zip(item.children, item.children.dropFirst()) {
                        if case .paragraph = first.kind, case .paragraph = second.kind { block.loose = true }
                    }
                }
                for i in block.children.indices {
                    if i > 0 && blankBetween(block.children[i-1], block.children[i]) { block.loose = true }
                    let children = block.children[i].children
                    for j in children.indices where j > 0 {
                        if blankBetween(children[j-1], children[j]) { block.loose = true }
                    }
                }
            case .table(let count):
                block.alignments = (0..<count).map { $0 < block.reportedAlignments.count ? block.reportedAlignments[$0] : nil }
                // The delimiter row follows the header row's line. Reading it
                // tells explicit left alignment (`:--`) from none.
                if let line = block.start, line < source.count,
                   source[line].unicodeScalars.allSatisfy({ "|:-> \t".unicodeScalars.contains($0) }),
                   source[line].contains("-") {
                    block.alignments = Array(repeating: nil, count: count)
                    let delimiter = source[line].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "> "))
                    var parts = delimiter.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
                    if parts.first == "" { parts.removeFirst() }; if parts.last == "" { parts.removeLast() }
                    for i in 0..<min(count, parts.count) {
                        if parts[i].hasPrefix(":") && parts[i].hasSuffix(":") { block.alignments[i] = "center" }
                        else if parts[i].hasPrefix(":") { block.alignments[i] = "left" }
                        else if parts[i].hasSuffix(":") { block.alignments[i] = "right" }
                    }
                }
            default: break
            }
        }
        return root
    }
}
