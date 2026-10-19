// SPDX-License-Identifier: MIT
//
// Part of OllamaBar — https://github.com/yutna/ollama-bar

import Foundation

/// Errors surfaced to the user when the server cannot be managed.
public enum OllamaError: LocalizedError {
    case binaryNotFound
    case launchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "The `ollama` executable could not be found."
        case .launchFailed(let reason):
            return reason
        }
    }
}

/// Owns the lifecycle of the local Ollama server and talks to its HTTP API.
public final class OllamaService {
    private(set) var serverProcess: Process?
    private var isStarting = false

    private let api: OllamaAPI

    /// How long `start()` waits for the API to answer, in seconds.
    static let startupTimeout: TimeInterval = 8

    /// How long `stop()` waits after SIGTERM before escalating to SIGKILL.
    static let stopGracePeriod: TimeInterval = 3

    /// Where the `ollama` CLI usually lives, in order of preference.
    private static let binaryCandidates = [
        "/opt/homebrew/bin/ollama",  // Homebrew (Apple Silicon)
        "/usr/local/bin/ollama",  // Homebrew (Intel) / manual
        "/opt/homebrew/opt/ollama/bin/ollama",  // Homebrew keg path
        "/usr/local/opt/ollama/bin/ollama",
        "/Applications/Ollama.app/Contents/Resources/ollama",  // Official app bundle
    ]

    public convenience init() {
        self.init(api: OllamaAPI())
    }

    init(api: OllamaAPI) {
        self.api = api
    }

    // MARK: - API

    /// `true` when a real Ollama server answers on the configured port.
    public var isServerRunning: Bool { (try? api.syncVersion()) != nil }

    /// Names of all models currently loaded in memory.
    public var loadedModelNames: [String] { (try? api.syncLoadedModelNames()) ?? [] }

    /// The first installed model, used for warm-up.
    public var firstInstalledModel: String? { (try? api.syncInstalledModelNames())?.first }

    /// Environment for `ollama` CLI calls: they must target the same host the
    /// app talks to, instead of the CLI's own `127.0.0.1:11434` default.
    private var cliEnvironment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["OLLAMA_HOST"] = Config.settings.listenHost
        return environment
    }

    // MARK: - Lifecycle

    /// Full path of the `ollama` executable, if one can be found.
    public var binaryPath: String? {
        for path in Self.binaryCandidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        if let resolved = Shell.capture("/usr/bin/env", ["which", "ollama"])?
            .trimmingCharacters(in: .whitespacesAndNewlines), !resolved.isEmpty
        {
            return resolved
        }
        return nil
    }

    /// Starts `ollama serve` with the optimized environment and waits until
    /// the API answers.
    ///
    /// Throws `OllamaError.launchFailed` with the tail of the server log when
    /// the process dies early or never becomes ready, so callers can show a
    /// meaningful alert instead of silently doing nothing.
    public func start() throws {
        guard !isStarting, serverProcess?.isRunning != true, !isServerRunning else { return }
        guard let binary = binaryPath else { throw OllamaError.binaryNotFound }

        isStarting = true
        defer { isStarting = false }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["serve"]

        var environment = ProcessInfo.processInfo.environment
        environment["OLLAMA_HOST"] = Config.settings.listenHost
        environment["OLLAMA_KEEP_ALIVE"] = Config.keepAlive
        environment["OLLAMA_CONTEXT_LENGTH"] = Config.contextLength
        environment["OLLAMA_MAX_LOADED_MODELS"] = Config.maxLoadedModels
        environment["OLLAMA_FLASH_ATTENTION"] = Config.flashAttention
        environment["OLLAMA_KV_CACHE_TYPE"] = Config.kvCacheType
        process.environment = environment
        attachLog(to: process)

        do {
            try process.run()
        } catch {
            throw OllamaError.launchFailed(error.localizedDescription)
        }
        serverProcess = process

        if waitUntilReady(process: process, timeout: Self.startupTimeout) { return }

        if process.isRunning {
            process.terminate()
            _ = waitForProcessExit(process, timeout: 2)
        }
        serverProcess = nil
        throw OllamaError.launchFailed(startFailureReason())
    }

    /// Unloads every model and stops the server, freeing its memory.
    ///
    /// Also catches `ollama serve` instances that were started outside the
    /// app, so "stop" always means "nothing is left running". SIGTERM is
    /// followed by SIGKILL when a process ignores the graceful stop.
    ///
    /// - Returns: `true` when nothing ollama-related is left running.
    @discardableResult
    public func stop() -> Bool {
        if let binary = binaryPath, isServerRunning {
            for model in loadedModelNames {
                Shell.run(binary, ["stop", model], environment: cliEnvironment)
            }
        }
        if let process = serverProcess, process.isRunning {
            process.terminate()
        }
        OllamaProcesses.signalAll(SIGTERM)
        if waitForShutdown(timeout: Self.stopGracePeriod) {
            serverProcess = nil
            return true
        }
        OllamaProcesses.signalAll(SIGKILL)
        let stopped = waitForShutdown(timeout: 2)
        serverProcess = nil
        return stopped
    }

    /// Preloads the first installed model so the next request is instant.
    @discardableResult
    public func warmUp() -> Bool {
        guard let model = firstInstalledModel else { return false }
        let body = "{\"model\":\"\(model)\"}"
        let exitCode = Shell.run(
            "/usr/bin/curl",
            [
                "-s", "--max-time", "90", "-X", "POST",
                Config.apiBase + "/api/generate",
                "-H", "Content-Type: application/json",
                "-d", body,
            ],
            timeout: 95
        )
        return exitCode == 0
    }

    // MARK: - Readiness

    /// Polls the API until it answers or `timeout` elapses.
    private func waitUntilReady(process: Process, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isServerRunning { return true }
            if !process.isRunning { return false }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return isServerRunning
    }

    /// Polls until neither the API answers nor any ollama process is left.
    private func waitForShutdown(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if !isServerRunning && !OllamaProcesses.anyRunning() { return true }
            if Date() >= deadline { return false }
            Thread.sleep(forTimeInterval: 0.25)
        }
    }

    private func waitForProcessExit(_ process: Process, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        return !process.isRunning
    }

    // MARK: - Logging

    /// Human-readable reason for a failed start, including the log tail.
    private func startFailureReason() -> String {
        let seconds = Int(Self.startupTimeout)
        let tail = logTail()
        guard !tail.isEmpty else {
            return "The server did not become ready within \(seconds)s."
        }
        return "The server did not become ready within \(seconds)s.\n\n\(tail)"
    }

    /// Last few lines of `server.log`, for error alerts.
    private func logTail(lines: Int = 10) -> String {
        let file = NSHomeDirectory() + "/.ollama/logs/server.log"
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: file)) else {
            return ""
        }
        defer { try? handle.close() }
        let end = (try? handle.seekToEnd()) ?? 0
        let window: UInt64 = 4096
        try? handle.seek(toOffset: end > window ? end - window : 0)
        let data = (try? handle.readToEnd()) ?? Data()
        let text = String(data: data, encoding: .utf8) ?? ""
        return text.split(separator: "\n").suffix(lines).joined(separator: "\n")
    }

    private func attachLog(to process: Process) {
        let directory = NSHomeDirectory() + "/.ollama/logs"
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let file = directory + "/server.log"
        if !FileManager.default.fileExists(atPath: file) {
            _ = FileManager.default.createFile(atPath: file, contents: nil)
        }
        if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: file)) {
            handle.seekToEndOfFile()
            process.standardOutput = handle
            process.standardError = handle
        } else {
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
        }
    }
}
