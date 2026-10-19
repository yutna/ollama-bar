// SPDX-License-Identifier: MIT
//
// Part of OllamaBar — https://github.com/yutna/ollama-bar

import AppKit
import ServiceManagement

/// Menu bar UI and user actions.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let service = OllamaService()
    private var statusItem: NSStatusItem?
    private var refreshTimer: Timer?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item

        refreshIcon()

        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            self?.refreshIcon()
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

    func applicationWillTerminate(_ notification: Notification) {
        service.stop()
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuild(menu)
    }

    // MARK: - Icon state

    private func refreshIcon() {
        guard let button = statusItem?.button else { return }
        let running = service.isServerRunning
        button.title = "🦙"
        button.alphaValue = running ? 1.0 : 0.35

        if running && !service.loadedModelNames.isEmpty {
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

        let running = service.isServerRunning
        let models = running ? service.loadedModelNames : []

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

        let login = addItem(to: menu, title: L10n.menuLogin, action: #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
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
        do {
            try service.start()
            refreshIcon()
        } catch OllamaError.binaryNotFound {
            alert(title: L10n.alertNotFoundTitle, body: L10n.alertNotFoundBody)
        } catch {
            alert(title: L10n.alertStartFailedTitle, body: error.localizedDescription)
        }
    }

    @objc private func stopAction() {
        service.stop()
        refreshIcon()
    }

    @objc private func warmAction() {
        guard service.firstInstalledModel != nil else {
            alert(title: L10n.alertNoModelsTitle, body: L10n.alertNoModelsBody)
            return
        }
        DispatchQueue.global().async { [weak self] in
            self?.service.warmUp()
            DispatchQueue.main.async { self?.refreshIcon() }
        }
    }

    @objc private func toggleLogin() {
        let loginItem = SMAppService.mainApp
        do {
            if loginItem.status == .enabled {
                try loginItem.unregister()
            } else {
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
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.runModal()
    }
}
