// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CalendarBar",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "CalendarBar", targets: ["CalendarBar"])
    ],
    targets: [
        .executableTarget(
            name: "CalendarBar",
            path: "Sources/CalendarBar",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .unsafeFlags(["-Osize", "-gnone"], .when(configuration: .release))
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-dead_strip"], .when(configuration: .release))
            ]
        ),
        .testTarget(
            name: "CalendarBarTests",
            dependencies: ["CalendarBar"],
            path: "Tests/CalendarBarTests"
        )
    ]
)
