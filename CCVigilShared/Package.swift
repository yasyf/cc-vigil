// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "CCVigilShared",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CCVigilShared", targets: ["CCVigilShared"]),
    ],
    targets: [
        .target(name: "CCVigilShared"),
        .testTarget(name: "CCVigilSharedTests", dependencies: ["CCVigilShared"]),
    ]
)
