import Foundation

nonisolated enum AnikotoTVResolver {

    static let providerName = "AnikotoTV"

    private static let baseURL = "https://anikototv.to"
    private static let requestUserAgent = "rakuroku/1.0 (anikototv-link-resolver)"

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
        guard let path = normalizeWatchPathInput(watchPath) else { return nil }
        let episodeNumber = max(episode, 1)
        return URL(string: "\(baseURL)\(path)/ep-\(episodeNumber)")
    }

    static func homeURL() -> URL? {
        URL(string: baseURL)
    }

    // MARK: - Input Normalization

    static func normalizeWatchPathInput(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed),
           let host = url.host?.lowercased(),
           host == "anikototv.to" || host.hasSuffix(".anikototv.to") {
            return extractWatchPathFromURL(url)
        }

        if trimmed.hasPrefix("/watch/") {
            return normalizeWatchPath(trimmed)
        }

        if let range = trimmed.range(of: #"/watch/[a-zA-Z0-9][a-zA-Z0-9-]*(?:/ep-\d+)?"#, options: .regularExpression) {
            return normalizeWatchPath(String(trimmed[range]))
        }

        if trimmed.range(of: #"^[a-zA-Z0-9][a-zA-Z0-9-]*$"#, options: .regularExpression) != nil {
            return "/watch/\(trimmed.lowercased())"
        }

        return nil
    }

    // MARK: - Resolution

    static func resolve(anilistId _: Int, title: String) async -> ResolveResult {
        guard let searchURL = searchURL(title: title),
              let candidates = await searchCandidates(url: searchURL),
              !candidates.isEmpty else {
            return ResolveResult(watchPath: nil, candidates: [])
        }

        if let best = bestCandidate(for: title, candidates: candidates) {
            return ResolveResult(watchPath: best.watchPath, candidates: candidates)
        }

        return ResolveResult(watchPath: nil, candidates: candidates)
    }

    private static func searchURL(title: String) -> URL? {
        var components = URLComponents(string: baseURL + "/filter")
        components?.queryItems = [
            URLQueryItem(name: "keyword", value: title),
        ]
        return components?.url
    }

    private static func searchCandidates(url: URL) async -> [Candidate]? {
        var request = URLRequest(url: url)
        request.setValue(requestUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8) else {
            return nil
        }

        return parseCandidates(from: html)
    }

    private static func parseCandidates(from html: String) -> [Candidate] {
        let pattern = #"<a\s+href=\"([^\"]*/watch/[^\"]+)\"[^>]*>\s*<img[^>]*\salt=\"([^\"]*)\""#
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }

        var candidates: [Candidate] = []
        var seen = Set<String>()
        let range = NSRange(html.startIndex..., in: html)
        for match in regex.matches(in: html, range: range) {
            guard let hrefRange = Range(match.range(at: 1), in: html),
                  let titleRange = Range(match.range(at: 2), in: html),
                  let watchPath = normalizeWatchPathInput(String(html[hrefRange])),
                  !seen.contains(watchPath) else {
                continue
            }

            seen.insert(watchPath)
            let title = decodeHTMLEntities(String(html[titleRange]))
            candidates.append(Candidate(watchPath: watchPath, title: title.isEmpty ? nil : title))
        }

        return candidates
    }

    private static func bestCandidate(for title: String, candidates: [Candidate]) -> Candidate? {
        let scored = candidates
            .map { candidate in (candidate, score(candidate: candidate, title: title)) }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.watchPath.count < rhs.0.watchPath.count
                }
                return lhs.1 > rhs.1
            }

        guard let best = scored.first, best.1 >= 800 else {
            return nil
        }

        if scored.dropFirst().contains(where: { $0.1 == best.1 }) {
            return nil
        }

        return best.0
    }

    private static func score(candidate: Candidate, title: String) -> Int {
        let querySlug = slugify(title)
        let queryComparable = comparableTitle(title)
        let candidateTitle = candidate.title ?? ""
        let candidateSlug = slugify(candidateTitle)
        let candidateComparable = comparableTitle(candidateTitle)
        let pathSlug = candidate.watchPath.replacingOccurrences(of: "/watch/", with: "")

        var score = 0
        if candidateComparable == queryComparable { score += 1000 }
        if candidateSlug == querySlug { score += 800 }
        if pathSlug == querySlug { score += 700 }
        if pathSlug.hasPrefix(querySlug + "-") { score += 100 }
        if candidateSlug.hasPrefix(querySlug + "-") { score += 50 }
        return score
    }

    private static func comparableTitle(_ title: String) -> String {
        slugify(title).replacingOccurrences(of: "-", with: " ")
    }

    private static func slugify(_ title: String) -> String {
        let latin = title.applyingTransform(.toLatin, reverse: false) ?? title
        let stripped = latin.applyingTransform(.stripCombiningMarks, reverse: false) ?? latin
        let lowercase = stripped.lowercased()

        var slug = ""
        var lastWasSeparator = false

        for scalar in lowercase.unicodeScalars {
            if (48...57).contains(scalar.value) || (97...122).contains(scalar.value) {
                slug.unicodeScalars.append(scalar)
                lastWasSeparator = false
            } else if !lastWasSeparator {
                slug.append("-")
                lastWasSeparator = true
            }
        }

        return slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func normalizeWatchPath(_ path: String) -> String? {
        let withoutFragment = path.components(separatedBy: "#").first ?? path
        let withoutQuery = withoutFragment.components(separatedBy: "?").first ?? withoutFragment
        let components = withoutQuery.split(separator: "/", omittingEmptySubsequences: true)

        guard components.count >= 2,
              components[0].lowercased() == "watch",
              components[1].range(of: #"^[a-zA-Z0-9][a-zA-Z0-9-]*$"#, options: .regularExpression) != nil else {
            return nil
        }

        return "/watch/\(components[1].lowercased())"
    }

    private static func extractWatchPathFromURL(_ url: URL) -> String? {
        normalizeWatchPath(url.path)
    }

    private static func decodeHTMLEntities(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}
