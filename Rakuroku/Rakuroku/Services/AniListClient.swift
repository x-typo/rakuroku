import Foundation

enum AniListError: LocalizedError {
    case rateLimited
    case apiError(Int)
    case graphQLError(String)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .rateLimited: "Too many requests. Please try again shortly."
        case .apiError(let code): "AniList API error: \(code)"
        case .graphQLError(let msg): msg
        case .networkError(let err): err.localizedDescription
        }
    }
}

actor AniListClient {
    static let shared = AniListClient()

    private let endpoint = URL(string: "https://graphql.anilist.co")!
    private var username: String
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    private init() {
        self.username = ProcessInfo.processInfo.environment["ANILIST_USERNAME"] ?? "xtypo"
    }

    // MARK: - Shared Response Types

    private struct MediaPage: Decodable {
        let pageInfo: PageInfo
        let media: [SeasonalMedia]
    }
    private struct MediaPageResponse: Decodable { let Page: MediaPage }

    // MARK: - Generic Fetcher

    private func execute<T: Decodable>(
        query: String,
        variables: [String: AnyCodable] = [:],
        accessToken: String? = nil,
        as type: T.Type
    ) async throws -> T {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let payload = GraphQLRequest(query: query, variables: variables)
        request.httpBody = try encoder.encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, !((200...299).contains(http.statusCode)) {
            if http.statusCode == 429 { throw AniListError.rateLimited }
            throw AniListError.apiError(http.statusCode)
        }

        let gqlResponse = try decoder.decode(GraphQLResponse<T>.self, from: data)

        if let errors = gqlResponse.errors, let first = errors.first {
            throw AniListError.graphQLError(first.message)
        }

        guard let result = gqlResponse.data else {
            throw AniListError.graphQLError("No data in response")
        }

        return result
    }

    // MARK: - Queries

    func fetchMediaList(type: MediaType, accessToken: String? = nil) async throws -> [MediaListEntry] {
        struct Response: Decodable { let MediaListCollection: MediaListCollection }

        guard !username.isEmpty else {
            throw AniListError.graphQLError("Not signed in")
        }

        let result: Response
        do {
            result = try await execute(
                query: Queries.mediaList,
                variables: ["userName": AnyCodable(username), "type": AnyCodable(type.rawValue)],
                accessToken: accessToken,
                as: Response.self
            )
        } catch let error as AniListError {
            // Fall back to public query on auth errors
            if accessToken != nil, case .apiError(let code) = error, [401, 403, 500].contains(code) {
                result = try await execute(
                    query: Queries.mediaList,
                    variables: ["userName": AnyCodable(username), "type": AnyCodable(type.rawValue)],
                    as: Response.self
                )
            } else {
                throw error
            }
        }

        let allEntries = result.MediaListCollection.lists.flatMap(\.entries)
            .filter { $0.media.isAdult != true }
        return allEntries.sorted { $0.updatedAt > $1.updatedAt }
    }

    func fetchMediaDetails(id: Int) async throws -> MediaDetails {
        struct Response: Decodable { let Media: MediaDetails }
        let result = try await execute(
            query: Queries.mediaDetails,
            variables: ["id": AnyCodable(id)],
            as: Response.self
        )
        return result.Media
    }

    func fetchUserMediaEntry(mediaId: Int) async throws -> UserMediaEntry? {
        struct Response: Decodable { let MediaList: UserMediaEntry? }
        do {
            let result = try await execute(
                query: Queries.userMediaStatus,
                variables: ["userName": AnyCodable(username), "mediaId": AnyCodable(mediaId)],
                as: Response.self
            )
            return result.MediaList
        } catch {
            return nil
        }
    }

    func fetchUser(accessToken: String? = nil) async throws -> AniListUser {
        if let accessToken {
            struct Response: Decodable { let Viewer: AniListUser }
            let result = try await execute(
                query: Queries.viewer,
                accessToken: accessToken,
                as: Response.self
            )
            username = result.Viewer.name
            return result.Viewer
        } else {
            struct Response: Decodable { let User: AniListUser }
            let result = try await execute(
                query: Queries.user,
                variables: ["name": AnyCodable(username)],
                as: Response.self
            )
            return result.User
        }
    }

    func fetchUserActivities(userId: Int, perPage: Int = 15) async throws -> [ListActivity] {
        struct Response: Decodable { let Page: ActivityPage }
        let result = try await execute(
            query: Queries.activity,
            variables: ["userId": AnyCodable(userId), "page": 1, "perPage": AnyCodable(perPage)],
            as: Response.self
        )
        return result.Page.activities
    }

    func fetchAiringSchedule(dayIndex: Int) async throws -> [AiringSchedule] {
        let now = Date()
        var calendar = Calendar.current
        calendar.timeZone = .current
        let currentDay = calendar.component(.weekday, from: now) - 1 // 0=Sun
        let daysToAdd = dayIndex - currentDay

        guard var targetDate = calendar.date(byAdding: .day, value: daysToAdd, to: now) else { return [] }
        targetDate = calendar.startOfDay(for: targetDate)

        let startOfDay = Int(targetDate.timeIntervalSince1970)
        let endOfDay = startOfDay + 86400 - 1

        var allSchedules: [AiringSchedule] = []
        var page = 1
        var hasNextPage = true

        while hasNextPage && page <= 20 {
            struct Response: Decodable { let Page: AiringSchedulePage }
            let result = try await execute(
                query: Queries.airingSchedule,
                variables: ["page": AnyCodable(page), "airingAt_greater": AnyCodable(startOfDay), "airingAt_lesser": AnyCodable(endOfDay)],
                as: Response.self
            )
            let filtered = result.Page.airingSchedules.filter { $0.media.isAdult != true }
            allSchedules.append(contentsOf: filtered)
            hasNextPage = result.Page.pageInfo.hasNextPage
            page += 1
        }

        return allSchedules
    }

    func fetchSeasonalAnime(
        season: Season,
        year: Int,
        page: Int = 1,
        perPage: Int = 20,
        sort: String = "SCORE_DESC"
    ) async throws -> (media: [SeasonalMedia], hasNextPage: Bool) {
        let result = try await execute(
            query: Queries.seasonalAnime,
            variables: [
                "season": AnyCodable(season.rawValue),
                "seasonYear": AnyCodable(year),
                "page": AnyCodable(page),
                "perPage": AnyCodable(perPage),
                "sort": AnyCodable([sort]),
            ],
            as: MediaPageResponse.self
        )
        let filtered = result.Page.media.filter { $0.isAdult != true }
        return (filtered, result.Page.pageInfo.hasNextPage)
    }

    func searchMedia(query: String, page: Int = 1, perPage: Int = 20) async throws -> (media: [SeasonalMedia], hasNextPage: Bool) {
        let result = try await execute(
            query: Queries.searchMedia,
            variables: ["search": AnyCodable(query), "page": AnyCodable(page), "perPage": AnyCodable(perPage)],
            as: MediaPageResponse.self
        )
        let filtered = result.Page.media.filter { $0.isAdult != true }
        return (filtered, result.Page.pageInfo.hasNextPage)
    }

    func fetchStudioDetails(studioId: Int) async throws -> [StudioMedia] {
        var allMedia: [StudioMedia] = []
        var page = 1
        var hasNextPage = true

        while hasNextPage && page <= 20 {
            struct Response: Decodable { let Studio: StudioDetails }
            let result = try await execute(
                query: Queries.studio,
                variables: ["id": AnyCodable(studioId), "page": AnyCodable(page)],
                as: Response.self
            )
            allMedia.append(contentsOf: result.Studio.media.edges.map(\.node))
            hasNextPage = result.Studio.media.pageInfo.hasNextPage
            page += 1
        }

        // Deduplicate
        var seen = Set<Int>()
        return allMedia.filter { seen.insert($0.id).inserted }
    }

    // MARK: - Mutations

    func updateProgress(mediaId: Int, progress: Int, accessToken: String) async throws {
        struct Entry: Decodable { let id: Int; let progress: Int; let status: MediaListStatus }
        struct Response: Decodable { let SaveMediaListEntry: Entry }
        _ = try await execute(
            query: Mutations.updateProgress,
            variables: ["mediaId": AnyCodable(mediaId), "progress": AnyCodable(progress)],
            accessToken: accessToken,
            as: Response.self
        )
    }

    func updateScore(mediaId: Int, score: Double, accessToken: String) async throws {
        struct Entry: Decodable { let id: Int; let score: Double; let status: MediaListStatus }
        struct Response: Decodable { let SaveMediaListEntry: Entry }
        _ = try await execute(
            query: Mutations.updateScore,
            variables: ["mediaId": AnyCodable(mediaId), "score": AnyCodable(score)],
            accessToken: accessToken,
            as: Response.self
        )
    }

    func updateStatus(mediaId: Int, status: MediaListStatus, accessToken: String) async throws {
        struct Entry: Decodable { let id: Int; let status: MediaListStatus; let score: Double; let progress: Int }
        struct Response: Decodable { let SaveMediaListEntry: Entry }
        _ = try await execute(
            query: Mutations.updateStatus,
            variables: ["mediaId": AnyCodable(mediaId), "status": AnyCodable(status.rawValue)],
            accessToken: accessToken,
            as: Response.self
        )
    }

    func deleteMediaListEntry(entryId: Int, accessToken: String) async throws {
        struct Deleted: Decodable { let deleted: Bool }
        struct Response: Decodable { let DeleteMediaListEntry: Deleted }
        _ = try await execute(
            query: Mutations.deleteEntry,
            variables: ["id": AnyCodable(entryId)],
            accessToken: accessToken,
            as: Response.self
        )
    }

    func addToList(mediaId: Int, status: MediaListStatus, accessToken: String) async throws -> UserMediaEntry {
        struct Response: Decodable { let SaveMediaListEntry: UserMediaEntry }
        let result = try await execute(
            query: Mutations.addToList,
            variables: ["mediaId": AnyCodable(mediaId), "status": AnyCodable(status.rawValue)],
            accessToken: accessToken,
            as: Response.self
        )
        return result.SaveMediaListEntry
    }
}

