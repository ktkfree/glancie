// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Glancie",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Glancie", targets: ["Glancie"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "Glancie",
            dependencies: [],
            path: "Sources/Glancie"
        ),
        .testTarget(
            name: "GlancieTests",
            dependencies: ["Glancie"],
            path: "Tests/GlancieTests"
        )
    ]
)
