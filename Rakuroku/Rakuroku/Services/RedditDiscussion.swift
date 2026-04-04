import Foundation

enum RedditDiscussion {

    private static let episodeRegex = try? NSRegularExpression(
        pattern: #"-\s*Episode\s+(\d+)\s+discussion(?:\s*-\s*FINAL)?\s*$"#,
        options: .caseInsensitive
    )

    static func findUrl(anilistId: Int, episode: Int, airingAt: Int) async -> URL? {
        let query = "author:AutoLovepon anilist.co/anime/\(anilistId)"
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchURL = URL(string: "https://www.reddit.com/r/anime/search.json?restrict_sr=1&sort=new&limit=25&q=\(encoded)") else {
            return nil
        }

        var request = URLRequest(url: searchURL)
        request.setValue("rakuroku/1.0 (reddit-discussion-linker)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return nil
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let listing = json["data"] as? [String: Any],
              let children = listing["children"] as? [[String: Any]] else {
            return nil
        }

        let expectedNeedle = "anilist.co/anime/\(anilistId)"

        struct Candidate {
            let permalink: String
            let parsedEpisode: Int?
            let createdUtc: Double
        }

        let candidates: [Candidate] = children.compactMap { child in
            guard let post = child["data"] as? [String: Any],
                  let author = post["author"] as? String, author == "AutoLovepon",
                  let subreddit = post["subreddit"] as? String, subreddit == "anime",
                  let title = post["title"] as? String,
                  let permalink = post["permalink"] as? String else { return nil }

            if let selftext = post["selftext"] as? String, !selftext.contains(expectedNeedle) {
                return nil
            }

            let createdUtc = post["created_utc"] as? Double ?? 0
            return Candidate(
                permalink: permalink,
                parsedEpisode: parseEpisode(from: title),
                createdUtc: createdUtc
            )
        }.sorted { $0.createdUtc > $1.createdUtc }

        // Prefer exact episode match
        if let exact = candidates.first(where: { $0.parsedEpisode == episode }) {
            return URL(string: "https://www.reddit.com\(exact.permalink)")
        }

        // Fall back to closest by airing time
        let airingUtc = Double(airingAt)
        let earlyWindow: Double = 12 * 3600
        let lateWindow: Double = 3 * 86400

        let timed = candidates
            .filter { $0.createdUtc > 0 && $0.createdUtc >= airingUtc - earlyWindow && $0.createdUtc <= airingUtc + lateWindow }
            .sorted { abs($0.createdUtc - airingUtc) < abs($1.createdUtc - airingUtc) }

        if let best = timed.first {
            return URL(string: "https://www.reddit.com\(best.permalink)")
        }

        return nil
    }

    private static func parseEpisode(from title: String) -> Int? {
        guard let regex = episodeRegex,
              let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
              let range = Range(match.range(at: 1), in: title) else {
            return nil
        }
        return Int(title[range])
    }
}
