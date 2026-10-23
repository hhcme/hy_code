import Foundation
// swift-tools-version: 6.0
import PackageDescription

let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path

let package = Package(
    name: "HyCode",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "HyCode", targets: ["HyCodeApp"]),
        .library(name: "HyCodeWorkspace", targets: ["HyCodeWorkspace"]),
        .executable(name: "HyCodeDirectoryProbe", targets: ["HyCodeDirectoryProbe"]),
        .executable(name: "HyCodeDartProbe", targets: ["HyCodeDartProbe"]),
        .executable(name: "HyCodeDebugProbe", targets: ["HyCodeDebugProbe"]),
        .executable(name: "HyCodeWebProbe", targets: ["HyCodeWebProbe"]),
        .executable(name: "HyCodeNativeLanguageProbe", targets: ["HyCodeNativeLanguageProbe"]),
        .executable(name: "HyCodeMarkupRuleProbe", targets: ["HyCodeMarkupRuleProbe"]),
        .executable(name: "HyCodeLargeFileProbe", targets: ["HyCodeLargeFileProbe"]),
    ],
    targets: [
        .systemLibrary(name: "CHyCodeCore", path: "bindings/CHyCodeCore"),
        .target(
            name: "HyCodeWorkspace", dependencies: ["CHyCodeCore"],
            path: "packages/HyCodeWorkspace/Sources",
            linkerSettings: [.unsafeFlags(["-L", packageRoot + "/.build/native"])]
        ),
        .executableTarget(
            name: "HyCodeApp", dependencies: ["HyCodeWorkspace"],
            path: "app/macos/Sources"
        ),
        .executableTarget(
            name: "HyCodeDirectoryProbe", dependencies: ["HyCodeWorkspace"], path: "tools/DirectoryProbe"),
        .testTarget(
            name: "HyCodeWorkspaceTests", dependencies: ["HyCodeWorkspace"],
            path: "packages/HyCodeWorkspace/Tests"
        ),
        .executableTarget(name: "HyCodeDartProbe", dependencies: ["HyCodeWorkspace"], path: "tools/DartProbe"),
        .executableTarget(name: "HyCodeDebugProbe", dependencies: ["HyCodeWorkspace"], path: "tools/DebugProbe"),
        .executableTarget(name: "HyCodeWebProbe", dependencies: ["HyCodeWorkspace"], path: "tools/WebProbe"),
        .executableTarget(
            name: "HyCodeNativeLanguageProbe", dependencies: ["HyCodeWorkspace"], path: "tools/NativeLanguageProbe"),
        .executableTarget(
            name: "HyCodeMarkupRuleProbe", dependencies: ["HyCodeWorkspace"], path: "tools/MarkupRuleProbe"),
        .executableTarget(
            name: "HyCodeLargeFileProbe", dependencies: ["HyCodeWorkspace"], path: "tools/LargeFileProbe"),
    ]
)
