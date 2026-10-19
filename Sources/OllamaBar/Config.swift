// SPDX-License-Identifier: MIT
//
// Part of OllamaBar — https://github.com/yutna/ollama-bar

import Foundation

/// Runtime configuration for the Ollama server that OllamaBar launches.
///
/// Every value can be overridden with an environment variable, which is handy
/// for scripting or when launching the binary directly.
enum Config {
    /// Port the Ollama API listens on.
    static let port = env("OLLAMABAR_PORT", "11434")

    /// How long models stay loaded after the last request (`-1` = forever).
    static let keepAlive = env("OLLAMABAR_KEEP_ALIVE", "-1")

    /// Default context window, in tokens.
    static let contextLength = env("OLLAMABAR_CONTEXT_LENGTH", "65536")

    /// Maximum number of models kept in memory at once.
    static let maxLoadedModels = env("OLLAMABAR_MAX_LOADED_MODELS", "1")

    /// Force Flash Attention on the llama.cpp backend.
    static let flashAttention = env("OLLAMABAR_FLASH_ATTENTION", "1")

    /// K/V cache quantization type for the llama.cpp backend.
    static let kvCacheType = env("OLLAMABAR_KV_CACHE_TYPE", "q8_0")

    /// Base URL of the local API.
    static var apiBase: String { "http://127.0.0.1:\(port)" }

    private static func env(_ key: String, _ fallback: String) -> String {
        if let value = ProcessInfo.processInfo.environment[key], !value.isEmpty {
            return value
        }
        return fallback
    }
}
