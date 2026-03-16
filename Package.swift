// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeAgentHUD",
    platforms: [.macOS(.v13)],
    targets: [
        // Library target: all app logic, testable
        .target(
            name: "ClaudeAgentHUDLib",
            path: "Sources/Lib"
        ),
        // Executable target: just the entry point
        .executableTarget(
            name: "ClaudeAgentHUD",
            dependencies: ["ClaudeAgentHUDLib"],
            path: "Sources/App"
        ),
        .testTarget(
            name: "ClaudeAgentHUDTests",
            dependencies: ["ClaudeAgentHUDLib"],
            path: "Tests"
        ),
    ]
)
