// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "CCVigilShared",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CCVigilShared", targets: ["CCVigilShared"]),
        .library(name: "CCVigilDaemonKit", targets: ["CCVigilDaemonKit"]),
        .library(name: "CCVigilCLIKit", targets: ["CCVigilCLIKit"]),
        .library(name: "CCVigilAppKit", targets: ["CCVigilAppKit"]),
    ],
    dependencies: [
        // Revision-pinned: cc-transcript ships no semver tags for the Swift
        // package; bump by landing a new root-manifest commit there and
        // updating this pin (the single pin for the whole project).
        .package(
            url: "https://github.com/yasyf/cc-transcript.git",
            revision: "e04b44cdb5596e84940027abeab6dc6842e89f5b"
        ),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .target(name: "CCVigilShared"),
        .target(
            name: "CCVigilDaemonKit",
            dependencies: [
                "CCVigilShared",
                .product(name: "CCTranscript", package: "cc-transcript"),
            ]
        ),
        .target(
            name: "CCVigilCLIKit",
            dependencies: [
                "CCVigilShared",
                "CCVigilDaemonKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .target(
            name: "CCVigilAppKit",
            dependencies: [
                "CCVigilShared",
                "CCVigilDaemonKit",
                "CCVigilCLIKit",
            ]
        ),
        .testTarget(name: "CCVigilSharedTests", dependencies: ["CCVigilShared"]),
        .testTarget(
            name: "CCVigilDaemonKitTests",
            dependencies: ["CCVigilDaemonKit"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "CCVigilCLIKitTests", dependencies: ["CCVigilCLIKit"]),
        .testTarget(name: "CCVigilAppKitTests", dependencies: ["CCVigilAppKit", "CCVigilCLIKit"]),
    ]
)
