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
            return L10n.errorBinaryNotFound
        case .launchFailed(let reason):
            return reason
        }
    }
}

/// Owns the lifecycle of the local Ollama server and talks to its HTTP API.
///
/// `start()` and `stop()` are serialized through a gate, so callers on
/// different threads never spawn or kill servers concurrently.
public final class OllamaService {
    private let processLock = NSLock()
    private var storedProcess: Process?

    /// The server process this instance spawned, if any.
    ///
    /// Mutated while the lifecycle gate is held, but guarded by its own tiny
    /// lock: `ownsRunningServer` is read from the main thread, and waiting for
    /// the gate there could freeze the menu for the whole startup timeout.
    var serverProcess: Process? {
        get {
            processLock.lock()
            defer { processLock.unlock() }
            return storedProcess
        }
        set {
            processLock.lock()
            defer { processLock.unlock() }
            storedProcess = newValue
        }
    }

    /// `true` while this instance owns a spawned `ollama serve` process, even
    /// when the API is not answering yet (still starting up, or hung).
    ///
    /// The menu offers Stop in that state: `start()` refuses to spawn twice
    /// and returns without a word, so Start would be a silent no-op.
    public var ownsRunningServer: Bool { serverProcess?.isRunning == true }

    private let api: OllamaAPI

    /// Where the log pump writes; injectable so tests can use a temp file.
    let logPath: String

    /// Serializes `start()`/`stop()`; internal so tests can hold it and check
    /// that reading process state never waits for a start in flight.
    let lifecycle = LifecycleGate()

    /// Kept between `attachLog` and a successful spawn: the parent's copies of
    /// the pipe are closed once the child owns the write end.
    private var logPipe: Pipe?

    /// How long `start()` waits for the API to answer, in seconds.
    static let startupTimeout: TimeInterval = 8

    /// How long `stop()` waits after SIGTERM before escalating to SIGKILL.
    static let stopGracePeriod: TimeInterval = 3

    /// Where the `ollama` CLI usually lives, in order of preference.
    ///
    /// The GUI app inherits the minimal launchd `PATH`, so `which` alone
    /// misses binaries that live in the user's shell profile; the common
    /// non-Homebrew locations (MacPorts, `~/.local/bin`, version-manager
    /// shims) are listed explicitly instead.
    static let binaryCandidates = [
        "/opt/homebrew/bin/ollama",  // Homebrew (Apple Silicon)
        "/usr/local/bin/ollama",  // Homebrew (Intel) / manual
        "/opt/homebrew/opt/ollama/bin/ollama",  // Homebrew keg path
        "/usr/local/opt/ollama/bin/ollama",
        "/Applications/Ollama.app/Contents/Resources/ollama",  // Official app bundle
        "/opt/local/bin/ollama",  // MacPorts
        NSHomeDirectory() + "/.local/bin/ollama",
        NSHomeDirectory() + "/bin/ollama",
        NSHomeDirectory() + "/.asdf/shims/ollama",
        NSHomeDirectory() + "/.local/share/mise/shims/ollama",
    ]

    public convenience init() {
        self.init(api: OllamaAPI())
    }

    init(api: OllamaAPI, logPath: String = OllamaService.logFilePath) {
        self.api = api
        self.logPath = logPath
    }

    // MARK: - API

    /// `true` when a real Ollama server answers on the configured port.
    public var isServerRunning: Bool { (try? api.syncVersion()) != nil }

    /// Names of all models currently loaded in memory.
    public var loadedModelNames: [String] { (try? api.syncLoadedModelNames()) ?? [] }

    /// What a warm-up request would preload, so the UI can tell "no models
    /// installed" apart from "the server did not answer".
    public enum WarmUpTarget: Equatable {
        case model(String)
        case noModels
        case serverUnreachable
    }

    /// Decides what warm-up should load.
    ///
    /// Embedding-only models (e.g. `nomic-embed-text`) are skipped so warm-up
    /// does not preload a model that could never answer a chat request.
    public func warmUpTarget() -> WarmUpTarget {
        guard let models = try? api.syncInstalledModels() else { return .serverUnreachable }
        guard let name = Self.warmUpCandidate(in: models) else { return .noModels }
        return .model(name)
    }

