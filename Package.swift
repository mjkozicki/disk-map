// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DiskMap",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DiskMap", targets: ["DiskMap"]),
        .executable(name: "disk-map-check", targets: ["DiskMapCheck"])
    ],
    targets: [
        .target(name: "DiskMapCore"),
        .executableTarget(name: "DiskMap", dependencies: ["DiskMapCore"]),
        .executableTarget(name: "DiskMapCheck", dependencies: ["DiskMapCore"])
    ]
)
