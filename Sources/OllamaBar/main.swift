// SPDX-License-Identifier: MIT
//
// Part of OllamaBar — https://github.com/yutna/ollama-bar

import AppKit
import OllamaBarCore

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

// A `kill` or logout does not run `applicationWillTerminate`, so trap the
// common termination signals and stop the managed server before exiting.
var signalSources: [DispatchSourceSignal] = []
for signalNumber in [SIGTERM, SIGINT, SIGHUP] {
    signal(signalNumber, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
    source.setEventHandler { delegate.handleTerminationSignal() }
    source.resume()
    signalSources.append(source)
}

app.run()
