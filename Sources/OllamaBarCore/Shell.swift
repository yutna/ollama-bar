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

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }

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

        var output = Data()
        let reader = DispatchQueue(label: "dev.ollamabar.shell.reader")
        if let outputPipe {
            reader.async {
                output = outputPipe.fileHandleForReading.readDataToEndOfFile()
            }
        }

        func drain() {
            reader.sync {}
        }

        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if finished.wait(timeout: .now() + 1) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 1)
            }
            drain()
            return nil
        }

        drain()
        return ExecutionResult(
            exitCode: process.terminationStatus,
            output: String(data: output, encoding: .utf8) ?? ""
        )
    }
}
