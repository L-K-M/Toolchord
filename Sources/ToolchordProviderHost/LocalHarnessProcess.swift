import Darwin
import Foundation

/// Each CLI runs in a new workspace. Arguments never contain the prompt. Drain
/// both ends of the pipes while waiting so a full pipe cannot hide cancellation.
enum LocalHarnessProcess {
    static func run(executable: URL, arguments: [String], input: Data,
                    directory: URL, environment: [String: String], timeout: Duration,
                    outputLimit: Int) async throws -> Data {
        try Task.checkCancellation()
        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = environment
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        let writer = stdin.fileHandleForWriting
        let reader = stdout.fileHandleForReading
        let diagnostic = stderr.fileHandleForReading
        for handle in [writer, reader, diagnostic] {
            let fd = handle.fileDescriptor
            let flags = fcntl(fd, F_GETFL)
            guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 else {
                throw HarnessError("Couldn’t prepare the harness pipes.")
            }
        }
        guard fcntl(writer.fileDescriptor, F_SETNOSIGPIPE, 1) == 0 else {
            throw HarnessError("Couldn’t prepare the harness input.")
        }
        try process.run()
        defer {
            // Foundation owns reaping. Terminate a wrapper's subprocesses as
            // well when the launch created a dedicated process group.
            if process.isRunning {
                let pid = process.processIdentifier
                if getpgid(pid) == pid { _ = kill(-pid, SIGKILL) }
                else { _ = kill(pid, SIGKILL) }
            }
            try? writer.close()
            try? reader.close()
            try? diagnostic.close()
        }

        let deadline = ContinuousClock.now + timeout
        var stdoutData = Data(), stderrData = Data()
        var buffer = [UInt8](repeating: 0, count: 32 * 1024)
        var inputPosition = 0
        var inputClosed = false, outputClosed = false, diagnosticClosed = false
        while true {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else { throw HarnessError("The harness timed out.") }
            var progress = false
            if !inputClosed {
                let remaining = input.count - inputPosition
                if remaining > 0 {
                    let count = input.withUnsafeBytes { bytes in
                        Darwin.write(writer.fileDescriptor, bytes.baseAddress!.advanced(by: inputPosition), min(buffer.count, remaining))
                    }
                    if count > 0 { inputPosition += count; progress = true }
                    else if count < 0, errno == EPIPE { inputClosed = true; try writer.close() }
                    else if count < 0, !wouldRetry { throw HarnessError("Couldn’t write to the harness.") }
                }
                if inputPosition == input.count {
                    try writer.close()
                    inputClosed = true
                }
            }
            if !outputClosed {
                progress = try drain(reader, into: &stdoutData, buffer: &buffer,
                                     limit: outputLimit, closed: &outputClosed) || progress
            }
            if !diagnosticClosed {
                progress = try drain(diagnostic, into: &stderrData, buffer: &buffer,
                                     limit: 512 * 1024, closed: &diagnosticClosed) || progress
            }
            if outputClosed, diagnosticClosed, !process.isRunning { break }
            if !progress { try await Task.sleep(for: .milliseconds(12)) }
        }
        guard process.terminationStatus == 0 else {
            // Harness diagnostics can echo prompts, credentials and local paths.
            // Recognize actionable failures without displaying the raw transcript.
            let message = String(decoding: stderrData, as: UTF8.self).lowercased()
            if message.contains("unexpected argument") || message.contains("unknown option") || message.contains("unrecognized configuration") {
                throw HarnessError("Update \(executable.lastPathComponent) to a version that supports Toolchord’s text-only mode.")
            }
            throw HarnessError("\(executable.lastPathComponent) exited with status \(process.terminationStatus). Check your CLI sign-in and selected model.")
        }
        return stdoutData
    }

    private static var wouldRetry: Bool { errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR }

    private static func drain(_ handle: FileHandle, into data: inout Data, buffer: inout [UInt8],
                              limit: Int, closed: inout Bool) throws -> Bool {
        let count = buffer.withUnsafeMutableBytes { Darwin.read(handle.fileDescriptor, $0.baseAddress, $0.count) }
        if count > 0 {
            guard count <= limit - data.count else { throw HarnessError("The harness returned too much output.") }
            data.append(contentsOf: buffer.prefix(count))
            return true
        }
        if count == 0 { closed = true }
        else if !wouldRetry { throw HarnessError("Couldn’t read from the harness.") }
        return false
    }
}

struct HarnessError: LocalizedError {
    var errorDescription: String? { message }
    private let message: String
    init(_ message: String) { self.message = message }
}
