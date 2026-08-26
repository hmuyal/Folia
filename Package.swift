// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Folia",
    platforms: [.macOS(.v14)],
    targets: [
        // The app executable. Resources (web bundle, fonts) are NOT declared here:
        // build.sh copies them straight into Folia.app/Contents/Resources so the app
        // uses Bundle.main directly rather than a SwiftPM resource bundle.
        .executableTarget(
            name: "Folia",
            path: "Sources/Folia",
            // Info.plist and AppIcon.png are build inputs for build.sh, not bundled
            // SwiftPM resources.
            exclude: ["Resources/Info.plist", "Resources/AppIcon.png"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
