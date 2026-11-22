import Foundation

enum LocalHarness {
    private static let supported = ["codex", "claude"]
    private static let catalogLimit = 8 * 1024 * 1024
    private static let responseLimit = 1024 * 1024

    static func available() -> [String] {
        let directories = searchDirectories(environment: ProcessInfo.processInfo.environment)
        return supported.filter { executable(for: $0, in: directories) != nil }
    }

    static func models(provider: String, environment: [String: String] = ProcessInfo.processInfo.environment) async throws -> [String] {
        try await inWorkspace(provider, environment: environment) { executable, directory, environment in
            let data: Data
            if provider == "codex" {
                data = try await run(executable, ["debug", "models"], directory: directory, environment: environment,
                                     timeout: .seconds(30), outputLimit: catalogLimit)
                return try codexModelIDs(data)
            }
            // The SDK initialization handshake lists models without creating a model turn.
            let request = #"{"type":"control_request","request_id":"toolchord","request":{"subtype":"initialize"}}"# + "\n"
            data = try await run(executable, claudeOptions + ["--input-format", "stream-json", "--output-format", "stream-json", "--verbose"],
                                 input: Data(request.utf8), directory: directory, environment: environment, timeout: .seconds(25))
            for line in data.split(separator: 10) {
                guard let message = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                      message["type"] as? String == "control_response",
                      let envelope = message["response"] as? [String: Any], envelope["request_id"] as? String == "toolchord",
                      let content = envelope["response"] as? [String: Any], let models = content["models"] as? [[String: Any]]
                else { continue }
                return uniqueIDs(models.compactMap { $0["value"] as? String }.filter { $0 != "default" })
            }
            throw HarnessError("Claude Code didn’t return its model list. Enter a model ID or use its default.")
        }
    }

