import Foundation

nonisolated enum AnimeKaiResolver {

    private static let baseURL = "https://animekai.to"
    private static let userAgent = "rakuroku/1.0 (animekai-resolver)"

    private static let watchPathRegexes: [NSRegularExpression] = [
        #"href\s*=\s*['"](/watch/[^'"?#\s]+)['"]"#,
        #"href\s*=\s*(/watch/[^'"?#\s>]+)"#,
        #"/watch/[a-z0-9][a-z0-9-]*"#,
    ].compactMap { try? NSRegularExpression(pattern: $0, options: .caseInsensitive) }

    private static let titleRegexes: [NSRegularExpression] = [
        #"<a[^>]*class\s*=\s*['"]title['"][^>]*>([^<]+)</a>"#,
        #"<a[^>]*class\s*=\s*['"]title['"][^>]*title\s*=\s*['"]([^'"]+)['"]"#,
    ].compactMap { try? NSRegularExpression(pattern: $0, options: .caseInsensitive) }

    // MARK: - Types

    struct Candidate: Identifiable, Sendable {
        var id: String { watchPath }
        let watchPath: String
        let title: String?
    }

    struct ResolveResult: Sendable {
        let watchPath: String?
        let candidates: [Candidate]
    }

    // MARK: - URL Builders

    static func buildEpisodeURL(watchPath: String, episode: Int) -> URL? {
        let clean = watchPath
            .replacingOccurrences(of: #"#ep=\d+"#, with: "", options: .regularExpression)
        let path = clean.hasPrefix("/watch/") ? clean : "/watch/\(clean)"
        return URL(string: "\(baseURL)\(path)#ep=\(episode)")
    }

    static func buildSearchURL(title: String) -> URL? {
        var components = URLComponents(string: "\(baseURL)/browser")
        components?.queryItems = [URLQueryItem(name: "keyword", value: title)]
        return components?.url
    }

    // MARK: - Input Normalization

    static func normalizeWatchPathInput(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Full URL: https://animekai.to/watch/slug...
        if trimmed.lowercased().hasPrefix("https://animekai.to/watch/") || trimmed.lowercased().hasPrefix("http://animekai.to/watch/") {
            if let url = URL(string: trimmed), let path = extractWatchPathFromURL(url) {
                return path
            }
        }

        // Path: /watch/slug
        if trimmed.hasPrefix("/watch/") && trimmed.count > 7 {
            let clean = trimmed.components(separatedBy: "#").first ?? trimmed
            return clean.components(separatedBy: "?").first ?? clean
        }

        // Embedded path: contains /watch/slug somewhere
        if let range = trimmed.range(of: #"/watch/[a-zA-Z0-9][a-zA-Z0-9-]*"#, options: .regularExpression) {
            return String(trimmed[range])
        }

        // Bare slug: alphanumeric-with-hyphens
        if trimmed.range(of: #"^[a-zA-Z0-9][a-zA-Z0-9-]*$"#, options: .regularExpression) != nil {
            return "/watch/\(trimmed)"
        }

        return nil
    }

    // MARK: - Resolution

    static func resolve(anilistId: Int, title: String) async -> ResolveResult {
        let keyword = title.trimmingCharacters(in: .whitespaces)
        guard !keyword.isEmpty, let searchURL = buildSearchURL(title: keyword) else {
            return ResolveResult(watchPath: nil, candidates: [])
        }

        guard let searchHTML = await fetchText(url: searchURL, timeout: 15) else {
            return ResolveResult(watchPath: nil, candidates: [])
        }

        let normalized = normalizeSearchHtml(searchHTML)
        let candidates = extractCandidates(from: normalized)

        guard !candidates.isEmpty else {
            return ResolveResult(watchPath: nil, candidates: [])
        }

        let topCandidates = Array(candidates.prefix(10))

        for candidate in topCandidates {
            guard let pageURL = URL(string: "\(baseURL)\(candidate.watchPath)") else { continue }
            guard let pageHtml = await fetchText(url: pageURL, timeout: 8) else { continue }

            if pageMentionsAniListId(pageHtml, anilistId: anilistId) {
                return ResolveResult(watchPath: candidate.watchPath, candidates: candidates)
            }
        }

        return ResolveResult(watchPath: nil, candidates: candidates)
    }

    private static func fetchText(url: URL, timeout: TimeInterval) async -> String? {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - HTML Parsing (Private)

    private static func normalizeSearchHtml(_ html: String) -> String {
        html
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: #"\\u002[fF]"#, with: "/", options: .regularExpression)
    }

    private static func extractWatchPaths(from html: String) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []

        for regex in watchPathRegexes {
            let range = NSRange(html.startIndex..., in: html)
            for match in regex.matches(in: html, range: range) {
                let captureRange = match.numberOfRanges > 1 ? match.range(at: 1) : match.range
                let effectiveRange = captureRange.location != NSNotFound ? captureRange : match.range
                guard let swiftRange = Range(effectiveRange, in: html) else { continue }
                var path = String(html[swiftRange])
                if path.hasPrefix("watch/") { path = "/\(path)" }
                guard path.hasPrefix("/watch/"), !seen.contains(path) else { continue }
                seen.insert(path)
                ordered.append(path)
            }
        }

        return ordered
    }

    private static func extractCandidates(from html: String) -> [Candidate] {
        let watchPaths = extractWatchPaths(from: html)
        guard !watchPaths.isEmpty else { return [] }

        return watchPaths.map { path in
            var title: String?

            if let pathRange = html.range(of: path) {
                let windowStart = pathRange.lowerBound
                let windowEnd = html.index(windowStart, offsetBy: 900, limitedBy: html.endIndex) ?? html.endIndex
                let window = String(html[windowStart..<windowEnd])

                for regex in titleRegexes {
                    let nsRange = NSRange(window.startIndex..., in: window)
                    if let match = regex.firstMatch(in: window, range: nsRange),
                       let captureRange = Range(match.range(at: 1), in: window) {
                        let found = String(window[captureRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !found.isEmpty {
                            title = found
                            break
                        }
                    }
                }
            }

            return Candidate(watchPath: path, title: title)
        }
    }

    private static func pageMentionsAniListId(_ html: String, anilistId: Int) -> Bool {
        html.contains("anilist.co/anime/\(anilistId)")
    }

    private static func extractWatchPathFromURL(_ url: URL) -> String? {
        let path = url.path
        guard path.hasPrefix("/watch/"), path.count > 7 else { return nil }
        return path
    }
}
