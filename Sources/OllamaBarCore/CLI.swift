// SPDX-License-Identifier: MIT
//
// Part of OllamaBar — https://github.com/yutna/ollama-bar

import Foundation

/// Command line interface so the app can be scripted.
///
/// The CLI intentionally stays in English: it targets scripts and CI,
/// not the localized UI.
public enum CLI {
    public static func run(_ arguments: [String]) -> Never {
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

    private static let usage = """
        OllamaBar — a menu bar toggle for a local Ollama server

        Usage:
          OllamaBar           Run the menu bar app
          OllamaBar --start   Start `ollama serve` with optimized defaults
          OllamaBar --stop    Stop the server and unload all models
          OllamaBar --status  Print: stopped | running | running model-loaded
          OllamaBar --warm    Preload the first installed model
          OllamaBar --help    Show this help
        """
}
