// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CapaCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "CapaCore", targets: ["CapaCore"])],
    targets: [.target(name: "CapaCore"), .testTarget(name: "CapaCoreTests", dependencies: ["CapaCore"]),
              .executableTarget(name: "CapaCoreChecks", dependencies: ["CapaCore"], path: "Checks")]
)