// MARK: - Query Strings

private enum Queries {
    static let mediaList = """
    query ($userName: String, $type: MediaType) {
      MediaListCollection(userName: $userName, type: $type, sort: UPDATED_TIME_DESC) {
        lists {
          status
          entries {
            id status progress score updatedAt
            media {
              id isAdult title { romaji english native }
              coverImage { large medium }
              episodes chapters format status averageScore
              nextAiringEpisode { airingAt timeUntilAiring episode }
            }
          }
        }
      }
    }
    """

    static let mediaDetails = """
    query ($id: Int) {
      Media(id: $id) {
        id title { romaji english native }
        coverImage { large medium } bannerImage
        description(asHtml: false)
        episodes chapters volumes format status
        averageScore meanScore popularity genres
        season seasonYear
        startDate { year month day } endDate { year month day }
        duration source
        studios { edges { isMain node { id name isAnimationStudio } } }
        trailer { id site thumbnail }
        rankings { id rank type format year season allTime context }
        type
        nextAiringEpisode { airingAt timeUntilAiring episode }
        relations { edges { relationType node {
          id title { romaji english native }
          coverImage { large medium } format type status
        } } }
      }
    }
    """

    static let userMediaStatus = """
    query ($userName: String, $mediaId: Int) {
      MediaList(userName: $userName, mediaId: $mediaId) {
        id status score progress
      }
    }
    """

