export type MediaType = "ANIME" | "MANGA";

export type MediaStatus =
  | "CURRENT"
  | "COMPLETED"
  | "DROPPED"
  | "PLANNING"
  | "PAUSED"
  | "REPEATING";

export interface MediaTitle {
  romaji: string;
  english: string | null;
  native: string | null;
}

export interface MediaCoverImage {
  large: string;
  medium: string;
}

export interface NextAiringEpisode {
  airingAt: number;
  timeUntilAiring: number;
  episode: number;
}

export interface Media {
  id: number;
  title: MediaTitle;
  coverImage: MediaCoverImage;
  episodes: number | null;
  chapters: number | null;
  format: string;
  status: string;
  averageScore: number | null;
  nextAiringEpisode: NextAiringEpisode | null;
}

export interface MediaListEntry {
  id: number;
  status: MediaStatus;
  progress: number;
  score: number;
  updatedAt: number;
  media: Media;
}

export interface MediaListGroup {
  status: MediaStatus;
  entries: MediaListEntry[];
}

export interface MediaListCollection {
  lists: MediaListGroup[];
}

export interface AiringSchedule {
  id: number;
  airingAt: number;
  timeUntilAiring: number;
  episode: number;
  media: Media;
}

export interface AiringSchedulePage {
  pageInfo: {
    hasNextPage: boolean;
    currentPage: number;
  };
  airingSchedules: AiringSchedule[];
}

export interface UserAvatar {
  large: string;
  medium: string;
}

export interface UserStatistics {
  anime: {
    count: number;
    episodesWatched: number;
    minutesWatched: number;
  };
  manga: {
    count: number;
    chaptersRead: number;
  };
}

export interface User {
  id: number;
  name: string;
  avatar: UserAvatar;
  bannerImage: string | null;
  statistics: UserStatistics;
}

export interface ListActivity {
  id: number;
  status: string;
  progress: string | null;
  createdAt: number;
  media: Media;
}

export interface ActivityPage {
  pageInfo: {
    hasNextPage: boolean;
    currentPage: number;
  };
  activities: ListActivity[];
}

export interface FuzzyDate {
  year: number | null;
  month: number | null;
  day: number | null;
}

export interface Studio {
  id: number;
  name: string;
  isAnimationStudio: boolean;
}

export interface StudioEdge {
  isMain: boolean;
  node: Studio;
}

export interface StudioConnection {
  edges: StudioEdge[];
}

export interface MediaTrailer {
  id: string;
  site: string;
  thumbnail: string;
}

export interface MediaRank {
  id: number;
  rank: number;
  type: "RATED" | "POPULAR";
  format: string;
  year: number | null;
  season: string | null;
  allTime: boolean;
  context: string;
}

export interface MediaDetails {
  id: number;
  title: MediaTitle;
  coverImage: MediaCoverImage;
  bannerImage: string | null;
  description: string | null;
  episodes: number | null;
  chapters: number | null;
  volumes: number | null;
  format: string;
  status: string;
  averageScore: number | null;
  meanScore: number | null;
  popularity: number | null;
  genres: string[];
  season: string | null;
  seasonYear: number | null;
  startDate: FuzzyDate | null;
  endDate: FuzzyDate | null;
  duration: number | null;
  source: string | null;
  studios: StudioConnection | null;
  trailer: MediaTrailer | null;
  rankings: MediaRank[];
  type: MediaType;
  nextAiringEpisode: NextAiringEpisode | null;
  relations: MediaRelationConnection | null;
}

export interface StudioMedia {
  id: number;
  title: MediaTitle;
  coverImage: MediaCoverImage;
  episodes: number | null;
  chapters: number | null;
  format: string;
  status: string;
  averageScore: number | null;
  startDate: FuzzyDate | null;
  type: MediaType;
}

export interface StudioMediaPage {
  pageInfo: {
    hasNextPage: boolean;
    currentPage: number;
  };
  edges: { node: StudioMedia }[];
}

export interface StudioDetails {
  id: number;
  name: string;
  isAnimationStudio: boolean;
  media: StudioMediaPage;
}

export type MediaRelationType =
  | "ADAPTATION"
  | "PREQUEL"
  | "SEQUEL"
  | "PARENT"
  | "SIDE_STORY"
  | "CHARACTER"
  | "SUMMARY"
  | "ALTERNATIVE"
  | "SPIN_OFF"
  | "OTHER"
  | "SOURCE"
  | "COMPILATION"
  | "CONTAINS";

export interface MediaRelationNode {
  id: number;
  title: MediaTitle;
  coverImage: MediaCoverImage;
  format: string;
  type: MediaType;
  status: string;
}

export interface MediaRelationEdge {
  relationType: MediaRelationType;
  node: MediaRelationNode;
}

export interface MediaRelationConnection {
  edges: MediaRelationEdge[];
}

export type Season = "WINTER" | "SPRING" | "SUMMER" | "FALL";

export interface SeasonalMedia {
  id: number;
  title: MediaTitle;
  coverImage: MediaCoverImage;
  episodes: number | null;
  format: string;
  status: string;
  averageScore: number | null;
  popularity: number | null;
  genres: string[];
  studios: StudioConnection | null;
  nextAiringEpisode: NextAiringEpisode | null;
}
