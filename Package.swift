// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "hop",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "hop", targets: ["Hop"]),
    ],
    targets: [
        // Pure logic: TOML parsing, config model, hotkey parsing, fuzzy matching.
        .target(name: "HopCore"),
        // AppKit shell: panel, global hotkey, launching.
        .executableTarget(
            name: "Hop",
            dependencies: ["HopCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "HopCoreTests", dependencies: ["HopCore"]),
    ]
)
