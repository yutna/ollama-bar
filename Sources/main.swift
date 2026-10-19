// OllamaBar
// A tiny macOS menu bar toggle that starts and stops a local Ollama server.
// https://github.com/yutna/ollama-bar
//
// SPDX-License-Identifier: MIT

import AppKit
import ServiceManagement

// MARK: - Configuration
//
// Sensible defaults for Apple Silicon laptops. Override any value with the
// matching environment variable (advanced usage; see README).

enum Config {
    static let port             = env("OLLAMABAR_PORT", "11434")
    static let keepAlive        = env("OLLAMABAR_KEEP_ALIVE", "-1")
    static let contextLength    = env("OLLAMABAR_CONTEXT_LENGTH", "65536")
    static let maxLoadedModels  = env("OLLAMABAR_MAX_LOADED_MODELS", "1")
    static let flashAttention   = env("OLLAMABAR_FLASH_ATTENTION", "1")
    static let kvCacheType      = env("OLLAMABAR_KV_CACHE_TYPE", "q8_0")

    static func env(_ key: String, _ fallback: String) -> String {
        if let v = ProcessInfo.processInfo.environment[key], !v.isEmpty { return v }
        return fallback
    }
}

let apiBase = "http://127.0.0.1:\(Config.port)"
let cliArgs = Array(CommandLine.arguments.dropFirst())
let cliMode = !cliArgs.isEmpty

