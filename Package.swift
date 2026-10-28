// swift-tools-version:6.0
import PackageDescription

// -Osize makes the app binary 47 KB (4%) smaller. The storeHotPaths benchmark shows no change outside the noise.
let size = SwiftSetting.unsafeFlags(["-Osize"], .when(configuration: .release))

let package = Package(
    name: "Dogear",
    platforms: [.macOS("15.4")], // NSPasteboard.detectedPatterns requires macOS 15.4+
    targets: [
        .target(name: "DogearKit", swiftSettings: [.swiftLanguageMode(.v5), size]),
        .executableTarget(
            name: "Dogear",
            dependencies: ["DogearKit"],
            swiftSettings: [.swiftLanguageMode(.v5), size]
        ),
        .testTarget(
            name: "DogearKitTests",
            dependencies: ["DogearKit"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
