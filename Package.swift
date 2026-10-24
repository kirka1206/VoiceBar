// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VoiceBar",
    platforms: [.macOS("14.2")],
    products: [
        .executable(name: "VoiceBar", targets: ["VoiceBar"])
    ],
    targets: [
        .target(
            name: "VoiceBarCore",
            path: "Sources/VoiceBarCore"
        ),
        .target(
            name: "VoiceBarPlatform",
            dependencies: ["VoiceBarCore"],
            path: "Sources/VoiceBarPlatform",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("AppKit"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Carbon"),
                .linkedFramework("SwiftData")
            ]
        ),
        .executableTarget(
            name: "VoiceBar",
            dependencies: ["VoiceBarCore", "VoiceBarPlatform"],
            path: "Sources/VoiceBar"
        ),
        .testTarget(
            name: "VoiceBarCoreTests",
            dependencies: ["VoiceBarCore"],
            path: "Tests/VoiceBarCoreTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
