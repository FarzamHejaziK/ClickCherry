// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "TaskAgentMacOS",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TaskAgentMacOS", targets: ["TaskAgentMacOS"])
    ],
    targets: [
        .executableTarget(
            name: "TaskAgentMacOS"
        ),
        .testTarget(
            name: "TaskAgentMacOSTests",
            dependencies: ["TaskAgentMacOS"]
        )
    ]
)
