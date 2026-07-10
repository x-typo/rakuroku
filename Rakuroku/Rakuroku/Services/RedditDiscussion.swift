import Foundation

nonisolated enum RedditDiscussion {

    private enum Request {
        static let rootURL = "https://www.reddit.com"
        static let feedSearchPath = "/r/anime/search.rss"
        static let author = "AutoLovepon"
        static let feedAuthor = "/u/\(author)"
        static let subreddit = "anime"
        static let userAgent = "rakuroku/1.0 (reddit-discussion-linker)"
        static let acceptFeed = "application/atom+xml"
        static let searchLimit = "25"
        static let restrictToSubreddit = "1"
        static let sortNewest = "new"
        static let timeout: TimeInterval = 15

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

    struct Match: Sendable {
        let url: URL
        let episode: Int
    }

    @concurrent
    static func findMatch(anilistId: Int, maximumEpisode: Int) async -> Match? {
        guard maximumEpisode > 0 else { return nil }

        var components = URLComponents(string: Request.rootURL + Request.feedSearchPath)
        var queryItems = searchQueryItems(anilistId: anilistId)
        queryItems.append(URLQueryItem(name: "limit", value: Request.searchLimit))
        components?.queryItems = queryItems

        guard let searchURL = components?.url else {
            return nil
        }

        var request = URLRequest(url: searchURL, timeoutInterval: Request.timeout)
        request.setValue(Request.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(Request.acceptFeed, forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return nil
        }

        let expectedNeedle = Request.aniListNeedle(anilistId: anilistId)
        let feedParser = FeedParser()
        let parser = XMLParser(data: data)
        parser.delegate = feedParser
        guard parser.parse() else { return nil }

        struct Candidate {
            let url: URL
            let episode: Int
            let feedIndex: Int
        }

        let candidates: [Candidate] = feedParser.entries.enumerated().compactMap { index, entry in
            guard entry.author == Request.feedAuthor,
                  entry.subreddit == Request.subreddit,
                  entry.content.contains(expectedNeedle),
                  let episode = parseEpisode(from: entry.title),
                  let url = normalizedDiscussionURL(entry.url),
                  episode <= maximumEpisode else { return nil }

            return Candidate(
                url: url,
                episode: episode,
                feedIndex: index
            )
        }.sorted {
            if $0.episode != $1.episode {
                return $0.episode > $1.episode
            }
            return $0.feedIndex < $1.feedIndex
        }

        guard let best = candidates.first else { return nil }
        return Match(url: best.url, episode: best.episode)
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

    private static func normalizedDiscussionURL(_ url: URL) -> URL? {
        let allowedHosts = ["www.reddit.com", "reddit.com", "old.reddit.com"]
        guard url.scheme == "https",
              let host = url.host?.lowercased(),
              allowedHosts.contains(host),
              url.path.hasPrefix("/r/anime/comments/"),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        components.host = "www.reddit.com"
        return components.url
    }

    private final class FeedParser: NSObject, XMLParserDelegate {
        struct Entry {
            let title: String
            let url: URL
            let author: String
            let subreddit: String
            let content: String
        }

        private struct PendingEntry {
            var title = ""
            var firstURL: URL?
            var alternateURL: URL?
            var author = ""
            var subreddit = ""
            var content = ""
        }

        private(set) var entries: [Entry] = []
        private var pendingEntry: PendingEntry?
        private var text = ""

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            if elementName == "entry" {
                pendingEntry = PendingEntry()
            }

            guard pendingEntry != nil else { return }
            text = ""

            if elementName == "link",
               let href = attributeDict["href"],
               let url = URL(string: href) {
                if pendingEntry?.firstURL == nil {
                    pendingEntry?.firstURL = url
                }
                if attributeDict["rel"]?.lowercased() == "alternate"
                    || attributeDict["rel"] == nil,
                   pendingEntry?.alternateURL == nil {
                    pendingEntry?.alternateURL = url
                }
            } else if elementName == "category" {
                pendingEntry?.subreddit = attributeDict["term"] ?? ""
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard pendingEntry != nil else { return }
            text += string
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            guard var entry = pendingEntry else { return }

            switch elementName {
            case "title":
                entry.title = text
            case "name":
                entry.author = text
            case "content":
                entry.content = text
            case "entry":
                if let url = entry.alternateURL ?? entry.firstURL {
                    entries.append(Entry(
                        title: entry.title,
                        url: url,
                        author: entry.author,
                        subreddit: entry.subreddit,
                        content: entry.content
                    ))
                }
                pendingEntry = nil
                text = ""
                return
            default:
                break
            }

            pendingEntry = entry
            text = ""
        }
    }
}
