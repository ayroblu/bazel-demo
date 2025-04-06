// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "bazel-project",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.12.0"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.0"),
    ]
)
