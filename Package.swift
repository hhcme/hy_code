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
        .executable(name: "HyCodeCodexProbe", targets: ["HyCodeCodexProbe"]),
        .executable(name: "HyCodeCodexSetup", targets: ["HyCodeCodexSetup"]),
        .executable(name: "HyCodeTerminalHost", targets: ["HyCodeTerminalHost"]),
        .executable(name: "HyCodeTerminalProbe", targets: ["HyCodeTerminalProbe"]),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.20.0")
    ],
    targets: [
        .systemLibrary(name: "CHyCodeCore", path: "bindings/CHyCodeCore"),
        .target(name: "CHyCodeTerminal", path: "bindings/CHyCodeTerminal"),
        .target(
            name: "HyCodeWorkspace", dependencies: ["CHyCodeCore", "CHyCodeTerminal"],
            path: "packages/HyCodeWorkspace/Sources",
            linkerSettings: [.unsafeFlags(["-L", packageRoot + "/.build/native"])]
        ),
        .executableTarget(
            name: "HyCodeApp", dependencies: ["HyCodeWorkspace", .product(name: "SwiftTerm", package: "SwiftTerm")],
            path: "app/macos/Sources"
        ),
        .executableTarget(
            name: "HyCodeDirectoryProbe", dependencies: ["HyCodeWorkspace"], path: "tools/DirectoryProbe"),
        .testTarget(
            name: "HyCodeWorkspaceTests",
            dependencies: ["HyCodeWorkspace", .product(name: "SwiftTerm", package: "SwiftTerm")],
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
        .executableTarget(name: "HyCodeCodexProbe", dependencies: ["HyCodeWorkspace"], path: "tools/CodexProbe"),
        .executableTarget(name: "HyCodeCodexSetup", dependencies: ["HyCodeWorkspace"], path: "tools/CodexSetup"),
        .executableTarget(name: "HyCodeTerminalHost", path: "tools/TerminalHost"),
        .executableTarget(
            name: "HyCodeTerminalProbe",
            dependencies: ["HyCodeWorkspace", .product(name: "SwiftTerm", package: "SwiftTerm")],
            path: "tools/TerminalProbe"),
    ]
)
