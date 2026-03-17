// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Claudblobs",
    platforms: [.macOS(.v13)],
    targets: [
        // Library target: all app logic, testable
        .target(
            name: "ClaudblobsLib",
            path: "Sources/Lib"
        ),
        // Executable target: just the entry point
        .executableTarget(
            name: "Claudblobs",
            dependencies: ["ClaudblobsLib"],
            path: "Sources/App"
        ),
        .testTarget(
            name: "ClaudblobsTests",
            dependencies: ["ClaudblobsLib"],
            path: "Tests"
        ),
    ]
)
