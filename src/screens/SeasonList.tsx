import { useState, useEffect, useCallback, useMemo, useRef } from "react";
import {
  StyleSheet,
  Text,
  View,
  FlatList,
  RefreshControl,
  Image,
  ActivityIndicator,
  Pressable,
} from "react-native";
import { RouteProp, useRoute, useNavigation } from "@react-navigation/native";
import { NativeStackNavigationProp } from "@react-navigation/native-stack";
import { Ionicons } from "@expo/vector-icons";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { colors } from "../constants";
import { fetchSeasonalAnime, fetchMediaList } from "../api";
import { SeasonalMedia, Season, MediaListEntry, MediaStatus } from "../types";
import { RootStackParamList } from "../../App";

type SeasonListRouteProp = RouteProp<RootStackParamList, "SeasonList">;
type NavigationProp = NativeStackNavigationProp<RootStackParamList>;

function formatSeasonName(season: Season): string {
  return season.charAt(0) + season.slice(1).toLowerCase();
}

function getMainStudio(media: SeasonalMedia): string | null {
  if (!media.studios?.edges) return null;
  const mainStudio = media.studios.edges.find((e) => e.isMain);
  return mainStudio?.node.name || media.studios.edges[0]?.node.name || null;
}

function getStatusColor(status: MediaStatus | null): string | null {
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

function getStatusLabel(status: MediaStatus | null): string | null {
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

export default function SeasonListScreen() {
  const route = useRoute<SeasonListRouteProp>();
  const navigation = useNavigation<NavigationProp>();
  const insets = useSafeAreaInsets();
  const { season, year, label } = route.params;

  const [media, setMedia] = useState<SeasonalMedia[]>([]);
  const [userAnimeList, setUserAnimeList] = useState<MediaListEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [hasNextPage, setHasNextPage] = useState(true);
  const currentPage = useRef(1);

  const userStatusMap = useMemo(() => {
    const map = new Map<number, MediaStatus>();
    userAnimeList.forEach((entry) => {
      map.set(entry.media.id, entry.status);
    });
    return map;
  }, [userAnimeList]);

  const loadData = useCallback(async (showRefreshing = false) => {
    if (showRefreshing) {
      setRefreshing(true);
    } else {
      setLoading(true);
    }
    setError(null);
    currentPage.current = 1;

    try {
      const [seasonData, animeList] = await Promise.all([
        fetchSeasonalAnime(season, year, 1, 25),
        fetchMediaList("ANIME"),
      ]);
      setMedia(seasonData.media);
      setHasNextPage(seasonData.hasNextPage);
      setUserAnimeList(animeList);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to load seasonal anime");
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [season, year]);

  const loadMore = useCallback(async () => {
    if (loadingMore || !hasNextPage) return;

    setLoadingMore(true);
    const nextPage = currentPage.current + 1;

    try {
      const seasonData = await fetchSeasonalAnime(season, year, nextPage, 25);
      setMedia((prev) => [...prev, ...seasonData.media]);
      setHasNextPage(seasonData.hasNextPage);
      currentPage.current = nextPage;
    } catch (err) {
      // Silently fail on load more - user can scroll up and try again
    } finally {
      setLoadingMore(false);
    }
  }, [season, year, loadingMore, hasNextPage]);

  useEffect(() => {
    loadData();
  }, [loadData]);

  const renderItem = useCallback(
    ({ item }: { item: SeasonalMedia }) => {
      const title = item.title.english || item.title.romaji;
      const studio = getMainStudio(item);
      const userStatus = userStatusMap.get(item.id) || null;
      const statusLabel = getStatusLabel(userStatus);
      const statusColor = getStatusColor(userStatus);

      return (
        <Pressable
          style={styles.card}
          onPress={() => navigation.navigate("MediaDetail", { mediaId: item.id })}
        >
          <View style={styles.cardRow}>
            <Image
              source={{ uri: item.coverImage.medium }}
              style={styles.coverImage}
            />
            <View style={styles.cardInfo}>
              <Text style={styles.cardTitle} numberOfLines={2}>
                {title}
              </Text>
              {studio && (
                <Text style={styles.studioName} numberOfLines={1}>
                  {studio}
                </Text>
              )}
              <View style={styles.metaRow}>
                {item.averageScore && (
                  <View style={styles.scoreContainer}>
                    <Ionicons name="bar-chart" size={12} color={colors.primary} />
                    <Text style={styles.scoreText}>{item.averageScore}%</Text>
                  </View>
                )}
                {item.episodes && (
                  <Text style={styles.episodesText}>{item.episodes} episodes</Text>
                )}
              </View>
              {statusLabel && statusColor && (
                <Text style={[styles.statusText, { color: statusColor }]}>
                  {statusLabel}
                </Text>
              )}
            </View>
          </View>
        </Pressable>
      );
    },
    [navigation, userStatusMap]
  );

  const renderHeader = () => (
    <View style={[styles.header, { paddingTop: insets.top + 16 }]}>
      <Text style={styles.headerTitle}>{label}</Text>
      <Text style={styles.headerSubtitle}>
        {formatSeasonName(season)} {year}
      </Text>
    </View>
  );

  const renderFooter = () => {
    if (!loadingMore) return null;
    return (
      <View style={styles.footerLoader}>
        <ActivityIndicator size="small" color={colors.primary} />
      </View>
    );
  };

  if (loading) {
    return (
      <View style={[styles.container, styles.centered]}>
        <ActivityIndicator size="large" color={colors.primary} />
      </View>
    );
  }

  if (error) {
    return (
      <View style={[styles.container, styles.centered]}>
        <Text style={styles.errorText}>{error}</Text>
        <Pressable style={styles.retryButton} onPress={() => loadData()}>
          <Text style={styles.retryText}>Retry</Text>
        </Pressable>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <FlatList
        data={media}
        renderItem={renderItem}
        keyExtractor={(item) => item.id.toString()}
        ListHeaderComponent={renderHeader}
        ListFooterComponent={renderFooter}
        contentContainerStyle={styles.listContent}
        onEndReached={loadMore}
        onEndReachedThreshold={0.5}
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            onRefresh={() => loadData(true)}
            tintColor={colors.primary}
          />
        }
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  centered: {
    alignItems: "center",
    justifyContent: "center",
  },
  header: {
    paddingHorizontal: 16,
    paddingBottom: 16,
  },
  headerTitle: {
    fontSize: 28,
    fontWeight: "bold",
    color: colors.textPrimary,
  },
  headerSubtitle: {
    fontSize: 16,
    color: colors.textSecondary,
    marginTop: 4,
  },
  listContent: {
    paddingBottom: 24,
  },
  card: {
    backgroundColor: colors.surface,
    borderRadius: 12,
    marginHorizontal: 16,
    marginBottom: 12,
    overflow: "hidden",
  },
  cardRow: {
    flexDirection: "row",
  },
  coverImage: {
    width: 80,
    height: 120,
  },
  cardInfo: {
    flex: 1,
    padding: 12,
    justifyContent: "center",
  },
  cardTitle: {
    fontSize: 16,
    fontWeight: "600",
    color: colors.textPrimary,
    marginBottom: 4,
  },
  studioName: {
    fontSize: 13,
    color: colors.textSecondary,
    marginBottom: 4,
  },
  metaRow: {
    flexDirection: "row",
    alignItems: "center",
    gap: 12,
  },
  scoreContainer: {
    flexDirection: "row",
    alignItems: "center",
    gap: 4,
  },
  scoreText: {
    fontSize: 13,
    color: colors.textSecondary,
  },
  episodesText: {
    fontSize: 13,
    color: colors.textSecondary,
  },
  statusText: {
    fontSize: 13,
    fontWeight: "600",
    marginTop: 4,
  },
  footerLoader: {
    paddingVertical: 16,
    alignItems: "center",
  },
  errorText: {
    fontSize: 16,
    color: colors.error,
    marginBottom: 16,
    textAlign: "center",
    paddingHorizontal: 24,
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
});
