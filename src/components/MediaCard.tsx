import { StyleSheet, Text, View, Image, Pressable, Keyboard } from "react-native";
import { useNavigation } from "@react-navigation/native";
import { NativeStackNavigationProp } from "@react-navigation/native-stack";
import { colors } from "../constants";
import { MediaListEntry } from "../types";
import { RootStackParamList } from "../../App";

type NavigationProp = NativeStackNavigationProp<RootStackParamList>;

interface MediaCardProps {
  entry: MediaListEntry;
  type: "ANIME" | "MANGA";
}

function formatNextAiring(airingAt: number): string {
  const now = Date.now() / 1000;
  const diff = airingAt - now;

  if (diff < 0) return "";
  if (diff < 3600) return `${Math.floor(diff / 60)}m`;
  if (diff < 86400) return `${Math.floor(diff / 3600)}h`;
  return `${Math.floor(diff / 86400)}d`;
}

export function MediaCard({ entry, type }: MediaCardProps) {
  const navigation = useNavigation<NavigationProp>();
  const total = type === "ANIME" ? entry.media.episodes : entry.media.chapters;
  const progressPercent = total ? (entry.progress / total) * 100 : 0;
  const showProgressBar = total && total > 0;

  const nextAiring = entry.media.nextAiringEpisode;
  const episodesBehind = nextAiring ? nextAiring.episode - 1 - entry.progress : 0;

  const getProgressText = () => {
    if (total) {
      return `${entry.progress}/${total}`;
    }
    return `${entry.progress}`;
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

  return (
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
  );
}

const styles = StyleSheet.create({
  container: {
    backgroundColor: colors.surface,
    borderRadius: 12,
    marginHorizontal: 16,
    marginBottom: 12,
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
    backgroundColor: "#2c2c2e",
  },
  progressBar: {
    height: "100%",
    backgroundColor: colors.primary,
  },
});