/// Locate the `ollama` executable across common install layouts.
func findOllamaBinary() -> String? {
    let candidates = [
        "/opt/homebrew/bin/ollama",                             // Homebrew (Apple Silicon)
        "/usr/local/bin/ollama",                                // Homebrew (Intel) / manual
        "/opt/homebrew/opt/ollama/bin/ollama",                  // Homebrew keg path
        "/usr/local/opt/ollama/bin/ollama",
        "/Applications/Ollama.app/Contents/Resources/ollama",   // Official app bundle
    ]
    for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
        return path
    }
    // Last resort: PATH lookup
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    p.arguments = ["which", "ollama"]
    let out = Pipe()
    p.standardOutput = out
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return nil }
    p.waitUntilExit()
    let data = out.fileHandleForReading.readDataToEndOfFile()
    guard let s = String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
    return s
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem?
    var serverProcess: Process?
    var refreshTimer: Timer?

    func applicationDidFinishLaunching(_ note: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        refreshIcon()
        let t = Timer(timeInterval: 3.0, repeats: true) { [weak self] _ in self?.refreshIcon() }
        RunLoop.main.add(t, forMode: .common)
        refreshTimer = t
    }

    func applicationWillTerminate(_ note: Notification) {
        stopOllama()
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu(menu)
    }

    // MARK: State

    func isServerRunning() -> Bool { api("/api/version") != nil }

    func loadedModelNames() -> [String] {
        guard let s = api("/api/ps"),
              let data = s.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = obj["models"] as? [[String: Any]] else { return [] }
        return models.compactMap { ($0["model"] as? String) ?? ($0["name"] as? String) }
    }

    func firstInstalledModel() -> String? {
        guard let s = api("/api/tags"),
              let data = s.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = obj["models"] as? [[String: Any]],
              let first = models.first else { return nil }
        return (first["model"] as? String) ?? (first["name"] as? String)
    }

    func api(_ path: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        p.arguments = ["-s", "--max-time", "2", apiBase + path]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        guard let s = String(data: data, encoding: .utf8), !s.isEmpty else { return nil }
        return s
    }

    func refreshIcon() {
        guard let button = statusItem?.button else { return }
        let running = isServerRunning()
        let loaded = running && !loadedModelNames().isEmpty
        button.title = "🦙"
        button.alphaValue = running ? 1.0 : 0.35
        if running && loaded {
            button.toolTip = "Ollama running — model loaded"
        } else if running {
            button.toolTip = "Ollama running — no model loaded"
        } else {
            button.toolTip = "Ollama stopped — click to start"
        }
    }

    func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let running = isServerRunning()
        let models = running ? loadedModelNames() : []
        let loaded = !models.isEmpty

        let header = NSMenuItem(
            title: running
                ? (loaded ? "● Ollama running — \(models.joined(separator: ", "))" : "● Ollama running — no model loaded")
                : "○ Ollama stopped",
            action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        if running {
            let stop = NSMenuItem(title: "■ Stop Ollama (free RAM now)", action: #selector(stopAction), keyEquivalent: "")
            stop.target = self
            menu.addItem(stop)
            if !loaded {
                let warm = NSMenuItem(title: "🔥 Warm up model (preload)", action: #selector(warmAction), keyEquivalent: "")
                warm.target = self
                menu.addItem(warm)
            }
        } else {
            let start = NSMenuItem(title: "▶︎ Start Ollama (optimized defaults)", action: #selector(startAction), keyEquivalent: "")
            start.target = self
            menu.addItem(start)
        }
        menu.addItem(.separator())

        let login = NSMenuItem(title: "Show icon at login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit (also stops Ollama)", action: #selector(quitAction), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    // MARK: Actions

    @objc func startAction() { startOllama() }
    @objc func stopAction() { stopOllama(); refreshIcon() }
    @objc func warmAction() { warmUp() }
    @objc func quitAction() { NSApp.terminate(nil) }

    @objc func toggleLogin() {
        let svc = SMAppService.mainApp
        do {
            if svc.status == .enabled { try svc.unregister() } else { try svc.register() }
        } catch {
            alert("Could not change login item",
                  "Add it manually under System Settings → General → Login Items.\n\n\(error.localizedDescription)")
        }
    }

    func startOllama() {
        guard !isServerRunning() else { refreshIcon(); return }
        guard let bin = findOllamaBinary() else {
            alert("Ollama not found",
                  "Install Ollama from https://ollama.com or run: brew install ollama")
            return
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = ["serve"]
        var env = ProcessInfo.processInfo.environment
        env["OLLAMA_KEEP_ALIVE"] = Config.keepAlive
        env["OLLAMA_CONTEXT_LENGTH"] = Config.contextLength
        env["OLLAMA_MAX_LOADED_MODELS"] = Config.maxLoadedModels
        env["OLLAMA_FLASH_ATTENTION"] = Config.flashAttention
        env["OLLAMA_KV_CACHE_TYPE"] = Config.kvCacheType
        p.environment = env

        let logDir = NSHomeDirectory() + "/.ollama/logs"
        try? FileManager.default.createDirectory(atPath: logDir, withIntermediateDirectories: true)
        let logPath = logDir + "/server.log"
        if !FileManager.default.fileExists(atPath: logPath) {
            _ = FileManager.default.createFile(atPath: logPath, contents: nil)
        }
        if let fh = try? FileHandle(forWritingTo: URL(fileURLWithPath: logPath)) {
            fh.seekToEndOfFile()
            p.standardOutput = fh
            p.standardError = fh
        } else {
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
        }

        do { try p.run() } catch {
            alert("Could not start Ollama", error.localizedDescription)
            return
        }
        serverProcess = p
        if !cliMode {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.refreshIcon() }
        }
    }

    func stopOllama() {
        if let bin = findOllamaBinary(), isServerRunning() {
            for name in loadedModelNames() {
                _ = run(bin, ["stop", name], timeout: 5)
            }
        }
        if let p = serverProcess, p.isRunning { p.terminate() }
        _ = run("/usr/bin/pkill", ["-TERM", "-f", "ollama serve"], timeout: 3)
        _ = run("/usr/bin/pkill", ["-TERM", "-f", "ollama runner"], timeout: 3)
        serverProcess = nil
    }

    func warmUp() {
        guard let model = firstInstalledModel() else {
            alert("No models installed", "Run `ollama pull <model>` first.")
            return
        }
        _ = run("/usr/bin/curl", ["-s", "--max-time", "90", "-X", "POST",
                                  apiBase + "/api/generate",
                                  "-H", "Content-Type: application/json",
                                  "-d", "{\"model\":\"\(model)\"}"], timeout: 95)
        refreshIcon()
    }

    @discardableResult
    func run(_ path: String, _ args: [String], timeout: TimeInterval = 5) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning && Date() < deadline { usleep(100_000) }
        if p.isRunning { p.terminate() }
        return true
    }

    func alert(_ title: String, _ body: String) {
        if cliMode { print("ERROR: \(title) — \(body)"); return }
        let a = NSAlert()
        a.messageText = title
        a.informativeText = body
        _ = a.runModal()
    }
}

// MARK: - CLI mode (for scripts and testing)

if cliMode {
    let d = AppDelegate()
    if cliArgs.contains("--start") {
        d.startOllama()
        Thread.sleep(forTimeInterval: 2.0)
        let ok = d.isServerRunning()
        print(ok ? "running" : "failed")
        exit(ok ? 0 : 1)
    } else if cliArgs.contains("--stop") {
        d.stopOllama()
        Thread.sleep(forTimeInterval: 1.0)
        print(d.isServerRunning() ? "still-running" : "stopped")
        exit(0)
    } else if cliArgs.contains("--warm") {
        d.warmUp()
        print(d.isServerRunning() && !d.loadedModelNames().isEmpty ? "loaded" : "not-loaded")
        exit(0)
    } else if cliArgs.contains("--status") {
        let running = d.isServerRunning()
        let loaded = running && !d.loadedModelNames().isEmpty
        print(running ? (loaded ? "running model-loaded" : "running") : "stopped")
        exit(0)
    } else {
        print("""
        OllamaBar — a menu bar toggle for a local Ollama server

        Usage:
          OllamaBar           Run the menu bar app
          OllamaBar --start   Start `ollama serve` with optimized defaults
          OllamaBar --stop    Stop the server and unload all models
          OllamaBar --status  Print: stopped | running | running model-loaded
          OllamaBar --warm    Preload the first installed model
          OllamaBar --help    Show this help
        """)
        exit(0)
    }
}

// MARK: - GUI

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
