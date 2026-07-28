// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GSIntelligence",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(name: "GSIntelligence", targets: ["GSIntelligence"])
    ],
    targets: [
        .target(
            name: "GSIntelligence",
            dependencies: [],
            path: "Sources/GSIntelligence"
        ),
        .testTarget(
            name: "GSIntelligenceTests",
            dependencies: ["GSIntelligence"],
            path: "Tests/GSIntelligenceTests"
        )
    ]
)
