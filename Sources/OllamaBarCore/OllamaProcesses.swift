// SPDX-License-Identifier: MIT
//
// Part of OllamaBar — https://github.com/yutna/ollama-bar

import Foundation

/// Finds and signals user-owned `ollama serve` / `ollama runner` processes.
///
/// Matching happens in three steps so "stop" never hits unrelated processes:
/// `pgrep -f` narrows candidates down by command line, the executable of each
/// candidate is verified to really be `ollama`, and the candidate must belong
/// to this user. A server started by root (or another account) cannot be
/// signalled anyway; counting it made Stop wait out its whole grace period and
/// then report a failure it could never fix.
enum OllamaProcesses {
    private static let patterns = ["ollama serve", "ollama runner"]

    /// PIDs of this user's running ollama server/runner processes.
    static func runningIDs() -> [Int32] {
        var ids: [Int32] = []
        for pattern in patterns {
            guard let output = Shell.capture("/usr/bin/pgrep", ["-f", pattern]) else { continue }
            ids.append(
                contentsOf: parsePIDs(output).filter {
                    isOwnedByCurrentUser($0) && isOllamaExecutable($0)
                })
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

    /// `true` when `pid` belongs to this user.
    ///
    /// Anything the kernel refuses to describe counts as not ours: `pgrep`
    /// lists other users' processes (a `sudo ollama serve` included), but
    /// `proc_pidinfo` answers `EPERM` for them, and a dead pid answers
    /// `ESRCH`. Either way there is nothing to signal, so nothing to wait for
    /// and nothing to report.
    static func isOwnedByCurrentUser(_ pid: Int32) -> Bool {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return false }
        return info.pbi_uid == getuid()
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
