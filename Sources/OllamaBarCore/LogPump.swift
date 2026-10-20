// SPDX-License-Identifier: MIT
//
// Part of OllamaBar — https://github.com/yutna/ollama-bar

import Foundation

/// Hidden `--log-pump <path>` mode: drains standard input into the server log
/// and rotates it while the server runs.
///
/// `OllamaService` gives the `ollama serve` child a pipe and starts a copy of
/// this binary as the pump. Keeping the reader in a separate process matters:
/// when the app or CLI exits while the server keeps running, an in-process
/// reader would close the pipe and the server would die with SIGPIPE at its
/// next log write. The pump lives until the server closes its end of the pipe.
///
/// `OLLAMABAR_LOG_MAX_BYTES` caps the log (default
/// `RotatingLogWriter.defaultMaxBytes`).
enum LogPump {
    static func run(path: String) -> Never {
        drain(from: .standardInput, into: RotatingLogWriter(path: path, maxBytes: Config.logMaxBytes))
        exit(0)
    }

    /// Copies `input` into `writer` until the child closes its end of the pipe.
    ///
    /// Split out of `run` so tests can push a short-lived child's output
    /// through the same code the pump process uses.
    static func drain(from input: FileHandle, into writer: RotatingLogWriter) {
        writer.open()
        while true {
            let data = autoreleasepool { input.availableData }
            guard !data.isEmpty else { break }  // End of file: the server exited.
            writer.append(data)
        }
        writer.close()
    }
}
