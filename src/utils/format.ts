import { colors } from "../constants";
import { MediaStatus, Season } from "../types";

// Status helpers
export function getStatusColor(status: MediaStatus | null): string | null {
  switch (status) {
    case "CURRENT":
      return colors.watching;
    case "COMPLETED":
      return colors.completed;
    case "DROPPED":
      return colors.dropped;
    case "PAUSED":
      return colors.warning;
    case "PLANNING":
      return colors.textSecondary;
    default:
      return null;
  }
}

export function getStatusLabel(status: MediaStatus | null, type?: "ANIME" | "MANGA"): string | null {
  switch (status) {
    case "CURRENT":
      return type === "MANGA" ? "Reading" : "Watching";
    case "COMPLETED":
      return "Completed";
    case "DROPPED":
      return "Dropped";
    case "PAUSED":
      return "Paused";
    case "PLANNING":
      return "Planning";
    case "REPEATING":
      return type === "MANGA" ? "Rereading" : "Rewatching";
    default:
      return null;
  }
}

// Season/date formatters
export function formatSeasonName(season: Season | string): string {
  if (typeof season === "string") {
    const seasonMap: Record<string, string> = {
      WINTER: "Winter",
      SPRING: "Spring",
      SUMMER: "Summer",
      FALL: "Fall",
    };
    return seasonMap[season] || season.charAt(0) + season.slice(1).toLowerCase();
  }
  return season.charAt(0) + season.slice(1).toLowerCase();
}

export function formatSeason(season: string | null, year: number | null): string {
  if (!season || !year) return "";
  return `${formatSeasonName(season)} ${year}`;
}

// Format type helpers
export function formatFormat(format: string): string {
  const formatMap: Record<string, string> = {
    TV: "TV",
    TV_SHORT: "TV Short",
    MOVIE: "Movie",
    SPECIAL: "Special",
    OVA: "OVA",
    ONA: "ONA",
    MUSIC: "Music",
    MANGA: "Manga",
    NOVEL: "Light Novel",
    ONE_SHOT: "One Shot",
  };
  return formatMap[format] || format;
}

export function formatStatus(status: string): string {
  const statusMap: Record<string, string> = {
    FINISHED: "Finished",
    RELEASING: "Releasing",
    NOT_YET_RELEASED: "Not Yet Released",
    CANCELLED: "Cancelled",
    HIATUS: "Hiatus",
  };
  return statusMap[status] || status;
}

export function formatSource(source: string | null): string {
  if (!source) return "Unknown";
  const sourceMap: Record<string, string> = {
    ORIGINAL: "Original",
    MANGA: "Manga",
    LIGHT_NOVEL: "Light Novel",
    VISUAL_NOVEL: "Visual Novel",
    VIDEO_GAME: "Video Game",
    OTHER: "Other",
    NOVEL: "Novel",
    DOUJINSHI: "Doujinshi",
    ANIME: "Anime",
    WEB_NOVEL: "Web Novel",
    LIVE_ACTION: "Live Action",
    GAME: "Game",
    COMIC: "Comic",
    MULTIMEDIA_PROJECT: "Multimedia Project",
    PICTURE_BOOK: "Picture Book",
  };
  return sourceMap[source] || source;
}

// Date formatters
export function formatDate(date: { year: number | null; month: number | null; day: number | null } | null): string {
  if (!date || !date.year) return "TBA";
  if (date.month) {
    const monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    return `${monthNames[date.month - 1]} ${date.day || ""}, ${date.year}`.trim();
  }
  return date.year.toString();
}

export function formatYear(startDate: { year: number | null } | null): string {
  if (!startDate?.year) return "";
  return startDate.year.toString();
}

// Time formatters
export function formatTimeAgo(timestamp: number): string {
  const now = Date.now() / 1000;
  const diff = now - timestamp;

  if (diff < 60) return "Just now";
  if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
  if (diff < 86400) return `${Math.floor(diff / 3600)}h ago`;
  if (diff < 604800) return `${Math.floor(diff / 86400)}d ago`;
  return `${Math.floor(diff / 604800)}w ago`;
}

export function formatAiringTime(airingAt: number): string {
  const date = new Date(airingAt * 1000);
  return date.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
}

export function formatNextAiring(airingAt: number, episode?: number): string {
  const now = Date.now() / 1000;
  const diff = airingAt - now;

  if (diff < 0) return "";

  let timeText = "";
  if (diff < 3600) {
    timeText = `${Math.floor(diff / 60)}m`;
  } else if (diff < 86400) {
    timeText = `${Math.floor(diff / 3600)}h`;
  } else {
    const days = Math.floor(diff / 86400);
    const hours = Math.floor((diff % 86400) / 3600);
    timeText = days > 0 ? `${days}d ${hours}h` : `${hours}h`;
  }

  if (episode !== undefined) {
    return `Episode ${episode} airing in ${timeText}`;
  }
  return timeText;
}

// HTML helpers
export function stripHtmlTags(text: string): string {
  return text
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<[^>]*>/g, "")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

// Studio helpers
interface StudioEdge {
  isMain: boolean;
  node: { id: number; name: string };
}

interface MediaWithStudios {
  studios?: { edges?: StudioEdge[] } | null;
}

export function getMainStudio(media: MediaWithStudios): { id: number; name: string } | null {
  if (!media.studios?.edges || media.studios.edges.length === 0) return null;
  const mainStudioEdge = media.studios.edges.find((edge) => edge.isMain);
  const studioNode = mainStudioEdge?.node || media.studios.edges[0]?.node;
  if (!studioNode) return null;
  return { id: studioNode.id, name: studioNode.name };
}

export function getMainStudioName(media: MediaWithStudios): string | null {
  if (!media.studios?.edges) return null;
  const mainStudio = media.studios.edges.find((e) => e.isMain);
  return mainStudio?.node.name || media.studios.edges[0]?.node.name || null;
}
