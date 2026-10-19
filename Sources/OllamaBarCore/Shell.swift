// SPDX-License-Identifier: MIT
//
// Part of OllamaBar — https://github.com/yutna/ollama-bar

import Foundation

/// Helpers for the short-lived helper commands the app needs
/// (`pkill`, `which`, and the `ollama` CLI itself).
enum Shell {
    /// Runs a command and waits up to `timeout` seconds for it to finish.
    ///
    /// Returns the command's exit code, or `nil` when the command could not be
    /// started or had to be killed after `timeout`.
    @discardableResult
    static func run(
        _ executable: String,
        _ arguments: [String],
        timeout: TimeInterval = 5,
        environment: [String: String]? = nil
    ) -> Int32? {
        execute(executable, arguments, timeout: timeout, environment: environment, captureOutput: false)?
            .exitCode
    }

    /// Runs a command and returns its standard output when the command exits 0.
    ///
    /// Returns `nil` when the command fails, times out, or prints nothing.
    static func capture(
        _ executable: String,
        _ arguments: [String],
        timeout: TimeInterval = 5,
        environment: [String: String]? = nil
    ) -> String? {
        guard
            let result = execute(
                executable,
                arguments,
                timeout: timeout,
                environment: environment,
                captureOutput: true
            ),
            result.exitCode == 0,
            !result.output.isEmpty
        else { return nil }
        return result.output
    }

    private struct ExecutionResult {
        let exitCode: Int32
        let output: String
    }

    /// Shared implementation.
    ///
    /// The pipe is drained on a background queue while the child runs, so a
    /// large output cannot deadlock it against a full pipe buffer. When the
    /// timeout elapses the process is terminated (SIGTERM, then SIGKILL).
    ///
    /// The drain is bounded: it ends at EOF, at its deadline, or once the child
    /// is gone and everything buffered has been read. A descendant that keeps
    /// the write end open (a background process started by a shell profile, a
    /// pipeline outliving its parent) therefore cannot block the caller.
    private static func execute(
        _ executable: String,
        _ arguments: [String],
        timeout: TimeInterval,
        environment: [String: String]?,
        captureOutput: Bool
    ) -> ExecutionResult? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment {
            process.environment = environment
        }
        process.standardError = FileHandle.nullDevice

        let outputPipe: Pipe?
        if captureOutput {
            let pipe = Pipe()
            process.standardOutput = pipe
            outputPipe = pipe
        } else {
            process.standardOutput = FileHandle.nullDevice
            outputPipe = nil
        }

        let exitLock = NSLock()
        var childExited = false
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            exitLock.lock()
            childExited = true
            exitLock.unlock()
            finished.signal()
        }

        do {
            try process.run()
        } catch {
            return nil
        }
        // The parent must not keep its end of the pipe open, or the reader
        // below never sees EOF even after the child exits.
        if let outputPipe {
            try? outputPipe.fileHandleForWriting.close()
        }

        let outputLock = NSLock()
        var output = Data()
        let reader = DispatchGroup()
        if let outputPipe {
            let handle = outputPipe.fileHandleForReading
            reader.enter()
            DispatchQueue(label: "dev.ollamabar.shell.reader").async {
                let data = readBounded(from: handle, deadline: .now() + timeout + drainGrace) {
                    exitLock.lock()
                    defer { exitLock.unlock() }
                    return childExited
                }
                outputLock.lock()
                output = data
                outputLock.unlock()
                reader.leave()
            }
        }

        let timedOut = finished.wait(timeout: .now() + timeout) == .timedOut
        if timedOut {
            process.terminate()
            if finished.wait(timeout: .now() + 1) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 1)
            }
        }
        // The reader stops on its own exactly like the child rule above, so
        // this wait is just a safety net; `terminationHandler` already ran.
        _ = reader.wait(timeout: .now() + timeout + drainGrace + 1)
        if timedOut {
            return nil
        }

        outputLock.lock()
        let captured = output
        outputLock.unlock()
        return ExecutionResult(
            exitCode: process.terminationStatus,
            output: String(data: captured, encoding: .utf8) ?? ""
        )
    }

    /// How long the drain may keep reading past the caller's timeout.
    private static let drainGrace: TimeInterval = 2

    /// How long a single `poll` may wait while the child is still running.
    private static let pollSliceMilliseconds: Int32 = 200

    /// Reads `handle` until EOF, until `deadline`, or until the child is gone
    /// and nothing is buffered any more, whichever comes first.
    ///
    /// `readDataToEndOfFile()` only returns once every copy of the write end is
    /// closed, and a descendant that inherited stdout keeps it open, so it can
    /// block forever. `poll(2)` makes the wait observable and stoppable: once
    /// the child exited there is nothing left to wait for, because everything
    /// it wrote is already in the kernel buffer.
    private static func readBounded(
        from handle: FileHandle,
        deadline: DispatchTime,
        childHasExited: () -> Bool
    ) -> Data {
        var data = Data()
        let descriptor = handle.fileDescriptor
        while DispatchTime.now() < deadline {
            let exited = childHasExited()
            // With the child gone, only take what is already buffered instead
            // of waiting for more.
            var descriptorPoll = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptorPoll, 1, exited ? 0 : pollSliceMilliseconds)
            if ready == 0 {
                if exited { break }
                continue
            }
            if ready < 0 {
                if errno == EINTR { continue }
                break
            }
            var buffer = [UInt8](repeating: 0, count: 4096)
            let count = buffer.withUnsafeMutableBytes {
                read(descriptor, $0.baseAddress, $0.count)
            }
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                break
            }
            data.append(contentsOf: buffer[0..<count])
        }
        return data
    }
}
