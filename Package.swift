// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClipFlow",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(
            name: "ClipFlow",
            targets: ["ClipFlow"]),
        .library(
            name: "ClipFlowBackend",
            targets: ["ClipFlowBackend"]),
        .library(
            name: "ClipFlowCore",
            targets: ["ClipFlowCore"]),
        .library(
            name: "ClipFlowAPI",
            targets: ["ClipFlowAPI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.0.0"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "ClipFlow",
            dependencies: [
                "ClipFlowBackend",
                "ClipFlowCore",
                "ClipFlowAPI",
                "KeyboardShortcuts"
            ],
            path: "Sources/ClipFlow",
            swiftSettings: [
                .unsafeFlags(["-Xfrontend", "-disable-availability-checking"]),
                .unsafeFlags(["-parse-as-library"]),
                .define("DISABLE_SENDABLE_CHECKING")
            ]
        ),
        .target(
            name: "ClipFlowBackend",
            dependencies: [
                "ClipFlowCore",
                "ClipFlowAPI",
                .product(name: "GRDB", package: "GRDB.swift"),
                "KeyboardShortcuts"
            ],
            path: "Sources/ClipFlowBackend"
        ),
        .target(
            name: "ClipFlowCore",
            dependencies: [],
            path: "Sources/ClipFlowCore"
        ),
        .target(
            name: "ClipFlowAPI",
            dependencies: ["ClipFlowCore"],
            path: "Sources/ClipFlowAPI"
        ),
    ]
)