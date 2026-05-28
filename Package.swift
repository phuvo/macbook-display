// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "display-control",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "display-control", targets: ["display-control"])
    ],
    targets: [
        .executableTarget(
            name: "display-control",
            linkerSettings: [
                .linkedFramework("CoreGraphics")
            ]
        )
    ]
)
