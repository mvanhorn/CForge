import Foundation

// MARK: - CFContest (top-level domain model)
// Previously nested inside ContestListView — lifted to top-level so ContestService,
// ContestRepository, and ContestViewModel can all reference it without qualification.

struct CFContest: Identifiable, Codable {
    let id: Int
    let name: String
    let type: String
    let phase: String
    let durationSeconds: Int
    let startTimeSeconds: Int?

    var registrationUrl: URL? {
        URL(string: "https://codeforces.com/contestRegistration/\(id)")
    }

    var contestUrl: URL? {
        URL(string: "https://codeforces.com/contest/\(id)")
    }

    var isRated: Bool {
        type.lowercased().contains("rated") || name.lowercased().contains("rated")
    }

    var startTime: Date {
        Date(timeIntervalSince1970: TimeInterval(startTimeSeconds ?? 0))
    }

    var duration: String {
        let hours = durationSeconds / 3600
        let minutes = (durationSeconds % 3600) / 60
        return "\(hours)h \(minutes)m"
    }

    var timeUntilStart: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: Date(), to: startTime) ?? ""
    }
}

// MARK: - ContestResponse

struct ContestResponse: Codable {
    let status: String
    let result: [CFContest]?
    let comment: String?
}
