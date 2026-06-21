// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StemacleMac",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "StemacleMac", targets: ["StemacleMac"]),
    ],
    targets: [
        .executableTarget(name: "StemacleMac"),
    ]
)
