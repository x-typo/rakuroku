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

export interface Media {
  id: number;
  title: MediaTitle;
  coverImage: MediaCoverImage;
  episodes: number | null;
  chapters: number | null;
  format: string;
  status: string;
  averageScore: number | null;
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
