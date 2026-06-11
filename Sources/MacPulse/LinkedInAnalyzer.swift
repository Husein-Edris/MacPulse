import Foundation

/// LinkedIn offers no public API for personal profiles, and scraping violates
/// its terms of service. So MacPulse analyzes profile data you enter once —
/// everything stays on this Mac (UserDefaults), nothing is sent anywhere.
struct LinkedInProfile: Codable, Equatable {
    var profileURL: String = ""
    var headline: String = ""
    var about: String = ""
    var hasPhoto: Bool = false
    var hasBanner: Bool = false
    var hasCustomURL: Bool = false
    var connections: Int = 0
    var skillsCount: Int = 0
    var experienceCount: Int = 0
    var educationCount: Int = 0
    var featuredCount: Int = 0
    var recommendationsCount: Int = 0
    var postsPerMonth: Int = 0

    var isEmpty: Bool { self == LinkedInProfile() }
}

struct LinkedInSectionScore: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let points: Int
    let maxPoints: Int
    let tip: String?
}

struct LinkedInAnalysis: Equatable {
    let totalPoints: Int
    let maxPoints: Int
    let grade: String
    let sections: [LinkedInSectionScore]

    var percent: Double { maxPoints == 0 ? 0 : Double(totalPoints) / Double(maxPoints) * 100 }
    var topTips: [String] {
        sections
            .filter { $0.tip != nil }
            .sorted { ($0.maxPoints - $0.points) > ($1.maxPoints - $1.points) }
            .compactMap { $0.tip }
    }
}

enum LinkedInAnalyzer {
    static func analyze(_ p: LinkedInProfile) -> LinkedInAnalysis {
        var sections: [LinkedInSectionScore] = []

        func score(_ name: String, _ points: Int, of max: Int, tip: String?) {
            sections.append(LinkedInSectionScore(
                name: name,
                points: points,
                maxPoints: max,
                tip: points >= max ? nil : tip
            ))
        }

        score("Profile photo", p.hasPhoto ? 10 : 0, of: 10,
              tip: "Add a professional photo — profiles with one get up to 21× more views.")
        score("Banner image", p.hasBanner ? 5 : 0, of: 5,
              tip: "Add a custom banner. The default gray strip is wasted brand space.")
        score("Custom URL", p.hasCustomURL ? 5 : 0, of: 5,
              tip: "Claim a custom linkedin.com/in/your-name URL in profile settings.")

        let headlinePoints: Int
        let headlineTip: String?
        let headline = p.headline.trimmingCharacters(in: .whitespacesAndNewlines)
        if headline.isEmpty {
            headlinePoints = 0
            headlineTip = "Write a headline: role + specialty + value (you have 220 characters)."
        } else if headline.count < 30 {
            headlinePoints = 5
            headlineTip = "Expand the headline beyond a bare job title — add specialty and value."
        } else {
            headlinePoints = 10
            headlineTip = nil
        }
        score("Headline", headlinePoints, of: 10, tip: headlineTip)

        let about = p.about.trimmingCharacters(in: .whitespacesAndNewlines)
        var aboutPoints = 0
        var aboutTip: String? = "Write an About section: story, skills, and measurable results."
        if about.count >= 500 {
            aboutPoints = 15
            aboutTip = nil
        } else if about.count >= 200 {
            aboutPoints = 10
            aboutTip = "Grow the About section toward 500+ characters with concrete outcomes."
        } else if !about.isEmpty {
            aboutPoints = 5
            aboutTip = "The About section is very short — aim for 3–5 paragraphs."
        }
        if about.rangeOfCharacter(from: .decimalDigits) != nil && !about.isEmpty {
            aboutPoints = min(20, aboutPoints + 5) // quantified achievements
        } else if aboutPoints >= 15 {
            aboutTip = "Add numbers — quantified results (%, €, users) make the About section credible."
        }
        score("About", aboutPoints, of: 20, tip: aboutTip)

        let expPoints = p.experienceCount >= 2 ? 10 : (p.experienceCount == 1 ? 6 : 0)
        score("Experience", expPoints, of: 10,
              tip: "List at least two roles with bullet-point achievements per role.")

        score("Education", p.educationCount > 0 ? 5 : 0, of: 5,
              tip: "Add education or certifications — they feed search filters.")

        let skillPoints = p.skillsCount >= 15 ? 10 : (p.skillsCount > 0 ? 5 : 0)
        score("Skills", skillPoints, of: 10,
              tip: "Add skills up to 15+ — recruiters filter searches by them.")

        let connPoints: Int
        if p.connections >= 500 { connPoints = 10 }
        else if p.connections >= 50 { connPoints = 6 }
        else { connPoints = p.connections > 0 ? 2 : 0 }
        score("Network", connPoints, of: 10,
              tip: "Grow toward 500+ connections — it unlocks the “500+” badge and reach.")

        score("Featured", p.featuredCount > 0 ? 5 : 0, of: 5,
              tip: "Pin posts, projects, or links in the Featured section.")

        let recPoints = p.recommendationsCount >= 2 ? 5 : (p.recommendationsCount == 1 ? 3 : 0)
        score("Recommendations", recPoints, of: 5,
              tip: "Ask two colleagues or clients for written recommendations.")

        let postPoints = p.postsPerMonth >= 2 ? 5 : (p.postsPerMonth == 1 ? 3 : 0)
        score("Activity", postPoints, of: 5,
              tip: "Post or comment at least twice a month to stay visible in feeds.")

        let total = sections.reduce(0) { $0 + $1.points }
        let max = sections.reduce(0) { $0 + $1.maxPoints }
        let pct = Double(total) / Double(max) * 100

        let grade: String
        switch pct {
        case 90...: grade = "A"
        case 80..<90: grade = "B"
        case 70..<80: grade = "C"
        case 55..<70: grade = "D"
        default: grade = "F"
        }

        return LinkedInAnalysis(totalPoints: total, maxPoints: max, grade: grade, sections: sections)
    }
}
