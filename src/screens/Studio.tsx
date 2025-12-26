import { useState, useEffect, useCallback, useMemo } from "react";
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
import { fetchStudioDetails, fetchMediaList } from "../api";
import { StudioMedia, MediaListEntry, MediaStatus } from "../types";
import { RootStackParamList } from "../../App";
import { formatYear, formatFormat, getStatusColor, getStatusLabel } from "../utils";

type StudioRouteProp = RouteProp<RootStackParamList, "Studio">;
type NavigationProp = NativeStackNavigationProp<RootStackParamList>;

export default function StudioScreen() {
  const route = useRoute<StudioRouteProp>();
  const navigation = useNavigation<NavigationProp>();
  const insets = useSafeAreaInsets();
  const { studioId, studioName } = route.params;

  const [media, setMedia] = useState<StudioMedia[]>([]);
  const [userAnimeList, setUserAnimeList] = useState<MediaListEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Create a map of media ID to user's status for quick lookup
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

    try {
      const [studioData, animeList] = await Promise.all([
        fetchStudioDetails(studioId),
        fetchMediaList("ANIME"),
      ]);
      setMedia(studioData);
      setUserAnimeList(animeList);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to load studio details");
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [studioId]);

  useEffect(() => {
    loadData();
  }, [loadData]);

  const renderItem = useCallback(
    ({ item }: { item: StudioMedia }) => {
      const title = item.title.english || item.title.romaji;
      const year = formatYear(item.startDate);
      const format = formatFormat(item.format);
      const episodeInfo = item.type === "ANIME" && item.episodes ? `${item.episodes} eps` : "";
      const isUnreleased = item.status === "NOT_YET_RELEASED";

      const userStatus = userStatusMap.get(item.id) || null;
      const statusLabel = getStatusLabel(userStatus);
      const statusColor = getStatusColor(userStatus);

      return (
        <Pressable
          style={styles.card}
          onPress={() => navigation.navigate("MediaDetail", { mediaId: item.id })}
        >
          <Image
            source={{ uri: item.coverImage.medium }}
            style={styles.coverImage}
          />
          <View style={styles.cardInfo}>
            <Text style={styles.cardTitle} numberOfLines={2}>
              {title}
            </Text>
            <Text style={styles.cardSubtitle}>
              {[format, isUnreleased ? "Unreleased" : year, episodeInfo].filter(Boolean).join(" • ")}
            </Text>
            {item.averageScore && !isUnreleased && (
              <View style={styles.scoreRow}>
                <Ionicons name="star" size={14} color={colors.primary} />
                <Text style={styles.scoreText}>{item.averageScore}%</Text>
              </View>
            )}
            {statusLabel && statusColor && (
              <Text style={[styles.statusText, { color: statusColor }]}>
                {statusLabel}
              </Text>
            )}
          </View>
        </Pressable>
      );
    },
    [navigation, userStatusMap]
  );

  const renderHeader = () => (
    <View style={[styles.header, { paddingTop: insets.top + 16 }]}>
      <Text style={styles.headerTitle} numberOfLines={1}>
        {studioName}
      </Text>
    </View>
  );

  if (loading) {
    return (
      <View style={styles.container}>
        {renderHeader()}
        <View style={styles.centerContent}>
          <ActivityIndicator size="large" color={colors.primary} />
        </View>
      </View>
    );
  }

  if (error) {
    return (
      <View style={styles.container}>
        {renderHeader()}
        <View style={styles.centerContent}>
          <Text style={styles.errorText}>{error}</Text>
          <Pressable style={styles.retryButton} onPress={() => loadData()}>
            <Text style={styles.retryText}>Retry</Text>
          </Pressable>
        </View>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      {renderHeader()}
      <Text style={styles.countText}>{media.length} productions</Text>
      <FlatList
        data={media}
        renderItem={renderItem}
        keyExtractor={(item, index) => `${item.id}-${index}`}
        contentContainerStyle={styles.listContent}
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            onRefresh={() => loadData(true)}
            tintColor={colors.primary}
          />
        }
        ListEmptyComponent={
          <View style={styles.emptyContainer}>
            <Text style={styles.emptyText}>No productions found</Text>
          </View>
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
  header: {
    alignItems: "center",
    paddingHorizontal: 16,
    paddingBottom: 16,
    backgroundColor: colors.surface,
  },
  headerTitle: {
    fontSize: 18,
    fontWeight: "bold",
    color: colors.textPrimary,
    textAlign: "center",
  },
  countText: {
    fontSize: 14,
    color: colors.textSecondary,
    paddingHorizontal: 16,
    paddingVertical: 12,
  },
  listContent: {
    paddingBottom: 32,
    paddingTop: 8,
  },
  centerContent: {
    flex: 1,
    alignItems: "center",
    justifyContent: "center",
  },
  card: {
    flexDirection: "row",
    backgroundColor: colors.surface,
    borderRadius: 12,
    marginHorizontal: 16,
    marginBottom: 12,
    overflow: "hidden",
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
  cardSubtitle: {
    fontSize: 13,
    color: colors.textSecondary,
    marginBottom: 4,
  },
  scoreRow: {
    flexDirection: "row",
    alignItems: "center",
    gap: 4,
    marginTop: 4,
  },
  scoreText: {
    fontSize: 14,
    color: colors.textSecondary,
  },
  statusText: {
    fontSize: 13,
    fontWeight: "600",
    marginTop: 4,
  },
  emptyContainer: {
    padding: 32,
    alignItems: "center",
  },
  emptyText: {
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
});
