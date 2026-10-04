// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "auto_orientation_v2",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(
            name: "auto-orientation-v2",
            targets: ["auto_orientation_v2"]
        )
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "auto_orientation_v2",
            dependencies: [
                .product(
                    name: "FlutterFramework",
                    package: "FlutterFramework"
                )
            ],
            resources: []
        )
    ]
)
