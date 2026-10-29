// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CleanMac",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "CleanMacCore"),
        .executableTarget(
            name: "CleanMac",
            dependencies: ["CleanMacCore"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "CleanMacCoreTests", dependencies: ["CleanMacCore"]),
    ]
)
