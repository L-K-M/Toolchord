import Foundation
import ToolchordCore

/// Raw authoring fields are recoverable even while a user is typing incomplete
/// JavaScript or JSON. Samples, generation prompts and credentials live elsewhere.
struct EditorDraftFields: Codable {
    let definition: ScriptToolDefinition
    let actionLines: String
    let optionsJSON: String
    let regenerateTitle: String
    let allowsClipboardWrite: Bool

    struct Recovery: Codable {
        let fields: EditorDraftFields
        let expected: ScriptToolDefinition?
        let baseline: Data?
        /// The source tool document, including extension metadata the editor leaves intact.
        let originalDocument: Data?

        func write(to url: URL) throws {
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                   attributes: [.posixPermissions: 0o700])
            let data = try JSONEncoder().encode(self)
            try data.write(to: url, options: .atomic)
        }
    }
}
