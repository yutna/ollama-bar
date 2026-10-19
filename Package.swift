// swift-tools-version: 5.9
//
// SPDX-License-Identifier: MIT

import PackageDescription

let package = Package(
    name: "OllamaBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "OllamaBar",
            path: "Sources/OllamaBar"
        )
    ]
)
