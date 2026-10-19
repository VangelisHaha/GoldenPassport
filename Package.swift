// swift-tools-version:5.8
import PackageDescription

let package = Package(
    name: "GoldenPassport",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "GoldenPassportCore"),
        .executableTarget(name: "GoldenPassport", dependencies: ["GoldenPassportCore"]),
        .testTarget(name: "GoldenPassportCoreTests", dependencies: ["GoldenPassportCore"]),
    ],
    swiftLanguageVersions: [.v5]
)