    static func generate(provider: String, model: String, prompt: String,
                         environment: [String: String] = ProcessInfo.processInfo.environment) async throws -> String {
        guard !prompt.isEmpty, prompt.utf8.count <= 512 * 1024 else { throw HarnessError("The tool description is empty or too long.") }
        guard model.isEmpty || validID(model) else { throw HarnessError("Enter a valid harness model ID.") }
        return try await inWorkspace(provider, environment: environment) { executable, directory, environment in
            let modelArguments = model.isEmpty ? [] : ["--model", model]
            let arguments: [String]
            if provider == "codex" {
                // The CLI's catalog can enable model-specific tools such as apply_patch
                // independently of its global shell setting. Keep this CLI version's
                // model metadata and remove tool declarations from the private copy.
                let catalog: Data
                do {
                    catalog = try await run(executable, ["debug", "models"], directory: directory,
                                            environment: environment, timeout: .seconds(25), outputLimit: catalogLimit)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    // A manually entered model can still run when discovery is unavailable.
                    catalog = try await run(executable, ["debug", "models", "--bundled"], directory: directory,
                                            environment: environment, timeout: .seconds(15), outputLimit: catalogLimit)
                }
                let catalogURL = directory.appendingPathComponent("models.json")
                try textOnlyCatalog(catalog).write(to: catalogURL)
                let pathEncoder = JSONEncoder()
                pathEncoder.outputFormatting = [.withoutEscapingSlashes]
                let catalogPath = String(decoding: try pathEncoder.encode(catalogURL.path), as: UTF8.self)
                arguments = codexOptions + ["-c", "model_catalog_json=" + catalogPath] + modelArguments + ["-"]
            } else {
                arguments = claudeOptions + ["--output-format", "json"] + modelArguments
            }
            let data = try await run(executable, arguments, input: Data(prompt.utf8), directory: directory, environment: environment,
                                     timeout: .seconds(120))
            let reply: String?
            if provider == "claude" {
                let result = try JSONDecoder().decode(ClaudeResult.self, from: data)
                guard result.subtype == "success", result.is_error != true else {
                    throw HarnessError("Claude Code could not complete this request. Check your CLI sign-in, model and usage limits.")
                }
                reply = result.result
            } else {
                reply = String(data: data, encoding: .utf8)
            }
            guard let reply, !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw HarnessError("The harness returned an empty response.")
            }
            return reply
        }
    }

    private struct ClaudeResult: Decodable {
        let subtype: String, is_error: Bool?, result: String?
    }

    private static let claudeOptions = [
        "--print", "--safe-mode", "--no-session-persistence", "--permission-mode", "dontAsk",
        "--disable-slash-commands", "--no-chrome", "--strict-mcp-config", "--mcp-config", #"{"mcpServers":{}}"#,
        "--system-prompt", "Return the requested Toolchord tool definition as JSON.", "--tools", ""
    ]

    private static let codexOptions: [String] = {
        var options = ["-a", "never", "exec", "--strict-config", "--ignore-user-config", "--ignore-rules",
                       "--ephemeral", "--skip-git-repo-check", "--sandbox", "read-only", "--color", "never"]
        let settings = ["project_doc_max_bytes=0", "skills.include_instructions=false", "web_search=\"disabled\"",
                        "agents.enabled=false", "mcp_servers={}", "tools.update_plan.enabled=false",
                        "tools.experimental_request_user_input.enabled=false"]
        let disabled = ["shell_tool", "unified_exec", "apps", "plugins", "view_image", "multi_agent", "multi_agent_v2",
                        "code_mode", "code_mode_host", "hooks", "image_generation", "browser_use", "computer_use",
                        "memories", "skill_search", "search_tool", "tool_search", "goals"]
        for setting in settings + disabled.map({ "features." + $0 + "=false" }) { options += ["-c", setting] }
        return options
    }()

    private static func textOnlyCatalog(_ data: Data) throws -> Data {
        guard var catalog = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var models = catalog["models"] as? [[String: Any]], !models.isEmpty else {
            throw HarnessError("Update Codex CLI to a version that supports model catalogs.")
        }
        for index in models.indices {
            models[index]["apply_patch_tool_type"] = NSNull()
            models[index]["experimental_supported_tools"] = [String]()
            models[index]["node_repl_disabled"] = true
            models[index]["tool_mode"] = "direct"
        }
        catalog["models"] = models
        return try JSONSerialization.data(withJSONObject: catalog)
    }

    private static func codexModelIDs(_ data: Data) throws -> [String] {
        guard let catalog = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = catalog["models"] as? [[String: Any]] else {
            throw HarnessError("Codex CLI didn’t return its model list. Enter a model ID or use its default.")
        }
        return uniqueIDs(models.filter { ($0["visibility"] as? String ?? "list") == "list" }.compactMap { $0["slug"] as? String })
    }

    private static func uniqueIDs(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for id in ids where validID(id) && seen.insert(id).inserted {
            result.append(id)
            if result.count == 512 { break }
        }
        return result
    }

    private static func validID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 256 && !value.hasPrefix("-") &&
            value.unicodeScalars.allSatisfy { !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.controlCharacters.contains($0) }
    }

    private static func inWorkspace<T: Sendable>(_ provider: String, environment inherited: [String: String],
        operation: (URL, URL, [String: String]) async throws -> T) async throws -> T {
        let directories = searchDirectories(environment: inherited)
        guard let executable = executable(for: provider, in: directories) else { throw HarnessError("Install the selected CLI and sign in.") }
        let files = FileManager.default
        let directory = files.temporaryDirectory.appendingPathComponent("ToolchordHarness-" + UUID().uuidString, isDirectory: true)
        try files.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? files.removeItem(at: directory) }
        var environment = inherited
        environment["PATH"] = directories.map(\.path).joined(separator: ":")
        // A GUI process can inherit integration settings from the app that
        // launched it. Never attach this invocation to a containing CLI session.
        for name in ["CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "CODEX_THREAD_ID"] { environment.removeValue(forKey: name) }
        return try await operation(executable, directory, environment)
    }

    private static func searchDirectories(environment: [String: String]) -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        var seen = Set<String>()
        return (path + [home + "/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", home + "/.volta/bin",
                        home + "/.bun/bin", "/usr/bin", "/bin"]).filter { $0.hasPrefix("/") && seen.insert($0).inserted }
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    private static func executable(for provider: String, in directories: [URL]) -> URL? {
        guard supported.contains(provider) else { return nil }
        return directories.lazy.map { $0.appendingPathComponent(provider) }.first {
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: $0.path, isDirectory: &isDirectory) && !isDirectory.boolValue &&
                FileManager.default.isExecutableFile(atPath: $0.path)
        }
    }

    private static func run(_ executable: URL, _ arguments: [String], input: Data = Data(), directory: URL,
                            environment: [String: String], timeout: Duration, outputLimit: Int = responseLimit) async throws -> Data {
        try await LocalHarnessProcess.run(executable: executable, arguments: arguments, input: input, directory: directory,
                                          environment: environment, timeout: timeout, outputLimit: outputLimit)
    }
}
