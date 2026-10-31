// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ShinobiPets",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ShinobiPets",
            path: "Sources/ShinobiPets",
            linkerSettings: [.linkedFramework("Carbon")]
        )
    ]
)
