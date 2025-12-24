import {
  MediaType,
  MediaStatus,
  MediaListEntry,
  MediaListCollection,
  AiringSchedule,
  AiringSchedulePage,
  User,
  ListActivity,
  ActivityPage,
  MediaDetails,
} from "../types";

const ANILIST_API = "https://graphql.anilist.co";
const USERNAME = process.env.EXPO_PUBLIC_ANILIST_USERNAME || "";

function handleApiError(status: number): never {
  if (status === 429) {
    throw new Error("Too many requests. Please try again shortly.");
  }
  throw new Error(`AniList API error: ${status}`);
}

const ACTIVITY_QUERY = `
query ($userId: Int, $page: Int, $perPage: Int) {
  Page(page: $page, perPage: $perPage) {
    pageInfo {
      hasNextPage
      currentPage
    }
    activities(userId: $userId, type: MEDIA_LIST, sort: ID_DESC) {
      ... on ListActivity {
        id
        status
        progress
        createdAt
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

const USER_QUERY = `
query ($name: String) {
  User(name: $name) {
    id
    name
    avatar {
      large
      medium
    }
    bannerImage
    statistics {
      anime {
        count
        episodesWatched
        minutesWatched
      }
      manga {
        count
        chaptersRead
      }
    }
  }
}
`;

const AIRING_SCHEDULE_QUERY = `
query ($page: Int, $airingAt_greater: Int, $airingAt_lesser: Int) {
  Page(page: $page, perPage: 50) {
    pageInfo {
      hasNextPage
      currentPage
    }
    airingSchedules(airingAt_greater: $airingAt_greater, airingAt_lesser: $airingAt_lesser, sort: TIME) {
      id
      airingAt
      timeUntilAiring
      episode
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
`;

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
          nextAiringEpisode {
            airingAt
            timeUntilAiring
            episode
          }
        }
      }
    }
  }
}
`;

const MEDIA_DETAILS_QUERY = `
query ($id: Int) {
  Media(id: $id) {
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
    bannerImage
    description(asHtml: false)
    episodes
    chapters
    volumes
    format
    status
    averageScore
    meanScore
    popularity
    genres
    season
    seasonYear
    startDate {
      year
      month
      day
    }
    endDate {
      year
      month
      day
    }
    duration
    source
    studios {
      edges {
        isMain
        node {
          id
          name
          isAnimationStudio
        }
      }
    }
    trailer {
      id
      site
      thumbnail
    }
    type
    nextAiringEpisode {
      airingAt
      timeUntilAiring
      episode
    }
  }
}
`;

export async function fetchMediaDetails(id: number): Promise<MediaDetails> {
  const response = await fetch(ANILIST_API, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      query: MEDIA_DETAILS_QUERY,
      variables: { id },
    }),
  });

  if (!response.ok) {
    handleApiError(response.status);
  }

  const json = await response.json();

  if (json.errors) {
    throw new Error(json.errors[0]?.message || "AniList API error");
  }

  return json.data.Media;
}

export async function fetchUserActivities(
  userId: number,
  perPage: number = 15
): Promise<ListActivity[]> {
  const response = await fetch(ANILIST_API, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      query: ACTIVITY_QUERY,
      variables: {
        userId,
        page: 1,
        perPage,
      },
    }),
  });

  if (!response.ok) {
    handleApiError(response.status);
  }

  const json = await response.json();

  if (json.errors) {
    throw new Error(json.errors[0]?.message || "AniList API error");
  }

  const pageData: ActivityPage = json.data.Page;
  return pageData.activities;
}

export async function fetchUser(): Promise<User> {
  const response = await fetch(ANILIST_API, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      query: USER_QUERY,
      variables: {
        name: USERNAME,
      },
    }),
  });

  if (!response.ok) {
    handleApiError(response.status);
  }

  const json = await response.json();

  if (json.errors) {
    throw new Error(json.errors[0]?.message || "AniList API error");
  }

  return json.data.User;
}

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
    handleApiError(response.status);
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

export async function fetchAiringSchedule(
  dayIndex: number
): Promise<AiringSchedule[]> {
  const now = new Date();
  const targetDate = new Date(now);

  // Calculate the target day
  const currentDay = now.getDay();
  let daysToAdd = dayIndex - currentDay;

  // If the target day is in the past this week, we still show it (could be earlier today or past days)
  targetDate.setDate(now.getDate() + daysToAdd);

  // Set to start of day (00:00:00) in local timezone
  targetDate.setHours(0, 0, 0, 0);
  const startOfDay = Math.floor(targetDate.getTime() / 1000);

  // Set to end of day (23:59:59)
  const endOfDay = startOfDay + 86400 - 1;

  const allSchedules: AiringSchedule[] = [];
  let page = 1;
  let hasNextPage = true;

  while (hasNextPage) {
    const response = await fetch(ANILIST_API, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        query: AIRING_SCHEDULE_QUERY,
        variables: {
          page,
          airingAt_greater: startOfDay,
          airingAt_lesser: endOfDay,
        },
      }),
    });

    if (!response.ok) {
      handleApiError(response.status);
    }

    const json = await response.json();

    if (json.errors) {
      throw new Error(json.errors[0]?.message || "AniList API error");
    }

    const pageData: AiringSchedulePage = json.data.Page;
    allSchedules.push(...pageData.airingSchedules);

    hasNextPage = pageData.pageInfo.hasNextPage;
    page++;
  }

  return allSchedules;
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
