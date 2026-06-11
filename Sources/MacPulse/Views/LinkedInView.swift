import SwiftUI

struct LinkedInView: View {
    @EnvironmentObject var state: AppState
    @State private var editing = false
    @State private var draft = LinkedInProfile()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if editing || state.profile.isEmpty {
                editorForm
            } else {
                analysisView
            }
        }
        .padding(12)
    }

    // MARK: - Analysis

    @ViewBuilder
    private var analysisView: some View {
        if let analysis = state.analysis {
            HStack(spacing: 16) {
                scoreRing(analysis)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Profile strength")
                        .font(.headline)
                    Text("\(analysis.totalPoints) of \(analysis.maxPoints) points")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack(spacing: 8) {
                        Button("Edit data") {
                            draft = state.profile
                            editing = true
                        }
                        .font(.caption)
                        if !state.profile.profileURL.isEmpty {
                            Button("Open profile") {
                                var url = state.profile.profileURL
                                if !url.hasPrefix("http") { url = "https://\(url)" }
                                Opener.open(url)
                            }
                            .font(.caption)
                        }
                    }
                }
                Spacer()
            }

            Divider()

            SectionHeader(title: "Sections")
            ForEach(analysis.sections) { section in
                HStack(spacing: 8) {
                    Text(section.name)
                        .font(.caption)
                        .frame(width: 110, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.primary.opacity(0.08))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(sectionColor(section))
                                .frame(width: max(2, geo.size.width * CGFloat(section.points) / CGFloat(max(section.maxPoints, 1))))
                        }
                    }
                    .frame(height: 5)
                    Text("\(section.points)/\(section.maxPoints)")
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
            }

            let tips = analysis.topTips
            if !tips.isEmpty {
                Divider()
                SectionHeader(title: "Biggest wins")
                ForEach(tips.prefix(4), id: \.self) { tip in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "lightbulb")
                            .font(.caption)
                            .foregroundColor(.yellow)
                        Text(tip)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Text("Analyzed locally — nothing is sent to LinkedIn or anywhere else.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.top, 4)
        }
    }

    private func scoreRing(_ analysis: LinkedInAnalysis) -> some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.1), lineWidth: 8)
            Circle()
                .trim(from: 0, to: CGFloat(analysis.percent / 100))
                .stroke(gradeColor(analysis.grade), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(analysis.grade)
                    .font(.title2.bold())
                Text("\(Int(analysis.percent))%")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 76, height: 76)
    }

    private func gradeColor(_ grade: String) -> Color {
        switch grade {
        case "A": return .green
        case "B": return .mint
        case "C": return .orange
        default: return .red
        }
    }

    private func sectionColor(_ section: LinkedInSectionScore) -> Color {
        section.points >= section.maxPoints ? .green
            : (section.points == 0 ? .red : .orange)
    }

    // MARK: - Editor

    private var editorForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                SectionHeader(title: "LinkedIn profile data")
                Text("LinkedIn has no public profile API, so enter your numbers once — they stay on this Mac and the analysis runs offline.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                TextField("Profile URL (linkedin.com/in/…)", text: $draft.profileURL)
                    .textFieldStyle(.roundedBorder)
                TextField("Headline", text: $draft.headline)
                    .textFieldStyle(.roundedBorder)

                Text("About section (paste it here)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextEditor(text: $draft.about)
                    .font(.caption)
                    .frame(height: 64)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(0.15)))
            }

            Group {
                Toggle("Professional photo", isOn: $draft.hasPhoto)
                Toggle("Custom banner image", isOn: $draft.hasBanner)
                Toggle("Custom profile URL", isOn: $draft.hasCustomURL)
            }

            Group {
                numberField("Connections", value: $draft.connections)
                numberField("Skills listed", value: $draft.skillsCount)
                numberField("Experience entries", value: $draft.experienceCount)
                numberField("Education entries", value: $draft.educationCount)
                numberField("Featured items", value: $draft.featuredCount)
                numberField("Recommendations", value: $draft.recommendationsCount)
                numberField("Posts per month", value: $draft.postsPerMonth)
            }

            HStack {
                Button("Save & analyze") {
                    state.profile = draft
                    editing = false
                }
                .keyboardShortcut(.defaultAction)
                if !state.profile.isEmpty {
                    Button("Cancel") { editing = false }
                }
            }
            .padding(.top, 4)
        }
        .toggleStyle(.checkbox)
        .font(.caption)
        .onAppear {
            if draft.isEmpty { draft = state.profile }
        }
    }

    private func numberField(_ label: String, value: Binding<Int>) -> some View {
        HStack {
            Text(label)
                .font(.caption)
            Spacer()
            TextField("0", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 64)
                .multilineTextAlignment(.trailing)
        }
    }
}
