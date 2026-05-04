// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "EngAssistant",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Core", targets: ["Core"]),
        .library(name: "Persistence", targets: ["Persistence"]),
        .executable(name: "smoke-cli", targets: ["SmokeCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0"),
    ],
    targets: [
        .target(
            name: "Core",
            resources: [.process("Resources")]
        ),
        .target(
            name: "Persistence",
            dependencies: [
                "Core",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .executableTarget(
            name: "SmokeCLI",
            dependencies: ["Core", "Persistence"]
        ),
        .testTarget(name: "CoreTests", dependencies: ["Core"]),
        .testTarget(name: "PersistenceTests", dependencies: ["Persistence"]),
    ]
)
