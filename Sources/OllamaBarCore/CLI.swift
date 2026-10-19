// SPDX-License-Identifier: MIT
//
// Part of OllamaBar — https://github.com/yutna/ollama-bar

import Foundation

/// Command line interface so the app can be scripted.
///
/// The CLI intentionally stays in English: it targets scripts and CI,
/// not the localized UI.
public enum CLI {
    /// Options the CLI owns. `main.swift` uses this list to tell CLI mode
    /// apart from a normal app launch, and mistyped options are rejected
    /// instead of silently starting the menu bar app.
    public static let flags: Set<String> = [
        "--start", "--stop", "--status", "--warm", "--help", "-h", "--version", "-v",
    ]

    public static func run(_ arguments: [String]) -> Never {
        // Internal mode: `OllamaService` runs the app as a log pump. It stays
        // out of `flags` so the user-facing option list and the usage text
        // stay in sync, and is handled before the unknown-option check.
        if let index = arguments.firstIndex(of: "--log-pump") {
            let path =
                arguments.indices.contains(index + 1)
                ? arguments[index + 1] : OllamaService.logFilePath
            LogPump.run(path: path)
        }

        let unknown = arguments.filter { $0.hasPrefix("--") && !flags.contains($0) }
        if let option = unknown.first {
            fail("unknown option '\(option)'")
        }

        if arguments.contains("--version") || arguments.contains("-v") {
            print("OllamaBar \(version(from: Bundle.main.infoDictionary))")
            exit(0)
        }

        let service = OllamaService()

        if arguments.contains("--start") {
            do {
                try service.start()
            } catch {
                print("failed: \(error.localizedDescription)")
                exit(1)
            }
            let running = service.isServerRunning
            print(running ? "running" : "failed")
            exit(running ? 0 : 1)
        }

        if arguments.contains("--stop") {
            let stopped = service.stop()
            print(stopped ? "stopped" : "still-running")
            exit(stopped ? 0 : 1)
        }

        if arguments.contains("--warm") {
            service.warmUp()
            let ready = service.isServerRunning && !service.loadedModelNames.isEmpty
            print(ready ? "loaded" : "not-loaded")
            exit(ready ? 0 : 1)
        }

        if arguments.contains("--status") {
            let running = service.isServerRunning
            let loaded = running && !service.loadedModelNames.isEmpty
            print(running ? (loaded ? "running model-loaded" : "running") : "stopped")
            exit(0)
        }

        print(usage)
        exit(0)
    }

    /// App version, read from the bundle so it always matches `Info.plist`.
    /// Falls back to `unknown` when the binary runs outside an app bundle.
    static func version(from infoDictionary: [String: Any]?) -> String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "unknown"
    }

    /// Prints an error plus the usage to standard error and exits with 2.
    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data(("error: " + message + "\n\n" + usage + "\n").utf8))
        exit(2)
    }

    private static let usage = """
        OllamaBar — a menu bar toggle for a local Ollama server

        Usage:
          OllamaBar           Run the menu bar app
          OllamaBar --start   Start `ollama serve` with optimized defaults
          OllamaBar --stop    Stop the server and unload all models
          OllamaBar --status  Print: stopped | running | running model-loaded
          OllamaBar --warm    Preload the first installed model
          OllamaBar --help    Show this help
          OllamaBar --version Print the app version
        """
}