    static let viewer = """
    query {
      Viewer {
        id name
        avatar { large medium } bannerImage
        statistics {
          anime { count episodesWatched minutesWatched }
          manga { count chaptersRead }
        }
      }
    }
    """

    static let user = """
    query ($name: String) {
      User(name: $name) {
        id name
        avatar { large medium } bannerImage
        statistics {
          anime { count episodesWatched minutesWatched }
          manga { count chaptersRead }
        }
      }
    }
    """

    static let activity = """
    query ($userId: Int, $page: Int, $perPage: Int) {
      Page(page: $page, perPage: $perPage) {
        pageInfo { hasNextPage currentPage }
        activities(userId: $userId, type: MEDIA_LIST, sort: ID_DESC) {
          ... on ListActivity {
            id status progress createdAt
            media {
              id title { romaji english native }
              coverImage { large medium }
              episodes chapters format status averageScore
            }
          }
        }
      }
    }
    """

    static let airingSchedule = """
    query ($page: Int, $airingAt_greater: Int, $airingAt_lesser: Int) {
      Page(page: $page, perPage: 50) {
        pageInfo { hasNextPage currentPage }
        airingSchedules(airingAt_greater: $airingAt_greater, airingAt_lesser: $airingAt_lesser, sort: TIME) {
          id airingAt timeUntilAiring episode
          media {
            id isAdult title { romaji english native }
            coverImage { large medium }
            episodes chapters format status averageScore
          }
        }
      }
    }
    """

