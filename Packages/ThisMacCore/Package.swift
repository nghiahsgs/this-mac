// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ThisMacCore",
    platforms: [.macOS(.v15)],
    products: [.library(name: "ThisMacCore", targets: ["ThisMacCore"])],
    targets: [
        .target(name: "ThisMacCore"),
        .testTarget(name: "ThisMacCoreTests", dependencies: ["ThisMacCore"]),
    ]
)
