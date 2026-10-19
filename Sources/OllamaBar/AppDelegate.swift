// SPDX-License-Identifier: MIT
//
// Part of OllamaBar — https://github.com/yutna/ollama-bar

import AppKit
import OllamaBarCore
import ServiceManagement

/// Menu bar UI and user actions.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    /// Cached server state, refreshed off the main thread.
    private struct ServerState: Equatable {
        var isRunning = false
        var loadedModels: [String] = []
    }

    private let service = OllamaService()
    private var statusItem: NSStatusItem?
    private var refreshTimer: Timer?
    private var state = ServerState()
    private var isRefreshing = false

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item

        if let button = item.button {
            button.title = "🦙"
            button.setAccessibilityLabel(L10n.accessibilityIcon)
        }
        refreshIcon()
        refreshState()

        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            self?.refreshState()
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer

        // Documentation helper: with `OLLAMABAR_SCREENSHOT=1` the app opens
        // its menu after launch and prints the status item frame (screen
        // coordinates, top-left origin) so docs screenshots can be scripted.
        // See CONTRIBUTING.md.
        if ProcessInfo.processInfo.environment["OLLAMABAR_SCREENSHOT"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let button = self?.statusItem?.button, let window = button.window,
                    let screen = NSScreen.main
                else { return }
                let frame = window.frame
                let top = screen.frame.height - frame.maxY
                print("OLLAMABAR_FRAME x=\(Int(frame.minX)) y=\(Int(top)) w=\(Int(frame.width)) h=\(Int(frame.height))")
                fflush(stdout)
                button.performClick(nil)
            }
        }
    }

    /// Quitting must not freeze the menu: stop off the main thread and let
    /// AppKit wait with `.terminateLater`. `applicationWillTerminate` keeps a
    /// fast safety-net call for paths that reach it without this one.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task.detached { [weak self] in
            _ = self?.service.stop(unloadingModels: false)
            await MainActor.run {
                NSApp.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        service.stop(unloadingModels: false)
    }

    /// Cleanup path for SIGTERM/SIGINT/SIGHUP (see `main.swift`).
    func handleTerminationSignal() {
        service.stop(unloadingModels: false)
        exit(0)
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuild(menu)
        refreshState()
    }

    // MARK: - State

    /// Refreshes the cached server state without blocking the main thread.
    private func refreshState() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task.detached { [weak self] in
            guard let self else { return }
            let status = await self.service.status()
            await MainActor.run {
                self.isRefreshing = false
                self.state = ServerState(isRunning: status.isRunning, loadedModels: status.loadedModels)
                self.refreshIcon()
            }
        }
    }

    // MARK: - Icon state

    private func refreshIcon() {
        guard let button = statusItem?.button else { return }
        let running = state.isRunning
        button.alphaValue = running ? 1.0 : 0.35

        if running && !state.loadedModels.isEmpty {
            button.toolTip = L10n.tooltipRunningLoaded
        } else if running {
            button.toolTip = L10n.tooltipRunning
        } else {
            button.toolTip = L10n.tooltipStopped
        }
    }

    // MARK: - Menu

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()

        let running = state.isRunning
        let models = state.loadedModels

        let header = NSMenuItem(title: statusTitle(running: running, models: models), action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        if running {
            addItem(to: menu, title: L10n.menuStop, action: #selector(stopAction))
            if models.isEmpty {
                addItem(to: menu, title: L10n.menuWarm, action: #selector(warmAction))
            }
        } else {
            addItem(to: menu, title: L10n.menuStart, action: #selector(startAction))
        }
        menu.addItem(.separator())

        let loginStatus = SMAppService.mainApp.status
        let loginTitle = loginStatus == .requiresApproval ? L10n.menuLoginPending : L10n.menuLogin
        let login = addItem(to: menu, title: loginTitle, action: #selector(toggleLogin))
        login.state = loginStatus == .enabled ? .on : .off
        menu.addItem(.separator())

        addItem(to: menu, title: L10n.menuQuit, action: #selector(quitAction), keyEquivalent: "q")
    }

    private func statusTitle(running: Bool, models: [String]) -> String {
        guard running else { return L10n.menuStatusStopped }
        guard !models.isEmpty else { return L10n.menuStatusRunning }
        return L10n.menuStatusRunning(models.joined(separator: ", "))
    }

    @discardableResult
    private func addItem(
        to menu: NSMenu,
        title: String,
        action: Selector,
        keyEquivalent: String = ""
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        menu.addItem(item)
        return item
    }

    // MARK: - Actions

    @objc private func startAction() {
        Task.detached { [weak self] in
            guard let self else { return }
            do {
                try self.service.start()
                await MainActor.run { self.refreshState() }
            } catch OllamaError.binaryNotFound {
                await MainActor.run { self.alert(title: L10n.alertNotFoundTitle, body: L10n.alertNotFoundBody) }
            } catch {
                await MainActor.run {
                    self.alert(title: L10n.alertStartFailedTitle, body: error.localizedDescription)
                }
            }
        }
    }

    @objc private func stopAction() {
        Task.detached { [weak self] in
            guard let self else { return }
            let stopped = self.service.stop()
            await MainActor.run {
                if !stopped {
                    self.alert(title: L10n.alertStopFailedTitle, body: L10n.alertStopFailedBody)
                }
                self.refreshState()
            }
        }
    }

    @objc private func warmAction() {
        Task.detached { [weak self] in
            guard let self else { return }
            guard let model = self.service.firstInstalledModel else {
                await MainActor.run { self.alert(title: L10n.alertNoModelsTitle, body: L10n.alertNoModelsBody) }
                return
            }
            let warmed = self.service.warmUp()
            await MainActor.run {
                if !warmed {
                    self.alert(
                        title: L10n.alertWarmFailedTitle,
                        body: String(format: L10n.alertWarmFailedBody, model))
                }
                self.refreshState()
            }
        }
    }

    @objc private func toggleLogin() {
        let loginItem = SMAppService.mainApp
        do {
            switch loginItem.status {
            case .enabled:
                try loginItem.unregister()
            case .requiresApproval:
                SMAppService.openSystemSettingsLoginItems()
            default:
                try loginItem.register()
            }
        } catch {
            alert(
                title: L10n.alertLoginTitle,
                body: String(format: L10n.alertLoginBody, error.localizedDescription))
        }
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }

    private func alert(title: String, body: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.runModal()
    }
}
