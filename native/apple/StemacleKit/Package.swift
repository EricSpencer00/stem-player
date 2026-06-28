// swift-tools-version: 5.9
import PackageDescription

// StemacleKit wraps the shared Rust DSP core (StemacleCore.xcframework) in a
// Swift-native API. Build the xcframework first:
//   bash scripts/build-apple-xcframework.sh
let package = Package(
    name: "StemacleKit",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "StemacleKit", targets: ["StemacleKit"]),
    ],
    targets: [
        .binaryTarget(
            name: "StemacleCore",
            path: "../StemacleCore.xcframework"
        ),
        .target(
            name: "StemacleKit",
            dependencies: ["StemacleCore"]
        ),
        .testTarget(
            name: "StemacleKitTests",
            dependencies: ["StemacleKit"]
        ),
    ]
)
