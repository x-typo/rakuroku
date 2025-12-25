import { useState, useRef } from "react";
import { StyleSheet, Text, View, Image, Pressable, Keyboard, ActivityIndicator } from "react-native";
import { useNavigation } from "@react-navigation/native";
import { NativeStackNavigationProp } from "@react-navigation/native-stack";
import { Swipeable } from "react-native-gesture-handler";
import { Ionicons } from "@expo/vector-icons";
import { colors } from "../constants";
import { MediaListEntry } from "../types";
import { updateProgress } from "../api";
import { useAuth } from "../context";
import { RootStackParamList } from "../../App";

type NavigationProp = NativeStackNavigationProp<RootStackParamList>;

interface MediaCardProps {
  entry: MediaListEntry;
  type: "ANIME" | "MANGA";
  onProgressUpdate?: (entryId: number, newProgress: number) => void;
}

function formatNextAiring(airingAt: number): string {
  const now = Date.now() / 1000;
  const diff = airingAt - now;

  if (diff < 0) return "";
  if (diff < 3600) return `${Math.floor(diff / 60)}m`;
  if (diff < 86400) return `${Math.floor(diff / 3600)}h`;
  return `${Math.floor(diff / 86400)}d`;
}

export function MediaCard({ entry, type, onProgressUpdate }: MediaCardProps) {
  const navigation = useNavigation<NavigationProp>();
  const { accessToken, isAuthenticated } = useAuth();
  const [isUpdating, setIsUpdating] = useState(false);
  const [localProgress, setLocalProgress] = useState(entry.progress);
  const swipeableRef = useRef<Swipeable>(null);

  const total = type === "ANIME" ? entry.media.episodes : entry.media.chapters;
  const progressPercent = total ? (localProgress / total) * 100 : 0;
  const showProgressBar = total && total > 0;
  const canIncrement = !total || localProgress < total;
  const canDecrement = localProgress > 0;

  const nextAiring = entry.media.nextAiringEpisode;
  const episodesBehind = nextAiring ? nextAiring.episode - 1 - localProgress : 0;

  const getProgressText = () => {
    if (total) {
      return `${localProgress}/${total}`;
    }
    return `${localProgress}`;
  };

  const getScoreColor = () => {
    if (entry.score >= 8) return colors.success;
    if (entry.score >= 5) return colors.warning;
    return colors.error;
  };

  const getScoreText = () => {
    if (entry.score > 0) {
      return `★ ${entry.score}`;
    }
    return null;
  };

  const handleProgressChange = async (delta: number) => {
    if (!isAuthenticated || !accessToken || isUpdating) return;
    if (delta > 0 && !canIncrement) return;
    if (delta < 0 && !canDecrement) return;

    const newProgress = localProgress + delta;
    setIsUpdating(true);
    setLocalProgress(newProgress);

    try {
      await updateProgress(entry.media.id, newProgress, accessToken);
      onProgressUpdate?.(entry.id, newProgress);
    } catch (error) {
      // Revert on failure
      setLocalProgress(localProgress);
    } finally {
      setIsUpdating(false);
    }
  };

  const renderLeftActions = () => {
    if (!isAuthenticated || !canDecrement) return null;
    return (
      <View style={styles.swipeAction}>
        <Ionicons name="remove-circle" size={28} color={colors.textPrimary} />
        <Text style={styles.swipeActionText}>-1</Text>
      </View>
    );
  };

  const renderRightActions = () => {
    if (!isAuthenticated || !canIncrement) return null;
    return (
      <View style={[styles.swipeAction, styles.swipeActionRight]}>
        <Text style={styles.swipeActionText}>+1</Text>
        <Ionicons name="add-circle" size={28} color={colors.textPrimary} />
      </View>
    );
  };

  const handleSwipeOpen = (direction: "left" | "right") => {
    if (isUpdating) return;
    if (direction === "right") {
      // Opened right side (swiped left) = increment
      handleProgressChange(1);
    } else {
      // Opened left side (swiped right) = decrement
      handleProgressChange(-1);
    }
    swipeableRef.current?.close();
  };

  return (
    <Swipeable
      ref={swipeableRef}
      renderLeftActions={renderLeftActions}
      renderRightActions={renderRightActions}
      onSwipeableOpen={handleSwipeOpen}
      overshootLeft={false}
      overshootRight={false}
      containerStyle={styles.swipeableContainer}
    >
      <Pressable
        style={styles.container}
        onPress={() => {
          Keyboard.dismiss();
          navigation.navigate("MediaDetail", { mediaId: entry.media.id });
        }}
      >
        <View style={styles.row}>
          <Image
            source={{ uri: entry.media.coverImage.medium }}
            style={styles.coverImage}
          />
          <View style={styles.info}>
            <Text style={styles.title} numberOfLines={2}>
              {entry.media.title.english || entry.media.title.romaji}
            </Text>
            <View style={styles.metaRow}>
              <Text style={styles.progress}>{getProgressText()}</Text>
              {isUpdating && (
                <ActivityIndicator size="small" color={colors.primary} />
              )}
              {episodesBehind > 0 && (
                <Text style={styles.behind}>
                  {episodesBehind} {episodesBehind === 1 ? "episode" : "episodes"} behind
                </Text>
              )}
            </View>
            {nextAiring && type === "ANIME" && (
              <Text style={styles.nextAiring}>
                Episode {nextAiring.episode} airing in {formatNextAiring(nextAiring.airingAt)}
              </Text>
            )}
            {getScoreText() && (
              <Text style={[styles.score, { color: getScoreColor() }]}>{getScoreText()}</Text>
            )}
          </View>
        </View>
        {showProgressBar && (
          <View style={styles.progressBarContainer}>
            <View
              style={[styles.progressBar, { width: `${Math.min(progressPercent, 100)}%` }]}
            />
          </View>
        )}
      </Pressable>
    </Swipeable>
  );
}

const styles = StyleSheet.create({
  swipeableContainer: {
    marginHorizontal: 16,
    marginBottom: 12,
  },
  container: {
    backgroundColor: colors.surface,
    borderRadius: 12,
    overflow: "hidden",
  },
  row: {
    flexDirection: "row",
  },
  coverImage: {
    width: 80,
    height: 130,
  },
  info: {
    flex: 1,
    padding: 12,
    justifyContent: "center",
  },
  title: {
    fontSize: 16,
    fontWeight: "600",
    color: colors.textPrimary,
    marginBottom: 6,
  },
  metaRow: {
    flexDirection: "row",
    alignItems: "center",
    flexWrap: "wrap",
    gap: 8,
  },
  progress: {
    fontSize: 14,
    color: colors.textSecondary,
  },
  score: {
    fontSize: 14,
    marginTop: 4,
  },
  behind: {
    fontSize: 14,
    color: colors.error,
  },
  nextAiring: {
    fontSize: 13,
    color: colors.warning,
    marginTop: 4,
  },
  progressBarContainer: {
    height: 3,
    backgroundColor: colors.surfaceLight,
  },
  progressBar: {
    height: "100%",
    backgroundColor: colors.primary,
  },
  swipeAction: {
    backgroundColor: colors.primary,
    justifyContent: "center",
    alignItems: "center",
    flexDirection: "row",
    paddingHorizontal: 20,
    gap: 4,
    borderRadius: 12,
  },
  swipeActionRight: {
    backgroundColor: colors.primary,
  },
  swipeActionText: {
    color: colors.textPrimary,
    fontSize: 16,
    fontWeight: "600",
  },
});
