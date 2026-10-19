// SPDX-License-Identifier: MIT
//
// Part of OllamaBar — https://github.com/yutna/ollama-bar

import Foundation

/// Finds and signals user-owned `ollama serve` / `ollama runner` processes.
///
/// Matching happens in two steps so "stop" never hits unrelated processes:
/// `pgrep -f` narrows candidates down by command line, then the executable of
/// each candidate is verified to really be `ollama`.
enum OllamaProcesses {
    private static let patterns = ["ollama serve", "ollama runner"]

    /// PIDs of running ollama server/runner processes.
    static func runningIDs() -> [Int32] {
        var ids: [Int32] = []
        for pattern in patterns {
            guard let output = Shell.capture("/usr/bin/pgrep", ["-f", pattern]) else { continue }
            ids.append(contentsOf: parsePIDs(output).filter { isOllamaExecutable($0) })
        }
        return ids
    }

    static func anyRunning() -> Bool {
        !runningIDs().isEmpty
    }

    /// Sends `signal` to every matching process, skipping this process itself.
    static func signalAll(_ signal: Int32) {
        let ownPID = getpid()
        for pid in runningIDs() where pid != ownPID {
            kill(pid, signal)
        }
    }

    /// Parses `pgrep` output: one PID per line, non-numeric lines ignored.
    static func parsePIDs(_ output: String) -> [Int32] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            Int32(line.trimmingCharacters(in: .whitespaces))
        }
    }

    private static func isOllamaExecutable(_ pid: Int32) -> Bool {
        guard
            let comm = Shell.capture("/bin/ps", ["-o", "comm=", "-p", String(pid)])?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !comm.isEmpty
        else { return false }
        return (comm as NSString).lastPathComponent == "ollama"
    }
}
