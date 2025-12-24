import { useState, useEffect, useRef, useCallback, useMemo } from "react";
import {
  StyleSheet,
  Text,
  View,
  TouchableOpacity,
  FlatList,
  RefreshControl,
  PanResponder,
  Image,
  ActivityIndicator,
} from "react-native";
import { colors } from "../constants";
import { fetchAiringSchedule, fetchMediaList } from "../api";
import { AiringSchedule, MediaListEntry, MediaStatus } from "../types";

const DAYS = ["S", "M", "T", "W", "T", "F", "S"] as const;

function formatAiringTime(airingAt: number): string {
  const date = new Date(airingAt * 1000);
  return date.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
}

function getStatusColor(status: MediaStatus | null): string | null {
  switch (status) {
    case "CURRENT":
      return colors.watching;
    case "DROPPED":
      return colors.dropped;
    case "COMPLETED":
      return colors.completed;
    default:
      return null;
  }
}

function getStatusLabel(status: MediaStatus | null): string | null {
  switch (status) {
    case "CURRENT":
      return "Watching";
    case "DROPPED":
      return "Dropped";
    case "COMPLETED":
      return "Completed";
    default:
      return null;
  }
}

export default function ScheduleScreen() {
  const [selectedDay, setSelectedDay] = useState(new Date().getDay());
  const [schedules, setSchedules] = useState<AiringSchedule[]>([]);
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
      const [scheduleData, animeListData] = await Promise.all([
        fetchAiringSchedule(selectedDay),
        fetchMediaList("ANIME"),
      ]);
      setSchedules(scheduleData);
      setUserAnimeList(animeListData);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to load schedule");
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [selectedDay]);

  useEffect(() => {
    loadData();
  }, [loadData]);

  const panResponder = useRef(
    PanResponder.create({
      onMoveShouldSetPanResponder: (_, gestureState) => {
        return Math.abs(gestureState.dx) > 20 && Math.abs(gestureState.dy) < 20;
      },
      onPanResponderRelease: (_, gestureState) => {
        if (gestureState.dx < -50) {
          setSelectedDay((prev) => (prev + 1) % 7);
        } else if (gestureState.dx > 50) {
          setSelectedDay((prev) => (prev - 1 + 7) % 7);
        }
      },
    })
  ).current;

  const renderItem = useCallback(
    ({ item }: { item: AiringSchedule }) => {
      const title = item.media.title.english || item.media.title.romaji;
      const airingTime = formatAiringTime(item.airingAt);
      const now = Date.now() / 1000;
      const hasAired = item.airingAt < now;

      const userStatus = userStatusMap.get(item.media.id) || null;
      const statusColor = getStatusColor(userStatus);
      const statusLabel = getStatusLabel(userStatus);
      const isHighlighted = userStatus === "CURRENT" || userStatus === "COMPLETED";

      return (
        <View style={[styles.scheduleItem, !isHighlighted && styles.scheduleItemDimmed]}>
          <Image
            source={{ uri: item.media.coverImage.medium }}
            style={styles.coverImage}
          />
          <View style={styles.scheduleInfo}>
            <Text style={styles.animeTitle} numberOfLines={2}>
              {title}
            </Text>
            <View style={styles.episodeRow}>
              <Text style={styles.episodeText}>Episode {item.episode}</Text>
              {statusLabel && (
                <Text style={[styles.statusBadge, { color: statusColor! }]}>
                  {statusLabel}
                </Text>
              )}
            </View>
            <Text
              style={[
                styles.airingTime,
                { color: hasAired ? colors.textSecondary : colors.warning },
              ]}
            >
              {hasAired ? `Aired at ${airingTime}` : `Airing at ${airingTime}`}
            </Text>
          </View>
        </View>
      );
    },
    [userStatusMap]
  );

  const renderContent = () => {
    if (loading) {
      return (
        <View style={styles.centerContent}>
          <ActivityIndicator size="large" color={colors.primary} />
        </View>
      );
    }

    if (error) {
      return (
        <View style={styles.centerContent}>
          <Text style={styles.errorText}>{error}</Text>
          <TouchableOpacity style={styles.retryButton} onPress={() => loadData()}>
            <Text style={styles.retryText}>Retry</Text>
          </TouchableOpacity>
        </View>
      );
    }

    if (schedules.length === 0) {
      return (
        <View style={styles.centerContent}>
          <Text style={styles.emptyText}>No episodes airing this day</Text>
        </View>
      );
    }

    return (
      <FlatList
        data={schedules}
        keyExtractor={(item) => item.id.toString()}
        renderItem={renderItem}
        contentContainerStyle={styles.listContent}
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            onRefresh={() => loadData(true)}
            tintColor={colors.primary}
          />
        }
        {...panResponder.panHandlers}
      />
    );
  };

  return (
    <View style={styles.container}>
      <View style={styles.dayBar}>
        {DAYS.map((day, index) => (
          <TouchableOpacity
            key={index}
            style={[
              styles.dayButton,
              selectedDay === index && styles.dayButtonSelected,
            ]}
            onPress={() => setSelectedDay(index)}
          >
            <Text
              style={[
                styles.dayText,
                selectedDay === index && styles.dayTextSelected,
              ]}
            >
              {day}
            </Text>
          </TouchableOpacity>
        ))}
      </View>

      {renderContent()}

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
  dayBar: {
    flexDirection: "row",
    backgroundColor: colors.surface,
    marginHorizontal: 16,
    marginTop: 16,
    borderRadius: 12,
    padding: 4,
  },
  dayButton: {
    flex: 1,
    alignItems: "center",
    paddingVertical: 12,
    borderRadius: 10,
  },
  dayButtonSelected: {
    backgroundColor: colors.primary,
  },
  dayText: {
    fontSize: 16,
    fontWeight: "600",
    color: colors.textPrimary,
  },
  dayTextSelected: {
    color: colors.textPrimary,
  },
  centerContent: {
    flex: 1,
    alignItems: "center",
    justifyContent: "center",
  },
  listContent: {
    padding: 16,
  },
  scheduleItem: {
    flexDirection: "row",
    backgroundColor: colors.surface,
    borderRadius: 12,
    marginBottom: 12,
    overflow: "hidden",
  },
  scheduleItemDimmed: {
    opacity: 0.5,
  },
  coverImage: {
    width: 80,
    height: 110,
  },
  scheduleInfo: {
    flex: 1,
    padding: 12,
    justifyContent: "center",
  },
  animeTitle: {
    fontSize: 16,
    fontWeight: "600",
    color: colors.textPrimary,
    marginBottom: 4,
  },
  episodeRow: {
    flexDirection: "row",
    alignItems: "center",
    marginBottom: 4,
  },
  episodeText: {
    fontSize: 14,
    color: colors.textSecondary,
  },
  statusBadge: {
    fontSize: 14,
    fontWeight: "600",
    marginLeft: 8,
  },
  airingTime: {
    fontSize: 14,
    fontWeight: "500",
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
  loadingOverlay: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: "rgba(0, 0, 0, 0.5)",
    alignItems: "center",
    justifyContent: "center",
  },
});
