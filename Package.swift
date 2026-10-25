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
            name: "TranscriptCorrectionEvaluationSupport",
            path: "Experiments/TranscriptCorrection/Support"
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
                .linkedFramework("SwiftData"),
                .linkedFramework("PDFKit"),
                .linkedFramework("NaturalLanguage")
            ]
        ),
        .executableTarget(
            name: "VoiceBar",
            dependencies: ["VoiceBarCore", "VoiceBarPlatform"],
            path: "Sources/VoiceBar"
        ),
        .executableTarget(
            name: "TranscriptCorrectionEvaluation",
            dependencies: ["VoiceBarCore", "TranscriptCorrectionEvaluationSupport"],
            path: "scripts",
            exclude: ["build-app.sh", "check-core.sh", "check-core.swift"],
            sources: ["evaluate-transcript-correction.swift"]
        ),
        .testTarget(
            name: "VoiceBarCoreTests",
            dependencies: ["VoiceBarCore", "TranscriptCorrectionEvaluationSupport"],
            path: "Tests/VoiceBarCoreTests"
        ),
        .testTarget(
            name: "VoiceBarPlatformTests",
            dependencies: ["VoiceBarCore", "VoiceBarPlatform"],
            path: "Tests/VoiceBarPlatformTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
