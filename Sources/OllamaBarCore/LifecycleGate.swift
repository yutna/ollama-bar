// SPDX-License-Identifier: MIT
//
// Part of OllamaBar — https://github.com/yutna/ollama-bar

import Foundation

/// Serializes the server lifecycle operations.
///
/// `start()` and `stop()` are called from different threads: menu actions run
/// in detached tasks, termination handlers run on a global queue, and the CLI
/// runs on the main thread. Without a gate, two overlapping calls could spawn
/// two `ollama serve` processes, or kill a server that is still starting up.
final class LifecycleGate: @unchecked Sendable {
    private let lock = NSLock()

    /// Runs `body` while holding the gate; other lifecycle work waits here.
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}
