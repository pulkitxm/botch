// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Botch",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BotchKit", targets: ["BotchKit"]),
        .executable(name: "Botch", targets: ["Botch"]),
    ],
    targets: [
        .target(
            name: "BotchKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Botch",
            dependencies: ["BotchKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "BotchTests",
            dependencies: ["BotchKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
