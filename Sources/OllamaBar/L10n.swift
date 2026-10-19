// SPDX-License-Identifier: MIT
//
// Part of OllamaBar — https://github.com/yutna/ollama-bar

import Foundation

/// Every user-facing string in one place.
///
/// Translations live in `resources/<language>.lproj/Localizable.strings`.
/// The `defaultValue` arguments keep development builds — which run outside
/// the app bundle — readable.
enum L10n {
    static var menuStatusStopped: String {
        String(localized: "menu.status.stopped", defaultValue: "○ Ollama stopped")
    }

    static var menuStatusRunning: String {
        String(localized: "menu.status.running", defaultValue: "● Ollama running — no model loaded")
    }

    static func menuStatusRunning(_ models: String) -> String {
        String(
            format: String(localized: "menu.status.runningModels", defaultValue: "● Ollama running — %@"),
            models)
    }

    static var menuStart: String {
        String(localized: "menu.start", defaultValue: "▶︎ Start Ollama (optimized defaults)")
    }

    static var menuStop: String {
        String(localized: "menu.stop", defaultValue: "■ Stop Ollama (free RAM now)")
    }

    static var menuWarm: String {
        String(localized: "menu.warm", defaultValue: "🔥 Warm up model (preload)")
    }

    static var menuLogin: String {
        String(localized: "menu.login", defaultValue: "Show icon at login")
    }

    static var menuQuit: String {
        String(localized: "menu.quit", defaultValue: "Quit (also stops Ollama)")
    }

    static var tooltipStopped: String {
        String(localized: "tooltip.stopped", defaultValue: "Ollama stopped — click to start")
    }

    static var tooltipRunning: String {
        String(localized: "tooltip.running", defaultValue: "Ollama running — no model loaded")
    }

    static var tooltipRunningLoaded: String {
        String(localized: "tooltip.runningLoaded", defaultValue: "Ollama running — model loaded")
    }

    static var alertLoginTitle: String {
        String(localized: "alert.login.title", defaultValue: "Could not change login item")
    }

    static var alertLoginBody: String {
        String(
            localized: "alert.login.body",
            defaultValue: "Add it manually under System Settings → General → Login Items.\n\n%@")
    }

    static var alertNotFoundTitle: String {
        String(localized: "alert.notFound.title", defaultValue: "Ollama not found")
    }

    static var alertNotFoundBody: String {
        String(
            localized: "alert.notFound.body",
            defaultValue: "Install Ollama from https://ollama.com or run: brew install ollama")
    }

    static var alertStartFailedTitle: String {
        String(localized: "alert.startFailed.title", defaultValue: "Could not start Ollama")
    }

    static var alertNoModelsTitle: String {
        String(localized: "alert.noModels.title", defaultValue: "No models installed")
    }

    static var alertNoModelsBody: String {
        String(localized: "alert.noModels.body", defaultValue: "Run `ollama pull <model>` first.")
    }
}
