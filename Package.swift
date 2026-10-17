// swift-tools-version: 6.2
import PackageDescription

// skill-health: one engine (SkillHealthCore), two front ends.
// - SkillHealthApp: the SwiftUI menu bar app (macOS only).
// - skill-health: the Claude Code plugin's command-line tool (plugin/bin/skill-health), which does every write.
// No third-party dependencies: Foundation, SwiftUI, ServiceManagement, CoreServices.
let package = Package(
    name: "SkillHealth",
    platforms: [.macOS("27.0")],
    products: [
        .executable(name: "SkillHealthApp", targets: ["SkillHealthApp"]),
        .executable(name: "skill-health", targets: ["skill-health"]),
        .library(name: "SkillHealthCore", targets: ["SkillHealthCore"]),
    ],
    targets: [
        .target(
            name: "SkillHealthCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "skill-health",
            dependencies: ["SkillHealthCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "SkillHealthApp",
            dependencies: ["SkillHealthCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .defaultIsolation(MainActor.self),
            ]
        ),
        // Depends on the tool too, so `swift test` builds it: ToolTests run the real binary.
        .testTarget(
            name: "SkillHealthCoreTests",
            dependencies: ["SkillHealthCore", "skill-health"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
