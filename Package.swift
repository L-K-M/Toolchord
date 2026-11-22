// swift-tools-version: 6.0
import PackageDescription

// Toolchord is split so that tool evaluation stays deterministic and testable
// without AppKit:
//
// - ToolchordCore: tool commands, input detection, and search ranking.
//   Foundation, CryptoKit, and the system JavaScriptCore runtime.
// - ToolchordSession: the palette's in-memory draft, evaluation scheduling,
//   and copy gating. No AppKit.
// - ToolchordTheme: the theme model, presets, the stored JSON format, and
//   contrast rules. Foundation only, so presets are audited without AppKit.
// - ToolchordMac: the panel, global shortcut, pasteboard, settings, and views.
// - ToolchordSnapshots: renders palette states to PNG for design review.
//
// The app bundle itself is produced from project.yml (XcodeGen) and links
// ToolchordMac.
let package = Package(
    name: "Toolchord",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "toolchord-script-runner", targets: ["ToolchordScriptRunner"]),
        .library(name: "ToolchordCore", targets: ["ToolchordCore"]),
        .library(name: "ToolchordSession", targets: ["ToolchordSession"]),
        .library(name: "ToolchordTheme", targets: ["ToolchordTheme"]),
        .library(name: "ToolchordMac", targets: ["ToolchordMac"]),
        .executable(name: "toolchord-snapshots", targets: ["ToolchordSnapshots"]),
    ],
    targets: [
        .target(name: "ToolchordCore", resources: [.copy("Scripts")]),
        .executableTarget(name: "ToolchordScriptRunner", dependencies: ["ToolchordCore"]),
        .target(name: "ToolchordSession", dependencies: ["ToolchordCore"]),
        .target(name: "ToolchordTheme"),
        .target(name: "ToolchordMac", dependencies: ["ToolchordCore", "ToolchordSession", "ToolchordTheme"]),
        .executableTarget(name: "ToolchordSnapshots", dependencies: ["ToolchordMac"]),
        .testTarget(name: "ToolchordCoreTests", dependencies: ["ToolchordCore"]),
        .testTarget(name: "ToolchordSessionTests", dependencies: ["ToolchordSession"]),
        .testTarget(name: "ToolchordThemeTests", dependencies: ["ToolchordTheme"]),
        .testTarget(name: "ToolchordMacTests", dependencies: ["ToolchordMac"]),
    ]
)
