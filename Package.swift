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
            // Info.plist is a build input for build.sh, not a bundled resource.
            exclude: ["Resources/Info.plist"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Draws the app icon with CoreGraphics; build.sh pipes its output to iconutil.
        .executableTarget(
            name: "IconGen",
            path: "Sources/IconGen",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
