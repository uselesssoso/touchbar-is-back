// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "QuotaBar",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "QuotaBar", targets: ["QuotaBar"])
    ],
    targets: [
        .target(
            name: "TouchBarPrivate",
            path: "Sources/TouchBarPrivate",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Foundation")
            ]
        ),
        .target(
            name: "OSCrypt",
            path: "Sources/OSCrypt",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "QuotaBar",
            dependencies: ["TouchBarPrivate", "OSCrypt"],
            path: "Sources/QuotaBar",
            linkerSettings: [
                .linkedFramework("Security")
            ]
        )
    ]
)
