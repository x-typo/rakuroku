import SwiftUI

enum Formatters {

    // MARK: - Status

    static func statusColor(_ status: MediaListStatus?) -> Color? {
        switch status {
        case .current: Theme.watching
        case .completed: Theme.completed
        case .dropped: Theme.dropped
        case .paused: Theme.warning
        case .planning: Theme.textSecondary
        case .repeating: Theme.watching
        case nil: nil
        }
    }

    static func statusLabel(_ status: MediaListStatus?, type: MediaType? = nil) -> String? {
        switch status {
        case .current: type == .manga ? "Reading" : "Watching"
        case .completed: "Completed"
        case .dropped: "Dropped"
        case .paused: "Paused"
        case .planning: "Planning"
        case .repeating: type == .manga ? "Rereading" : "Rewatching"
        case nil: nil
        }
    }

    // MARK: - Season

    static func seasonName(_ season: String) -> String {
        let map = ["WINTER": "Winter", "SPRING": "Spring", "SUMMER": "Summer", "FALL": "Fall"]
        return map[season] ?? season.prefix(1).uppercased() + season.dropFirst().lowercased()
    }

    static func seasonText(_ season: String?, year: Int?) -> String {
        guard let season, let year else { return "" }
        return "\(seasonName(season)) \(year)"
    }

    static func currentSeason() -> (season: Season, year: Int) {
        let month = Calendar.current.component(.month, from: Date())
        let year = Calendar.current.component(.year, from: Date())
        let season: Season = switch month {
        case 1...3: .winter
        case 4...6: .spring
        case 7...9: .summer
        default: .fall
        }
        return (season, year)
    }

    static func nextSeason(after current: (season: Season, year: Int)) -> (season: Season, year: Int) {
        let order: [Season] = [.winter, .spring, .summer, .fall]
        guard let idx = order.firstIndex(of: current.season) else { return (order[0], current.year + 1) }
        let nextIdx = (idx + 1) % 4
        return (order[nextIdx], nextIdx == 0 ? current.year + 1 : current.year)
    }

    // MARK: - Format

    static func formatType(_ format: String?) -> String {
        guard let format else { return "" }
        let map: [String: String] = [
            "TV": "TV", "TV_SHORT": "TV Short", "MOVIE": "Movie",
            "SPECIAL": "Special", "OVA": "OVA", "ONA": "ONA",
            "MUSIC": "Music", "MANGA": "Manga", "NOVEL": "Light Novel",
            "ONE_SHOT": "One Shot",
        ]
        return map[format] ?? format
    }

    static func formatStatus(_ status: String?) -> String {
        guard let status else { return "" }
        let map: [String: String] = [
            "FINISHED": "Finished", "RELEASING": "Releasing",
            "NOT_YET_RELEASED": "Not Yet Released", "CANCELLED": "Cancelled",
            "HIATUS": "Hiatus",
        ]
        return map[status] ?? status
    }

    static func formatSource(_ source: String?) -> String {
        guard let source else { return "Unknown" }
        let map: [String: String] = [
            "ORIGINAL": "Original", "MANGA": "Manga", "LIGHT_NOVEL": "Light Novel",
            "VISUAL_NOVEL": "Visual Novel", "VIDEO_GAME": "Video Game", "OTHER": "Other",
            "NOVEL": "Novel", "ANIME": "Anime", "WEB_NOVEL": "Web Novel",
            "DOUJINSHI": "Doujinshi", "LIVE_ACTION": "Live Action", "GAME": "Game",
            "COMIC": "Comic", "MULTIMEDIA_PROJECT": "Multimedia Project",
            "PICTURE_BOOK": "Picture Book",
        ]
        return map[source] ?? source
    }

    static func formatRelationType(_ type: MediaRelationType) -> String {
        switch type {
        case .adaptation: "Adaptation"
        case .prequel: "Prequel"
        case .sequel: "Sequel"
        case .parent: "Parent"
        case .sideStory: "Side Story"
        case .character: "Character"
        case .summary: "Summary"
        case .alternative: "Alternative"
        case .spinOff: "Spin Off"
        case .other: "Other"
        case .source: "Source"
        case .compilation: "Compilation"
        case .contains: "Contains"
        }
    }

    // MARK: - Date

    static func formatFuzzyDate(_ date: FuzzyDate?) -> String {
        guard let date, let year = date.year else { return "TBA" }
        if let month = date.month, (1...12).contains(month) {
            let names = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
            let dayStr = date.day.map { " \($0)," } ?? ""
            return "\(names[month - 1])\(dayStr) \(year)"
        }
        return "\(year)"
    }

    static func formatYear(_ startDate: FuzzyDate?) -> String {
        guard let year = startDate?.year else { return "" }
        return "\(year)"
    }

    // MARK: - Time

    static func timeAgo(_ timestamp: Int) -> String {
        let now = Date().timeIntervalSince1970
        let diff = now - Double(timestamp)

        if diff < 60 { return "Just now" }
        if diff < 3600 { return "\(Int(diff / 60))m ago" }
        if diff < 86400 { return "\(Int(diff / 3600))h ago" }
        if diff < 604800 { return "\(Int(diff / 86400))d ago" }
        return "\(Int(diff / 604800))w ago"
    }

    private static let airingTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    static func airingTime(_ airingAt: Int) -> String {
        let date = Date(timeIntervalSince1970: Double(airingAt))
        return airingTimeFormatter.string(from: date)
    }

    static func nextAiring(_ airingAt: Int, episode: Int? = nil) -> String {
        let now = Date().timeIntervalSince1970
        let diff = Double(airingAt) - now
        guard diff > 0 else { return "" }

        let timeText: String
        if diff < 3600 {
            timeText = "\(Int(diff / 60))m"
        } else if diff < 86400 {
            timeText = "\(Int(diff / 3600))h"
        } else {
            let days = Int(diff / 86400)
            let hours = Int(diff.truncatingRemainder(dividingBy: 86400) / 3600)
            timeText = "\(days)d \(hours)h"
        }

        if let episode {
            return "Episode \(episode) airing in \(timeText)"
        }
        return timeText
    }

    // MARK: - HTML

    static func stripHtml(_ text: String) -> String {
        text
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Studio Helpers

    static func mainStudioName(_ studios: StudioConnection?) -> String? {
        guard let edges = studios?.edges, !edges.isEmpty else { return nil }
        let main = edges.first(where: \.isMain)
        return main?.node.name ?? edges.first?.node.name
    }

    static func mainStudio(_ studios: StudioConnection?) -> Studio? {
        guard let edges = studios?.edges, !edges.isEmpty else { return nil }
        let main = edges.first(where: \.isMain)
        return main?.node ?? edges.first?.node
    }
}
