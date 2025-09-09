// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "LogTapIOS",
  defaultLocalization: "en",
  platforms: [
    .iOS(.v14),     // covers iPhone + iPad
    .macOS(.v12)
  ],
  products: [
    .library(name: "LogTapIOS", type: .static, targets: ["LogTapIOS"])
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-nio.git", from: "2.63.0"),
    .package(url: "https://github.com/apple/swift-nio-transport-services.git", from: "1.20.0"),
    .package(url: "https://github.com/vapor/websocket-kit.git", from: "2.13.0")
  ],
  targets: [
    .target(
      name: "LogTapIOS",
      dependencies: [
        .product(name: "NIO", package: "swift-nio"),
        .product(name: "NIOHTTP1", package: "swift-nio"),
        .product(name: "NIOTransportServices", package: "swift-nio-transport-services"),
        .product(name: "WebSocketKit", package: "websocket-kit")
      ],
      path: "LogTapIOS/Sources/LogTapIOS"
    )
  ]
)
