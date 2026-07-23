// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "CCVigilShared",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "CCVigilShared", targets: ["CCVigilShared"]),
        .library(name: "CCVigilRuntime", targets: ["CCVigilRuntime"]),
        .library(name: "CCVigilTransport", targets: ["CCVigilTransport"]),
        .library(name: "CCVigilCLIKit", targets: ["CCVigilCLIKit"]),
        .library(name: "CCVigilAppKit", targets: ["CCVigilAppKit"]),
    ],
    dependencies: [
        // Revision-pinned: cc-transcript ships no semver tags for the Swift
        // package; bump by landing a new root-manifest commit there and
        // updating this pin (the single pin for the whole project).
        .package(
            url: "https://github.com/yasyf/cc-transcript.git",
            revision: "dadcda0b98d7abaaf30d38677cb762ffa0ec72eb"
        ),
        .package(url: "https://github.com/yasyf/daemonkit.git", exact: "0.7.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .target(name: "CCVigilShared"),
        .target(
            name: "CCVigilRuntime",
            dependencies: [
                "CCVigilShared",
                .product(name: "CCTranscript", package: "cc-transcript"),
            ]
        ),
        .target(
            name: "CCVigilTransport",
            dependencies: [
                "CCVigilShared",
                .product(name: "DaemonKit", package: "daemonkit"),
            ]
        ),
        .target(
            name: "CCVigilCLIKit",
            dependencies: [
                "CCVigilShared",
                "CCVigilRuntime",
                "CCVigilTransport",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .target(
            name: "CCVigilAppKit",
            dependencies: [
                "CCVigilShared",
                "CCVigilRuntime",
                "CCVigilCLIKit",
            ]
        ),
        .testTarget(name: "CCVigilSharedTests", dependencies: ["CCVigilShared"]),
        .testTarget(
            name: "CCVigilRuntimeTests",
            dependencies: ["CCVigilRuntime"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "CCVigilCLIKitTests",
            dependencies: [
                "CCVigilCLIKit",
                "CCVigilTransport",
                .product(name: "DaemonKit", package: "daemonkit"),
            ]
        ),
        .testTarget(
            name: "CCVigilAppKitTests",
            dependencies: ["CCVigilAppKit", "CCVigilCLIKit", "CCVigilTransport"]
        ),
    ]
)
