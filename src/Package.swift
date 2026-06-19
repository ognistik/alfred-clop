// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AlfredClop",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "alfred-clop", targets: ["AlfredClop"])
    ],
    targets: [
        .executableTarget(
            name: "AlfredClop",
            path: "Sources/AlfredClop",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "AlfredClopTests",
            dependencies: ["AlfredClop"],
            path: "Tests/AlfredClopTests"
        )
    ]
)
