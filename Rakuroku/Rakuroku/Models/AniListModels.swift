import Foundation

// MARK: - Enums

enum MediaType: String, Codable, Sendable {
    case anime = "ANIME"
    case manga = "MANGA"
}

enum MediaListStatus: String, Codable, CaseIterable, Sendable {
    case current = "CURRENT"
    case completed = "COMPLETED"
    case dropped = "DROPPED"
    case planning = "PLANNING"
    case paused = "PAUSED"
    case repeating = "REPEATING"
}

enum Season: String, Codable, Sendable {
    case winter = "WINTER"
    case spring = "SPRING"
    case summer = "SUMMER"
    case fall = "FALL"
}

enum MediaRelationType: String, Codable, Sendable {
    case adaptation = "ADAPTATION"
    case prequel = "PREQUEL"
    case sequel = "SEQUEL"
    case parent = "PARENT"
    case sideStory = "SIDE_STORY"
    case character = "CHARACTER"
    case summary = "SUMMARY"
    case alternative = "ALTERNATIVE"
    case spinOff = "SPIN_OFF"
    case other = "OTHER"
    case source = "SOURCE"
    case compilation = "COMPILATION"
    case contains = "CONTAINS"
}

// MARK: - Core Models

struct MediaTitle: Codable, Sendable {
    let romaji: String?
    let english: String?
    let native: String?

    var display: String {
        english ?? romaji ?? native ?? "Unknown"
    }
}

extension MediaTitle {
    func matches(_ query: String) -> Bool {
        let q = query.lowercased()
        return romaji?.lowercased().contains(q) == true ||
               english?.lowercased().contains(q) == true ||
               native?.contains(query) == true
    }
}

struct MediaCoverImage: Codable, Sendable {
    let large: String?
    let medium: String?
}

struct NextAiringEpisode: Codable, Sendable {
    let airingAt: Int
    let timeUntilAiring: Int
    let episode: Int
}

struct FuzzyDate: Codable, Sendable {
    let year: Int?
    let month: Int?
    let day: Int?
}

struct Studio: Codable, Sendable, Identifiable {
    let id: Int
    let name: String
    let isAnimationStudio: Bool
}

struct StudioEdge: Codable, Sendable {
    let isMain: Bool
    let node: Studio
}

struct StudioConnection: Codable, Sendable {
    let edges: [StudioEdge]?
}

struct MediaTrailer: Codable, Sendable {
    let id: String
    let site: String
    let thumbnail: String?
}

struct MediaRank: Codable, Sendable, Identifiable {
    let id: Int
    let rank: Int
    let type: String // "RATED" or "POPULAR"
    let format: String?
    let year: Int?
    let season: String?
    let allTime: Bool
    let context: String
}

// MARK: - Media

struct Media: Codable, Sendable, Identifiable {
    let id: Int
    let isAdult: Bool?
    let title: MediaTitle
    let coverImage: MediaCoverImage?
    let episodes: Int?
    let chapters: Int?
    let format: String?
    let status: String?
    let averageScore: Int?
    let nextAiringEpisode: NextAiringEpisode?
}

// MARK: - Media List

struct MediaListEntry: Codable, Sendable, Identifiable {
    let id: Int
    let status: MediaListStatus
    let progress: Int
    let score: Double
    let updatedAt: Int
    let media: Media
}

struct MediaListGroup: Codable, Sendable {
    let status: MediaListStatus?
    let entries: [MediaListEntry]
}

struct MediaListCollection: Codable, Sendable {
    let lists: [MediaListGroup]
}

// MARK: - Airing Schedule

struct AiringSchedule: Codable, Sendable, Identifiable {
    let id: Int
    let airingAt: Int
    let timeUntilAiring: Int
    let episode: Int
    let media: Media
}

struct AiringSchedulePage: Codable, Sendable {
    let pageInfo: PageInfo
    let airingSchedules: [AiringSchedule]
}

struct PageInfo: Codable, Sendable {
    let hasNextPage: Bool
    let currentPage: Int
}

