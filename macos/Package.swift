// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "CAPAMac",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../ios/CapaCore")],
    targets: [.executableTarget(name: "CAPAMac", dependencies: [.product(name: "CapaCore", package: "CapaCore")])],
    swiftLanguageModes: [.v5]
)
