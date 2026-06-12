import SwiftUI
import AppKit

@main
struct MacPulseApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            RootView()
                .environmentObject(state)
        } label: {
            MenuBarLabel(state: state)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    @ObservedObject var state: AppState

    var body: some View {
        // Show live CPU/RAM/SSD readouts (Stats-app style: small label stacked over each value) when
        // any metric is enabled and we have data; otherwise fall back to the bare pulse glyph so the
        // menu bar item never disappears.
        if let snapshot = state.system,
           let image = MenuBarRenderer.image(metrics: state.menuBarMetrics(for: snapshot)) {
            Image(nsImage: image).renderingMode(.template)
        } else {
            Image(systemName: "waveform.path.ecg")
        }
    }
}
