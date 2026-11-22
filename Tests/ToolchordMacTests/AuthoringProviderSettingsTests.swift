import AppKit
import Foundation
import SwiftUI
import Testing
@testable import ToolchordMac

@MainActor
private final class AuthoringTestHost: AuthoringProviderAccess {
    var installed = ["codex", "unknown", "ollama", "claude"]
    var list: (String, String) async throws -> [String] = { _, _ in [] }
    var keys: [String: String] = [:]

    func harnesses() async throws -> [String] { installed }
    func models(provider: String, endpoint: String) async throws -> [String] { try await list(provider, endpoint) }
    func setKey(_ key: String?, endpoint: String) async throws { keys[endpoint] = key }
    func hasKey(endpoint: String) async throws -> Bool { keys[endpoint] != nil }
}

@MainActor @Suite struct AuthoringProviderSettingsTests {
    private let suite = "ToolchordProviderTests." + UUID().uuidString
    private var defaults: UserDefaults { UserDefaults(suiteName: suite)! }

    @Test func discoveryListsInstalledHarnessesAndPreservesSelection() async {
        defer { defaults.removePersistentDomain(forName: suite) }
        let host = AuthoringTestHost()
        let settings = AuthoringProviderSettings(defaults: defaults, host: host)
        await settings.discover()
        #expect(settings.selected == .apple)
        #expect(settings.choices == [.apple, .codex, .claude, .ollama, .endpoint])
        settings.select(.codex)
        host.installed = ["claude"]
        await settings.discover()
        #expect(settings.selected == .codex)
        #expect(settings.generationProblem != nil)
        #expect(settings.detected == [.claude])
    }

    @Test func modelsPersistPerHarnessAndEndpoint() {
        defer { defaults.removePersistentDomain(forName: suite) }
        let host = AuthoringTestHost()
        let settings = AuthoringProviderSettings(defaults: defaults, host: host)
        settings.select(.codex)
        settings.setModel("codex-model")
        settings.select(.claude)
        settings.setModel("claude-model")
        settings.select(.endpoint)
        #expect(settings.useEndpoint("https://one.example"))
        settings.setModel("first-model")
        #expect(settings.useEndpoint("http://localhost:8080/v1"))
        settings.setModel("second-model")

        let reopened = AuthoringProviderSettings(defaults: defaults, host: host)
        #expect(reopened.selected == .endpoint && reopened.model == "second-model")
        #expect(reopened.useEndpoint("https://ONE.example/v1/"))
        #expect(reopened.model == "first-model")
        reopened.select(.codex)
        #expect(reopened.model == "codex-model")
        reopened.select(.claude)
        #expect(reopened.model == "claude-model")
    }

    @Test func ollamaRequiresAnInstalledModelAndReportsServerOrInventoryChanges() async {
        defer { defaults.removePersistentDomain(forName: suite) }
        let host = AuthoringTestHost()
        let settings = AuthoringProviderSettings(defaults: defaults, host: host)
        await settings.discover()
        settings.select(.ollama)
        host.list = { _, _ in throw URLError(.cannotConnectToHost) }
        await settings.loadModels()
        #expect(settings.modelMessage?.contains("local server") == true)
        #expect(settings.generationProblem != nil)
        host.list = { provider, endpoint in
            #expect(provider == "ollama" && endpoint.isEmpty)
            return ["local-model:latest"]
        }
        await settings.loadModels()
        #expect(settings.model.isEmpty)
        settings.setModel("local-model:latest")
        #expect(settings.generationProblem == nil)
        host.list = { _, _ in [] }
        await settings.loadModels()
        #expect(settings.generationProblem != nil && settings.modelMessage?.contains("Download a model") == true)
        let reopened = AuthoringProviderSettings(defaults: defaults, host: host)
        #expect(reopened.selected == .ollama && reopened.model == "local-model:latest")
    }

