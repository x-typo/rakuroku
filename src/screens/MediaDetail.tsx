import { useState, useEffect, useCallback } from "react";
import {
  StyleSheet,
  Text,
  View,
  Image,
  ScrollView,
  RefreshControl,
  ActivityIndicator,
  Dimensions,
  Pressable,
} from "react-native";
import { RouteProp, useRoute, useNavigation } from "@react-navigation/native";
import { NativeStackNavigationProp } from "@react-navigation/native-stack";
import { Ionicons } from "@expo/vector-icons";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { colors } from "../constants";
import { fetchMediaDetails, fetchUserMediaStatus } from "../api";
import { MediaDetails, MediaStatus, MediaRank, Studio } from "../types";
import { RootStackParamList } from "../../App";

type MediaDetailRouteProp = RouteProp<RootStackParamList, "MediaDetail">;
type NavigationProp = NativeStackNavigationProp<RootStackParamList>;

const { width: SCREEN_WIDTH } = Dimensions.get("window");

function formatDate(date: { year: number | null; month: number | null; day: number | null } | null): string {
  if (!date || !date.year) return "TBA";
  const parts = [date.year];
  if (date.month) {
    const monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    return `${monthNames[date.month - 1]} ${date.day || ""}, ${date.year}`.trim();
  }
  return date.year.toString();
}

function formatStatus(status: string): string {
  const statusMap: Record<string, string> = {
    FINISHED: "Finished",
    RELEASING: "Releasing",
    NOT_YET_RELEASED: "Not Yet Released",
    CANCELLED: "Cancelled",
    HIATUS: "Hiatus",
  };
  return statusMap[status] || status;
}

