import Foundation

/// Converts HTML to readable plain text the way a browser lays it out,
/// without validating: a lenient, linear tokenizer feeding a
/// ``PlainTextWriter``. Script, style, and other non-rendered content is
/// skipped; character references follow ``HTMLTools`` unescaping.
enum HTMLTextConverter {
    struct Tag { var name: String; var end: Bool; var attributes: [String: String]; var selfClosing: Bool }
    struct Frame { var name: String; var prefix: Bool; var next: Int = 1 }
    static let raw: Set<String> = ["script", "style", "title", "iframe", "noscript", "noembed", "noframes"]
    static let hidden: Set<String> = ["template", "object", "svg", "math", "canvas", "audio", "video", "datalist"]
    static let paragraphs: Set<String> = ["p", "h1", "h2", "h3", "h4", "h5", "h6", "pre", "listing", "blockquote", "ul", "ol", "menu", "dl", "table", "hr", "figure", "address", "fieldset", "details"]
    static let lines: Set<String> = ["article", "aside", "body", "caption", "center", "dd", "dialog", "div", "dt", "figcaption", "footer", "form", "header", "hgroup", "html", "legend", "li", "main", "nav", "option", "search", "section", "summary", "tbody", "textarea", "tfoot", "thead", "tr"]
    static let lists: Set<String> = ["ul", "ol", "menu", "dl"]
    /// End tags of enclosing blocks: inside a hidden element they close it, as
    /// `</p>` closes an unclosed `<span hidden>` in a browser.
    static let enclosingEnds: Set<String> = paragraphs.union(lines).union(["td", "th"])
    /// Start tags that end an open `p`.
    static let closesParagraph: Set<String> = [
        "address", "article", "aside", "blockquote", "center", "details", "dialog", "div", "dl", "fieldset",
        "figcaption", "figure", "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6", "header", "hgroup", "hr",
        "listing", "main", "menu", "nav", "ol", "p", "pre", "search", "section", "summary", "table", "ul",
    ]
    /// The most elements tracked inside a hidden element.
    static let maxHiddenInner = 256

    /// Whether start tag `start` implicitly ends the hidden element `hidden`
    /// (an omitted end tag, as for `<p hidden>a<p>b`), given the elements
    /// opened inside it.
    static func startTagEnds(_ hidden: String, start: String, inner: [String]) -> Bool {
        switch hidden {
        case "p": closesParagraph.contains(start) && !inner.contains { ["button", "table", "td", "th", "caption", "template", "object"].contains($0) }
        case "li": start == "li" && !inner.contains { lists.contains($0) }
        case "dt", "dd": (start == "dt" || start == "dd") && !inner.contains("dl")
        case "option": start == "option" || start == "optgroup"
        case "tr": start == "tr" && !inner.contains("table")
        case "td", "th": ["td", "th", "tr"].contains(start) && !inner.contains("table")
        default: false
        }
    }

    /// Elements that never have content or an end tag.
    static let void: Set<String> = ["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr"]
    static let foreignRoots: Set<String> = ["svg", "math"]

