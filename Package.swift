// swift-tools-version: 6.2

import PackageDescription


let package = Package(
    name: "SwiftLAME",
    platforms: [.macOS(.v12), .iOS(.v15)],
    products: [
        .library(
            name: "SwiftLAME",
            targets: [
                "SwiftLAME"
            ]
        )
    ],
    targets: [
        
        // Targets
        
        .target(
            name: "SwiftLAME",
            dependencies: ["LAME"]
        ),
        .target(
            name: "LAME",
            publicHeadersPath: "include",
            cSettings: [
                .define("HAVE_CONFIG_H"),
                .disableWarning("absolute-value"),
                .disableWarning("shift-negative-value"),
                .disableWarning("tautological-pointer-compare")
            ]
        ),
        
        // Tests
        
        .testTarget(
            name: "SwiftLAMETests",
            dependencies: ["SwiftLAME"]
        )
    ]
)
