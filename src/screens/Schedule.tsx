import { useState, useEffect, useRef, useCallback, useMemo } from "react";
import {
  StyleSheet,
  Text,
  View,
  Alert,
  TouchableOpacity,
  FlatList,
  RefreshControl,
  PanResponder,
  Image,
  ActivityIndicator,
  Pressable,
} from "react-native";
import { useNavigation } from "@react-navigation/native";
import { NativeStackNavigationProp } from "@react-navigation/native-stack";
import { Ionicons } from "@expo/vector-icons";
import * as WebBrowser from "expo-web-browser";
import { colors } from "../constants";
import { fetchAiringSchedule, fetchMediaList } from "../api";
import { AiringSchedule, MediaListEntry, MediaStatus } from "../types";
import { RootStackParamList } from "../../App";
import { formatAiringTime, getStatusColor, getStatusLabel } from "../utils";

type NavigationProp = NativeStackNavigationProp<RootStackParamList>;

const DAYS = ["S", "M", "T", "W", "T", "F", "S"] as const;

const REDDIT_USER_AGENT = "rakuroku/1.0 (reddit-discussion-linker)";

type RedditSearchResponse = {
  data?: {
    children?: {
      data?: RedditSearchPost;
    }[];
  };
};

type RedditSearchPost = {
  author?: string;
  subreddit?: string;
  title?: string;
  permalink?: string;
  created_utc?: number;
  selftext?: string;
};

function parseEpisodeFromDiscussionTitle(title: string): number | null {
  const match = title.match(/-\s*Episode\s+(\d+)\s+discussion(?:\s*-\s*FINAL)?\s*$/i);
  if (!match) return null;
  const episode = Number(match[1]);
  return Number.isFinite(episode) ? episode : null;
}

async function findAutoLoveponDiscussionUrl(params: {
  anilistId: number;
  episode: number;
  airingAt?: number;
}): Promise<string | null> {
  const q = `author:AutoLovepon anilist.co/anime/${params.anilistId}`;
  const searchUrl =
    "https://www.reddit.com/r/anime/search.json" +
    `?restrict_sr=1&sort=new&limit=25&q=${encodeURIComponent(q)}`;

  const response = await fetch(searchUrl, {
    headers: {
      "User-Agent": REDDIT_USER_AGENT,
      Accept: "application/json",
    },
  });

  const rawText = await response.text();
  if (!response.ok) {
    throw new Error(`Reddit search failed (${response.status})`);
  }

  let json: unknown;
  try {
    json = JSON.parse(rawText);
  } catch {
    throw new Error("Reddit response was not JSON");
  }

  const children = (json as RedditSearchResponse).data?.children;
  if (!Array.isArray(children)) return null;

  const expectedNeedle = `anilist.co/anime/${params.anilistId}`;

  const candidates = children
    .map((child) => child.data)
    .filter((post): post is RedditSearchPost => Boolean(post))
    .filter((post) => post.author === "AutoLovepon" && post.subreddit === "anime")
    .filter((post) => typeof post.title === "string" && typeof post.permalink === "string")
    .filter((post) => {
      if (typeof post.selftext === "string") {
        return post.selftext.includes(expectedNeedle);
      }
      return true;
    })
    .map((post) => ({
      post,
      parsedEpisode: post.title ? parseEpisodeFromDiscussionTitle(post.title) : null,
      createdUtc: Number(post.created_utc) || 0,
    }))
    .sort((a, b) => b.createdUtc - a.createdUtc);

  const exactEpisodeMatches = candidates.filter((candidate) => {
    return candidate.parsedEpisode === params.episode;
  });

  if (exactEpisodeMatches[0]?.post?.permalink) {
    return `https://www.reddit.com${exactEpisodeMatches[0].post.permalink}`;
  }

  const airingAt = params.airingAt;
  if (typeof airingAt === "number" && Number.isFinite(airingAt)) {
    const earlyThreadWindowSeconds = 12 * 60 * 60;
    const lateThreadWindowSeconds = 3 * 24 * 60 * 60;
    const timed = candidates
      .filter((candidate) => {
        if (candidate.createdUtc <= 0) return false;
        return (
          candidate.createdUtc >= airingAt - earlyThreadWindowSeconds &&
          candidate.createdUtc <= airingAt + lateThreadWindowSeconds
        );
      })
      .map((candidate) => ({
        ...candidate,
        deltaSeconds: Math.abs(candidate.createdUtc - airingAt),
      }))
      .sort((a, b) => a.deltaSeconds - b.deltaSeconds);

    const bestTimed = timed[0];
    if (bestTimed?.post?.permalink) {
      return `https://www.reddit.com${bestTimed.post.permalink}`;
    }
  }

  return null;
}

export default function ScheduleScreen() {
  const navigation = useNavigation<NavigationProp>();
  const [selectedDay, setSelectedDay] = useState(new Date().getDay());
  const [schedules, setSchedules] = useState<AiringSchedule[]>([]);
  const [userAnimeList, setUserAnimeList] = useState<MediaListEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [openingDiscussionForId, setOpeningDiscussionForId] = useState<number | null>(null);

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

  const openDiscussion = useCallback(async (schedule: AiringSchedule) => {
    setOpeningDiscussionForId(schedule.id);
    try {
      const url = await findAutoLoveponDiscussionUrl({
        anilistId: schedule.media.id,
        episode: schedule.episode,
        airingAt: schedule.airingAt,
      });

      if (!url) {
        Alert.alert(
          "Discussion not found",
          "Couldn't find an AutoLovepon discussion thread for this episode yet."
        );
        return;
      }

      await WebBrowser.openBrowserAsync(url);
    } catch (err) {
      Alert.alert(
        "Failed to open discussion",
        err instanceof Error ? err.message : "Unknown error"
      );
    } finally {
      setOpeningDiscussionForId((prev) => (prev === schedule.id ? null : prev));
    }
  }, []);

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
      const isOpeningDiscussion = openingDiscussionForId === item.id;

      return (
        <View style={[styles.scheduleItem, !isHighlighted && styles.scheduleItemDimmed]}>
          <Pressable
            style={styles.scheduleMain}
            onPress={() => navigation.navigate("MediaDetail", { mediaId: item.media.id })}
          >
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
          </Pressable>

          <View style={styles.discussionColumn}>
            <TouchableOpacity
              style={[
                styles.discussionButton,
                !hasAired && styles.discussionButtonDisabled,
              ]}
              onPress={() => openDiscussion(item)}
              disabled={!hasAired || isOpeningDiscussion}
            >
              {isOpeningDiscussion ? (
                <ActivityIndicator size="small" color={colors.primary} />
              ) : (
                <>
                  <Ionicons name="logo-reddit" size={14} color={colors.textPrimary} />
                  <Text style={styles.discussionButtonText}>Discuss</Text>
                </>
              )}
            </TouchableOpacity>
          </View>
        </View>
      );
    },
    [userStatusMap, navigation, openDiscussion, openingDiscussionForId]
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
  scheduleMain: {
    flex: 1,
    flexDirection: "row",
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
  discussionColumn: {
    justifyContent: "center",
    paddingRight: 12,
    paddingLeft: 8,
  },
  discussionButton: {
    flexDirection: "row",
    alignItems: "center",
    backgroundColor: colors.surfaceLight,
    paddingHorizontal: 10,
    paddingVertical: 4,
    borderRadius: 8,
  },
  discussionButtonDisabled: {
    opacity: 0.4,
  },
  discussionButtonText: {
    marginLeft: 6,
    fontSize: 12,
    fontWeight: "600",
    color: colors.textPrimary,
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
