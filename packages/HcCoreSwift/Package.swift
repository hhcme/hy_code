// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HcCoreSwift",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HcCore", targets: ["HcCore"]),
        .library(name: "HcLibrary", targets: ["HcLibrary"]),
    ],
    targets: [
        .binaryTarget(name: "hc_coreFFI", path: "hc_coreFFI.xcframework"),
        .target(name: "HcCore", dependencies: ["hc_coreFFI"], path: "Sources/HcCore"),
        .target(name: "HcLibrary", path: "Sources/HcLibrary"),
        .testTarget(
            name: "HcCoreTests",
            dependencies: ["HcCore", "HcLibrary"],
            path: "Tests/HcCoreTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
