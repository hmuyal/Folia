import Combine
import Sparkle

/// Wraps Sparkle's updater controller so `MenuCommands` can trigger a manual
/// check and know whether one is already running — Sparkle's own recommended
/// shape for a SwiftUI "Check for Updates…" menu item.
final class UpdateChecker: ObservableObject {
    private let controller: SPUStandardUpdaterController
    @Published private(set) var canCheckForUpdates = false

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
