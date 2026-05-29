// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "macbook-display",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "macbook-display", targets: ["macbook-display"])
    ],
    targets: [
        .executableTarget(
            name: "macbook-display",
            linkerSettings: [
                .linkedFramework("CoreGraphics")
            ]
        )
    ]
)
