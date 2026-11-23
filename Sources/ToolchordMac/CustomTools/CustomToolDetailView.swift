import SwiftUI
import ToolchordCore

struct CustomToolDetailView: View {
    private enum Page { case describe, script, options }

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
                Text("Options").tag(Page.options)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Editor section")

            switch page {
            case .describe: descriptionPage
            case .script: scriptPage
            case .options: optionsPage
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
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 7) {
                GridRow {
                    Text("Name")
                    TextField("Tool title", text: $model.definition.title)
                }
                GridRow {
                    Text("Summary")
                    TextField("Summary", text: $model.definition.summary)
                }
            }
            .textFieldStyle(.roundedBorder)
            Divider().padding(.vertical, 3)
            HStack {
                Text("JavaScript").font(.headline)
                if ToolCatalog.command(id: model.definition.id) != nil {
                    Text(model.definition.id)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .help("This tool’s identifier is available to the script as api.id.")
                }
            }
            AuthoringTextEditor(text: $model.definition.source, label: "Custom tool JavaScript", monospaced: true)
            Text("preview(input, options, api) returns text or a result object. Custom buttons call perform(action, input, options, api).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .disabled(model.isBusy)
    }

    private var optionsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Custom buttons").font(.headline)
                Text("Enter one action-id | Button Title per line.")
                AuthoringTextEditor(text: $model.actionLines, label: "Custom buttons, action ID and title per line", monospaced: true)
                    .frame(height: 68)
                Toggle("Allow buttons to write the clipboard", isOn: $model.allowsClipboardWrite)
                    .font(.body)
                Text("Only a custom button can write to the clipboard. Samples leave your clipboard unchanged.")
                Divider().padding(.vertical, 3)
                Text("Tool options").font(.headline)
                Text("Toolchord uses this JSON to build controls in the palette and sample inspector. Your script reads the selected values from `options`. Leave `[]` for a tool with no options.")
                AuthoringTextEditor(text: $model.optionsJSON, label: "Custom tool options JSON", monospaced: true)
                    .frame(height: 100)
                DisclosureGroup("Example option") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(#"[{"id":"uppercase","label":"Uppercase","defaultValue":"false"}]"#)
                            .font(.system(.caption, design: .monospaced))
                        Text("Read this toggle as `options.uppercase === \"true\"`. For a choice list, add `choices` with an `id` and `label` for each choice.")
                    }
                    .textSelection(.enabled)
                }
                Divider().padding(.vertical, 3)
                Text("Generator").font(.headline)
                TextField("Regenerate button title", text: $model.regenerateTitle)
                    .textFieldStyle(.roundedBorder)
                    .font(.body)
                Text("Leave the title empty for a text tool. Generators use api.seed to keep a result until Regenerate is pressed.")
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(2)
            .disabled(model.isBusy)
        }
    }
}
