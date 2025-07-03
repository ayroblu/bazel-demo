// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// This + Sources folder only exists to appease swiftc + sourcekit-lsp
let package = Package(
  name: "MyPackage",
  platforms: [
    .macOS("15.2"), .iOS(.v17),
  ],
  dependencies: [
    .package(
      url: "https://github.com/pointfreeco/swift-snapshot-testing",
      from: "1.12.0"
    ),
    .package(
      url: "https://github.com/apple/swift-collections.git",
      .upToNextMinor(from: "1.2.0")
    ),
  ],
  targets: [
    .target(name: "utils", path: "utils"),
    .target(name: "g1protocol", path: "g1protocol"),
    .target(
      name: "content",
      dependencies: [
        "Log", "g1protocol", .product(name: "Collections", package: "swift-collections"),
      ], path: "content"),
    .target(name: "Log", path: "swift-shared/Log"),
    .target(name: "LogUtils", dependencies: ["Log"], path: "swift-shared/LogUtils"),
    .target(name: "Jotai", path: "swift-shared/Jotai"),
    .target(name: "maps", dependencies: ["Log", "MySnapshotTesting"], path: "maps"),
    .target(
      name: "MySnapshotTesting",
      dependencies: [
        .product(name: "SnapshotTesting", package: "swift-snapshot-testing")
      ], path: "snapshot-testing"),
    // .testTarget(name: "utils-test", path: "utils"),
  ]
)
