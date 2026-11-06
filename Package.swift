// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Curtain",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "curtaind", targets: ["curtaind"]),
        .executable(name: "curtainctl", targets: ["curtainctl"]),
        .library(name: "CurtainKit", targets: ["CurtainKit"]),
    ],
    targets: [
        .target(name: "CurtainKit"),
        .executableTarget(name: "curtaind", dependencies: ["CurtainKit"]),
        .executableTarget(name: "curtainctl", dependencies: ["CurtainKit"]),
    ],
    swiftLanguageVersions: [.v5]
)
