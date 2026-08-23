// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Dogear",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "DogearKit", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(
            name: "Dogear",
            dependencies: ["DogearKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "DogearKitTests",
            dependencies: ["DogearKit"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
