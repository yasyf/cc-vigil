// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "CCVigilShared",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CCVigilShared", targets: ["CCVigilShared"]),
        .library(name: "CCVigilDaemonKit", targets: ["CCVigilDaemonKit"]),
    ],
    dependencies: [
        // Revision-pinned: cc-transcript ships no semver tags for the Swift
        // package; bump by landing a new root-manifest commit there and
        // updating this pin (the single pin for the whole project).
        .package(
            url: "https://github.com/yasyf/cc-transcript.git",
            revision: "efd4594df05e0dd9963601e1ac98789b49db005b"
        ),
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
        .testTarget(name: "CCVigilSharedTests", dependencies: ["CCVigilShared"]),
        .testTarget(
            name: "CCVigilDaemonKitTests",
            dependencies: ["CCVigilDaemonKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
