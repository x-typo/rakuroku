import Foundation
import Observation

@MainActor @Observable
final class AnimeKaiStore {
    private(set) var resolvedPaths: [String: String]
    private(set) var overridePaths: [String: String]

    private let resolvedKey = "animekai_resolved_v1"
    private let overrideKey = "animekai_overrides_v1"

    init() {
        resolvedPaths = UserDefaults.standard.dictionary(forKey: resolvedKey) as? [String: String] ?? [:]
        overridePaths = UserDefaults.standard.dictionary(forKey: overrideKey) as? [String: String] ?? [:]
    }

    func getWatchPath(mediaId: Int) -> String? {
        let key = String(mediaId)
        return overridePaths[key] ?? resolvedPaths[key]
    }

    func hasOverride(mediaId: Int) -> Bool {
        overridePaths[String(mediaId)] != nil
    }

    func resolve(mediaId: Int, title: String) async -> AnimeKaiResolver.ResolveResult {
        let key = String(mediaId)

        if let override = overridePaths[key] {
            return AnimeKaiResolver.ResolveResult(watchPath: override, candidates: [])
        }

        if let cached = resolvedPaths[key] {
            return AnimeKaiResolver.ResolveResult(watchPath: cached, candidates: [])
        }

        let result = await AnimeKaiResolver.resolve(anilistId: mediaId, title: title)

        if let path = result.watchPath {
            resolvedPaths[key] = path
            UserDefaults.standard.set(resolvedPaths, forKey: resolvedKey)
        }

        return result
    }

    func setOverride(mediaId: Int, watchPath: String) {
        guard let normalized = AnimeKaiResolver.normalizeWatchPathInput(watchPath) else { return }
        overridePaths[String(mediaId)] = normalized
        UserDefaults.standard.set(overridePaths, forKey: overrideKey)
    }

    func clearOverride(mediaId: Int) {
        overridePaths.removeValue(forKey: String(mediaId))
        UserDefaults.standard.set(overridePaths, forKey: overrideKey)
    }
}
