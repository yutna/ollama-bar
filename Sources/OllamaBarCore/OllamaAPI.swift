// SPDX-License-Identifier: MIT
//
// Part of OllamaBar — https://github.com/yutna/ollama-bar

import Foundation

/// Errors returned by the local API client.
enum OllamaAPIError: Error {
    case badStatus(Int)
    case malformedResponse
    case timedOut
}

/// Minimal HTTP client for the local Ollama API.
///
/// Replaces shelling out to `curl`, so responses are validated (HTTP status and
/// JSON shape) instead of trusting a helper command's exit code alone.
struct OllamaAPI {
    /// Request timeout, in seconds.
    static let timeout: TimeInterval = 2

    /// Warm-up may have to load a multi-gigabyte model from disk.
    static let warmUpTimeout: TimeInterval = 120

    /// An installed model as reported by `GET /api/tags`.
    struct InstalledModel: Equatable {
        let name: String
        /// Model family, e.g. `llama`, `qwen2`, or `bert` for embedding models.
        let family: String?
    }

    let baseURL: URL
    private let session: URLSession

    init(
        baseURL: URL = URL(string: Config.apiBase) ?? URL(string: "http://127.0.0.1:11434")!,
        session: URLSession = .ollama
    ) {
        var base = baseURL.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        self.baseURL = URL(string: base) ?? baseURL
        self.session = session
    }

    // MARK: - Endpoints

    /// `GET /api/version` — proves a real Ollama server is answering.
    func version() async throws -> String {
        let json = try await getObject("/api/version")
        guard let version = json["version"] as? String, !version.isEmpty else {
            throw OllamaAPIError.malformedResponse
        }
        return version
    }

    /// `GET /api/ps` — names of the models currently loaded in memory.
    func loadedModelNames() async throws -> [String] {
        modelNames(in: try await getObject("/api/ps"))
    }

    /// `GET /api/tags` — every installed model, in server order.
    func installedModels() async throws -> [InstalledModel] {
        let json = try await getObject("/api/tags")
        guard let models = json["models"] as? [[String: Any]] else { return [] }
        return models.compactMap { entry in
            guard let name = (entry["model"] as? String) ?? (entry["name"] as? String) else { return nil }
            let family = (entry["details"] as? [String: Any])?["family"] as? String
            return InstalledModel(name: name, family: family)
        }
    }

    /// `GET /api/tags` — names of every installed model, in server order.
    func installedModelNames() async throws -> [String] {
        try await installedModels().map(\.name)
    }

    /// `POST /api/generate` — loads `model` into memory and keeps it there
    /// according to `keepAlive` (`-1` = forever).
    func warmUp(model: String, keepAlive: String) async throws {
        var body: [String: Any] = ["model": model]
        // Ollama accepts a number of seconds or a duration string; keep `-1`
        // numeric so "forever" is unambiguous.
        if let seconds = Int(keepAlive) {
            body["keep_alive"] = seconds
        } else {
            body["keep_alive"] = keepAlive
        }
        var request = URLRequest(url: url("/api/generate"))
        request.httpMethod = "POST"
        request.timeoutInterval = Self.warmUpTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw OllamaAPIError.badStatus(http.statusCode)
        }
    }

    // MARK: - Sync bridges

    func syncVersion() throws -> String {
        try blocking { try await self.version() }
    }

    func syncLoadedModelNames() throws -> [String] {
        try blocking { try await self.loadedModelNames() }
    }

    func syncInstalledModels() throws -> [InstalledModel] {
        try blocking { try await self.installedModels() }
    }

    func syncWarmUp(model: String, keepAlive: String) throws {
        try blocking(timeout: Self.warmUpTimeout) { try await self.warmUp(model: model, keepAlive: keepAlive) }
    }

    // MARK: - Implementation

    private func url(_ path: String) -> URL {
        URL(string: baseURL.absoluteString + path) ?? baseURL
    }

    private func getObject(_ path: String) async throws -> [String: Any] {
        let (data, response) = try await session.data(from: url(path))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw OllamaAPIError.badStatus(http.statusCode)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OllamaAPIError.malformedResponse
        }
        return json
    }

    private func modelNames(in json: [String: Any]) -> [String] {
        guard let models = json["models"] as? [[String: Any]] else { return [] }
        return models.compactMap { ($0["model"] as? String) ?? ($0["name"] as? String) }
    }

    /// Blocks the calling thread until `operation` finishes.
    ///
    /// Callers that must stay synchronous (the CLI) use this; the UI uses the
    /// async entry points directly so it never blocks the main thread.
    private func blocking<T>(timeout: TimeInterval? = nil, _ operation: @escaping () async throws -> T) throws -> T {
        let box = ResultBox<T>()
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            do {
                box.result = .success(try await operation())
            } catch {
                box.result = .failure(error)
            }
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + (timeout ?? Self.timeout) + 1) == .success else {
            throw OllamaAPIError.timedOut
        }
        guard let result = box.result else { throw OllamaAPIError.timedOut }
        return try result.get()
    }
}

/// Carries a result from the detached task back to the blocked caller.
private final class ResultBox<T>: @unchecked Sendable {
    var result: Result<T, Error>?
}

extension URLSession {
    /// Session with short timeouts, suited to probing a local server.
    ///
    /// The resource timeout is left at its default so long-running requests
    /// (warm-up) can override the per-request timeout.
    static var ollama: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = OllamaAPI.timeout
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }
}
