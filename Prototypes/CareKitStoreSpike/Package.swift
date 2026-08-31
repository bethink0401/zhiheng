// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "CareKitStoreSpike",
    platforms: [
        .macOS(.v15),
        .iOS(.v18)
    ],
    products: [
        .library(name: "CareKitStoreSpike", targets: ["CareKitStoreSpike"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/carekit-apple/CareKit.git",
            exact: "4.1.0"
        )
    ],
    targets: [
        .target(
            name: "CareKitStoreSpike",
            dependencies: [
                .product(name: "CareKitStore", package: "CareKit")
            ]
        ),
        .testTarget(
            name: "CareKitStoreSpikeTests",
            dependencies: ["CareKitStoreSpike"]
        )
    ]
)

