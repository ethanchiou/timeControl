// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TimeControlCore",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "TimeControlCore", targets: ["TimeControlCore"])
    ],
    targets: [
        .target(name: "TimeControlCore"),
        .testTarget(name: "TimeControlCoreTests", dependencies: ["TimeControlCore"])
    ]
)
