// SPDX-License-Identifier: MIT
//
// Part of OllamaBar — https://github.com/yutna/ollama-bar

import AppKit
import OllamaBarCore

let arguments = Array(CommandLine.arguments.dropFirst())

// Enter CLI mode for options the user typed. Cocoa itself passes single-dash
// arguments such as `-AppleLanguages` or `-psn_...` when the app is launched
// by the system. Unknown `--` options go to the CLI as well: `CLI.run` prints
// the usage and exits instead of silently starting the menu bar app.
if arguments.contains(where: { $0.hasPrefix("--") || CLI.flags.contains($0) }) {
    CLI.run(arguments)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate

// A `kill` or logout does not run `applicationWillTerminate`, so trap the
// common termination signals and stop the managed server before exiting.
// The sources run off the main queue on purpose: during menu tracking the
// main queue can be stalled, and termination must not wait for it.
var signalSources: [DispatchSourceSignal] = []
for signalNumber in [SIGTERM, SIGINT, SIGHUP] {
    signal(signalNumber, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .global(qos: .userInitiated))
    source.setEventHandler { delegate.handleTerminationSignal() }
    source.resume()
    signalSources.append(source)
}

app.run()
