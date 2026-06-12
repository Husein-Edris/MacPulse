import SwiftUI

struct GitHubView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "GitHub · @\(state.githubUser)")
                Spacer()
                if state.githubLoading {
                    ProgressView().controlSize(.mini)
                }
            }

            if let error = state.githubError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            if let gh = state.github {
                Group {
                    HStack(spacing: 8) {
                        StatTile(value: "\(gh.totalContributionsYear)", label: "contributions", accent: .green)
                        StatTile(value: "\(gh.streakDays)d", label: "streak", accent: gh.streakDays > 0 ? .orange : .primary)
                    }
                    HStack(spacing: 8) {
                        StatTile(value: "\(gh.publicRepos)", label: "public repos")
                        StatTile(value: "\(gh.followers)", label: "followers")
                    }

                    HStack(spacing: 6) {
                        Image(systemName: gh.activeToday ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(gh.activeToday ? .green : .secondary)
                            .font(.caption)
                        Text(gh.activeToday ? "Contributed today" : "No contributions yet today")
                            .font(.caption)
                        Spacer()
                        Text("\(gh.activeDaysLast7)/7 days active this week")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                }

                Divider()

                SectionHeader(title: "Recent activity")
                if gh.events.isEmpty {
                    Text("No recent public activity")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                ForEach(gh.events) { event in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 4))
                            .foregroundColor(.accentColor)
                            .padding(.top, 5)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(event.message)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            HStack {
                                Text(event.repo)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                if let date = event.date {
                                    Text("· \(Fmt.ago(date))")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }

                Group {
                    HStack(spacing: 6) {
                        Image(systemName: gh.authenticated ? "lock.fill" : "globe")
                            .foregroundColor(gh.authenticated ? .green : .secondary)
                        Text(gh.authenticated
                             ? "Authenticated via gh • \(gh.privateRepos ?? 0) private repos"
                             : "Public only")
                            .font(.caption2).foregroundColor(.secondary)
                    }

                    if !gh.recentCommits.isEmpty {
                        SectionHeader(title: "Recent commits")
                        ForEach(gh.recentCommits) { c in
                            Button { Opener.open(c.url) } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: c.isPrivate ? "lock.fill" : "globe")
                                        .font(.caption2)
                                        .foregroundColor(c.isPrivate ? .orange : .secondary)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(c.message).font(.caption).lineLimit(1)
                                        Text(c.repo).font(.caption2).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if let d = c.date { Text(Fmt.ago(d)).font(.caption2).foregroundColor(.secondary) }
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 1)
                        }
                    }
                }

                Divider()

                HStack {
                    Text("Fetched \(Fmt.ago(gh.fetchedAt))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Open profile") {
                        Opener.open("https://github.com/\(state.githubUser)")
                    }
                    .font(.caption)
                }
            } else if !state.githubLoading {
                VStack(spacing: 8) {
                    Text("No GitHub data yet.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Fetch now") { state.refreshGitHub(force: true) }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            }
        }
        .padding(12)
    }
}
