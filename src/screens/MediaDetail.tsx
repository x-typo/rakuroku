import React, { useState, useCallback, useRef } from "react";
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
  Share,
  Modal,
  TextInput,
  Platform,
  Linking,
} from "react-native";
import * as Clipboard from "expo-clipboard";
import * as WebBrowser from "expo-web-browser";
import { RouteProp, useRoute, useNavigation, useFocusEffect } from "@react-navigation/native";
import { NativeStackNavigationProp } from "@react-navigation/native-stack";
import { Ionicons } from "@expo/vector-icons";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { colors } from "../constants";
import { fetchMediaDetails, fetchUserMediaEntry, updateScore, updateStatus, deleteMediaListEntry, addToList, updateProgress, UserMediaEntry } from "../api";
import { MediaDetails, MediaStatus, MediaRank, MediaRelationType } from "../types";
import { RootStackParamList } from "../../App";
import { useAnimeKai, useAuth } from "../context";
import {
  ANIMEKAI_HOME_URL,
  AnimeKaiCandidate,
  buildAnimeKaiEpisodeUrl,
  normalizeAnimeKaiWatchPathInput,
} from "../providers/animekai";
import {
  formatDate,
  formatStatus,
  formatFormat,
  formatSeason,
  formatSeasonName,
  formatNextAiring,
  getStatusColor,
  getStatusLabel,
  stripHtmlTags,
} from "../utils";

type MediaDetailRouteProp = RouteProp<RootStackParamList, "MediaDetail">;
type NavigationProp = NativeStackNavigationProp<RootStackParamList>;

const { width: SCREEN_WIDTH } = Dimensions.get("window");

function getSeasonalRank(rankings: MediaRank[], season: string | null, year: number | null): MediaRank | null {
  if (!season || !year || !rankings) return null;
  return rankings.find(
    (r) => r.season === season && r.year === year && r.type === "RATED"
  ) || rankings.find(
    (r) => r.season === season && r.year === year && r.type === "POPULAR"
  ) || null;
}

function formatRelationType(type: MediaRelationType): string {
  const typeMap: Record<MediaRelationType, string> = {
    ADAPTATION: "Adaptation",
    PREQUEL: "Prequel",
    SEQUEL: "Sequel",
    PARENT: "Parent",
    SIDE_STORY: "Side Story",
    CHARACTER: "Character",
    SUMMARY: "Summary",
    ALTERNATIVE: "Alternative",
    SPIN_OFF: "Spin Off",
    OTHER: "Other",
    SOURCE: "Source",
    COMPILATION: "Compilation",
    CONTAINS: "Contains",
  };
  return typeMap[type] || type;
}

