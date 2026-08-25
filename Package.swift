// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "PersonalReader",
  platforms: [
    .iOS(.v17),
    .macOS(.v14),
  ],
  products: [
    .library(
      name: "PersonalReaderCore",
      targets: ["PersonalReaderCore"]
    )
  ],
  dependencies: [
    .package(
      url: "https://github.com/groue/GRDB.swift.git",
      from: "7.0.0"
    )
  ],
  targets: [
    .target(
      name: "PersonalReaderCore",
      dependencies: [
        .product(name: "GRDB", package: "GRDB.swift")
      ]
    ),
    .testTarget(
      name: "PersonalReaderCoreTests",
      dependencies: ["PersonalReaderCore"]
    ),
  ],
  swiftLanguageModes: [.v6]
)