    /// An element the page doesn't render: the `hidden` attribute, or an
    /// inline `display: none` (common for preheader text in email HTML).
    static func isHiddenByAttribute(_ tag: Tag) -> Bool {
        if tag.attributes["hidden"] != nil { return true }
        guard let style = tag.attributes["style"] else { return false }
        // The last `display` declaration wins; custom properties such as
        // `--display` don't count.
        var display: String?
        for declaration in style.split(separator: ";") {
            guard let colon = declaration.firstIndex(of: ":") else { continue }
            let property = declaration[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard property == "display" else { continue }
            var value = declaration[declaration.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if value.hasSuffix("!important") { value = value.dropLast("!important".count).trimmingCharacters(in: .whitespacesAndNewlines) }
            display = value
        }
        return display == "none"
    }

    /// Whether a start tag opens content that isn't shown: raw text such as
    /// `script`, a hidden container such as `template`, or an element hidden
    /// by attribute. Only foreign elements honor a self-closing slash;
    /// ordinary HTML containers stay open until their explicit or implied end.
    static func opensHiddenContent(_ tag: Tag) -> Bool {
        guard !tag.end else { return false }
        if raw.contains(tag.name) || tag.name == "textarea" && isHiddenByAttribute(tag) { return true }
        guard !void.contains(tag.name), !(tag.selfClosing && foreignRoots.contains(tag.name)) else { return false }
        return hidden.contains(tag.name) || isHiddenByAttribute(tag)
    }
    static func space(_ b: UInt8) -> Bool { b == 32 || b == 9 || b == 10 || b == 13 || b == 12 }
    static func letter(_ b: UInt8) -> Bool { (65...90).contains(b) || (97...122).contains(b) }
    static func lower(_ b: UInt8) -> UInt8 { (65...90).contains(b) ? b + 32 : b }

    static func decode(_ text: String, cancellation: CancellationCheck) throws -> String {
        guard text.utf8.contains(38) else { return text }
        let scalars = Array(text.unicodeScalars)
        var result = String.UnicodeScalarView(); result.reserveCapacity(scalars.count)
        var i = 0; var ticks = 0
        while i < scalars.count {
            ticks += 1
            if ticks % 2048 == 0, cancellation.isCancelled { throw MarkupFailure.cancelled }
            if scalars[i] == "&", let numeric = HTMLTools.numericReference(in: scalars, at: i) {
                result.append(numeric.scalar ?? "\u{FFFD}"); i = numeric.end
            } else if scalars[i] == "&", let named = HTMLTools.namedReference(in: scalars, at: i), let point = HTMLEntityTable.codePoints[named.name], let scalar = Unicode.Scalar(point) {
                result.append(scalar); i = named.end
            } else { result.append(scalars[i]); i += 1 }
        }
        return String(result)
    }

    static func tag(_ bytes: [UInt8], at start: Int, cancellation: CancellationCheck) throws -> (Tag, Int)? {
        var i = start + 1; var end = false
        if i < bytes.count, bytes[i] == 47 { end = true; i += 1 }
        guard i < bytes.count, letter(bytes[i]) else { return nil }
        let nameStart = i
        while i < bytes.count, letter(bytes[i]) || (48...57).contains(bytes[i]) || bytes[i] == 45 || bytes[i] == 58 || bytes[i] == 46 { i += 1 }
        let name = String(decoding: bytes[nameStart..<i].map(lower), as: UTF8.self)
        var attrs: [String: String] = [:]
        var selfClosing = false
        while i < bytes.count {
            if i % 4096 == 0, cancellation.isCancelled { throw MarkupFailure.cancelled }
            while i < bytes.count, space(bytes[i]) { i += 1 }
            guard i < bytes.count else { return nil }
            if bytes[i] == 62 { return (Tag(name: name, end: end, attributes: attrs, selfClosing: selfClosing), i + 1) }
            if bytes[i] == 47 { selfClosing = true; i += 1; continue }
            selfClosing = false
            let a = i
            while i < bytes.count, !space(bytes[i]), bytes[i] != 61, bytes[i] != 62, bytes[i] != 47 { i += 1 }
            if a == i { i += 1; continue }
            let key = String(decoding: bytes[a..<i].map(lower), as: UTF8.self)
            while i < bytes.count, space(bytes[i]) { i += 1 }
            var value = ""
            if i < bytes.count, bytes[i] == 61 {
                i += 1
                while i < bytes.count, space(bytes[i]) { i += 1 }
                if i < bytes.count, bytes[i] == 34 || bytes[i] == 39 {
                    let quote = bytes[i]; i += 1; let a = i
                    while i < bytes.count, bytes[i] != quote {
                        if i % 4096 == 0, cancellation.isCancelled { throw MarkupFailure.cancelled }
                        i += 1
                    }
                    guard i < bytes.count else { return nil }
                    value = String(decoding: bytes[a..<i], as: UTF8.self); i += 1
                } else {
                    let a = i
                    while i < bytes.count, !space(bytes[i]), bytes[i] != 62 { i += 1 }
                    value = String(decoding: bytes[a..<i], as: UTF8.self)
                }
            }
            if attrs[key] == nil { attrs[key] = try decode(value, cancellation: cancellation) }
        }
        return nil
    }

    static func convert(_ text: String, writer: PlainTextWriter, request: ToolRequest) throws {
        let b = Array(text.utf8)
        var i = 0; var frames: [Frame] = []; var depth = 0
        // The hidden element and the elements opened inside it so far. Past
        // `maxHiddenInner` the stack overflows: only same-name nesting
        // (`hiddenSameDepth`, always counted) decides where it ends.
        var hiddenName: String?; var hiddenInner: [String] = []; var rawName: String?
        var hiddenOverflow = false; var hiddenSameDepth = 0
        // Elements hidden by attribute end where a browser would close them;
        // hidden containers such as `template` only at their own end tag.
        var hiddenByAttribute = false
        // `textarea` content is raw text that is shown (entities decoded, no tags).
        var rawKeepsText = false
        var preDepth = 0; var dropFirstBreak = false
        var anchor: (url: String, text: String)?
        var cell: PlainTextWriter?; var cells: [String] = []; var rowOpen = false
        // Open tables. Rows and cells of a table nested in a cell are
        // flattened into that cell, separated by spaces, since a cell is
        // one line of the outer table's output.
        var tableDepth = 0
        var rowBytes = 0
        var work = 0
        func current() -> PlainTextWriter { cell ?? writer }
        func textOut(_ s: String, verbatim: Bool = false) throws {
            if anchor != nil { anchor!.text += s }
            if cell != nil { try cell!.write(s) } else { try writer.write(s, verbatim: verbatim) }
        }
        func boundary(_ n: Int) { if cell != nil { cell!.pendingSpace = cell!.lineContent } else { writer.boundary(n) } }
        func endCell() throws {
            if let c = cell {
                let text = c.finish().trimmingCharacters(in: .whitespacesAndNewlines)
                rowBytes += text.utf8.count + (cells.isEmpty ? 0 : 1)
                if rowBytes > request.limits.maxOutputBytes - writer.bytes.count { throw MarkupFailure.output }
                cells.append(text); cell = nil
            }
        }
        func endRow() throws {
            try endCell()
            if rowOpen || !cells.isEmpty {
                writer.boundary(1); try writer.row(cells); writer.boundary(1)
            }
            cells = []; rowOpen = false; rowBytes = 0
        }
        func close(_ name: String) {
            guard let index = frames.lastIndex(where: { $0.name == name }) else { return }
            for frame in frames[index...].reversed() {
                if frame.prefix { current().popPrefix() }
                if frame.name == "blockquote" || lists.contains(frame.name) || frame.name == "dd" { depth -= 1 }
            }
            frames.removeSubrange(index...)
        }
        func open(_ name: String, prefix: Bool, next: Int = 1) throws {
            if name == "blockquote" || lists.contains(name) || name == "dd" {
                depth += 1
                if depth > request.limits.maxNestingDepth { throw MarkupFailure.nesting }
            }
            frames.append(Frame(name: name, prefix: prefix, next: next))
        }
        while i < b.count {
            work += 1
            if work % 2048 == 1, request.cancellation.isCancelled { throw MarkupFailure.cancelled }
            if let name = rawName {
                let target = Array(("</" + name).utf8)
                let rawStart = i
                var found = false
                while i < b.count {
                    if i % 4096 == 0, request.cancellation.isCancelled { throw MarkupFailure.cancelled }
                    if b[i] == 60, i + target.count < b.count {
                        var matches = true
                        for j in target.indices where lower(b[i + j]) != target[j] { matches = false; break }
                        if matches, space(b[i + target.count]) || b[i + target.count] == 47 || b[i + target.count] == 62 { found = true; break }
                    }
                    i += 1
                }
                rawName = nil
                if rawKeepsText {
                    rawKeepsText = false
                    var s = try decode(String(decoding: b[rawStart..<i], as: UTF8.self), cancellation: request.cancellation)
                    if s.hasPrefix("\r\n") { s = String(decoding: s.utf8.dropFirst(2), as: UTF8.self) }
                    else if s.hasPrefix("\n") || s.hasPrefix("\r") { s.removeFirst() }
                    try textOut(s, verbatim: true)
                }
                if !found { break }
            }
            if b[i] != 60 {
                let start = i
                while i < b.count, b[i] != 60 {
                    if i % 4096 == 0, request.cancellation.isCancelled { throw MarkupFailure.cancelled }
                    i += 1
                }
                if hiddenName == nil {
                    var s = try decode(String(decoding: b[start..<i], as: UTF8.self), cancellation: request.cancellation)
                    if dropFirstBreak {
                        if s.hasPrefix("\r\n") { s = String(decoding: s.utf8.dropFirst(2), as: UTF8.self) }
                        else if s.hasPrefix("\n") || s.hasPrefix("\r") { s.removeFirst() }
                        dropFirstBreak = false
                    }
                    try textOut(s, verbatim: preDepth > 0)
                }
                continue
            }
            dropFirstBreak = false
            if i + 1 < b.count, b[i + 1] == 33 || b[i + 1] == 63 {
                let comment = i + 3 < b.count && b[i + 1] == 33 && b[i + 2] == 45 && b[i + 3] == 45
                let cdata = i + 8 < b.count && b[i...i+8].elementsEqual("<![CDATA[".utf8)
                i += comment ? 4 : (cdata ? 9 : 2)
                while i < b.count {
                    if i % 4096 == 0, request.cancellation.isCancelled { throw MarkupFailure.cancelled }
                    if comment, i + 2 < b.count, b[i] == 45, b[i+1] == 45, b[i+2] == 62 { i += 3; break }
                    if cdata, i + 2 < b.count, b[i] == 93, b[i+1] == 93, b[i+2] == 62 { i += 3; break }
                    if !comment && !cdata && b[i] == 62 { i += 1; break }
                    i += 1
                }
                continue
            }
            let validStart = i + 1 < b.count && (letter(b[i+1]) || (b[i+1] == 47 && i+2 < b.count && letter(b[i+2])))
            guard validStart else { if hiddenName == nil { try textOut("<", verbatim: preDepth > 0) }; i += 1; continue }
            guard let (t, next) = try tag(b, at: i, cancellation: request.cancellation) else { break }
            i = next
            if let h = hiddenName {
                // Implied ends need fully tracked nesting, and nothing in
                // template, svg, or math content can close an outer element.
                let impliedEnds = hiddenByAttribute && !hiddenOverflow && !hiddenInner.contains { ["template", "svg", "math"].contains($0) }
                if t.end {
                    if !hiddenOverflow, let open = hiddenInner.lastIndex(of: t.name) {
                        hiddenSameDepth -= hiddenInner[open...].filter { $0 == h }.count
                        hiddenInner.removeSubrange(open...)
                        continue
                    }
                    if t.name == h {
                        if hiddenSameDepth > 0 {
                            hiddenSameDepth -= 1
                        } else {
                            hiddenName = nil
                            hiddenInner = []
                            hiddenOverflow = false
                        }
                        continue
                    }
                    // The end of an enclosing block closes the hidden element
                    // too; the tag itself is visible markup.
                    guard impliedEnds, enclosingEnds.contains(t.name) else { continue }
                } else if !(impliedEnds && startTagEnds(h, start: t.name, inner: hiddenInner)) {
                    // Raw text (including a textarea's) can't close the container.
                    if raw.contains(t.name) || t.name == "textarea" { rawName = t.name; rawKeepsText = false }
                    let inForeignContent = foreignRoots.contains(h) || hiddenInner.contains(where: foreignRoots.contains)
                    let selfClosingForeign = t.selfClosing && (inForeignContent || foreignRoots.contains(t.name))
                    if !selfClosingForeign && !void.contains(t.name) {
                        if t.name == h { hiddenSameDepth += 1 }
                        if hiddenInner.count < maxHiddenInner { hiddenInner.append(t.name) } else { hiddenOverflow = true }
                    }
                    continue
                }
                hiddenName = nil
                hiddenInner = []
                hiddenOverflow = false
                hiddenSameDepth = 0
            }
            if !t.end, raw.contains(t.name) { rawName = t.name; continue }
            if !t.end, t.name == "textarea", isHiddenByAttribute(t) { rawName = t.name; rawKeepsText = false; continue }
            if !t.end, hidden.contains(t.name) || isHiddenByAttribute(t) {
                // A hidden void element (`<img hidden>`) just disappears.
                if opensHiddenContent(t) {
                    hiddenName = t.name
                    hiddenInner = []
                    hiddenOverflow = false
                    hiddenSameDepth = 0
                    hiddenByAttribute = !hidden.contains(t.name)
                }
                continue
            }
            let nestedList = lists.contains(t.name) && frames.contains { ["li", "dd", "dt"].contains($0.name) }
            let amount = paragraphs.contains(t.name) ? (nestedList ? 1 : 2) : (lines.contains(t.name) ? 1 : 0)
            if t.end {
                switch t.name {
                case "a":
                    if let a = anchor, request.options.flag("links") { try textOut(markupLinkSuffix(text: a.text, url: a.url)) }
                    anchor = nil
                case "pre", "listing": preDepth = max(0, preDepth - 1)
                case "td", "th", "tr":
                    if tableDepth > 1 { boundary(1) } else if t.name == "tr" { try endRow() } else { try endCell() }
                case "table":
                    if tableDepth > 1 { tableDepth -= 1; boundary(1) } else { tableDepth = 0; try endRow() }
                default: break
                }
                close(t.name)
                if amount > 0 { boundary(amount) }
                continue
            }
            if t.name == "li" {
                if let item = frames.lastIndex(where: { $0.name == "li" }), item > (frames.lastIndex(where: { lists.contains($0.name) }) ?? -1) { close("li") }
            }
            if amount > 0 { boundary(amount) }
            switch t.name {
            case "br": if cell != nil { cell!.pendingSpace = cell!.lineContent } else { try writer.hardBreak() }
            case "blockquote": current().pushQuote(); try open(t.name, prefix: true)
            case "ul", "ol", "menu", "dl": try open(t.name, prefix: false, next: Int(t.attributes["start"] ?? "") ?? 1)
            case "li":
                var marker = "• "
                if let index = frames.lastIndex(where: { lists.contains($0.name) }), frames[index].name == "ol" {
                    let n = Int(t.attributes["value"] ?? "") ?? frames[index].next
                    marker = "\(n). "; frames[index].next = n == Int.max ? n : n + 1
                }
                try current().beginItem(marker); try open("li", prefix: true)
            case "dd": current().pushIndent(2); try open("dd", prefix: true)
            case "dt": close("dt"); try open("dt", prefix: false)
            case "pre", "listing": preDepth += 1; dropFirstBreak = true
            case "textarea": rawName = "textarea"; rawKeepsText = true
            case "img":
                let alt = (t.attributes["alt"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !alt.isEmpty { try textOut("[\(alt)]") }
            case "a": anchor = (t.attributes["href"] ?? "", "")
            case "table": tableDepth += 1
            case "tr":
                if tableDepth > 1 { boundary(1) } else { try endRow(); rowOpen = true }
            case "td", "th":
                if tableDepth > 1 { boundary(1) } else { try endCell(); cell = PlainTextWriter(request: request); rowOpen = true }
            default: break
            }
        }
        if let a = anchor, request.options.flag("links") {
            anchor = nil
            try textOut(markupLinkSuffix(text: a.text, url: a.url))
        }
        try endRow()
    }
}
