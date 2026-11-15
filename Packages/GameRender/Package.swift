// swift-tools-version: 6.0
// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import PackageDescription

let package = Package(
    name: "GameRender",
    platforms: [
        .macOS(.v13),
        .iOS(.v17),
    ],
    products: [
        .library(name: "GameRender", targets: ["GameRender"]),
    ],
    dependencies: [
        .package(path: "../GameCore"),
    ],
    targets: [
        .target(name: "GameRender", dependencies: ["GameCore"]),
        .testTarget(name: "GameRenderTests", dependencies: ["GameRender"]),
    ]
)