function formatFormat(format: string): string {
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

function formatSource(source: string | null): string {
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

function formatSeason(season: string | null, year: number | null): string {
  if (!season || !year) return "";
  const seasonMap: Record<string, string> = {
    WINTER: "Winter",
    SPRING: "Spring",
    SUMMER: "Summer",
    FALL: "Fall",
  };
  return `${seasonMap[season] || season} ${year}`;
}

function getSeasonalRank(rankings: MediaRank[], season: string | null, year: number | null): MediaRank | null {
  if (!season || !year || !rankings) return null;
  // Find the ranking that matches the season and year (rated type preferred)
  return rankings.find(
    (r) => r.season === season && r.year === year && r.type === "RATED"
  ) || rankings.find(
    (r) => r.season === season && r.year === year && r.type === "POPULAR"
  ) || null;
}

function formatSeasonName(season: string): string {
  const seasonMap: Record<string, string> = {
    WINTER: "Winter",
    SPRING: "Spring",
    SUMMER: "Summer",
    FALL: "Fall",
  };
  return seasonMap[season] || season;
}

function getUserStatusColor(status: MediaStatus | null): string | null {
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

function getUserStatusLabel(status: MediaStatus | null): string | null {
  switch (status) {
    case "CURRENT":
      return "Watching";
    case "COMPLETED":
      return "Completed";
    case "DROPPED":
      return "Dropped";
    case "PAUSED":
      return "Paused";
    case "PLANNING":
      return "Planning";
    case "REPEATING":
      return "Rewatching";
    default:
      return null;
  }
}

function formatNextAiring(airingAt: number, episode: number): string {
  const date = new Date(airingAt * 1000);
  const now = Date.now();
  const diff = airingAt * 1000 - now;

  if (diff < 0) return "";

  const days = Math.floor(diff / (1000 * 60 * 60 * 24));
  const hours = Math.floor((diff % (1000 * 60 * 60 * 24)) / (1000 * 60 * 60));

  let timeText = "";
  if (days > 0) {
    timeText = `${days}d ${hours}h`;
  } else if (hours > 0) {
    timeText = `${hours}h`;
  } else {
    const minutes = Math.floor((diff % (1000 * 60 * 60)) / (1000 * 60));
    timeText = `${minutes}m`;
  }

  return `Episode ${episode} airing in ${timeText}`;
}

function stripHtmlTags(text: string): string {
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

export default function MediaDetailScreen() {
  const route = useRoute<MediaDetailRouteProp>();
  const navigation = useNavigation<NavigationProp>();
  const insets = useSafeAreaInsets();
  const { mediaId } = route.params;

  const [media, setMedia] = useState<MediaDetails | null>(null);
  const [userStatus, setUserStatus] = useState<MediaStatus | null>(null);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const loadData = useCallback(async (showRefreshing = false) => {
    if (showRefreshing) {
      setRefreshing(true);
    } else {
      setLoading(true);
    }
    setError(null);

    try {
      const [data, status] = await Promise.all([
        fetchMediaDetails(mediaId),
        fetchUserMediaStatus(mediaId),
      ]);
      setMedia(data);
      setUserStatus(status);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to load media details");
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [mediaId]);

  useEffect(() => {
    loadData();
  }, [loadData]);

  const getMainStudio = (): { id: number; name: string } | null => {
    if (!media?.studios?.edges || media.studios.edges.length === 0) return null;
    const mainStudioEdge = media.studios.edges.find((edge) => edge.isMain);
    const studioNode = mainStudioEdge?.node || media.studios.edges[0]?.node;
    if (!studioNode) return null;
    return { id: studioNode.id, name: studioNode.name };
  };

  if (loading) {
    return (
      <View style={styles.centerContainer}>
        <ActivityIndicator size="large" color={colors.primary} />
      </View>
    );
  }

  if (error) {
    return (
      <View style={styles.centerContainer}>
        <Text style={styles.errorText}>{error}</Text>
        <Pressable style={styles.retryButton} onPress={() => loadData()}>
          <Text style={styles.retryText}>Retry</Text>
        </Pressable>
      </View>
    );
  }

  if (!media) {
    return (
      <View style={styles.centerContainer}>
        <Text style={styles.subtitle}>No media data available</Text>
      </View>
    );
  }

  const title = media.title.english || media.title.romaji;
  const studio = getMainStudio();
  const seasonText = formatSeason(media.season, media.seasonYear);
  const userStatusLabel = getUserStatusLabel(userStatus);
  const userStatusColor = getUserStatusColor(userStatus);
  const seasonalRank = getSeasonalRank(media.rankings, media.season, media.seasonYear);

  return (
    <View style={styles.container}>
      <ScrollView
        contentContainerStyle={styles.content}
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            onRefresh={() => loadData(true)}
            tintColor={colors.primary}
          />
        }
      >
        <View style={{ height: insets.top }} />
        {media.bannerImage ? (
          <Image source={{ uri: media.bannerImage }} style={styles.bannerImage} />
        ) : (
          <View style={styles.bannerPlaceholder} />
        )}

        <View style={styles.headerSection}>
          <Image source={{ uri: media.coverImage.large }} style={styles.coverImage} />
          <View style={styles.headerInfo}>
            <Text style={styles.title} numberOfLines={3}>
              {title}
            </Text>
            {studio && (
              <Pressable onPress={() => navigation.navigate("Studio", { studioId: studio.id, studioName: studio.name })}>
                <Text style={styles.studio}>{studio.name}</Text>
              </Pressable>
            )}
            {seasonText && <Text style={styles.season}>{seasonText}</Text>}
            {userStatusLabel && userStatusColor && (
              <Text style={[styles.status, { color: userStatusColor }]}>
                {userStatusLabel}
              </Text>
            )}
            {media.nextAiringEpisode && (
              <Text style={styles.nextAiring}>
                {formatNextAiring(media.nextAiringEpisode.airingAt, media.nextAiringEpisode.episode)}
              </Text>
            )}
          </View>
        </View>

        <View style={styles.statsRow}>
          {media.averageScore && (
            <View style={styles.statItem}>
              <Ionicons name="bar-chart" size={16} color={colors.primary} />
              <Text style={styles.statValue}>{media.averageScore}%</Text>
            </View>
          )}
          {seasonalRank && (
            <View style={styles.statItem}>
              <Ionicons name="trophy" size={16} color="#FFD700" />
              <Text style={styles.statValue}>
                #{seasonalRank.rank} {formatSeasonName(seasonalRank.season!)} {seasonalRank.year}
              </Text>
            </View>
          )}
        </View>

        {media.genres.length > 0 && (
          <View style={styles.genresContainer}>
            {media.genres.map((genre) => (
              <View key={genre} style={styles.genreTag}>
                <Text style={styles.genreText}>{genre}</Text>
              </View>
            ))}
          </View>
        )}

        <View style={styles.infoSection}>
          <View style={styles.infoRow}>
            <Text style={styles.infoLabel}>Format</Text>
            <Text style={styles.infoValue}>{formatFormat(media.format)}</Text>
          </View>
          {media.type === "ANIME" && media.episodes && (
            <View style={styles.infoRow}>
              <Text style={styles.infoLabel}>Episodes</Text>
              <Text style={styles.infoValue}>{media.episodes}</Text>
            </View>
          )}
          {media.type === "MANGA" && media.chapters && (
            <View style={styles.infoRow}>
              <Text style={styles.infoLabel}>Chapters</Text>
              <Text style={styles.infoValue}>{media.chapters}</Text>
            </View>
          )}
          {media.type === "MANGA" && media.volumes && (
            <View style={styles.infoRow}>
              <Text style={styles.infoLabel}>Volumes</Text>
              <Text style={styles.infoValue}>{media.volumes}</Text>
            </View>
          )}
          <View style={styles.infoRow}>
            <Text style={styles.infoLabel}>Status</Text>
            <Text style={styles.infoValue}>{formatStatus(media.status)}</Text>
          </View>
          <View style={styles.infoRow}>
            <Text style={styles.infoLabel}>Start Date</Text>
            <Text style={styles.infoValue}>{formatDate(media.startDate)}</Text>
          </View>
          {media.endDate?.year && (
            <View style={styles.infoRow}>
              <Text style={styles.infoLabel}>End Date</Text>
              <Text style={styles.infoValue}>{formatDate(media.endDate)}</Text>
            </View>
          )}
        </View>

        {media.description && (
          <View style={styles.descriptionSection}>
            <Text style={styles.sectionTitle}>Synopsis</Text>
            <Text style={styles.description}>{stripHtmlTags(media.description)}</Text>
          </View>
        )}
      </ScrollView>

      {refreshing && (
        <View style={styles.loadingOverlay}>
          <ActivityIndicator size="large" color={colors.primary} />
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  content: {
    paddingBottom: 32,
  },
  centerContainer: {
    flex: 1,
    backgroundColor: colors.background,
    alignItems: "center",
    justifyContent: "center",
  },
  bannerImage: {
    width: SCREEN_WIDTH,
    height: 180,
  },
  bannerPlaceholder: {
    width: SCREEN_WIDTH,
    height: 100,
    backgroundColor: colors.surface,
  },
  headerSection: {
    flexDirection: "row",
    paddingHorizontal: 16,
    marginTop: -60,
  },
  coverImage: {
    width: 120,
    height: 180,
    borderRadius: 8,
  },
  headerInfo: {
    flex: 1,
    marginLeft: 16,
    paddingTop: 70,
  },
  title: {
    fontSize: 20,
    fontWeight: "bold",
    color: colors.textPrimary,
    marginBottom: 4,
  },
  altTitle: {
    fontSize: 14,
    color: colors.textSecondary,
    marginBottom: 8,
  },
  studio: {
    fontSize: 14,
    color: colors.primary,
    marginBottom: 4,
  },
  season: {
    fontSize: 13,
    color: colors.textSecondary,
  },
  status: {
    fontSize: 13,
    fontWeight: "600",
    marginTop: 4,
  },
  nextAiring: {
    fontSize: 13,
    color: colors.warning,
    marginTop: 4,
  },
  statsRow: {
    flexDirection: "row",
    flexWrap: "wrap",
    paddingHorizontal: 16,
    paddingTop: 16,
    gap: 16,
  },
  statItem: {
    flexDirection: "row",
    alignItems: "center",
    gap: 4,
  },
  statValue: {
    fontSize: 14,
    color: colors.textPrimary,
  },
  genresContainer: {
    flexDirection: "row",
    flexWrap: "wrap",
    paddingHorizontal: 16,
    paddingTop: 16,
    gap: 8,
  },
  genreTag: {
    backgroundColor: colors.surface,
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 16,
  },
  genreText: {
    fontSize: 12,
    color: colors.textPrimary,
  },
  infoSection: {
    marginTop: 24,
    marginHorizontal: 16,
    backgroundColor: colors.surface,
    borderRadius: 12,
    padding: 16,
  },
  infoRow: {
    flexDirection: "row",
    justifyContent: "space-between",
    paddingVertical: 8,
    borderBottomWidth: 1,
    borderBottomColor: colors.background,
  },
  infoLabel: {
    fontSize: 14,
    color: colors.textSecondary,
  },
  infoValue: {
    fontSize: 14,
    color: colors.textPrimary,
    fontWeight: "500",
  },
  descriptionSection: {
    marginTop: 24,
    paddingHorizontal: 16,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: "bold",
    color: colors.textPrimary,
    marginBottom: 12,
  },
  description: {
    fontSize: 14,
    color: colors.textSecondary,
    lineHeight: 22,
  },
  subtitle: {
    fontSize: 16,
    color: colors.textSecondary,
  },
  errorText: {
    fontSize: 16,
    color: colors.error,
    marginBottom: 16,
  },
  retryButton: {
    backgroundColor: colors.primary,
    paddingHorizontal: 24,
    paddingVertical: 12,
    borderRadius: 8,
  },
  retryText: {
    color: colors.textPrimary,
    fontWeight: "600",
  },
  loadingOverlay: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: "rgba(0, 0, 0, 0.5)",
    alignItems: "center",
    justifyContent: "center",
  },
});
