// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SarvAuth",
    defaultLocalization: "en",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "SarvAuth", targets: ["SarvAuth"]),
    ],
    targets: [
        .target(
            name: "SarvAuth",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "SarvAuthTests",
            dependencies: ["SarvAuth"]
        ),
    ]
)
