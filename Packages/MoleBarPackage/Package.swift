// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MoleBarPackage",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MoleBarCore", targets: ["MoleBarCore"]),
        .library(name: "MoleBarStores", targets: ["MoleBarStores"]),
        .library(name: "MoleBarUI", targets: ["MoleBarUI"]),
    ],
    dependencies: [
        // Phase 2+ adds dependencies here (e.g., swift-snapshot-testing)
    ],
    targets: [
        .target(name: "MoleBarCore"),
        .target(name: "MoleBarStores", dependencies: ["MoleBarCore"]),
        .target(name: "MoleBarUI", dependencies: ["MoleBarStores"]),
    ]
)
