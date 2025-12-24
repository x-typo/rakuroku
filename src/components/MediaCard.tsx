import { StyleSheet, Text, View, Image } from "react-native";
import { colors } from "../constants";
import { MediaListEntry } from "../types";

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

  const getScoreText = () => {
    if (entry.score > 0) {
      return `★ ${entry.score}`;
    }
    return null;
  };

  return (
    <View style={styles.container}>
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
            {getScoreText() && (
              <Text style={styles.score}>{getScoreText()}</Text>
            )}
            {episodesBehind > 0 && (
              <Text style={styles.behind}>
                {episodesBehind} ep behind
              </Text>
            )}
          </View>
          {nextAiring && type === "ANIME" && (
            <Text style={styles.nextAiring}>
              Ep {nextAiring.episode} in {formatNextAiring(nextAiring.airingAt)}
            </Text>
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
    </View>
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
    height: 110,
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
    color: colors.warning,
  },
  behind: {
    fontSize: 14,
    color: colors.error,
  },
  nextAiring: {
    fontSize: 13,
    color: colors.primary,
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
