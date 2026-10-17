// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Cellar",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "cellar", targets: ["cellar"]),
        .library(name: "CellarCore", targets: ["CellarCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(name: "CellarCore", resources: [.process("Resources")]),
        .executableTarget(
            name: "cellar",
            dependencies: [
                "CellarCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(name: "CellarCoreTests", dependencies: ["CellarCore"]),
    ]
)
