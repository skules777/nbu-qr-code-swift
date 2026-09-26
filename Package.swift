// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NBUQRCode",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(name: "NBUQRCode", targets: ["NBUQRCode"]),
        .library(name: "NBUQRCodeImage", targets: ["NBUQRCodeImage"])
    ],
    targets: [
        .target(name: "NBUQRCode"),
        .target(name: "NBUQRCodeImage", dependencies: ["NBUQRCode"]),
        .testTarget(name: "NBUQRCodeTests", dependencies: ["NBUQRCode", "NBUQRCodeImage"])
    ]
)
