// SPDX-License-Identifier: MIT
//
// Part of OllamaBar — https://github.com/yutna/ollama-bar

import Foundation

/// Runtime configuration for the Ollama server that OllamaBar launches.
///
/// Every value can be overridden with an environment variable, which is handy
/// for scripting or when launching the binary directly. Values that do not
/// parse fall back to the documented default, so a typo never leaves the app
/// polling a server that cannot exist.
enum Config {
    /// Validated configuration values.
    struct Settings: Equatable {
        /// Port the Ollama API listens on.
        var port: String
        /// How long models stay loaded after the last request (`-1` = forever,
        /// `0` = unload immediately).
        var keepAlive: String
        /// Default context window, in tokens.
        var contextLength: String
        /// Maximum number of models kept in memory at once.
        var maxLoadedModels: String
        /// Force Flash Attention on the llama.cpp backend.
        var flashAttention: String
        /// K/V cache quantization type for the llama.cpp backend.
        var kvCacheType: String
        /// Largest `server.log` before it is rotated, in bytes.
        var logMaxBytes: String

        /// Base URL of the local API.
        var apiBase: String { "http://127.0.0.1:\(port)" }

        /// Value the `ollama serve` child should listen on.
        var listenHost: String { "127.0.0.1:\(port)" }
    }

    /// Default value for every setting.
    static let defaults = Settings(
        port: "11434",
        keepAlive: "-1",
        contextLength: "65536",
        maxLoadedModels: "1",
        flashAttention: "1",
        kvCacheType: "q8_0",
        logMaxBytes: String(RotatingLogWriter.defaultMaxBytes)
    )

    /// The configuration in effect for this process.
    static let settings = resolve(env: ProcessInfo.processInfo.environment)

    static var port: String { settings.port }
    static var keepAlive: String { settings.keepAlive }
    static var contextLength: String { settings.contextLength }
    static var maxLoadedModels: String { settings.maxLoadedModels }
    static var flashAttention: String { settings.flashAttention }
    static var kvCacheType: String { settings.kvCacheType }
    static var apiBase: String { settings.apiBase }

    /// Log cap in bytes, used by the log pump.
    static var logMaxBytes: UInt64 {
        UInt64(settings.logMaxBytes) ?? RotatingLogWriter.defaultMaxBytes
    }

    /// Validates every `OLLAMABAR_*` override, falling back to defaults.
    static func resolve(env environment: [String: String]) -> Settings {
        Settings(
            port: validatedPort(env("OLLAMABAR_PORT", defaults.port, in: environment)) ?? defaults.port,
            keepAlive: validatedKeepAlive(env("OLLAMABAR_KEEP_ALIVE", defaults.keepAlive, in: environment))
                ?? defaults.keepAlive,
            contextLength: validatedPositiveInt(
                env("OLLAMABAR_CONTEXT_LENGTH", defaults.contextLength, in: environment))
                ?? defaults.contextLength,
            maxLoadedModels: validatedPositiveInt(
                env("OLLAMABAR_MAX_LOADED_MODELS", defaults.maxLoadedModels, in: environment))
                ?? defaults.maxLoadedModels,
            flashAttention: validatedFlag(env("OLLAMABAR_FLASH_ATTENTION", defaults.flashAttention, in: environment))
                ?? defaults.flashAttention,
            kvCacheType: validatedKvCacheType(
                env("OLLAMABAR_KV_CACHE_TYPE", defaults.kvCacheType, in: environment))
                ?? defaults.kvCacheType,
            logMaxBytes: validatedPositiveInt(
                env("OLLAMABAR_LOG_MAX_BYTES", defaults.logMaxBytes, in: environment))
                ?? defaults.logMaxBytes
        )
    }

    /// Reads an environment override, falling back when it is missing or empty.
    static func env(
        _ key: String,
        _ fallback: String,
        in environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        if let value = environment[key], !value.isEmpty {
            return value
        }
        return fallback
    }

    // MARK: - Validation

    /// A TCP port between 1 and 65535.
    static func validatedPort(_ value: String) -> String? {
        guard let port = Int(value), (1...65535).contains(port) else { return nil }
        return String(port)
    }

    /// A positive integer (context length, model count, ...).
    static func validatedPositiveInt(_ value: String) -> String? {
        guard let number = Int(value), number > 0 else { return nil }
        return String(number)
    }

    /// `-1` (keep forever), `0` (unload immediately), a positive number of
    /// seconds, or a duration such as `30s`, `5m`, `2h`.
    static func validatedKeepAlive(_ value: String) -> String? {
        if value == "-1" || value == "0" { return value }
        if let seconds = Int(value), seconds > 0 { return String(seconds) }
        if value.range(of: #"^[0-9]+(ms|s|m|h)$"#, options: .regularExpression) != nil { return value }
        return nil
    }

    /// `0` or `1`.
    static func validatedFlag(_ value: String) -> String? {
        value == "0" || value == "1" ? value : nil
    }

    /// Lower-case token such as `f16`, `q8_0`, or a future quantization type.
    static func validatedKvCacheType(_ value: String) -> String? {
        guard !value.isEmpty,
            value.range(of: #"^[a-z0-9_]+$"#, options: .regularExpression) != nil
        else { return nil }
        return value
    }
}