    /// Picks the warm-up candidate: first generative model, or the first
    /// installed model when everything is an embedding model.
    static func warmUpCandidate(in models: [OllamaAPI.InstalledModel]) -> String? {
        let generative = models.filter { !isEmbeddingModel($0) }
        return (generative.first ?? models.first)?.name
    }

    /// Heuristic: embedding models are named `*embed*` or belong to the
    /// `bert` family (`bert`, `nomic-bert`, ...).
    ///
    /// Models report their `capabilities` on current servers, so that wins:
    /// embedding-only means the server listed `embedding` without also listing
    /// `completion`.
    static func isEmbeddingModel(_ model: OllamaAPI.InstalledModel) -> Bool {
        if !model.capabilities.isEmpty {
            return model.capabilities.contains("embedding")
                && !model.capabilities.contains("completion")
        }
        if model.name.lowercased().contains("embed") { return true }
        if let family = model.family?.lowercased(), family.contains("bert") { return true }
        return false
    }

    /// Async snapshot for the UI: never blocks the main thread.
    public func status() async -> (isRunning: Bool, loadedModels: [String]) {
        guard (try? await api.version()) != nil else {
            return (false, [])
        }
        return (true, (try? await api.loadedModelNames()) ?? [])
    }

    /// Environment for `ollama` CLI calls: they must target the same host the
    /// app talks to, instead of the CLI's own `127.0.0.1:11434` default.
    private var cliEnvironment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["OLLAMA_HOST"] = Config.settings.listenHost
        return environment
    }

    // MARK: - Lifecycle

    /// Full path of the `ollama` executable, if one can be found.
    ///
    /// Search order: known install locations, then `PATH` (trustworthy only
    /// when the app is launched from a terminal), then the user's login shell
    /// for entries the shell profile adds to `PATH` — GUI apps never see
    /// those.
    public var binaryPath: String? {
        if let candidate = Self.firstExecutable(in: Self.binaryCandidates) {
            return candidate
        }
        if let output = Shell.capture("/usr/bin/env", ["which", "ollama"]),
            let resolved = Self.executableFromShell(output: output)
        {
            return resolved
        }
        let shell = Self.loginShell
        if let output = Shell.capture(shell, ["-l", "-c", "command -v ollama"], timeout: 5),
            let resolved = Self.executableFromShell(output: output)
        {
            return resolved
        }
        return nil
    }

    /// First path in `paths` that exists and is executable.
    static func firstExecutable(
        in paths: [String],
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String? {
        paths.first(where: isExecutable)
    }

    /// Extracts an executable named `ollama` from shell output.
    ///
    /// Profiles may print banners, and `command -v` prints an alias or a
    /// function definition instead of a path when the user has one, so every
    /// line has to be an absolute path to `ollama` and the last match wins.
    static func executableFromShell(
        output: String,
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String? {
        for line in output.split(separator: "\n").reversed() {
            let path = line.trimmingCharacters(in: .whitespaces)
            guard path.hasPrefix("/"),
                (path as NSString).lastPathComponent == "ollama",
                isExecutable(path)
            else { continue }
            return path
        }
        return nil
    }

    /// The user's login shell for the `PATH` fallback, with a safe default.
    private static var loginShell: String {
        if let shell = ProcessInfo.processInfo.environment["SHELL"],
            FileManager.default.isExecutableFile(atPath: shell)
        {
            return shell
        }
        return "/bin/zsh"
    }

    /// Starts `ollama serve` with the optimized environment and waits until
    /// the API answers.
    ///
    /// Throws `OllamaError.launchFailed` with the tail of the server log when
    /// the process dies early or never becomes ready, so callers can show a
    /// meaningful alert instead of silently doing nothing.
    ///
    /// Serialized against `stop()`: a second call while the server is starting
    /// only waits for the gate and then sees the server running.
    public func start() throws {
        try lifecycle.withLock {
            guard serverProcess?.isRunning != true, !isServerRunning else { return }
            guard let binary = binaryPath else { throw OllamaError.binaryNotFound }

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

            // Everything already in the log belongs to an earlier session;
            // only what this start appends can explain a failure.
            let logOffset = Self.logFileSize(at: logPath)

            do {
                try process.run()
            } catch {
                closeLogPipe()
                throw OllamaError.launchFailed(error.localizedDescription)
            }
            closeLogPipe()
            serverProcess = process

            if waitUntilReady(process: process, timeout: Self.startupTimeout) { return }

            if process.isRunning {
                process.terminate()
                _ = waitForProcessExit(process, timeout: 2)
            }
            serverProcess = nil
            throw OllamaError.launchFailed(startFailureReason(since: logOffset))
        }
    }

    /// Unloads every model and stops the server, freeing its memory.
    ///
    /// Also catches `ollama serve` instances that were started outside the
    /// app, so "stop" always means "nothing is left running". SIGTERM is
    /// followed by SIGKILL when a process ignores the graceful stop.
    ///
    /// - Parameter unloadingModels: ask the `ollama` CLI to unload each loaded
    ///   model before stopping. App termination passes `false`: the server is
    ///   killed anyway (SIGTERM reclaims the memory) and skipping the
    ///   round-trips keeps quitting fast.
    /// - Returns: `true` when nothing ollama-related is left running.
    @discardableResult
    public func stop(unloadingModels: Bool = true) -> Bool {
        lifecycle.withLock {
            // Look for the binary last: a stopped server has nothing to unload,
            // and the login-shell fallback can take seconds (or, with a
            // misbehaving profile, forever — see Shell's bounded drain).
            if unloadingModels, isServerRunning, let binary = binaryPath {
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
    }

    /// Preloads the first installed model so the next request is instant.
    ///
    /// A no-op when a model is already loaded: with the default
    /// `OLLAMA_MAX_LOADED_MODELS=1`, loading another one would evict the model
    /// the user is working with.
    @discardableResult
    public func warmUp() -> Bool {
        guard Self.shouldPreloadModel(loadedModels: loadedModelNames) else { return true }
        guard case .model(let model) = warmUpTarget() else { return false }
        do {
            try api.syncWarmUp(model: model, keepAlive: Config.keepAlive)
            return true
        } catch {
            return false
        }
    }

    /// Warm-up only preloads a model when nothing is loaded; otherwise Ollama
    /// would have to unload the model in use to make room.
    static func shouldPreloadModel(loadedModels: [String]) -> Bool {
        loadedModels.isEmpty
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

    /// Human-readable reason for a failed start: what this start wrote to the
    /// log, when it wrote anything at all.
    private func startFailureReason(since offset: UInt64) -> String {
        let seconds = Int(Self.startupTimeout)
        // The pump writes from another process: give it a moment to drain the
        // child's last output before reading the file.
        Thread.sleep(forTimeInterval: 0.2)
        let tail = Self.logTail(at: logPath, since: offset)
        guard !tail.isEmpty else {
            return L10n.errorLaunchTimeout(seconds)
        }
        return L10n.errorLaunchTimeoutWithLog(seconds, tail)
    }

    /// Size of `path`, or 0 when it does not exist yet.
    static func logFileSize(at path: String) -> UInt64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        return (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
    }

    /// Last few lines of `path` since `offset`, for error alerts.
    ///
    /// Only what a start appended is useful: the file is never truncated
    /// between sessions, so the plain tail showed whatever the previous
    /// session left behind — a "Listening on 127.0.0.1:11434" line under a
    /// "did not become ready" error. A file shorter than the offset was rotated
    /// while the server started, and then all of it is new.
    static func logTail(at path: String, since offset: UInt64, lines: Int = 10) -> String {
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else {
            return ""
        }
        defer { try? handle.close() }
        let end = (try? handle.seekToEnd()) ?? 0
        let start: UInt64 = end < offset ? 0 : offset
        let window: UInt64 = 4096
        let from = max(start, end > window ? end - window : 0)
        try? handle.seek(toOffset: from)
        let data = (try? handle.readToEnd()) ?? Data()
        let text = String(decoding: data, as: UTF8.self)
        return text.split(separator: "\n").suffix(lines).joined(separator: "\n")
    }

    /// Where the server writes its log.
    static let logFilePath = NSHomeDirectory() + "/.ollama/logs/server.log"

    /// Captures the child's output into `server.log` through a pipe and a log
    /// pump (the app started with `--log-pump`).
    ///
    /// The pump is a separate process because the log has to outlive the
    /// process that started the server: with an in-process reader, a CLI
    /// `--start` (or a crashed app) would close the pipe and the still-running
    /// server would die with SIGPIPE at its next log write. Rotation while the
    /// server runs only works when the writer is the app's side of the pipe.
    private func attachLog(to process: Process) {
        attachLog(to: process, pumpExecutable: Bundle.main.executableURL)
    }

    /// Wires the child's output into the log through a `--log-pump` helper.
    ///
    /// `pumpExecutable` is internal so tests can pass a stub instead of this
    /// binary: the pump protocol is "read stdin, write the log file at argv[2]".
    func attachLog(to process: Process, pumpExecutable: URL?) {
        let pipe = Pipe()
        // Do not leak the pipe ends into helper processes: an inherited
        // duplicate of the write end would keep the pump waiting for an EOF
        // that never comes.
        Self.setCloseOnExec(pipe.fileHandleForReading.fileDescriptor)
        Self.setCloseOnExec(pipe.fileHandleForWriting.fileDescriptor)
        guard let executable = pumpExecutable,
            Self.spawnLogPump(executable, logPath: logPath, input: pipe)
        else {
            attachFileLog(to: process)
            return
        }
        logPipe = pipe
        process.standardOutput = pipe
        process.standardError = pipe
    }

    /// Fallback when the pump cannot be started: the child writes the file
    /// itself, which the app can only rotate at the next start.
    private func attachFileLog(to process: Process) {
        attachFileLog(to: process, maxBytes: Config.logMaxBytes)
    }

    /// Fallback used when the log pump cannot be started: hand the file over to
    /// the child directly.
    ///
    /// The child then owns the handle, so the log can no longer be rotated
    /// while the server runs — the price of a start without a pump. It is still
    /// opened with `O_APPEND` and the configured cap (`OLLAMABAR_LOG_MAX_BYTES`)
    /// is applied before the handover, so the server's lines end up at the end
    /// of the file even while something else appends, and an oversized log left
    /// by a previous session is rotated instead of ignored.
    ///
    /// - Parameter maxBytes: cap for the handover rotation; tests pass a small
    ///   value instead of the process-wide configuration.
    func attachFileLog(to process: Process, maxBytes: UInt64) {
        let writer = RotatingLogWriter(path: logPath, maxBytes: maxBytes)
        writer.open()
        writer.close()
        if let handle = RotatingLogWriter.openForAppending(logPath) {
            process.standardOutput = handle
            process.standardError = handle
        } else {
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
        }
    }

    /// Starts the current binary in its hidden log-pump mode.
    private static func spawnLogPump(_ executable: URL, logPath: String, input: Pipe) -> Bool {
        let pump = Process()
        pump.executableURL = executable
        pump.arguments = ["--log-pump", logPath]
        pump.standardInput = input
        pump.standardOutput = FileHandle.nullDevice
        pump.standardError = FileHandle.nullDevice
        do {
            try pump.run()
            return true
        } catch {
            return false
        }
    }

    private static func setCloseOnExec(_ descriptor: Int32) {
        _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)
    }

    /// Closes the parent's copies of the log pipe once the child has its own.
    private func closeLogPipe() {
        guard let pipe = logPipe else { return }
        logPipe = nil
        try? pipe.fileHandleForReading.close()
        try? pipe.fileHandleForWriting.close()
    }
}
