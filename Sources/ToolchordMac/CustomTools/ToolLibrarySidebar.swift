import SwiftUI
import ToolchordCore

struct ToolLibrarySidebar: View {
    let model: CustomToolEditorModel
    @Binding var filter: String
    let onSelect: (String) -> Void

    var body: some View {
        let query = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = model.library.definitions.filter { matchesFilter($0, query: query) }
        let custom = matches.filter { ToolCatalog.command(id: $0.id) == nil }
        let builtIn = matches.filter { ToolCatalog.command(id: $0.id) != nil }
        let selectionIsVisible = model.documentID == "new" || matches.contains { $0.id == model.documentID }
        VStack(spacing: 0) {
            TextField("Filter tools", text: $filter)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Filter tools")
                .onSubmit {
                    guard !query.isEmpty, let first = custom.first ?? builtIn.first else { return }
                    onSelect(first.id)
                }
                .padding(8)
            ScrollViewReader { scroll in
                List(selection: Binding<String?>(
                    get: { selectionIsVisible ? model.documentID : nil },
                    set: { if let id = $0, id != model.documentID { onSelect(id) } }
                )) {
                    Section("Library") {
                        Label(model.documentID == "new" && model.isDirty ? draftTitle : "New Tool", systemImage: "square.and.pencil")
                            .lineLimit(1)
                            .tag("new")
                            .id("new")
                    }
                    if !custom.isEmpty {
                        Section("My Tools") { toolRows(custom) }
                    }
                    if !builtIn.isEmpty {
                        Section("Built-In Tools") { toolRows(builtIn) }
                    }
                    if !query.isEmpty && matches.isEmpty {
                        Text("No matching tools")
                            .foregroundStyle(.secondary)
                            .selectionDisabled()
                    }
                }
                .listStyle(.sidebar)
                // Rebuild the table when entering or leaving a filter. AppKit
                // cannot reselect a newly revealed row during its own row update.
                .id(query.isEmpty)
                .accessibilityLabel("Tool library")
                .onChange(of: model.documentID, initial: true) { _, id in
                    if id != "new", !query.isEmpty, !matches.contains(where: { $0.id == id }) {
                        filter = ""
                    }
                    DispatchQueue.main.async {
                        if model.documentID == id { scroll.scrollTo(id) }
                    }
                }
            }
        }
    }

    private var draftTitle: String {
        model.definition.title.isEmpty ? "Untitled Tool" : model.definition.title
    }

    private func matchesFilter(_ tool: ScriptToolDefinition, query: String) -> Bool {
        if query.isEmpty { return true }
        if [tool.title, tool.id, tool.summary].contains(where: { $0.localizedStandardContains(query) }) { return true }
        guard let original = ToolCatalog.command(id: tool.id) else { return false }
        return ([original.title, original.group.name] + original.aliases).contains { $0.localizedStandardContains(query) }
    }

    private func toolRows(_ tools: [ScriptToolDefinition]) -> some View {
        ForEach(tools) { tool in
            let title = tool.id == model.documentID ? draftTitle : tool.title
            let modified = model.library.isModifiedBuiltIn(id: tool.id)
            Label(title, systemImage: modified ? "pencil" : "wrench")
                .lineLimit(1)
                .tag(tool.id)
                .accessibilityLabel(modified ? "\(title), customized built-in tool" : title)
                .help(modified ? "\(title) (customized built-in tool)" : (tool.summary.isEmpty ? title : tool.summary))
        }
    }
}