    static let seasonalAnime = """
    query ($season: MediaSeason, $seasonYear: Int, $page: Int, $perPage: Int, $sort: [MediaSort]) {
      Page(page: $page, perPage: $perPage) {
        pageInfo { hasNextPage currentPage }
        media(season: $season, seasonYear: $seasonYear, type: ANIME, sort: $sort) {
          id isAdult title { romaji english native }
          coverImage { large medium }
          episodes format status averageScore popularity genres
          studios { edges { isMain node { id name isAnimationStudio } } }
          nextAiringEpisode { airingAt timeUntilAiring episode }
        }
      }
    }
    """

    static let searchMedia = """
    query ($search: String, $page: Int, $perPage: Int) {
      Page(page: $page, perPage: $perPage) {
        pageInfo { hasNextPage currentPage }
        media(search: $search, sort: SEARCH_MATCH) {
          id isAdult type title { romaji english native }
          coverImage { large medium }
          episodes chapters format status averageScore popularity genres
          studios { edges { isMain node { id name isAnimationStudio } } }
          nextAiringEpisode { airingAt timeUntilAiring episode }
        }
      }
    }
    """

    static let studio = """
    query ($id: Int, $page: Int) {
      Studio(id: $id) {
        id name isAnimationStudio
        media(sort: [START_DATE_DESC], page: $page, perPage: 50) {
          pageInfo { hasNextPage currentPage }
          edges { node {
            id title { romaji english native }
            coverImage { large medium }
            episodes chapters format status averageScore
            startDate { year month day } type
          } }
        }
      }
    }
    """
}

private enum Mutations {
    static let updateProgress = """
    mutation ($mediaId: Int, $progress: Int) {
      SaveMediaListEntry(mediaId: $mediaId, progress: $progress) { id progress status }
    }
    """

    static let updateScore = """
    mutation ($mediaId: Int, $score: Float) {
      SaveMediaListEntry(mediaId: $mediaId, score: $score) { id score status }
    }
    """

    static let updateStatus = """
    mutation ($mediaId: Int, $status: MediaListStatus) {
      SaveMediaListEntry(mediaId: $mediaId, status: $status) { id status score progress }
    }
    """

    static let deleteEntry = """
    mutation ($id: Int) {
      DeleteMediaListEntry(id: $id) { deleted }
    }
    """

    static let addToList = """
    mutation ($mediaId: Int, $status: MediaListStatus) {
      SaveMediaListEntry(mediaId: $mediaId, status: $status) { id status score progress }
    }
    """
}
