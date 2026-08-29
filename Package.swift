// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ThematicAnalysis",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ThematicAnalysis", targets: ["ThematicAnalysis"])],
    targets: [
        .executableTarget(name: "ThematicAnalysis", resources: [.process("Resources")]),
        .testTarget(name: "ThematicAnalysisTests", dependencies: ["ThematicAnalysis"])
    ]
)
