// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "session-mesh",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "SessionMeshCore", targets: ["SessionMeshCore"]),
        .executable(name: "session-mesh", targets: ["session-mesh"])
    ],
    targets: [
        .target(name: "SessionMeshCore"),
        .executableTarget(
            name: "session-mesh",
            dependencies: ["SessionMeshCore"]
        ),
        .testTarget(
            name: "SessionMeshCoreTests",
            dependencies: ["SessionMeshCore"]
        )
    ],
    swiftLanguageModes: [.v5]
)
