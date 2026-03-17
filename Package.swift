// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeBlobs",
    platforms: [.macOS(.v13)],
    targets: [
        // Library target: all app logic, testable
        .target(
            name: "ClaudeBlobsLib",
            path: "Sources/Lib"
        ),
        // Executable target: just the entry point
        .executableTarget(
            name: "ClaudeBlobs",
            dependencies: ["ClaudeBlobsLib"],
            path: "Sources/App"
        ),
        .testTarget(
            name: "ClaudeBlobsTests",
            dependencies: ["ClaudeBlobsLib"],
            path: "Tests"
        ),
    ]
)