// MARK: - User

struct UserAvatar: Codable, Sendable {
    let large: String?
    let medium: String?
}

struct AnimeStatistics: Codable, Sendable {
    let count: Int
    let episodesWatched: Int
    let minutesWatched: Int
}

struct MangaStatistics: Codable, Sendable {
    let count: Int
    let chaptersRead: Int
}

struct UserStatistics: Codable, Sendable {
    let anime: AnimeStatistics
    let manga: MangaStatistics
}

struct AniListUser: Codable, Sendable, Identifiable {
    let id: Int
    let name: String
    let avatar: UserAvatar?
    let bannerImage: String?
    let statistics: UserStatistics
}

// MARK: - Activity

struct ListActivity: Codable, Sendable, Identifiable {
    let id: Int
    let status: String?
    let progress: String?
    let createdAt: Int
    let media: Media
}

struct ActivityPage: Codable, Sendable {
    let pageInfo: PageInfo
    let activities: [ListActivity]
}

// MARK: - Media Details

struct MediaRelationNode: Codable, Sendable, Identifiable {
    let id: Int
    let isAdult: Bool?
    let title: MediaTitle
    let coverImage: MediaCoverImage?
    let format: String?
    let type: MediaType?
    let status: String?
}

struct MediaRelationEdge: Codable, Sendable {
    let relationType: MediaRelationType
    let node: MediaRelationNode
}

struct MediaRelationConnection: Codable, Sendable {
    let edges: [MediaRelationEdge]?

    private enum CodingKeys: String, CodingKey {
        case edges
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        edges = try container.decodeIfPresent([MediaRelationEdge].self, forKey: .edges)?
            .filter { $0.node.isAdult != true }
    }
}

struct MediaDetails: Codable, Sendable, Identifiable {
    let id: Int
    let isAdult: Bool?
    let title: MediaTitle
    let coverImage: MediaCoverImage?
    let bannerImage: String?
    let description: String?
    let episodes: Int?
    let chapters: Int?
    let volumes: Int?
    let format: String?
    let status: String?
    let averageScore: Int?
    let meanScore: Int?
    let popularity: Int?
    let genres: [String]?
    let season: String?
    let seasonYear: Int?
    let startDate: FuzzyDate?
    let endDate: FuzzyDate?
    let duration: Int?
    let source: String?
    let studios: StudioConnection?
    let trailer: MediaTrailer?
    let rankings: [MediaRank]?
    let type: MediaType?
    let nextAiringEpisode: NextAiringEpisode?
    let relations: MediaRelationConnection?
}

// MARK: - User Media Entry (for detail screen)

struct UserMediaEntry: Codable, Sendable {
    let id: Int
    let status: MediaListStatus
    let score: Double
    let progress: Int
}

// MARK: - Seasonal

struct SeasonalMedia: Codable, Sendable, Identifiable {
    let id: Int
    let isAdult: Bool?
    let type: MediaType?
    let title: MediaTitle
    let coverImage: MediaCoverImage?
    let episodes: Int?
    let chapters: Int?
    let format: String?
    let status: String?
    let averageScore: Int?
    let popularity: Int?
    let genres: [String]?
    let studios: StudioConnection?
    let nextAiringEpisode: NextAiringEpisode?
}

// MARK: - Studio Details

struct StudioMedia: Codable, Sendable, Identifiable {
    let id: Int
    let isAdult: Bool?
    let title: MediaTitle
    let coverImage: MediaCoverImage?
    let episodes: Int?
    let chapters: Int?
    let format: String?
    let status: String?
    let averageScore: Int?
    let startDate: FuzzyDate?
    let type: MediaType?
}

struct StudioMediaPage: Codable, Sendable {
    let pageInfo: PageInfo
    let edges: [StudioMediaEdge]
}

struct StudioMediaEdge: Codable, Sendable {
    let node: StudioMedia
}

struct StudioDetails: Codable, Sendable, Identifiable {
    let id: Int
    let name: String
    let isAnimationStudio: Bool
    let media: StudioMediaPage
}
