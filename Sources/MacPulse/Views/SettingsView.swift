import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var usernameDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Group {
                SectionHeader(title: "GitHub")
                HStack {
                    TextField("GitHub username", text: $usernameDraft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(applyUsername)
                    Button("Apply", action: applyUsername)
                        .disabled(usernameDraft.trimmingCharacters(in: .whitespaces).isEmpty
                                  || usernameDraft == state.githubUser)
                }
                Text("Only public data is fetched — no token, nothing stored except a local cache.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Divider()

            Group {
                SectionHeader(title: "Menu bar")
                Text("Show live readouts in the menu bar.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Toggle("CPU %", isOn: $state.menuBarCPU)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                Toggle("Memory %", isOn: $state.menuBarRAM)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                Toggle("Disk %", isOn: $state.menuBarDisk)
                    .toggleStyle(.checkbox)
                    .font(.caption)
            }

            Divider()

            Group {
                SectionHeader(title: "Behavior")
                Toggle("Launch at login", isOn: $state.launchAtLogin)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                if let error = state.loginItemError {
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()

            SectionHeader(title: "About")
            VStack(alignment: .leading, spacing: 4) {
                Text("MacPulse 1.0.0")
                    .font(.caption.weight(.semibold))
                Text("System and GitHub dashboard for the menu bar. Native Swift, no third-party dependencies, all analysis on-device.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Source on GitHub") {
                    Opener.open("https://github.com/Husein-Edris/MacPulse")
                }
                .font(.caption)
            }
        }
        .padding(12)
        .onAppear { usernameDraft = state.githubUser }
    }

    private func applyUsername() {
        let trimmed = usernameDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != state.githubUser else { return }
        state.githubUser = trimmed
        state.refreshGitHub(force: true)
    }
}
