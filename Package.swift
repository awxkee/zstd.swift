// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "zstd",
    platforms: [.iOS(.v13), .macOS(.v11)],
    products: [
        .library(
            name: "zstd",
            targets: ["zstd"]),
        .library(name: "libzstd", targets: ["libzstd"])
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "zstd",
            dependencies: ["zstdc"]),
        .target(name: "zstdc", dependencies: ["libzstd"]),
        .binaryTarget(name: "libzstd", path: "Sources/libzstd/libzstd.xcframework"),
        .testTarget(
            name: "zstd-Tests",
            dependencies: ["zstd"]),
    ]
)
