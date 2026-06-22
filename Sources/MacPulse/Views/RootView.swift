import SwiftUI

struct RootView: View {
    @EnvironmentObject var state: AppState
    @State private var tab: Tab = .overview
    @State private var showSettings = false

    enum Tab: String, CaseIterable {
        case overview = "Overview"
        case github = "GitHub"
        case backups = "Backups"
        case claude = "Claude"
        case tips = "Tips"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if !showSettings {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
            Divider()
            ScrollView {
                if showSettings {
                    SettingsView()
                } else {
                    switch tab {
                    case .overview: OverviewView()
                    case .github: GitHubView()
                    case .backups: BackupView()
                    case .claude: ClaudeUsageView()
                    case .tips: TipsView()
                    }
                }
            }
            .frame(height: 400)
            Divider()
            footer
        }
        .frame(width: 380)
        .onAppear { state.popoverDidOpen() }
        .onDisappear { state.popoverDidClose() }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "waveform.path.ecg")
                .foregroundColor(.accentColor)
            Text("MacPulse")
                .font(.headline)
            Spacer()
            if let snapshot = state.system {
                Text("updated \(Fmt.ago(snapshot.date))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack {
            Button {
                state.refreshAll()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh everything now")

            Spacer()

            Button {
                showSettings.toggle()
            } label: {
                Image(systemName: showSettings ? "chevron.backward.circle" : "gearshape")
            }
            .buttonStyle(.borderless)
            .help(showSettings ? "Back" : "Settings")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("Quit MacPulse")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
