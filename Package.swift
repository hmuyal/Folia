// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Folia",
    platforms: [.macOS(.v14)],
    dependencies: [
        // In-app "Check for Updates…", signed and served from appcast.xml.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.6"),
    ],
    targets: [
        // The app executable. Resources (web bundle, fonts) are NOT declared here:
        // build.sh copies them straight into Folia.app/Contents/Resources so the app
        // uses Bundle.main directly rather than a SwiftPM resource bundle.
        .executableTarget(
            name: "Folia",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Folia",
            // Info.plist and AppIcon.png are build inputs for build.sh, not bundled
            // SwiftPM resources.
            exclude: ["Resources/Info.plist", "Resources/AppIcon.png"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
