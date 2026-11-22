import Foundation

/// Foundation's Markdown parser supplies presentation intents that do not exist
/// in JavaScriptCore. The script renders this document tree as HTML or text.
enum ScriptStructuredHost {
    static func call(_ name: String, _ args: [Any], _ request: ToolRequest) throws -> Any? {
        guard name == "markdown.parse" else { return nil }
        guard args.count == 1, let text = args[0] as? String else {
            return ["error": "invalid", "message": "markdown.parse expects one string."]
        }
        guard text.utf8.count <= request.limits.maxInputBytes else {
            return ["error": "tooLarge", "message": request.limits.inputLimitMessage]
        }
        do {
            let root = try MarkdownDocument.parse(text, request: request)
            var queue = [root]
            var nodes: [[String: Any]] = []
            var index = 0
            while index < queue.count {
                if request.cancellation.isCancelled { throw MarkupFailure.cancelled }
                let node = queue[index]
                let firstChild = queue.count
                queue.append(contentsOf: node.children)
                var value = block(node)
                value["children"] = Array(firstChild..<queue.count)
                nodes.append(value)
                index += 1
            }
            return ["nodes": nodes]
        } catch MarkupFailure.nesting {
            return ["error": "tooLarge", "message": request.limits.nestingLimitMessage]
        } catch MarkupFailure.cancelled {
            return ["error": "unsupported", "message": "Evaluation was cancelled."]
        } catch {
            return ["error": "invalid", "message": "Couldn’t parse the Markdown."]
        }
    }

    private static func block(_ node: MarkdownBlock) -> [String: Any] {
        var value: [String: Any] = [
            "runs": node.runs.map(inline),
        ]
        switch node.kind {
        case .root: value["kind"] = "root"
        case .paragraph: value["kind"] = "paragraph"
        case .header(let level): value["kind"] = "header"; value["value"] = level
        case .orderedList: value["kind"] = "orderedList"
        case .unorderedList: value["kind"] = "unorderedList"
        case .item(let ordinal): value["kind"] = "item"; value["value"] = ordinal
        case .code(let language): value["kind"] = "code"; value["value"] = language
        case .quote: value["kind"] = "quote"
        case .thematic: value["kind"] = "thematic"
        case .table(let columns): value["kind"] = "table"; value["value"] = columns
        case .headerRow: value["kind"] = "headerRow"
        case .row: value["kind"] = "row"
        case .cell(let column): value["kind"] = "cell"; value["value"] = column
        case .html: value["kind"] = "html"
        }
        value["loose"] = node.loose
        value["alignments"] = node.alignments
        value["task"] = node.task
        return value
    }

    private static func inline(_ run: MarkdownInline) -> [String: Any] {
        var value: [String: Any] = ["text": run.text]
        value["link"] = run.link
        value["image"] = run.image
        if run.emphasis { value["emphasis"] = true }
        if run.strong { value["strong"] = true }
        if run.strike { value["strike"] = true }
        if run.code { value["code"] = true }
        if run.soft { value["soft"] = true }
        if run.hard { value["hard"] = true }
        if run.html { value["html"] = true }
        if run.linkEmphasis { value["linkEmphasis"] = true }
        if run.linkStrong { value["linkStrong"] = true }
        if run.linkStrike { value["linkStrike"] = true }
        return value
    }
}
