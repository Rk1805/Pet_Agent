// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ShinobiPets",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ShinobiPets",
            path: "Sources/ShinobiPets",
            linkerSettings: [
                .linkedFramework("Carbon"),
                // Apple's on-device model needs macOS 26; weak-link so the app still launches on older systems.
                .unsafeFlags(["-Xlinker", "-weak_framework", "-Xlinker", "FoundationModels"]),
            ]
        )
    ]
)
