export const ANIME_FILTERS = ["All", "Watching", "Completed", "Dropped", "Planning"] as const;
export const MANGA_FILTERS = ["All", "Reading", "Completed", "Dropped", "Planning"] as const;

export type AnimeFilter = (typeof ANIME_FILTERS)[number];
export type MangaFilter = (typeof MANGA_FILTERS)[number];

export const DEFAULT_ANIME_FILTER: AnimeFilter = "Watching";
export const DEFAULT_MANGA_FILTER: MangaFilter = "Reading";
