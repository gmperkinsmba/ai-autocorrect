// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AIAutocorrect",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "AI Autocorrect", targets: ["AIAutocorrect"])],
    targets: [
        .target(name: "AIAutocorrectCore"),
        .executableTarget(name: "AIAutocorrect", dependencies: ["AIAutocorrectCore"]),
        .executableTarget(name: "AIAutocorrectChecks", dependencies: ["AIAutocorrectCore"])
    ]
)
