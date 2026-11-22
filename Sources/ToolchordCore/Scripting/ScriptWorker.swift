import Darwin
import Foundation

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
            let executable: URL?
            let arguments: [String]
            let app = Bundle.main
            if app.bundleURL.pathExtension == "app", app.bundleIdentifier == "ch.lkmc.Toolchord" {
                executable = app.executableURL
                arguments = [argument]
            } else {
                // SwiftPM places executable products alongside the test bundle.
                let directory = Bundle(for: ScriptWorkerAnchor.self).bundleURL.deletingLastPathComponent()
                let candidates = [directory, app.bundleURL, app.executableURL?.deletingLastPathComponent()].compactMap { $0 }
                executable = candidates.map { $0.appendingPathComponent("toolchord-script-runner") }
                    .first { FileManager.default.isExecutableFile(atPath: $0.path) }
                arguments = []
            }
            guard let executable else { throw ScriptFailure("Could not locate the Toolchord script runner.") }
            let reply = try exchange(data, executable: executable, arguments: arguments, cancellation: request.cancellation)
            if request.cancellation.isCancelled { return .cancelled }
            return try ScriptRuntime.result(reply, limits: request.limits)
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .invalid(ToolDiagnostic(error.localizedDescription))
        }
    }

    private static let stoppedMessage = "The script stopped or exceeded its time or memory limit."
    private static let chunkSize = 64 * 1024

    /// Own both pipes and the child on this calling thread. Blocking a Swift
    /// task while dispatching its pipe work can starve the cooperative pool.
    /// Nonblocking I/O also keeps cancellation and the deadline active through
    /// partial requests, full response pipes, missing EOF, and child shutdown.
    private static func exchange(_ data: Data, executable: URL, arguments: [String], cancellation: CancellationCheck) throws -> Data {
        var input = try makePipe()
        defer { input.closeAll() }
        var output = try makePipe()
        defer { output.closeAll() }
        try nonblocking(input.writeFD)
        try nonblocking(output.readFD)
        guard fcntl(input.writeFD, F_SETNOSIGPIPE, 1) != -1 else { throw systemError() }

        let pid = try spawn(executable, arguments: arguments, input: input.readFD, output: output.writeFD)
        // Only our waitpid reaps this child, reserving its PID until then. Never
        // signal a PID after it was reaped, even if the response pipe stays open.
        var ownsChild = true
        var exitStatus: Int32?
        defer { if ownsChild { terminateAndReap(pid) } }
        input.closeRead()
        output.closeWrite()

        let deadline = ContinuousClock.now + .seconds(3)
        var written = 0
        var response = Data()
        var buffer = [UInt8](repeating: 0, count: chunkSize)
        while true {
            if cancellation.isCancelled { throw CancellationError() }
            guard ContinuousClock.now < deadline else { throw ScriptFailure(stoppedMessage) }

            if ownsChild {
                var status: Int32 = 0
                let waited = waitpid(pid, &status, WNOHANG)
                if waited == pid {
                    ownsChild = false
                    exitStatus = status
                } else if waited == -1, errno != EINTR {
                    // ECHILD means somebody else already reaped it. Do not risk
                    // signalling a recycled PID during error cleanup.
                    if errno == ECHILD { ownsChild = false }
                    throw systemError()
                }
                if ownsChild {
                    var info = proc_taskinfo()
                    let size = Int32(MemoryLayout.size(ofValue: info))
                    if proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size,
                       info.pti_resident_size > 256 * 1024 * 1024 {
                        throw ScriptFailure(stoppedMessage)
                    }
                }
            }

            if output.readFD != -1 {
                let count = buffer.withUnsafeMutableBytes { Darwin.read(output.readFD, $0.baseAddress, $0.count) }
                if count > 0 {
                    guard response.count <= ScriptRuntime.wireLimit - count else {
                        throw ScriptFailure("Script data exceeds the size limit.")
                    }
                    response.append(contentsOf: buffer.prefix(count))
                } else if count == 0 {
                    output.closeRead()
                } else if errno != EAGAIN, errno != EWOULDBLOCK, errno != EINTR {
                    throw systemError()
                }
            }
            if input.writeFD != -1 {
                let count = data.withUnsafeBytes { bytes in
                    Darwin.write(input.writeFD, bytes.baseAddress!.advanced(by: written), min(chunkSize, data.count - written))
                }
                if count > 0 {
                    written += count
                    if written == data.count { input.closeWrite() }
                } else if count == -1 {
                    if errno == EPIPE { input.closeWrite() }
                    else if errno != EAGAIN, errno != EWOULDBLOCK, errno != EINTR { throw systemError() }
                }
            }
            if let exitStatus, output.readFD == -1 {
                guard exitStatus == 0 else { throw ScriptFailure(stoppedMessage) }
                return response
            }

            var descriptors = [
                pollfd(fd: output.readFD, events: Int16(POLLIN), revents: 0),
                pollfd(fd: input.writeFD, events: Int16(POLLOUT), revents: 0)
            ]
            let ready = descriptors.withUnsafeMutableBufferPointer { Darwin.poll($0.baseAddress, nfds_t($0.count), 25) }
            if ready == -1, errno != EINTR { throw systemError() }
        }
    }

    private struct PipeDescriptors {
        var readFD: Int32
        var writeFD: Int32

        mutating func closeRead() { Self.close(&readFD) }
        mutating func closeWrite() { Self.close(&writeFD) }
        mutating func closeAll() { closeRead(); closeWrite() }

        private static func close(_ descriptor: inout Int32) {
            guard descriptor != -1 else { return }
            let owned = descriptor
            descriptor = -1
            _ = Darwin.close(owned)
        }
    }

    private static func makePipe() throws -> PipeDescriptors {
        var descriptors: [Int32] = [-1, -1]
        guard Darwin.pipe(&descriptors) == 0 else { throw systemError() }
        var pipe = PipeDescriptors(readFD: descriptors[0], writeFD: descriptors[1])
        do {
            // Keep child dup2 actions away from stdio numbers even when the
            // launching application has a closed standard descriptor.
            for index in descriptors.indices {
                let replacement = fcntl(descriptors[index], F_DUPFD_CLOEXEC, 3)
                guard replacement != -1 else { throw systemError() }
                _ = Darwin.close(descriptors[index])
                if index == 0 { pipe.readFD = replacement }
                else { pipe.writeFD = replacement }
            }
            return pipe
        } catch {
            pipe.closeAll()
            throw error
        }
    }

    private static func nonblocking(_ descriptor: Int32) throws {
        let flags = fcntl(descriptor, F_GETFL)
        guard flags != -1, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) != -1 else { throw systemError() }
    }

    private static func spawn(_ executable: URL, arguments: [String], input: Int32, output: Int32) throws -> pid_t {
        var actions: posix_spawn_file_actions_t?
        try check(posix_spawn_file_actions_init(&actions))
        defer { posix_spawn_file_actions_destroy(&actions) }
        try check(posix_spawn_file_actions_adddup2(&actions, input, STDIN_FILENO))
        try check(posix_spawn_file_actions_adddup2(&actions, output, STDOUT_FILENO))
        try check(posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0))
        var attributes: posix_spawnattr_t?
        try check(posix_spawnattr_init(&attributes))
        defer { posix_spawnattr_destroy(&attributes) }
        // Inherit only the explicitly configured stdio, never another worker's
        // pipe endpoints or application files. Otherwise EOF can be delayed.
        try check(posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT)))
        var argv = ([executable.path] + arguments).map { strdup($0) }
        defer { argv.forEach { free($0) } }
        guard argv.allSatisfy({ $0 != nil }) else { throw ScriptFailure("Could not allocate script launch arguments.") }
        argv.append(nil)
        var pid: pid_t = 0
        try executable.path.withCString { path in
            try argv.withUnsafeMutableBufferPointer { arguments in
                try check(posix_spawn(&pid, path, &actions, &attributes, arguments.baseAddress, environ))
            }
        }
        return pid
    }

    /// SIGKILL normally reaps immediately. Bound cleanup too; a rare delayed
    /// kernel exit must not hold up the caller or leave an eventual zombie.
    private static func terminateAndReap(_ pid: pid_t) {
        _ = kill(pid, SIGKILL)
        let deadline = ContinuousClock.now + .seconds(1)
        repeat {
            var status: Int32 = 0
            let result = waitpid(pid, &status, WNOHANG)
            if result == pid || (result == -1 && errno == ECHILD) { return }
            _ = Darwin.poll(nil, 0, 10)
        } while ContinuousClock.now < deadline
        Thread.detachNewThread {
            var status: Int32 = 0
            while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
        }
    }

    private static func check(_ code: Int32) throws {
        if code != 0 { throw NSError(domain: NSPOSIXErrorDomain, code: Int(code)) }
    }

    private static func systemError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
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
