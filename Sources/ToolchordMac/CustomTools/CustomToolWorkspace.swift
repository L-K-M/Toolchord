import SwiftUI

/// Pane visibility belongs to the window, independently of the selected tool.
@MainActor
@Observable
final class CustomToolWorkspace {
    var showsSidebar = true
    var showsInspector = true
    var providerAddress = ""
    var providerKey = ""
    private var selectedProvider: AuthoringProvider?
    private var appliedAddress = ""

    var hasPendingProviderEdits: Bool {
        selectedProvider == .endpoint && (providerAddress != appliedAddress || !providerKey.isEmpty)
    }

    /// These unsent fields survive switching editor sections and leave memory with
    /// the window. Changing the destination always clears the previous credential.
    func syncProviderForm(with settings: AuthoringProviderSettings) {
        guard selectedProvider != settings.selected || appliedAddress != settings.endpoint else { return }
        selectedProvider = settings.selected
        appliedAddress = settings.endpoint
        providerAddress = settings.endpoint
        providerKey = ""
    }

    @ObservationIgnored private var document: String?
    @ObservationIgnored private var editors: [String: AuthoringTextEditor.Coordinator] = [:]

    /// NSTextView owns its typing history. Keep the editor and its delegate alive while
    /// an inspector or segment is hidden, so Undo in the window still updates the draft.
    func editor(for label: String, model: CustomToolEditorModel, text: Binding<String>) -> AuthoringTextEditor.Coordinator {
        if document != model.definition.id {
            editors.removeAll()
            document = model.definition.id
        }
        if let existing = editors[label] {
            existing.text = text
            return existing
        }
        let editor = AuthoringTextEditor.Coordinator(text: text, undo: model.undoManager)
        editors[label] = editor
        return editor
    }
}
