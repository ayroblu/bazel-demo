// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "monorepo",
  platforms: [.macOS(.v15)],
  dependencies: [
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.12.0"),
    .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.0"),
    .package(url: "https://github.com/marmelroy/Zip.git", from: "2.1.2"),
    .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.27.0"),
  ]
)
