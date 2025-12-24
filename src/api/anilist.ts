import {
  MediaType,
  MediaStatus,
  MediaListEntry,
  MediaListCollection,
} from "../types";

const ANILIST_API = "https://graphql.anilist.co";
const USERNAME = process.env.EXPO_PUBLIC_ANILIST_USERNAME || "";

const MEDIA_LIST_QUERY = `
query ($userName: String, $type: MediaType) {
  MediaListCollection(userName: $userName, type: $type, sort: UPDATED_TIME_DESC) {
    lists {
      status
      entries {
        id
        status
        progress
        score
        updatedAt
        media {
          id
          title {
            romaji
            english
            native
          }
          coverImage {
            large
            medium
          }
          episodes
          chapters
          format
          status
          averageScore
        }
      }
    }
  }
}
`;

export async function fetchMediaList(type: MediaType): Promise<MediaListEntry[]> {
  const response = await fetch(ANILIST_API, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      query: MEDIA_LIST_QUERY,
      variables: {
        userName: USERNAME,
        type,
      },
    }),
  });

  if (!response.ok) {
    throw new Error(`AniList API error: ${response.status}`);
  }

  const json = await response.json();

  if (json.errors) {
    throw new Error(json.errors[0]?.message || "AniList API error");
  }

  const collection: MediaListCollection = json.data.MediaListCollection;

  const allEntries = collection.lists.flatMap((list) => list.entries);
  allEntries.sort((a, b) => b.updatedAt - a.updatedAt);

  return allEntries;
}

export function filterByStatus(
  entries: MediaListEntry[],
  filter: string
): MediaListEntry[] {
  if (filter === "All") {
    return entries;
  }

  const statusMap: Record<string, MediaStatus[]> = {
    Watching: ["CURRENT"],
    Reading: ["CURRENT"],
    Completed: ["COMPLETED"],
    Dropped: ["DROPPED"],
    Planning: ["PLANNING"],
  };

  const statuses = statusMap[filter];
  if (!statuses) return entries;

  return entries.filter((entry) => statuses.includes(entry.status));
}

export function searchEntries(
  entries: MediaListEntry[],
  query: string
): MediaListEntry[] {
  if (!query.trim()) return entries;

  const lowerQuery = query.toLowerCase();
  return entries.filter((entry) => {
    const { title } = entry.media;
    return (
      title.romaji?.toLowerCase().includes(lowerQuery) ||
      title.english?.toLowerCase().includes(lowerQuery) ||
      title.native?.includes(query)
    );
  });
}
