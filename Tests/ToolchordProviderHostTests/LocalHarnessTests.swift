import Foundation
import Testing
@testable import ToolchordProviderHost

struct LocalHarnessTests {
    private func withCLI(_ name: String, script: String, test: ([String: String]) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cli = directory.appendingPathComponent(name)
        try ("#!/bin/sh\nset -eu\n" + script).write(to: cli, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cli.path)
        try await test(["PATH": directory.path])
    }

    @Test func codexListsVisibleModelsAndUsesSelectedModel() async throws {
        try await withCLI("codex", script: #"""
        if [ "$1" = debug ]; then
          echo '{"models":[{"slug":"tool-model","visibility":"list","apply_patch_tool_type":"freeform"},{"slug":"hidden","visibility":"hide"},{"slug":"tool-model","visibility":"list"}]}'
        else
          case " $* " in *" --model tool-model - ") ;; *) exit 3;; esac
          case " $* " in *" --sandbox read-only "*) ;; *) exit 4;; esac
          case " $* " in *" --ignore-user-config "*) ;; *) exit 5;; esac
          /usr/bin/grep -q '"apply_patch_tool_type":null' models.json
          /bin/cat
        fi
        """#, test: { environment in
            let models = try await LocalHarness.models(provider: "codex", environment: environment)
            #expect(models == ["tool-model"])
            let prompt = "A private description\nwith 'quotes' and $shell syntax"
            let result = try await LocalHarness.generate(provider: "codex", model: "tool-model", prompt: prompt, environment: environment)
            #expect(result == prompt)
        })
    }

    @Test func claudeUsesInitializationAndTextOnlyPrintMode() async throws {
        try await withCLI("claude", script: #"""
        case " $* " in *" --strict-mcp-config "*) ;; *) exit 3;; esac
        case " $* " in *" --tools  "*) ;; *) exit 4;; esac
        if [ "$1" = "--print" ] && [ "$(/bin/cat)" != "private authoring request" ]; then
          echo '{"type":"control_response","response":{"request_id":"toolchord","response":{"models":[{"value":"default"},{"value":"sonnet"},{"value":"model-a"},{"value":"sonnet"}]}}}'
        else
          case " $* " in *" --model "*) exit 5;; esac
          printf '%s\n' '{"type":"result","subtype":"success","result":"generated source","is_error":false}'
        fi
        """#, test: { environment in
            let models = try await LocalHarness.models(provider: "claude", environment: environment)
            #expect(models == ["sonnet", "model-a"])
            let result = try await LocalHarness.generate(provider: "claude", model: "", prompt: "private authoring request", environment: environment)
            #expect(result == "generated source")
        })
    }

    @Test func rejectsUnknownProviderAndModelFlags() async {
        await #expect(throws: HarnessError.self) { try await LocalHarness.models(provider: "/bin/sh") }
        await #expect(throws: HarnessError.self) { try await LocalHarness.generate(provider: "codex", model: "--bad", prompt: "x") }
    }
}
