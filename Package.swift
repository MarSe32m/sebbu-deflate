// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "sebbu-deflate",
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
            ],
            swiftSettings: [
                .enableExperimentalFeature("TildeSendable")
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
