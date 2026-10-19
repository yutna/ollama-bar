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

    private let api: OllamaAPI

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

    /// Starts `ollama serve` with the optimized environment.
    public func start() throws {
        guard !isServerRunning else { return }
        guard let binary = binaryPath else { throw OllamaError.binaryNotFound }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["serve"]

        var environment = ProcessInfo.processInfo.environment
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
    }

    /// Unloads every model and stops the server, freeing its memory immediately.
    ///
    /// The `pkill` calls also catch `ollama serve` instances that were started
    /// outside the app, so "stop" always means "nothing is left running".
    public func stop() {
        if let binary = binaryPath, isServerRunning {
            for model in loadedModelNames {
                Shell.run(binary, ["stop", model])
            }
        }
        if let process = serverProcess, process.isRunning {
            process.terminate()
        }
        Shell.run("/usr/bin/pkill", ["-TERM", "-f", "ollama serve"], timeout: 3)
        Shell.run("/usr/bin/pkill", ["-TERM", "-f", "ollama runner"], timeout: 3)
        serverProcess = nil
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

    // MARK: - Logging

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
