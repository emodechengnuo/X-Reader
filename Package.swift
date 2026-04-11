// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "X-Reader",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "X-Reader", targets: ["X-Reader"])
    ],
    dependencies: [
        .package(url: "https://github.com/Jud/kokoro-coreml.git", from: "0.8.0")
    ],
    targets: [
        .executableTarget(
            name: "X-Reader",
            dependencies: [
                .product(name: "KokoroCoreML", package: "kokoro-coreml")
            ],
            path: "Sources",
            resources: [
                .process("Resources/CEFR")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
