// swift-tools-version: 5.9
//
// SPDX-License-Identifier: MIT

import PackageDescription

let package = Package(
    name: "OllamaBar",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "OllamaBarCore",
            path: "Sources/OllamaBarCore"
        ),
        .executableTarget(
            name: "OllamaBar",
            dependencies: ["OllamaBarCore"],
            path: "Sources/OllamaBar"
        ),
        .testTarget(
            name: "OllamaBarCoreTests",
            dependencies: ["OllamaBarCore"],
            path: "Tests/OllamaBarCoreTests"
        ),
    ]
)
