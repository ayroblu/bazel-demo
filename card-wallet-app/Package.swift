// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// This + Sources folder only exists to appease swiftc + sourcekit-lsp
let package = Package(
  name: "MyPackage",
  platforms: [
    .macOS("15.2"), .iOS(.v17),
  ],
  targets: [
    .target(name: "content", dependencies: ["SwiftUIUtils"], path: "content"),
    .target(name: "Log", path: "swift-shared/Log"),
    .target(name: "LogUtils", dependencies: ["Log"], path: "swift-shared/LogUtils"),
    .target(name: "Jotai", path: "swift-shared/Jotai"),
    .target(name: "SwiftUIUtils", path: "swift-shared/SwiftUIUtils"),
    // .testTarget(name: "utils-test", path: "utils"),
  ]
)
