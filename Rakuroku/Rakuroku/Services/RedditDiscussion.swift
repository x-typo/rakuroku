import Foundation

enum RedditDiscussion {

    private enum Request {
        static let rootURL = "https://www.reddit.com"
        static let browserSearchPath = "/r/anime/search/"
        static let jsonSearchPath = "/r/anime/search.json"
        static let author = "AutoLovepon"
        static let subreddit = "anime"
        static let userAgent = "rakuroku/1.0 (reddit-discussion-linker)"
        static let acceptJSON = "application/json"
        static let searchLimit = "25"
        static let restrictToSubreddit = "1"
        static let sortNewest = "new"

        static func aniListNeedle(anilistId: Int) -> String {
            "anilist.co/anime/\(anilistId)"
        }

        static func discussionQuery(anilistId: Int) -> String {
            "author:\(author) \(aniListNeedle(anilistId: anilistId))"
        }
    }

    private static let episodeRegex = try? NSRegularExpression(
        pattern: #"-\s*Episode\s+(\d+)\s+discussion(?:\s*-\s*FINAL)?\s*$"#,
        options: .caseInsensitive
    )

    static func searchUrl(anilistId: Int) -> URL? {
        var components = URLComponents(string: Request.rootURL + Request.browserSearchPath)
        components?.queryItems = searchQueryItems(anilistId: anilistId)
        return components?.url
    }

    static func findUrl(anilistId: Int, episode: Int, airingAt: Int) async -> URL? {
        var components = URLComponents(string: Request.rootURL + Request.jsonSearchPath)
        var queryItems = searchQueryItems(anilistId: anilistId)
        queryItems.append(URLQueryItem(name: "limit", value: Request.searchLimit))
        components?.queryItems = queryItems

        guard let searchURL = components?.url else {
            return nil
        }

        var request = URLRequest(url: searchURL)
        request.setValue(Request.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(Request.acceptJSON, forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return nil
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let listing = json["data"] as? [String: Any],
              let children = listing["children"] as? [[String: Any]] else {
            return nil
        }

        let expectedNeedle = Request.aniListNeedle(anilistId: anilistId)

        struct Candidate {
            let permalink: String
            let parsedEpisode: Int?
            let createdUtc: Double
        }

        let candidates: [Candidate] = children.compactMap { child in
            guard let post = child["data"] as? [String: Any],
                  let author = post["author"] as? String, author == Request.author,
                  let subreddit = post["subreddit"] as? String, subreddit == Request.subreddit,
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
            return URL(string: Request.rootURL + exact.permalink)
        }

        // Fall back to closest by airing time
        let airingUtc = Double(airingAt)
        let earlyWindow: Double = 12 * 3600
        let lateWindow: Double = 3 * 86400

        let timed = candidates
            .filter { $0.createdUtc > 0 && $0.createdUtc >= airingUtc - earlyWindow && $0.createdUtc <= airingUtc + lateWindow }
            .sorted { abs($0.createdUtc - airingUtc) < abs($1.createdUtc - airingUtc) }

        if let best = timed.first {
            return URL(string: Request.rootURL + best.permalink)
        }

        return nil
    }

    private static func searchQueryItems(anilistId: Int) -> [URLQueryItem] {
        [
            URLQueryItem(name: "q", value: Request.discussionQuery(anilistId: anilistId)),
            URLQueryItem(name: "restrict_sr", value: Request.restrictToSubreddit),
            URLQueryItem(name: "sort", value: Request.sortNewest),
        ]
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
