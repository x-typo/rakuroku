import { StyleSheet, Text, View, Image } from "react-native";
import { colors } from "../constants";
import { MediaListEntry } from "../types";

interface MediaCardProps {
  entry: MediaListEntry;
  type: "ANIME" | "MANGA";
}

export function MediaCard({ entry, type }: MediaCardProps) {
  const getProgressText = () => {
    const total = type === "ANIME" ? entry.media.episodes : entry.media.chapters;
    if (total) {
      return `${entry.progress}/${total}`;
    }
    return `${entry.progress}`;
  };

  return (
    <View style={styles.container}>
      <Image
        source={{ uri: entry.media.coverImage.medium }}
        style={styles.coverImage}
      />
      <View style={styles.info}>
        <Text style={styles.title} numberOfLines={2}>
          {entry.media.title.english || entry.media.title.romaji}
        </Text>
        <Text style={styles.progress}>{getProgressText()}</Text>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flexDirection: "row",
    padding: 12,
    borderBottomWidth: 1,
    borderBottomColor: colors.surface,
  },
  coverImage: {
    width: 60,
    height: 85,
    borderRadius: 6,
    backgroundColor: colors.surface,
  },
  info: {
    flex: 1,
    marginLeft: 12,
    justifyContent: "center",
  },
  title: {
    fontSize: 16,
    fontWeight: "600",
    color: colors.textPrimary,
    marginBottom: 4,
  },
  progress: {
    fontSize: 14,
    color: colors.textSecondary,
  },
});
