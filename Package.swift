// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "sebbu-deflate",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .watchOS(.v26),
        .tvOS(.v26)
    ],
    products: [
        .library(
            name: "SebbuDeflate",
            targets: ["SebbuDeflate"]
        ),
        .library(
            name: "CLibDeflate", 
            targets: ["CLibDeflate"]
        )
    ],
    targets: [
        .target(
            name: "CLibDeflate"
        ),
        .target(
            name: "SebbuDeflate",
            dependencies: [
                "CLibDeflate"
            ]
        ),
        .target(
            name: "SebbuDeflateFoundation",
            dependencies: [
                "SebbuDeflate"
            ]
        ),
        .testTarget(
            name: "SebbuDeflateTests",
            dependencies: ["SebbuDeflate", "SebbuDeflateFoundation"],
        ),
    ]
)
