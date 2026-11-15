// swift-tools-version: 6.0
// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import PackageDescription

let package = Package(
    name: "GameCore",
    platforms: [
        .macOS(.v13),
        .iOS(.v17),
    ],
    products: [
        .library(name: "GameCore", targets: ["GameCore"]),
    ],
    targets: [
        .target(
            name: "GameCore",
            resources: [
                .copy("Resources"),
            ]
        ),
        .testTarget(name: "GameCoreTests", dependencies: ["GameCore"]),
    ]
)
