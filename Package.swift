// swift-tools-version:5.9
// GVIntelligence iOS SDK — public tag 0.0.10 (branch-agnostic mirror trigger)
import PackageDescription

let package = Package(
    name: "GVIntelligence",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(name: "GVIntelligence", targets: ["GVIntelligence"])
    ],
    targets: [
        .target(
            name: "GVIntelligence",
            dependencies: [],
            path: "Sources/GVIntelligence"
        ),
        .testTarget(
            name: "GVIntelligenceTests",
            dependencies: ["GVIntelligence"],
            path: "Tests/GVIntelligenceTests"
        )
    ]
)