export default function MediaDetailScreen() {
  const route = useRoute<MediaDetailRouteProp>();
  const navigation = useNavigation<NavigationProp>();
  const insets = useSafeAreaInsets();
  const { mediaId } = route.params;
  const { isAuthenticated, accessToken } = useAuth();
  const animeKai = useAnimeKai();
  const hasLoadedOnce = useRef(false);
  const pendingCandidateModalOpenUrlRef = useRef<string | null>(null);

  const [media, setMedia] = useState<MediaDetails | null>(null);
  const [userEntry, setUserEntry] = useState<UserMediaEntry | null>(null);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [scoreModalVisible, setScoreModalVisible] = useState(false);
  const [updatingScore, setUpdatingScore] = useState(false);
  const [statusModalVisible, setStatusModalVisible] = useState(false);
  const [updatingStatus, setUpdatingStatus] = useState(false);
  const [addingToList, setAddingToList] = useState(false);
  const [progressModalVisible, setProgressModalVisible] = useState(false);
  const [updatingProgress, setUpdatingProgress] = useState(false);
  const [showCopied, setShowCopied] = useState(false);
  const [watchLoading, setWatchLoading] = useState(false);
  const [watchError, setWatchError] = useState<string | null>(null);
  const [watchDebugLog, setWatchDebugLog] = useState<string | null>(null);
  const [watchDebugCopied, setWatchDebugCopied] = useState(false);
  const [watchCandidates, setWatchCandidates] = useState<AnimeKaiCandidate[]>([]);
  const [watchCandidateModalVisible, setWatchCandidateModalVisible] = useState(false);
  const [watchLinkModalVisible, setWatchLinkModalVisible] = useState(false);
  const [watchLinkValue, setWatchLinkValue] = useState("");
  const [watchLinkValueError, setWatchLinkValueError] = useState<string | null>(null);

  const openExternalUrl = useCallback(
    async (url: string) => {
      if (Platform.OS === "web") {
        void Linking.openURL(url);
        return;
      }

      try {
        await WebBrowser.openBrowserAsync(url);
        return;
      } catch {
      }

      try {
        await Linking.openURL(url);
      } catch {
        setWatchError("Failed to open episode link.");
      }
    },
    []
  );

  const loadData = useCallback(async (showRefreshing = false) => {
    if (showRefreshing) {
      setRefreshing(true);
    } else {
      setLoading(true);
    }
    setError(null);

    try {
      const [data, entry] = await Promise.all([
        fetchMediaDetails(mediaId),
        fetchUserMediaEntry(mediaId),
      ]);
      setMedia(data);
      setUserEntry(entry);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to load media details");
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [mediaId]);

  useFocusEffect(
    useCallback(() => {
      const showRefreshing = hasLoadedOnce.current;
      hasLoadedOnce.current = true;
      void loadData(showRefreshing);
    }, [loadData])
  );

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
  const userStatus = userEntry?.status || null;
  const userStatusLabel = getStatusLabel(userStatus);
  const userStatusColor = getStatusColor(userStatus);
  const seasonalRank = getSeasonalRank(media.rankings, media.season, media.seasonYear);
  const canEditScore = isAuthenticated && userEntry !== null;
  const overrideWatchPath = animeKai.getOverrideWatchPath(mediaId);
  const hasWatchOverride = Boolean(overrideWatchPath);
  const nextEpisodeNumber = userEntry ? userEntry.progress + 1 : null;
  const allEpisodesWatched =
    media.type === "ANIME" && Boolean(media.episodes) && Boolean(userEntry) && (userEntry?.progress ?? 0) >= (media.episodes ?? 0);
  const watchDisabled =
    !userEntry ||
    watchLoading ||
    (media.type === "ANIME" && media.episodes && nextEpisodeNumber ? nextEpisodeNumber > media.episodes : false);

  const handleShare = async () => {
    try {
      await Share.share({
        message: `https://anilist.co/${media.type.toLowerCase()}/${media.id}`,
      });
    } catch {
    }
  };

  const handleCopy = async () => {
    await Clipboard.setStringAsync(title);
    setShowCopied(true);
    setTimeout(() => setShowCopied(false), 1500);
  };

  const handleCopyWatchDebug = async () => {
    if (!watchDebugLog) return;
    await Clipboard.setStringAsync(watchDebugLog);
    setWatchDebugCopied(true);
    setTimeout(() => setWatchDebugCopied(false), 1500);
  };

  const handleScoreUpdate = async (newScore: number) => {
    if (!accessToken || !userEntry) return;

    setUpdatingScore(true);
    try {
      await updateScore(mediaId, newScore, accessToken);
      setUserEntry({ ...userEntry, score: newScore });
      setScoreModalVisible(false);
    } catch {
    } finally {
      setUpdatingScore(false);
    }
  };

  const handleStatusUpdate = async (newStatus: MediaStatus) => {
    if (!accessToken || !userEntry) return;

    setUpdatingStatus(true);
    try {
      await updateStatus(mediaId, newStatus, accessToken);
      let newScore = userEntry.score;

      // Auto-rate as 1 star when dropping
      if (newStatus === "DROPPED") {
        await updateScore(mediaId, 1, accessToken);
        newScore = 1;
      }

      setUserEntry({ ...userEntry, status: newStatus, score: newScore });
      setStatusModalVisible(false);
    } catch {
    } finally {
      setUpdatingStatus(false);
    }
  };

  const handleDeleteEntry = async () => {
    if (!accessToken || !userEntry) return;

    setUpdatingStatus(true);
    try {
      await deleteMediaListEntry(userEntry.id, accessToken);
      setUserEntry(null);
      setStatusModalVisible(false);
    } catch {
    } finally {
      setUpdatingStatus(false);
    }
  };

  const handleAddToList = async (status: MediaStatus) => {
    if (!accessToken || !media) return;

    setAddingToList(true);
    try {
      const entry = await addToList(mediaId, status, accessToken);
      setUserEntry(entry);
      setStatusModalVisible(false);
    } catch {
    } finally {
      setAddingToList(false);
    }
  };

  const handleProgressUpdate = async (delta: number) => {
    if (!accessToken || !userEntry) return;

    const total = media?.type === "ANIME" ? media?.episodes : media?.chapters;
    const newProgress = Math.max(0, userEntry.progress + delta);
    if (total && newProgress > total) return;

    setUpdatingProgress(true);
    try {
      await updateProgress(mediaId, newProgress, accessToken);
      setUserEntry({ ...userEntry, progress: newProgress });
    } catch {
    } finally {
      setUpdatingProgress(false);
    }
  };

  const openWatchLinkEditor = () => {
    const existing = animeKai.getOverrideWatchPath(mediaId) ?? animeKai.getWatchPath(mediaId) ?? "";
    setWatchLinkValue(existing);
    setWatchLinkValueError(null);
    setWatchLinkModalVisible(true);
  };

  const handleSaveWatchLink = async () => {
    setWatchLinkValueError(null);
    const normalized = normalizeAnimeKaiWatchPathInput(watchLinkValue);
    if (!normalized) {
      setWatchLinkValueError("Paste an AnimeKai watch URL, /watch path, or slug.");
      return;
    }

    await animeKai.setOverrideWatchPath(mediaId, normalized);
    setWatchError(null);
    setWatchLinkModalVisible(false);
  };

  const handleClearWatchLink = async () => {
    await animeKai.clearOverrideWatchPath(mediaId);
    setWatchLinkValue("");
    setWatchError(null);
    setWatchLinkModalVisible(false);
  };

  const handleOpenAnimeKaiHome = () => {
    void openExternalUrl(ANIMEKAI_HOME_URL);
  };

  const handleWatchNextEpisode = async () => {
    if (!accessToken || !isAuthenticated || !userEntry) return;
    if (!media || media.type !== "ANIME") return;

    const nextEp = userEntry.progress + 1;
    if (media.episodes && nextEp > media.episodes) {
      setWatchError("All episodes watched.");
      return;
    }

    setWatchLoading(true);
    setWatchError(null);
    setWatchDebugLog(null);
    setWatchCandidates([]);
    setWatchCandidateModalVisible(false);

    try {
      const animeTitle = media.title.english || media.title.romaji || media.title.native || "";
      const resolved = await animeKai.resolveWatchPathWithDebug({ mediaId, title: animeTitle });
      const watchPath = resolved.watchPath;

      const isDev = Boolean((globalThis as any).__DEV__);
      if (isDev) {
        console.log(resolved.debugLog);
      }
      if (!watchPath || isDev) {
        setWatchDebugLog(resolved.debugLog);
      }

      if (!watchPath) {
        setWatchError("Couldn't find this show on AnimeKai.");
        if (resolved.candidates.length > 0) {
          setWatchCandidates(resolved.candidates);
          setWatchCandidateModalVisible(true);
        }
        setWatchLoading(false);
        return;
      }

      const url = buildAnimeKaiEpisodeUrl(watchPath, nextEp);
      if (Platform.OS === "web") {
        void Linking.openURL(url);
        setWatchLoading(false);
        return;
      }

      setWatchLoading(false);
      void openExternalUrl(url);
    } catch {
      setWatchError("Failed to resolve AnimeKai link.");
      setWatchLoading(false);
    }
  };

  const handleSelectCandidate = async (candidate: AnimeKaiCandidate) => {
    if (!media || media.type !== "ANIME" || !userEntry) return;

    const nextEp = userEntry.progress + 1;
    await animeKai.setOverrideWatchPath(mediaId, candidate.watchPath);
    setWatchCandidateModalVisible(false);
    setWatchError(null);
    setWatchDebugLog(null);

    const url = buildAnimeKaiEpisodeUrl(candidate.watchPath, nextEp);
    if (Platform.OS === "web") {
      void Linking.openURL(url);
      return;
    }

    if (Platform.OS === "ios") {
      pendingCandidateModalOpenUrlRef.current = url;
      setWatchLoading(true);
      setWatchCandidateModalVisible(false);
      return;
    }
    setWatchCandidateModalVisible(false);
    setWatchLoading(false);
    void openExternalUrl(url);
  };

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
            {isAuthenticated && !userEntry && (
              <Pressable
                style={styles.addButton}
                onPress={() => setStatusModalVisible(true)}
              >
                <Text style={styles.addButtonText}>Add</Text>
              </Pressable>
            )}
            {userStatusLabel && userStatusColor && (
              canEditScore ? (
                <Pressable onPress={() => setStatusModalVisible(true)}>
                  <Text style={[styles.status, { color: userStatusColor }]}>
                    {userStatusLabel}
                  </Text>
                </Pressable>
              ) : (
                <Text style={[styles.status, { color: userStatusColor }]}>
                  {userStatusLabel}
                </Text>
              )
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
          {canEditScore && (
            <Pressable
              style={styles.statItemTouchable}
              onPress={() => setScoreModalVisible(true)}
              hitSlop={{ top: 10, bottom: 10, left: 8, right: 8 }}
            >
              <Ionicons name="star" size={16} color={colors.warning} />
              <Text style={styles.statValue}>
                {userEntry.score > 0 ? `${userEntry.score}/10` : "Rate"}
              </Text>
            </Pressable>
          )}
          {canEditScore && (
            <Pressable
              style={styles.statItemTouchable}
              onPress={() => setProgressModalVisible(true)}
              hitSlop={{ top: 10, bottom: 10, left: 8, right: 8 }}
            >
              <Ionicons name="film" size={16} color={colors.textSecondary} />
              <Text style={styles.statValue}>
                {userEntry.progress}/{media.type === "ANIME" ? (media.episodes || "?") : (media.chapters || "?")}
              </Text>
            </Pressable>
          )}
          {seasonalRank && (
            <View style={styles.statItem}>
              <Ionicons name="trophy" size={16} color={colors.gold} />
              <Text style={styles.statValue}>
                #{seasonalRank.rank} {formatSeasonName(seasonalRank.season!)} {seasonalRank.year}
              </Text>
            </View>
          )}
        </View>

        <View style={styles.actionsRow}>
          <Pressable onPress={handleCopy} style={styles.actionButton}>
            <Ionicons name="copy-outline" size={20} color={colors.textPrimary} />
            <Text style={styles.actionText}>{showCopied ? "Copied" : "Copy"}</Text>
          </Pressable>
          <Pressable onPress={handleShare} style={styles.actionButton}>
            <Ionicons name="share-outline" size={20} color={colors.textPrimary} />
            <Text style={styles.actionText}>Share</Text>
          </Pressable>
        </View>

        {media.type === "ANIME" && (
          <View style={styles.watchSection}>
            <Text style={styles.sectionTitle}>Watch</Text>

            {!isAuthenticated && (
              <Text style={styles.watchHint}>Login to track progress and watch the next episode.</Text>
            )}

            {isAuthenticated && !userEntry && (
              <>
                <Text style={styles.watchHint}>Add this anime to your list to track episode progress.</Text>
                <Pressable style={styles.watchSecondaryButton} onPress={() => setStatusModalVisible(true)}>
                  <Text style={styles.watchSecondaryText}>Add to List</Text>
                </Pressable>
              </>
            )}

            {isAuthenticated && userEntry && (
              <>
                <Pressable
                  style={[styles.watchButton, watchDisabled && styles.watchButtonDisabled]}
                  onPress={handleWatchNextEpisode}
                  disabled={watchDisabled}
                >
                  <Ionicons name="play" size={18} color={colors.textPrimary} />
                  <Text style={styles.watchButtonText}>
                    Watch episode {nextEpisodeNumber ?? "?"}
                  </Text>
                  {watchLoading && (
                    <ActivityIndicator
                      size="small"
                      color={colors.textPrimary}
                      style={styles.watchSpinner}
                    />
                  )}
                </Pressable>

                {allEpisodesWatched && <Text style={styles.watchHint}>All episodes watched.</Text>}
                {watchError && <Text style={styles.watchErrorText}>{watchError}</Text>}
                {watchError && watchDebugLog && (
                  <Pressable style={styles.watchSecondaryButton} onPress={handleCopyWatchDebug}>
                    <Text style={styles.watchSecondaryText}>
                      {watchDebugCopied ? "Debug Copied" : "Copy Debug Log"}
                    </Text>
                  </Pressable>
                )}

                <View style={styles.watchButtonsRow}>
                  <Pressable style={styles.watchSecondaryButton} onPress={() => void handleOpenAnimeKaiHome()}>
                    <Text style={styles.watchSecondaryText}>AnimeKai Home</Text>
                  </Pressable>
                  <Pressable style={styles.watchSecondaryButton} onPress={openWatchLinkEditor}>
                    <Text style={styles.watchSecondaryText}>
                      {hasWatchOverride ? "Edit Override" : "Override Link"}
                    </Text>
                  </Pressable>
                </View>

                {hasWatchOverride && (
                  <Pressable style={styles.watchClearButton} onPress={handleClearWatchLink}>
                    <Text style={styles.watchClearText}>Clear Override</Text>
                  </Pressable>
                )}
              </>
            )}
          </View>
        )}

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
          {(() => {
            const rows: React.ReactNode[] = [];
            if (studio) {
              rows.push(
                <Pressable
                  key="studio"
                  style={styles.infoRow}
                  onPress={() => navigation.navigate("Studio", { studioId: studio.id, studioName: studio.name })}
                >
                  <Text style={styles.infoLabel}>Studio</Text>
                  <Text style={[styles.infoValue, styles.studioLink]}>{studio.name}</Text>
                </Pressable>
              );
            }
            rows.push(
              <View key="format" style={styles.infoRow}>
                <Text style={styles.infoLabel}>Format</Text>
                <Text style={styles.infoValue}>{formatFormat(media.format)}</Text>
              </View>
            );
            if (media.type === "ANIME" && media.episodes) {
              rows.push(
                <View key="episodes" style={styles.infoRow}>
                  <Text style={styles.infoLabel}>Episodes</Text>
                  <Text style={styles.infoValue}>{media.episodes}</Text>
                </View>
              );
            }
            if (media.type === "MANGA" && media.chapters) {
              rows.push(
                <View key="chapters" style={styles.infoRow}>
                  <Text style={styles.infoLabel}>Chapters</Text>
                  <Text style={styles.infoValue}>{media.chapters}</Text>
                </View>
              );
            }
            if (media.type === "MANGA" && media.volumes) {
              rows.push(
                <View key="volumes" style={styles.infoRow}>
                  <Text style={styles.infoLabel}>Volumes</Text>
                  <Text style={styles.infoValue}>{media.volumes}</Text>
                </View>
              );
            }
            rows.push(
              <View key="status" style={styles.infoRow}>
                <Text style={styles.infoLabel}>Status</Text>
                <Text style={styles.infoValue}>{formatStatus(media.status)}</Text>
              </View>
            );
            rows.push(
              <View key="startDate" style={styles.infoRow}>
                <Text style={styles.infoLabel}>Start Date</Text>
                <Text style={styles.infoValue}>{formatDate(media.startDate)}</Text>
              </View>
            );
            if (media.endDate?.year) {
              rows.push(
                <View key="endDate" style={styles.infoRow}>
                  <Text style={styles.infoLabel}>End Date</Text>
                  <Text style={styles.infoValue}>{formatDate(media.endDate)}</Text>
                </View>
              );
            }
            if (seasonText) {
              rows.push(
                <View key="season" style={styles.infoRow}>
                  <Text style={styles.infoLabel}>Season</Text>
                  <Text style={styles.infoValue}>{seasonText}</Text>
                </View>
              );
            }
            return rows.map((row, index) =>
              index === rows.length - 1
                ? React.cloneElement(row as React.ReactElement<{ style?: object }>, {
                    style: [styles.infoRow, styles.infoRowLast],
                  })
                : row
            );
          })()}
        </View>

        {media.description && (
          <View style={styles.descriptionSection}>
            <Text style={styles.sectionTitle}>Synopsis</Text>
            <Text style={styles.description}>{stripHtmlTags(media.description)}</Text>
          </View>
        )}

        {media.relations?.edges && media.relations.edges.filter((e) => e.relationType !== "ADAPTATION" && e.relationType !== "OTHER").length > 0 && (
          <View style={styles.relationsSection}>
            <Text style={styles.sectionTitle}>Relations</Text>
            <ScrollView
              horizontal
              showsHorizontalScrollIndicator={false}
              contentContainerStyle={styles.relationsContainer}
            >
              {media.relations.edges.filter((e) => e.relationType !== "ADAPTATION" && e.relationType !== "OTHER").map((edge) => (
                <Pressable
                  key={edge.node.id}
                  style={styles.relationCard}
                  onPress={() => navigation.navigate("MediaDetail", { mediaId: edge.node.id })}
                >
                  <Image
                    source={{ uri: edge.node.coverImage.medium }}
                    style={styles.relationCover}
                  />
                  <Text style={styles.relationType}>
                    {formatRelationType(edge.relationType)}
                  </Text>
                  <Text style={styles.relationTitle} numberOfLines={2}>
                    {edge.node.title.english || edge.node.title.romaji}
                  </Text>
                </Pressable>
              ))}
            </ScrollView>
          </View>
        )}
      </ScrollView>

      {refreshing && (
        <View style={styles.loadingOverlay}>
          <ActivityIndicator size="large" color={colors.primary} />
        </View>
      )}

      <Modal
        visible={scoreModalVisible}
        transparent
        animationType="fade"
        onRequestClose={() => setScoreModalVisible(false)}
      >
        <Pressable
          style={styles.modalOverlay}
          onPress={() => setScoreModalVisible(false)}
        >
          <View style={styles.scoreModal}>
            <Text style={styles.scoreModalTitle}>Rate this {media.type === "ANIME" ? "anime" : "manga"}</Text>
            <View style={styles.scoreOptions}>
              {[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10].map((score) => (
                <Pressable
                  key={score}
                  style={[
                    styles.scoreOption,
                    userEntry?.score === score && styles.scoreOptionSelected,
                  ]}
                  onPress={() => handleScoreUpdate(score)}
                  disabled={updatingScore}
                >
                  <Text
                    style={[
                      styles.scoreOptionText,
                      userEntry?.score === score && styles.scoreOptionTextSelected,
                    ]}
                  >
                    {score === 0 ? "−" : score}
                  </Text>
                </Pressable>
              ))}
            </View>
            {updatingScore && (
              <ActivityIndicator
                size="small"
                color={colors.primary}
                style={styles.scoreLoading}
              />
            )}
          </View>
        </Pressable>
      </Modal>

      <Modal
        visible={statusModalVisible}
        transparent
        animationType="fade"
        onRequestClose={() => setStatusModalVisible(false)}
      >
        <Pressable
          style={styles.modalOverlay}
          onPress={() => setStatusModalVisible(false)}
        >
          <View style={styles.statusModal}>
            <Text style={styles.statusModalTitle}>
              {userEntry ? "Update Status" : "Add to List"}
            </Text>
            <View style={styles.statusOptions}>
              {(
                [
                  { status: "CURRENT" as MediaStatus, label: media.type === "ANIME" ? "Watching" : "Reading" },
                  { status: "COMPLETED" as MediaStatus, label: "Completed" },
                  { status: "DROPPED" as MediaStatus, label: "Dropped" },
                  { status: "PLANNING" as MediaStatus, label: "Planning" },
                ] as const
              ).map((item) => (
                <Pressable
                  key={item.status}
                  style={[
                    styles.statusOption,
                    userEntry?.status === item.status && styles.statusOptionSelected,
                  ]}
                  onPress={() => userEntry ? handleStatusUpdate(item.status) : handleAddToList(item.status)}
                  disabled={updatingStatus || addingToList}
                >
                  <Text
                    style={[
                      styles.statusOptionText,
                      userEntry?.status === item.status && styles.statusOptionTextSelected,
                    ]}
                  >
                    {item.label}
                  </Text>
                  {userEntry?.status === item.status && (
                    <Ionicons name="checkmark" size={20} color={colors.background} />
                  )}
                </Pressable>
              ))}
            </View>
            {userEntry && (
              <Pressable
                style={styles.deleteButton}
                onPress={handleDeleteEntry}
                disabled={updatingStatus}
              >
                <Text style={styles.deleteButtonText}>Delete from List</Text>
              </Pressable>
            )}
            {(updatingStatus || addingToList) && (
              <ActivityIndicator
                size="small"
                color={colors.primary}
                style={styles.statusLoading}
              />
            )}
          </View>
        </Pressable>
      </Modal>

      <Modal
        visible={progressModalVisible}
        transparent
        animationType="fade"
        onRequestClose={() => setProgressModalVisible(false)}
      >
        <Pressable
          style={styles.modalOverlay}
          onPress={() => setProgressModalVisible(false)}
        >
          <View style={styles.progressModal}>
            <Text style={styles.progressModalTitle}>
              {media?.type === "ANIME" ? "Episode" : "Chapter"} Progress
            </Text>
            <View style={styles.progressControls}>
              <Pressable
                style={[styles.progressButton, (!userEntry || userEntry.progress <= 0) && styles.progressButtonDisabled]}
                onPress={() => handleProgressUpdate(-1)}
                disabled={updatingProgress || !userEntry || userEntry.progress <= 0}
              >
                <Ionicons name="remove" size={32} color={colors.textPrimary} />
              </Pressable>
              <View style={styles.progressDisplay}>
                {updatingProgress ? (
                  <ActivityIndicator size="small" color={colors.primary} />
                ) : (
                  <Text style={styles.progressValue}>
                    {userEntry?.progress || 0}
                  </Text>
                )}
                <Text style={styles.progressTotal}>
                  / {media?.type === "ANIME" ? (media?.episodes || "?") : (media?.chapters || "?")}
                </Text>
              </View>
              <Pressable
                style={[
                  styles.progressButton,
                  (() => {
                    if (!userEntry) return null;
                    if (media?.type === "ANIME" && media?.episodes && userEntry.progress >= media.episodes) {
                      return styles.progressButtonDisabled;
                    }
                    if (media?.type === "MANGA" && media?.chapters && userEntry.progress >= media.chapters) {
                      return styles.progressButtonDisabled;
                    }
                    return null;
                  })(),
                ]}
                onPress={() => handleProgressUpdate(1)}
                disabled={
                  updatingProgress ||
                  !userEntry ||
                  (media?.type === "ANIME" && media?.episodes ? userEntry.progress >= media.episodes : false) ||
                  (media?.type === "MANGA" && media?.chapters ? userEntry.progress >= media.chapters : false)
                }
              >
                <Ionicons name="add" size={32} color={colors.textPrimary} />
              </Pressable>
            </View>
          </View>
        </Pressable>
      </Modal>

      <Modal
        visible={watchLinkModalVisible}
        transparent
        animationType="fade"
        onRequestClose={() => setWatchLinkModalVisible(false)}
      >
        <Pressable
          style={styles.modalOverlay}
          onPress={() => setWatchLinkModalVisible(false)}
        >
          <Pressable style={styles.watchLinkModal} onPress={() => {}}>
            <Text style={styles.watchLinkModalTitle}>AnimeKai Link Override</Text>
            <Text style={styles.watchLinkModalHint}>
              Paste an AnimeKai watch URL, /watch path, or slug.
            </Text>
            <TextInput
              style={styles.watchLinkInput}
              placeholder="https://animekai.to/watch/... or /watch/... or slug"
              placeholderTextColor={colors.textSecondary}
              autoCapitalize="none"
              autoCorrect={false}
              value={watchLinkValue}
              onChangeText={(text) => {
                setWatchLinkValue(text);
                setWatchLinkValueError(null);
              }}
            />
            {watchLinkValueError && (
              <Text style={styles.watchLinkErrorText}>{watchLinkValueError}</Text>
            )}

            <View style={styles.watchLinkButtonsRow}>
              <Pressable style={styles.watchLinkSaveButton} onPress={handleSaveWatchLink}>
                <Text style={styles.watchLinkSaveText}>Save</Text>
              </Pressable>
              <Pressable
                style={styles.watchLinkCancelButton}
                onPress={() => setWatchLinkModalVisible(false)}
              >
                <Text style={styles.watchLinkCancelText}>Cancel</Text>
              </Pressable>
            </View>

            {hasWatchOverride && (
              <Pressable style={styles.watchLinkClearButton} onPress={handleClearWatchLink}>
                <Text style={styles.watchLinkClearText}>Clear Override</Text>
              </Pressable>
            )}
          </Pressable>
        </Pressable>
      </Modal>

      <Modal
        visible={watchCandidateModalVisible}
        transparent
        animationType="fade"
        onDismiss={() => {
          const url = pendingCandidateModalOpenUrlRef.current;
          pendingCandidateModalOpenUrlRef.current = null;
          if (!url) return;
          setWatchLoading(false);
          void openExternalUrl(url);
        }}
        onRequestClose={() => setWatchCandidateModalVisible(false)}
      >
        <Pressable
          style={styles.modalOverlay}
          onPress={() => {
            pendingCandidateModalOpenUrlRef.current = null;
            setWatchCandidateModalVisible(false);
            setWatchLoading(false);
          }}
        >
          <Pressable style={styles.watchCandidateModal} onPress={() => {}}>
            <Text style={styles.watchLinkModalTitle}>Choose AnimeKai Link</Text>
            <Text style={styles.watchLinkModalHint}>
              We found multiple results. Pick the correct one once and we will remember it.
            </Text>

            <ScrollView style={styles.watchCandidateList} contentContainerStyle={styles.watchCandidateListContent}>
              {watchCandidates.map((candidate) => (
                <Pressable
                  key={candidate.watchPath}
                  style={styles.watchCandidateRow}
                  onPress={() => void handleSelectCandidate(candidate)}
                >
                  <Text style={styles.watchCandidateTitle} numberOfLines={2}>
                    {candidate.title ?? candidate.watchPath.replace(/^\/watch\//, "")}
                  </Text>
                  <Text style={styles.watchCandidatePath} numberOfLines={1}>
                    {candidate.watchPath}
                  </Text>
                </Pressable>
              ))}
            </ScrollView>

            <View style={styles.watchLinkButtonsRow}>
              <Pressable
                style={styles.watchLinkCancelButton}
                onPress={() => {
                  pendingCandidateModalOpenUrlRef.current = null;
                  setWatchCandidateModalVisible(false);
                  setWatchLoading(false);
                }}
              >
                <Text style={styles.watchLinkCancelText}>Cancel</Text>
              </Pressable>
              <Pressable
                style={styles.watchLinkSaveButton}
                onPress={() => {
                  if (Platform.OS === "web") {
                    void Linking.openURL(ANIMEKAI_HOME_URL);
                    return;
                  }

                  if (Platform.OS === "ios") {
                    pendingCandidateModalOpenUrlRef.current = ANIMEKAI_HOME_URL;
                    setWatchLoading(true);
                    setWatchCandidateModalVisible(false);
                    return;
                  }

                  setWatchCandidateModalVisible(false);
                  setWatchLoading(false);
                  void openExternalUrl(ANIMEKAI_HOME_URL);
                }}
              >
                <Text style={styles.watchLinkSaveText}>AnimeKai Home</Text>
              </Pressable>
            </View>

            <Pressable style={styles.watchLinkClearButton} onPress={openWatchLinkEditor}>
              <Text style={styles.watchLinkClearText}>Paste Link Instead</Text>
            </Pressable>
          </Pressable>
        </Pressable>
      </Modal>
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
  studioLink: {
    color: colors.primary,
  },
  addButton: {
    backgroundColor: colors.primary,
    paddingHorizontal: 16,
    paddingVertical: 6,
    borderRadius: 6,
    marginTop: 8,
    alignSelf: "flex-start",
    minWidth: 50,
    alignItems: "center",
  },
  addButtonText: {
    fontSize: 14,
    fontWeight: "600",
    color: colors.textPrimary,
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
    alignItems: "center",
    paddingHorizontal: 16,
    paddingTop: 16,
    gap: 16,
  },
  statItem: {
    flexDirection: "row",
    alignItems: "center",
    gap: 4,
  },
  statItemTouchable: {
    flexDirection: "row",
    alignItems: "center",
    gap: 4,
    paddingVertical: 8,
    paddingHorizontal: 4,
    marginVertical: -8,
    marginHorizontal: -4,
  },
  statValue: {
    fontSize: 14,
    color: colors.textPrimary,
  },
  actionsRow: {
    flexDirection: "row",
    paddingHorizontal: 16,
    paddingTop: 12,
    gap: 16,
  },
  watchSection: {
    marginTop: 16,
    marginHorizontal: 16,
    backgroundColor: colors.surface,
    borderRadius: 12,
    padding: 16,
  },
  watchHint: {
    fontSize: 13,
    color: colors.textSecondary,
    marginTop: 8,
  },
  watchButton: {
    marginTop: 12,
    backgroundColor: colors.primary,
    borderRadius: 10,
    paddingVertical: 12,
    paddingHorizontal: 14,
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "center",
    gap: 10,
  },
  watchButtonDisabled: {
    opacity: 0.5,
  },
  watchButtonText: {
    fontSize: 15,
    fontWeight: "700",
    color: colors.textPrimary,
  },
  watchSpinner: {
    marginLeft: 8,
  },
  watchErrorText: {
    marginTop: 10,
    fontSize: 13,
    color: colors.error,
  },
  watchButtonsRow: {
    flexDirection: "row",
    gap: 12,
    marginTop: 12,
  },
  watchSecondaryButton: {
    flex: 1,
    backgroundColor: colors.surfaceLight,
    borderRadius: 10,
    paddingVertical: 10,
    alignItems: "center",
    justifyContent: "center",
  },
  watchSecondaryText: {
    fontSize: 13,
    fontWeight: "600",
    color: colors.textPrimary,
  },
  watchClearButton: {
    marginTop: 12,
    paddingVertical: 10,
    alignItems: "center",
    borderRadius: 10,
    backgroundColor: "rgba(239, 68, 68, 0.15)",
  },
  watchClearText: {
    fontSize: 13,
    fontWeight: "700",
    color: colors.error,
  },
  actionButton: {
    flexDirection: "row",
    alignItems: "center",
    gap: 6,
  },
  actionText: {
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
  infoRowLast: {
    borderBottomWidth: 0,
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
  relationsSection: {
    marginTop: 24,
  },
  relationsContainer: {
    paddingHorizontal: 16,
    gap: 12,
  },
  relationCard: {
    width: 100,
  },
  relationCover: {
    width: 100,
    height: 140,
    borderRadius: 8,
  },
  relationType: {
    fontSize: 11,
    color: colors.primary,
    marginTop: 6,
  },
  relationTitle: {
    fontSize: 12,
    color: colors.textPrimary,
    marginTop: 2,
  },
  modalOverlay: {
    flex: 1,
    backgroundColor: "rgba(0, 0, 0, 0.7)",
    justifyContent: "center",
    alignItems: "center",
  },
  watchLinkModal: {
    backgroundColor: colors.surface,
    borderRadius: 16,
    padding: 24,
    width: "85%",
    maxWidth: 360,
  },
  watchCandidateModal: {
    backgroundColor: colors.surface,
    borderRadius: 16,
    padding: 24,
    width: "90%",
    maxWidth: 380,
    maxHeight: "80%",
  },
  watchCandidateList: {
    marginTop: 10,
    marginBottom: 6,
  },
  watchCandidateListContent: {
    gap: 10,
    paddingBottom: 4,
  },
  watchCandidateRow: {
    backgroundColor: colors.surfaceLight,
    borderRadius: 12,
    paddingVertical: 12,
    paddingHorizontal: 12,
  },
  watchCandidateTitle: {
    fontSize: 14,
    fontWeight: "700",
    color: colors.textPrimary,
  },
  watchCandidatePath: {
    marginTop: 4,
    fontSize: 12,
    color: colors.textSecondary,
  },
  watchLinkModalTitle: {
    fontSize: 18,
    fontWeight: "bold",
    color: colors.textPrimary,
    textAlign: "center",
    marginBottom: 10,
  },
  watchLinkModalHint: {
    fontSize: 13,
    color: colors.textSecondary,
    textAlign: "center",
    marginBottom: 14,
  },
  watchLinkInput: {
    backgroundColor: colors.background,
    borderRadius: 12,
    paddingHorizontal: 14,
    paddingVertical: 12,
    color: colors.textPrimary,
    fontSize: 14,
  },
  watchLinkErrorText: {
    marginTop: 10,
    fontSize: 13,
    color: colors.error,
    textAlign: "center",
  },
  watchLinkButtonsRow: {
    flexDirection: "row",
    gap: 12,
    marginTop: 16,
  },
  watchLinkSaveButton: {
    flex: 1,
    backgroundColor: colors.primary,
    borderRadius: 12,
    paddingVertical: 12,
    alignItems: "center",
  },
  watchLinkSaveText: {
    fontSize: 14,
    fontWeight: "700",
    color: colors.textPrimary,
  },
  watchLinkCancelButton: {
    flex: 1,
    backgroundColor: colors.surfaceLight,
    borderRadius: 12,
    paddingVertical: 12,
    alignItems: "center",
  },
  watchLinkCancelText: {
    fontSize: 14,
    fontWeight: "700",
    color: colors.textPrimary,
  },
  watchLinkClearButton: {
    marginTop: 16,
    paddingVertical: 12,
    alignItems: "center",
    borderRadius: 12,
    backgroundColor: "rgba(239, 68, 68, 0.15)",
  },
  watchLinkClearText: {
    fontSize: 14,
    fontWeight: "700",
    color: colors.error,
  },
  scoreModal: {
    backgroundColor: colors.surface,
    borderRadius: 16,
    padding: 24,
    width: "85%",
    maxWidth: 340,
  },
  scoreModalTitle: {
    fontSize: 18,
    fontWeight: "bold",
    color: colors.textPrimary,
    textAlign: "center",
    marginBottom: 20,
  },
  scoreOptions: {
    flexDirection: "row",
    flexWrap: "wrap",
    justifyContent: "center",
    gap: 10,
  },
  scoreOption: {
    width: 48,
    height: 48,
    borderRadius: 24,
    backgroundColor: colors.background,
    justifyContent: "center",
    alignItems: "center",
  },
  scoreOptionSelected: {
    backgroundColor: colors.primary,
  },
  scoreOptionText: {
    fontSize: 16,
    fontWeight: "600",
    color: colors.textPrimary,
  },
  scoreOptionTextSelected: {
    color: colors.background,
  },
  scoreLoading: {
    marginTop: 16,
  },
  statusModal: {
    backgroundColor: colors.surface,
    borderRadius: 16,
    padding: 24,
    width: "85%",
    maxWidth: 340,
  },
  statusModalTitle: {
    fontSize: 18,
    fontWeight: "bold",
    color: colors.textPrimary,
    textAlign: "center",
    marginBottom: 20,
  },
  statusOptions: {
    gap: 10,
  },
  statusOption: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    paddingVertical: 14,
    paddingHorizontal: 16,
    borderRadius: 12,
    backgroundColor: colors.background,
  },
  statusOptionSelected: {
    backgroundColor: colors.primary,
  },
  statusOptionText: {
    fontSize: 16,
    fontWeight: "500",
    color: colors.textPrimary,
  },
  statusOptionTextSelected: {
    color: colors.background,
  },
  deleteButton: {
    marginTop: 20,
    paddingVertical: 14,
    alignItems: "center",
    borderRadius: 12,
    backgroundColor: "rgba(239, 68, 68, 0.15)",
  },
  deleteButtonText: {
    fontSize: 16,
    fontWeight: "600",
    color: colors.error,
  },
  statusLoading: {
    marginTop: 16,
  },
  progressModal: {
    backgroundColor: colors.surface,
    borderRadius: 16,
    padding: 24,
    width: "85%",
    maxWidth: 340,
  },
  progressModalTitle: {
    fontSize: 18,
    fontWeight: "bold",
    color: colors.textPrimary,
    textAlign: "center",
    marginBottom: 24,
  },
  progressControls: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "center",
    gap: 24,
  },
  progressButton: {
    width: 56,
    height: 56,
    borderRadius: 28,
    backgroundColor: colors.background,
    justifyContent: "center",
    alignItems: "center",
  },
  progressButtonDisabled: {
    opacity: 0.4,
  },
  progressDisplay: {
    flexDirection: "row",
    alignItems: "baseline",
    minWidth: 80,
    justifyContent: "center",
  },
  progressValue: {
    fontSize: 32,
    fontWeight: "bold",
    color: colors.textPrimary,
  },
  progressTotal: {
    fontSize: 18,
    color: colors.textSecondary,
    marginLeft: 2,
  },
});
