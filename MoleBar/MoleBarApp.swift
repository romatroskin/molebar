import SwiftUI
import Sparkle

@main
struct MoleBarApp: App {
    private let updaterController: SPUStandardUpdaterController

    init() {
        // Sparkle's SwiftUI-recommended setup. startingUpdater: true schedules
        // automatic checks per SUEnableAutomaticChecks in Info.plist.
        // Source: https://sparkle-project.org/documentation/programmatic-setup/
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var body: some Scene {
        MenuBarExtra("MoleBar", systemImage: "circle.dotted") {
            PopoverRootView(updater: updaterController.updater)
        }
        .menuBarExtraStyle(.window)
    }
}
