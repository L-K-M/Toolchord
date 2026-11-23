import SwiftUI
import UniformTypeIdentifiers

struct CustomToolEditorView: View {
    @Bindable var model: CustomToolEditorModel
    let workspace: CustomToolWorkspace
    let onSelect: (String) -> Void
    let onOpenFile: (URL) -> Void

    init(model: CustomToolEditorModel, workspace: CustomToolWorkspace = CustomToolWorkspace(),
         onSelect: ((String) -> Void)? = nil, onOpenFile: @escaping (URL) -> Void = { _ in }) {
        self.model = model
        self.workspace = workspace
        self.onSelect = onSelect ?? model.selectDocument
        self.onOpenFile = onOpenFile
    }

    var body: some View {
        VStack(spacing: 0) {
            if let problem = model.library.loadProblem {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    ScrollView {
                        Text(problem)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 56)
                    Button("Reload Saved Tools") { model.library.reload() }
                        .disabled(model.isBusy)
                }
                .font(.callout)
                .padding(10)
                Divider()
            }
            HSplitView {
                if workspace.showsSidebar {
                    library
                        .frame(minWidth: 144, idealWidth: 178, maxWidth: 220)
                }
                CustomToolDetailView(model: model, workspace: workspace)
                    .id(model.definition.id)
                    .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
                if workspace.showsInspector {
                    CustomToolSampleInspector(model: model)
                        .id(model.definition.id)
                        .frame(minWidth: 218, idealWidth: 274, maxWidth: 440, maxHeight: .infinity)
                }
            }
            Divider()
            status
        }
        .environment(workspace)
        .environment(model)
        .frame(minWidth: 820, minHeight: 540)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard providers.count == 1, let provider = providers.first, provider.canLoadObject(ofClass: URL.self) else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.isFileURL else { return }
                Task { @MainActor in onOpenFile(url) }
            }
            return true
        }
    }

    private var library: some View {
        List(selection: Binding<String?>(
            get: { model.documentID },
            set: { if let id = $0, id != model.documentID { onSelect(id) } }
        )) {
            Section("Library") {
                Label(model.documentID == "new" && model.isDirty ? draftTitle : "New Tool", systemImage: "square.and.pencil")
                    .lineLimit(1)
                    .tag("new")
            }
            Section("Saved Tools") {
                if model.library.definitions.isEmpty {
                    Text("Saved tools appear here.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .selectionDisabled()
                }
                ForEach(model.library.definitions, id: \.id) { tool in
                    Label(tool.id == model.documentID ? draftTitle : tool.title, systemImage: "wrench")
                        .lineLimit(1)
                        .tag(tool.id)
                        .help(tool.summary.isEmpty ? tool.title : tool.summary)
                }
            }
        }
        .listStyle(.sidebar)
        .accessibilityLabel("Tool library")
    }

    private var draftTitle: String {
        model.definition.title.isEmpty ? "Untitled Tool" : model.definition.title
    }

    private var status: some View {
        HStack(spacing: 7) {
            if model.isBusy {
                ProgressView().controlSize(.small)
                Text(model.isGenerating ? "Generating tool…" : "Running sample…")
            } else if let message = model.message {
                Image(systemName: model.isError ? "exclamationmark.triangle" : "info.circle")
                    .foregroundStyle(model.isError ? Color.orange : Color.secondary)
                Text(message).textSelection(.enabled)
            } else {
                Text(model.hasPendingDescription
                     ? "Generate your description to apply it to this tool."
                     : "Run a sample successfully to enable Save.")
            }
            Spacer(minLength: 0)
            if model.isBusy {
                Button("Cancel") { model.cancelWork() }
                    .controlSize(.small)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }
}
