// swift-tools-version: 6.0
// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import PackageDescription

let package = Package(
    name: "Services",
    platforms: [
        .macOS(.v13),
        .iOS(.v17),
    ],
    products: [
        .library(name: "Services", targets: ["Services"]),
    ],
    dependencies: [
        .package(path: "../GameCore"),
    ],
    targets: [
        .target(name: "Services", dependencies: ["GameCore"]),
        .testTarget(name: "ServicesTests", dependencies: ["Services"]),
    ]
)
