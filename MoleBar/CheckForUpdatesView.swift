import SwiftUI
import Sparkle

/// Observes Sparkle's `canCheckForUpdates` so the button auto-disables
/// while a check is in flight. Pattern from Sparkle's programmatic-setup docs,
/// adapted for Swift 6 strict concurrency: `@MainActor` is required because
/// `SPUUpdater.canCheckForUpdates` is main-actor-isolated, so the key-path
/// publisher subscription must originate on the main actor.
@MainActor
final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

struct CheckForUpdatesView: View {
    @ObservedObject private var viewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self.viewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates…", action: updater.checkForUpdates)
            .disabled(!viewModel.canCheckForUpdates)
    }
}
