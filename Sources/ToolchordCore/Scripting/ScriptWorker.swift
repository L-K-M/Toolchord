import Darwin
import Foundation
import os

/// User code runs in a disposable process. A synchronous loop or a large
/// allocation there must never take down the palette or block the next draft.
public enum ScriptWorker {
    public static let argument = "--toolchord-script-worker"
    private static let requestLimit = 12 * 1024 * 1024

    private struct Invocation: Codable {
        let id, source: String
        let input, action, capturedSeed: String?
        let requiresActionHandler: Bool?
        let options: [String: String]
        let now: Date
        let timeZone: String
        let maxInput, maxOutput, maxDepth: Int
    }

    public static func serve() {
        // A second limit still applies if the parent disappears mid-run.
        alarm(8)
        do {
            let bytes = try readBounded(.standardInput, limit: requestLimit)
            let invocation = try JSONDecoder().decode(Invocation.self, from: bytes)
            let limits = ToolLimits(maxInputBytes: invocation.maxInput, maxOutputBytes: invocation.maxOutput, maxNestingDepth: invocation.maxDepth)
            var request = ToolRequest(input: invocation.input.map(ToolInput.text) ?? .none,
                                      options: ToolOptions(invocation.options), now: invocation.now,
                                      timeZone: TimeZone(identifier: invocation.timeZone) ?? .gmt, limits: limits)
            if let captured = invocation.capturedSeed {
                let seed = try JSONDecoder().decode(CapturedSeed.self, from: Data(captured.utf8))
                let context = SeedContext(now: seed.now, options: ToolOptions(seed.options))
                request.seed = try ScriptRuntime.seed(id: invocation.id, source: invocation.source, context: context, entropy: Array(seed.entropy))
            }
            let reply = try ScriptRuntime.evaluate(id: invocation.id, source: invocation.source, request: request, action: invocation.action,
                                                   requiresActionHandler: invocation.requiresActionHandler == true)
            try FileHandle.standardOutput.write(contentsOf: ScriptRuntime.checkedUserResponse(reply))
        } catch {
            let reply = ["error": "invalid", "message": error.localizedDescription]
            if let bytes = try? JSONEncoder().encode(reply) { try? FileHandle.standardOutput.write(contentsOf: bytes) }
        }
    }

    private struct CapturedSeed: Codable {
        let entropy: Data
        let now: Date
        let options: [String: String]
    }

    /// Capture randomness and the clock on selection. User-supplied makeSeed
    /// runs in the worker so it cannot block the main actor.
    static func captureSeed(_ context: SeedContext) -> String {
        let seed = CapturedSeed(entropy: Data((0..<512).map { _ in UInt8.random(in: .min ... .max) }),
                                now: context.now, options: context.options.values)
        guard let data = try? JSONEncoder().encode(seed) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    static func run(id: String, source: String, request: ToolRequest, action: String? = nil, requiresActionHandler: Bool = false) -> ToolResult {
        if request.cancellation.isCancelled { return .cancelled }
        do {
            let invocation = Invocation(id: id, source: source, input: request.input.text, action: action, capturedSeed: request.seed,
                                        requiresActionHandler: requiresActionHandler,
                                        options: request.options.values, now: request.now,
                                        timeZone: request.timeZone.identifier, maxInput: request.limits.maxInputBytes,
                                        maxOutput: request.limits.maxOutputBytes, maxDepth: request.limits.maxNestingDepth)
            let data = try JSONEncoder().encode(invocation)
            guard data.count <= requestLimit else { return .tooLarge(request.limits.inputLimitMessage) }
            let process = Process()
            let app = Bundle.main
            if app.bundleURL.pathExtension == "app", app.bundleIdentifier == "ch.lkmc.Toolchord" {
                process.executableURL = app.executableURL
                process.arguments = [argument]
            } else {
                // SwiftPM places executable products alongside the test bundle.
                let directory = Bundle(for: ScriptWorkerAnchor.self).bundleURL.deletingLastPathComponent()
                let candidates = [directory, app.bundleURL, app.executableURL?.deletingLastPathComponent()].compactMap { $0 }
                process.executableURL = candidates.map { $0.appendingPathComponent("toolchord-script-runner") }
                    .first { FileManager.default.isExecutableFile(atPath: $0.path) }
            }
            guard process.executableURL != nil else { throw ScriptFailure("Could not locate the Toolchord script runner.") }
            let input = Pipe(), output = Pipe()
            process.standardInput = input
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            try process.run()
            let inputHandle = input.fileHandleForWriting
            _ = fcntl(inputHandle.fileDescriptor, F_SETNOSIGPIPE, 1)
            DispatchQueue.global().async {
                try? inputHandle.write(contentsOf: data)
                try? inputHandle.close()
            }
            let pid = process.processIdentifier
            let deadline = ContinuousClock.now + .seconds(3)
            let completed = DispatchSemaphore(value: 0)
            let response = OSAllocatedUnfairLock<Result<Data, any Error>?>(initialState: nil)
            DispatchQueue.global(qos: .userInitiated).async {
                let reply = Result { try readBounded(output.fileHandleForReading, limit: ScriptRuntime.wireLimit) }
                response.withLock { $0 = reply }
                completed.signal()
            }
            // Poll on the calling task: Task.isCancelled belongs to that task,
            // not to the Dispatch queue draining the child's pipe.
            while completed.wait(timeout: .now() + .milliseconds(25)) == .timedOut {
                guard process.isRunning else { continue }
                var info = proc_taskinfo()
                let size = Int32(MemoryLayout.size(ofValue: info))
                let overMemory = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size && info.pti_resident_size > 256 * 1024 * 1024
                if request.cancellation.isCancelled || ContinuousClock.now >= deadline || overMemory {
                    _ = kill(pid, SIGKILL)
                }
            }
            let reply: Data
            do {
                guard let result = response.withLock({ $0 }) else { throw ScriptFailure("Missing script response.") }
                reply = try result.get()
            } catch {
                if process.isRunning { _ = kill(pid, SIGKILL) }
                process.waitUntilExit()
                throw error
            }
            process.waitUntilExit()
            if request.cancellation.isCancelled { return .cancelled }
            guard process.terminationStatus == 0 else { throw ScriptFailure("The script stopped or exceeded its time or memory limit.") }
            return try ScriptRuntime.result(reply, limits: request.limits)
        } catch {
            return .invalid(ToolDiagnostic(error.localizedDescription))
        }
    }

    private static func readBounded(_ handle: FileHandle, limit: Int) throws -> Data {
        var data = Data()
        while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            guard data.count <= limit - chunk.count else { throw ScriptFailure("Script data exceeds the size limit.") }
            data.append(chunk)
        }
        return data
    }
}

private final class ScriptWorkerAnchor: NSObject {}
