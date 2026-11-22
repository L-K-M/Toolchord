import Foundation
import Testing
@testable import ToolchordProviderHost

@Suite(.timeLimit(.minutes(1)))
struct LocalHarnessProcessTests {
    private func run(_ path: String, _ args: [String] = [], input: Data = Data(),
                     limit: Int = 1024 * 1024, timeout: Duration = .seconds(10)) async throws -> Data {
        try await LocalHarnessProcess.run(executable: URL(fileURLWithPath: path), arguments: args,
                                          input: input, directory: FileManager.default.temporaryDirectory,
                                          environment: [:], timeout: timeout, outputLimit: limit)
    }

    @Test func preservesBytesAcrossFullPipes() async throws {
        let payload = Data(String(repeating: "é\u{301}\n🐾", count: 42_000).utf8)
        #expect(try await run("/bin/cat", input: payload) == payload)
        #expect(try await run("/bin/cat").isEmpty)
    }

    @Test func boundsOutputAndRuntime() async {
        await #expect(throws: HarnessError.self) {
            try await run("/usr/bin/yes", limit: 200)
        }
        await #expect(throws: HarnessError.self) {
            try await run("/bin/sleep", ["5"], timeout: .milliseconds(75))
        }
        await #expect(throws: HarnessError.self) { try await run("/usr/bin/false") }
    }

    @Test func cancellationStopsTheHarness() async throws {
        let task = Task { try await run("/bin/sleep", ["10"]) }
        try await Task.sleep(for: .milliseconds(75))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
