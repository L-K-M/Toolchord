import SwiftUI

struct CustomToolDetailView: View {
    private enum Page { case describe, script }

    @Bindable var model: CustomToolEditorModel
    let workspace: CustomToolWorkspace
    @State private var page: Page
    @State private var confirmingRestore = false

    init(model: CustomToolEditorModel, workspace: CustomToolWorkspace) {
        self.workspace = workspace
        self.model = model
        _page = State(initialValue: model.hasPendingDescription || (model.expected == nil && !model.isDirty) ? .describe : .script)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Editor section", selection: $page) {
                Text(model.isRevisingTool ? "Update" : "Describe").tag(Page.describe)
                Text("Script").tag(Page.script)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Editor section")

            switch page {
            case .describe: descriptionPage
            case .script: scriptPage
            }

            if model.library.isModifiedBuiltIn(id: model.documentID) {
                HStack {
                    Text("Customized built-in tool")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Restore Built-In Version…") { confirmingRestore = true }
                        .disabled(model.isBusy)
                }
                .alert("Restore the built-in version?", isPresented: $confirmingRestore) {
                    Button("Cancel", role: .cancel) {}
                    Button("Restore", role: .destructive) { model.restoreBuiltIn() }
                } message: {
                    Text("Your saved edits to “\(model.expected?.title ?? model.definition.title)” and any unsaved changes to this tool will be discarded.")
                }
            }
        }
        .padding(18)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var descriptionPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(model.isRevisingTool ? "Update your tool" : "Describe your tool").font(.headline)
                AuthoringTextEditor(text: $model.description, label: "Tool instructions", monospaced: false)
                    .frame(height: 140)
                    .overlay(alignment: .topLeading) {
                        if model.description.isEmpty {
                            Text(model.isRevisingTool ? "What would you like to change?"
                                 : "For example, sort lines by length and remove duplicates.")
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                Divider()
                AuthoringProviderControls(model: model, workspace: workspace)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(2)
            .disabled(model.isBusy)
        }
    }

    private var scriptPage: some View {
        VStack(alignment: .leading, spacing: 8) {
            AuthoringTextEditor(text: $model.scriptText, label: "Tool JavaScript file", monospaced: true)
            if let problem = model.scriptProblem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            } else {
                Text("The `@toolchord` header defines the tool and its controls. The JavaScript below it runs the tool.")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .disabled(model.isBusy)
    }
}