    @Test func invalidAddressesNeverReplaceEndpointOrEnterPreferences() {
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AuthoringProviderSettings(defaults: defaults, host: AuthoringTestHost())
        settings.select(.endpoint)
        #expect(settings.useEndpoint("https://one.example"))
        for address in ["https://user:private@two.example/v1", "https://two.example?key=private", "https://two.example/#private"] {
            #expect(!settings.useEndpoint(address))
        }
        #expect(settings.endpoint == "https://one.example/v1")
        #expect(!(defaults.persistentDomain(forName: suite) ?? [:]).description.contains("private"))
    }

    @Test func listingFailureKeepsManualModelUsable() async {
        defer { defaults.removePersistentDomain(forName: suite) }
        let host = AuthoringTestHost()
        host.list = { _, _ in throw URLError(.cannotConnectToHost) }
        let settings = AuthoringProviderSettings(defaults: defaults, host: host)
        settings.select(.endpoint)
        #expect(settings.useEndpoint("https://one.example"))
        settings.setModel("manual-id")
        await settings.loadModels()
        #expect(settings.modelMessage != nil)
        #expect(settings.selection.model == "manual-id")
        #expect(settings.generationProblem == nil)
    }

    @Test func lateModelListCannotReplaceNewSelection() async {
        defer { defaults.removePersistentDomain(forName: suite) }
        let host = AuthoringTestHost()
        let entered = AsyncStream<Void>.makeStream()
        let release = AsyncStream<Void>.makeStream()
        host.list = { provider, _ in
            if provider == "codex" {
                entered.continuation.finish()
                for await _ in release.stream {}
                return ["old-model"]
            }
            return ["new-model", "new-model"]
        }
        let settings = AuthoringProviderSettings(defaults: defaults, host: host)
        settings.select(.codex)
        let pending = Task { await settings.loadModels() }
        for await _ in entered.stream {}
        settings.select(.claude)
        await settings.loadModels()
        release.continuation.finish()
        await pending.value
        #expect(settings.availableModels == ["new-model"])
    }

    @Test func keyIsScopedToTheAppliedEndpointAndKeptOutOfPreferences() async {
        defer { defaults.removePersistentDomain(forName: suite) }
        let host = AuthoringTestHost()
        let settings = AuthoringProviderSettings(defaults: defaults, host: host)
        settings.select(.endpoint)
        #expect(settings.useEndpoint("https://one.example"))
        #expect(await settings.updateKey("private-secret"))
        #expect(settings.keyStored == true)
        #expect(host.keys == ["https://one.example/v1": "private-secret"])
        #expect(!(defaults.persistentDomain(forName: suite) ?? [:]).description.contains("private-secret"))
        #expect(settings.useEndpoint("https://two.example"))
        await settings.checkKey()
        #expect(settings.keyStored == false)
        #expect(settings.useEndpoint("https://one.example"))
        await settings.checkKey()
        #expect(settings.keyStored == true)
        #expect(await settings.updateKey(nil))
        #expect(host.keys.isEmpty && settings.keyStored == false)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["TOOLCHORD_RENDER_CUSTOM_EDITOR"] == "1"))
    func renderConfiguredEndpointAtMinimumWindowSize() async throws {
        defer { defaults.removePersistentDomain(forName: suite) }
        let access = AuthoringTestHost()
        access.list = { _, _ in ["text-small", "text-large"] }
        let settings = AuthoringProviderSettings(defaults: defaults, host: access)
        settings.select(.endpoint)
        #expect(settings.useEndpoint("http://localhost:1234/v1"))
        #expect(await settings.updateKey("test-key"))
        await settings.loadModels()
        settings.setModel("text-large")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = CustomToolLibrary(store: ScriptToolStore(directoryURL: folder))
        let editor = CustomToolEditorModel(library: library, providers: settings)
        editor.description = "Convert a list of keys to a JSON array."
        _ = NSApplication.shared
        let view = NSHostingView(rootView: CustomToolEditorView(model: editor).background(Color(nsColor: .windowBackgroundColor)))
        let rect = NSRect(x: 0, y: 0, width: 820, height: 620)
        let window = NSWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = view
        window.layoutIfNeeded()
        for _ in 0..<4 {
            view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(60))
        }
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("toolchord-custom-provider.png"))
    }
}
