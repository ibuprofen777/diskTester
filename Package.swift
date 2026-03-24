// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DiskTester",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "DiskTester",
            targets: ["DiskTesterApp"]
        )
    ],
    targets: [
        .executableTarget(
            name: "DiskTesterApp"
        )
    ]
)
