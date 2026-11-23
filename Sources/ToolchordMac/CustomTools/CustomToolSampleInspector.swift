import SwiftUI
import ToolchordCore

struct CustomToolSampleInspector: View {
    @Bindable var model: CustomToolEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Sample input").font(.headline)
                Spacer()
                if !model.draftActions.isEmpty {
                    Menu("Try Button") {
                        ForEach(model.draftActions, id: \.id) { action in
                            Button(action.title) { model.tryAction(action.id) }
                        }
                    }
                    .fixedSize()
                    .controlSize(.small)
                    .disabled(model.isBusy)
                }
            }

            AuthoringTextEditor(text: $model.sampleInput, label: "Sample input for the custom tool", monospaced: true)
                .frame(minHeight: 90, idealHeight: 150, maxHeight: 180)
                .disabled(model.isBusy)
            if !model.declaredOptions.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(model.declaredOptions, id: \.id) { option in
                            sampleOptionControl(option)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: min(CGFloat(model.declaredOptions.count) * 36, 150))
                .disabled(model.isBusy)
            }
            Divider().padding(.vertical, 3)
            Text(model.trialWasAction && model.trialResult != nil ? "Button would copy" : "Sample result")
                .font(.headline)

            if let result = model.trialResult {
                ScrollView {
                    resultContent(result)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            } else {
                Text("Run a sample to see its result.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private func sampleOptionControl(_ option: ScriptOption) -> some View {
        if let choices = option.choices {
            Picker(option.label, selection: Binding(
                get: { model.sampleOptions[option.id] ?? option.defaultValue },
                set: { model.sampleOptions[option.id] = $0 }
            )) {
                ForEach(choices, id: \.id) { choice in Text(choice.label).tag(choice.id) }
            }
        } else {
            Toggle(option.label, isOn: Binding(
                get: { (model.sampleOptions[option.id] ?? option.defaultValue) == "true" },
                set: { model.sampleOptions[option.id] = $0 ? "true" : "false" }
            ))
        }
    }

    @ViewBuilder
    private func resultContent(_ result: ToolResult) -> some View {
        if let output = result.output {
            VStack(alignment: .leading, spacing: 10) {
                Text(output.status).font(.callout).foregroundStyle(.secondary)
                Text(output.primaryText.isEmpty ? "(empty result)" : output.primaryText)
                    .font(.system(.body, design: .monospaced))

                ForEach(output.fields) { field in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(field.label).font(.caption).foregroundStyle(.secondary)
                        Text(field.value).font(field.isMonospaced ? .system(.body, design: .monospaced) : .body)
                        if let note = field.note {
                            Text(note).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                ForEach(Array(output.warnings.enumerated()), id: \.offset) { _, warning in
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                }
            }
        } else {
            Label(result.problem ?? "The sample failed.", systemImage: "exclamationmark.triangle")
                .font(.callout)
        }
    }
}
