// SPDX-License-Identifier: MIT
//
// Part of OllamaBar — https://github.com/yutna/ollama-bar

import Foundation

/// Every user-facing string in one place.
///
/// Translations live in `resources/<language>.lproj/Localizable.strings`.
/// The `defaultValue` arguments keep development builds — which run outside
/// the app bundle — readable.
public enum L10n {
    public static var menuStatusStopped: String {
        String(localized: "menu.status.stopped", defaultValue: "○ Ollama stopped")
    }

    public static var menuStatusRunning: String {
        String(localized: "menu.status.running", defaultValue: "● Ollama running — no model loaded")
    }

    public static func menuStatusRunning(_ models: String) -> String {
        String(
            format: String(localized: "menu.status.runningModels", defaultValue: "● Ollama running — %@"),
            models)
    }

    public static var menuStart: String {
        String(localized: "menu.start", defaultValue: "▶︎ Start Ollama (optimized defaults)")
    }

    public static var menuStop: String {
        String(localized: "menu.stop", defaultValue: "■ Stop Ollama (free RAM now)")
    }

    public static var menuWarm: String {
        String(localized: "menu.warm", defaultValue: "🔥 Warm up model (preload)")
    }

    public static var menuLogin: String {
        String(localized: "menu.login", defaultValue: "Show icon at login")
    }

    public static var menuLoginPending: String {
        String(
            localized: "menu.login.pending",
            defaultValue: "Login item needs approval — open System Settings")
    }

    public static var accessibilityIcon: String {
        String(localized: "accessibility.icon", defaultValue: "OllamaBar")
    }

    public static var menuQuit: String {
        String(localized: "menu.quit", defaultValue: "Quit (also stops Ollama)")
    }

    public static var tooltipStopped: String {
        String(localized: "tooltip.stopped", defaultValue: "Ollama stopped — click to start")
    }

    public static var tooltipRunning: String {
        String(localized: "tooltip.running", defaultValue: "Ollama running — no model loaded")
    }

    public static var tooltipRunningLoaded: String {
        String(localized: "tooltip.runningLoaded", defaultValue: "Ollama running — model loaded")
    }

    public static var alertLoginTitle: String {
        String(localized: "alert.login.title", defaultValue: "Could not change login item")
    }

    public static var alertLoginBody: String {
        String(
            localized: "alert.login.body",
            defaultValue: "Add it manually under System Settings → General → Login Items.\n\n%@")
    }

    public static var alertNotFoundTitle: String {
        String(localized: "alert.notFound.title", defaultValue: "Ollama not found")
    }

    public static var alertNotFoundBody: String {
        String(
            localized: "alert.notFound.body",
            defaultValue: "Install Ollama from https://ollama.com or run: brew install ollama")
    }

    public static var alertStartFailedTitle: String {
        String(localized: "alert.startFailed.title", defaultValue: "Could not start Ollama")
    }

    public static var alertNoModelsTitle: String {
        String(localized: "alert.noModels.title", defaultValue: "No models installed")
    }

    public static var alertNoModelsBody: String {
        String(localized: "alert.noModels.body", defaultValue: "Run `ollama pull <model>` first.")
    }
}
