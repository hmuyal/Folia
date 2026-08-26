// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MDApp",
    platforms: [.macOS(.v14)],
    targets: [
        // The app executable. Resources (web bundle, fonts) are NOT declared here:
        // build.sh copies them straight into MDApp.app/Contents/Resources so the app
        // uses Bundle.main directly rather than a SwiftPM resource bundle.
        .executableTarget(
            name: "MDApp",
            path: "Sources/MDApp",
            // Info.plist and AppIcon.png are build inputs for build.sh, not bundled
            // SwiftPM resources.
            exclude: ["Resources/Info.plist", "Resources/AppIcon.png"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
