import SwiftUI
import ToolchordCore

struct CustomToolEditorView: View {
    @Bindable var model: CustomToolEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Picker("Tool", selection: Binding(get: { model.documentID }, set: { model.selectDocument($0) })) {
                    Text("New Custom Tool").tag("new")
                    ForEach(model.library.definitions, id: \.id) { definition in
                        Text(definition.title).tag(definition.id)
                    }
                }
                .frame(maxWidth: 360)
                .disabled(model.isBusy || model.isDirty)
                Button("Revert Changes") { model.revert() }
                    .disabled(!model.isDirty || model.isBusy)
                Spacer()
                if model.isBusy {
                    ProgressView().controlSize(.small)
                    Button("Cancel") { model.cancelWork() }
                }
                Button(model.expected == nil ? "Save Tool" : "Update Tool") { model.save() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!model.canSave)
            }

            if let problem = model.library.loadProblem {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.triangle")
                    ScrollView {
                        Text(problem)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 80)
                    Button("Reload Saved Tools") { model.library.reload() }
                        .disabled(model.isBusy)
                }
                .font(.callout)
                .foregroundStyle(.red)
            }

            HStack(alignment: .top, spacing: 18) {
                ScrollView {
                    authoring
                        .padding(.trailing, 6)
                }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                sample
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if let message = model.message {
                Label(message, systemImage: model.isError ? "exclamationmark.triangle" : "info.circle")
                    .font(.callout)
                    .foregroundStyle(model.isError ? Color.red : Color.secondary)
                    .textSelection(.enabled)
            } else {
                Text(model.hasPendingDescription
                     ? "Your description is pending. Generate it, or Revert Changes to discard it."
                     : "Run the current draft successfully on your sample to enable Save. Samples stay in memory.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(minWidth: 820, minHeight: 620)
    }

    private var authoring: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Describe your tool").font(.headline)
            TextEditor(text: $model.description)
                .font(.body)
                .frame(height: 65)
                .border(.separator)
                .accessibilityLabel("Describe the custom tool")
            HStack {
                Button("Generate on This Mac") { model.generate() }
                    .disabled(model.isBusy || model.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.unavailableReason != nil)
                Spacer()
                Button("Check Availability") { model.refreshAvailability() }
                    .help("Refresh the on-device model status")
                    .disabled(model.isBusy)
            }
            if let reason = model.unavailableReason {
                Text(reason).font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Apple Intelligence drafts the tool on this Mac. Review and try the result before saving.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            TextField("Tool title", text: $model.definition.title)
                .textFieldStyle(.roundedBorder)
            TextField("Summary", text: $model.definition.summary)
                .textFieldStyle(.roundedBorder)
            Text("JavaScript").font(.headline)
            TextEditor(text: $model.definition.source)
                .font(.system(size: 12, design: .monospaced))
                .autocorrectionDisabled()
                .frame(height: 240)
                .border(.separator)
                .accessibilityLabel("Custom tool JavaScript")
            Text("Define preview(input, options, api) to return text or a result object. Custom buttons call perform(action, input, options, api).")
                .font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("Custom buttons and clipboard access") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("One button per line: action-id | Button Title")
                        .font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $model.actionLines)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(height: 50)
                        .border(.separator)
                        .accessibilityLabel("Custom buttons, action ID and title per line")
                    Toggle("Allow buttons to write the clipboard", isOn: $model.allowsClipboardWrite)
                    Text("Only clicking a custom button can request api.clipboard.writeText(text). Preview and sample trials do not change the system clipboard.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.top, 6)
            }
            DisclosureGroup("Options and generators") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Options JSON: [{\"id\":\"uppercase\",\"label\":\"Uppercase\",\"defaultValue\":\"false\"}]. Add choices: [{\"id\":\"value\",\"label\":\"Value\"}] for a choice control.")
                        .font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $model.optionsJSON)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(height: 65)
                        .border(.separator)
                        .accessibilityLabel("Custom tool options JSON")
                    TextField("Regenerate button title (leave empty for a text tool)", text: $model.regenerateTitle)
                        .textFieldStyle(.roundedBorder)
                    Text("Generators use api.seed for a value that stays stable until Regenerate.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.top, 6)
            }
        }
        .disabled(model.isBusy)
    }

    private var sample: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Sample input").font(.headline)
                Spacer()
                Button("Run Sample") { model.runSample() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(model.isBusy)
                if !model.draftActions.isEmpty {
                    Menu("Try Button") {
                        ForEach(model.draftActions, id: \.id) { action in
                            Button(action.title) { model.tryAction(action.id) }
                        }
                    }
                    .disabled(model.isBusy)
                }
            }
            TextEditor(text: $model.sampleInput)
                .font(.system(size: 12, design: .monospaced))
                .autocorrectionDisabled()
                .frame(minHeight: 90, maxHeight: 190)
                .border(.separator)
                .accessibilityLabel("Sample input for the custom tool")
                .disabled(model.isBusy)
            if !model.declaredOptions.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        sampleOptionControls
                    }
                }
                .frame(height: min(CGFloat(model.declaredOptions.count) * 32, 160))
            }
            Text(model.trialWasAction ? "Button would copy" : "Sample result").font(.headline)
            if let result = model.trialResult {
                if let output = result.output {
                    Text(output.status).font(.callout).foregroundStyle(.secondary)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(output.primaryText.isEmpty ? "(empty result)" : output.primaryText)
                                .font(.system(size: 12, design: .monospaced))
                            ForEach(output.fields) { field in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(field.label).font(.caption).foregroundStyle(.secondary)
                                    Text(field.value).font(.system(size: 12, design: .monospaced))
                                }
                            }
                            ForEach(Array(output.warnings.enumerated()), id: \.offset) { _, warning in
                                Text(warning).font(.callout).foregroundStyle(.orange)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .textSelection(.enabled)
                    }
                    .border(.separator)
                } else {
                    Text(result.problem ?? "The sample failed.")
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            } else {
                Text("Run your draft to see its output here.")
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var sampleOptionControls: some View {
        ForEach(model.declaredOptions, id: \.id) { option in
            if let choices = option.choices {
                Picker(option.label, selection: Binding(
                    get: { model.sampleOptions[option.id] ?? option.defaultValue },
                    set: { model.sampleOptions[option.id] = $0 }
                )) {
                    ForEach(choices, id: \.id) { choice in Text(choice.label).tag(choice.id) }
                }
                .disabled(model.isBusy)
            } else {
                Toggle(option.label, isOn: Binding(
                    get: { (model.sampleOptions[option.id] ?? option.defaultValue) == "true" },
                    set: { model.sampleOptions[option.id] = $0 ? "true" : "false" }
                ))
                .disabled(model.isBusy)
            }
        }
    }
}
