// SPDX-License-Identifier: MIT
//
// Part of OllamaBar — https://github.com/yutna/ollama-bar

import AppKit

let arguments = Array(CommandLine.arguments.dropFirst())

// Enter CLI mode only for flags we know; Cocoa itself passes arguments such
// as `-AppleLanguages` or `-psn_...` when the app is launched by the system.
let cliFlags: Set<String> = ["--start", "--stop", "--status", "--warm", "--help", "-h"]
if arguments.contains(where: { cliFlags.contains($0) }) {
    CLI.run(arguments)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
