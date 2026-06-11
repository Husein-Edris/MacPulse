import SwiftUI

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
        if state.showCPUInMenuBar, let snapshot = state.system {
            Image(systemName: "waveform.path.ecg")
            Text(String(format: "%.0f%%", snapshot.cpuPercent))
        } else {
            Image(systemName: "waveform.path.ecg")
        }
    }
}
