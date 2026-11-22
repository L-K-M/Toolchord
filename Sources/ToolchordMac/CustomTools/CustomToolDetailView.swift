import SwiftUI

struct CustomToolDetailView: View {
    private enum Page: String, CaseIterable { case describe = "Describe", script = "Script", options = "Options" }

    @Bindable var model: CustomToolEditorModel
    let workspace: CustomToolWorkspace
    @State private var page: Page

    init(model: CustomToolEditorModel, workspace: CustomToolWorkspace) {
        self.workspace = workspace
        self.model = model
        _page = State(initialValue: model.hasPendingDescription || (model.expected == nil && !model.isDirty) ? .describe : .script)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Editor section", selection: $page) {
                ForEach(Page.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Editor section")

            switch page {
            case .describe: descriptionPage
            case .script: scriptPage
            case .options: optionsPage
            }
        }
        .padding(18)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var descriptionPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Describe your tool").font(.headline)
                AuthoringTextEditor(text: $model.description, label: "Describe the custom tool", monospaced: false)
                    .frame(height: 140)
                    .overlay(alignment: .topLeading) {
                        if model.description.isEmpty {
                            Text("For example, sort lines by length and remove duplicates.")
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
            Text("JavaScript").font(.headline)
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
                Text("Enter an array of options in JSON. Each option has an id, label and defaultValue. For a choice list, add choices with an id and label.")
                AuthoringTextEditor(text: $model.optionsJSON, label: "Custom tool options JSON", monospaced: true)
                    .frame(height: 100)
                DisclosureGroup("Example option") {
                    Text(#"[{"id":"uppercase","label":"Uppercase","defaultValue":"false"}]"#)
                        .font(.system(.caption, design: .monospaced))
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
