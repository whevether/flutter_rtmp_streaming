// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "rtmp_streaming",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "rtmp-streaming", targets: ["rtmp_streaming"])
    ],
    dependencies: [
        .package(url: "https://github.com/HaishinKit/HaishinKit.swift", exact: "2.2.5")
    ],
    targets: [
        .target(
            name: "rtmp_streaming",
            dependencies: [
                .product(name: "HaishinKit", package: "HaishinKit.swift"),
                .product(name: "RTMPHaishinKit", package: "HaishinKit.swift"),
                .product(name: "SRTHaishinKit", package: "HaishinKit.swift")
            ],
            resources: [
            ]
        )
    ]
)
