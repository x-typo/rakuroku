import { useState, useEffect, useCallback } from "react";
import {
  StyleSheet,
  Text,
  View,
  Image,
  ScrollView,
  RefreshControl,
  ActivityIndicator,
  TouchableOpacity,
  Dimensions,
} from "react-native";
import { RouteProp, useRoute, useNavigation } from "@react-navigation/native";
import { Ionicons } from "@expo/vector-icons";
import { colors } from "../constants";
import { fetchMediaDetails } from "../api";
import { MediaDetails } from "../types";

type MediaDetailRouteProp = RouteProp<
  { MediaDetail: { mediaId: number } },
  "MediaDetail"
>;

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

export default function MediaDetailScreen() {
  const route = useRoute<MediaDetailRouteProp>();
  const navigation = useNavigation();
  const { mediaId } = route.params;

  const [media, setMedia] = useState<MediaDetails | null>(null);
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
      const data = await fetchMediaDetails(mediaId);
      setMedia(data);
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

  const getMainStudio = () => {
    if (!media?.studios?.edges) return null;
    const mainStudio = media.studios.edges.find((edge) => edge.isMain);
    return mainStudio?.node.name || media.studios.edges[0]?.node.name || null;
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
        <TouchableOpacity style={styles.retryButton} onPress={() => loadData()}>
          <Text style={styles.retryText}>Retry</Text>
        </TouchableOpacity>
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
            {media.title.romaji && media.title.english && (
              <Text style={styles.altTitle} numberOfLines={2}>
                {media.title.romaji}
              </Text>
            )}
            {studio && <Text style={styles.studio}>{studio}</Text>}
            {seasonText && <Text style={styles.season}>{seasonText}</Text>}
          </View>
        </View>

        <View style={styles.statsRow}>
          {media.averageScore && (
            <View style={styles.statItem}>
              <Ionicons name="star" size={16} color={colors.primary} />
              <Text style={styles.statValue}>{media.averageScore}%</Text>
            </View>
          )}
          {media.popularity && (
            <View style={styles.statItem}>
              <Ionicons name="heart" size={16} color="#ff6b6b" />
              <Text style={styles.statValue}>{media.popularity.toLocaleString()}</Text>
            </View>
          )}
          {media.type === "ANIME" && media.episodes && (
            <View style={styles.statItem}>
              <Ionicons name="tv" size={16} color={colors.textSecondary} />
              <Text style={styles.statValue}>{media.episodes} eps</Text>
            </View>
          )}
          {media.type === "MANGA" && media.chapters && (
            <View style={styles.statItem}>
              <Ionicons name="book" size={16} color={colors.textSecondary} />
              <Text style={styles.statValue}>{media.chapters} chs</Text>
            </View>
          )}
          {media.duration && (
            <View style={styles.statItem}>
              <Ionicons name="time" size={16} color={colors.textSecondary} />
              <Text style={styles.statValue}>{media.duration} min</Text>
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
          <View style={styles.infoRow}>
            <Text style={styles.infoLabel}>Source</Text>
            <Text style={styles.infoValue}>{formatSource(media.source)}</Text>
          </View>
        </View>

        {media.description && (
          <View style={styles.descriptionSection}>
            <Text style={styles.sectionTitle}>Synopsis</Text>
            <Text style={styles.description}>{media.description}</Text>
          </View>
        )}
      </ScrollView>

      <TouchableOpacity
        style={styles.backButton}
        onPress={() => navigation.goBack()}
      >
        <Ionicons name="arrow-back" size={24} color={colors.textPrimary} />
      </TouchableOpacity>

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
  backButton: {
    position: "absolute",
    top: 50,
    left: 16,
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: "rgba(0, 0, 0, 0.5)",
    alignItems: "center",
    justifyContent: "center",
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
