import SwiftUI
import Sparkle

struct PopoverRootView: View {
    let updater: SPUUpdater

    private var versionString: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        return "MoleBar \(short) — nothing here yet"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(versionString)
                .font(.headline)
                .padding(.horizontal)
                .padding(.top)
            Divider()
            CheckForUpdatesView(updater: updater)
                .buttonStyle(.borderless)
                .padding(.horizontal)
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("q")
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .frame(width: 240)
    }
}
