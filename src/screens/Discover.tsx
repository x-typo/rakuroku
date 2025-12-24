import { useState, useEffect, useCallback } from "react";
import {
  StyleSheet,
  Text,
  View,
  ScrollView,
  RefreshControl,
  Image,
  Pressable,
  ActivityIndicator,
} from "react-native";
import { useNavigation } from "@react-navigation/native";
import { NativeStackNavigationProp } from "@react-navigation/native-stack";
import { Ionicons } from "@expo/vector-icons";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { colors } from "../constants";
import { fetchSeasonalAnime, getSeasonInfo } from "../api";
import { SeasonalMedia, Season } from "../types";
import { RootStackParamList } from "../../App";

type NavigationProp = NativeStackNavigationProp<RootStackParamList>;

function formatSeasonName(season: Season): string {
  return season.charAt(0) + season.slice(1).toLowerCase();
}

function getMainStudio(media: SeasonalMedia): string | null {
  if (!media.studios?.edges) return null;
  const mainStudio = media.studios.edges.find((e) => e.isMain);
  return mainStudio?.node.name || media.studios.edges[0]?.node.name || null;
}

export default function DiscoverScreen() {
  const navigation = useNavigation<NavigationProp>();
  const insets = useSafeAreaInsets();

  const [currentSeasonAnime, setCurrentSeasonAnime] = useState<SeasonalMedia[]>([]);
  const [nextSeasonAnime, setNextSeasonAnime] = useState<SeasonalMedia[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const seasonInfo = getSeasonInfo();

  const loadData = useCallback(async (showRefreshing = false) => {
    if (showRefreshing) {
      setRefreshing(true);
    } else {
      setLoading(true);
    }
    setError(null);

    try {
      const [currentPage, nextPage] = await Promise.all([
        fetchSeasonalAnime(seasonInfo.current.season, seasonInfo.current.year, 1, 20, "POPULARITY_DESC"),
        fetchSeasonalAnime(seasonInfo.next.season, seasonInfo.next.year, 1, 20, "POPULARITY_DESC"),
      ]);
      setCurrentSeasonAnime(currentPage.media);
      setNextSeasonAnime(nextPage.media);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to load seasonal anime");
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [seasonInfo.current.season, seasonInfo.current.year, seasonInfo.next.season, seasonInfo.next.year]);

  useEffect(() => {
    loadData();
  }, [loadData]);

  const renderMediaCard = (item: SeasonalMedia) => {
    const title = item.title.english || item.title.romaji;
    const studio = getMainStudio(item);

    return (
      <Pressable
        key={item.id}
        style={styles.mediaCard}
        onPress={() => navigation.navigate("MediaDetail", { mediaId: item.id })}
      >
        <Image source={{ uri: item.coverImage.large }} style={styles.coverImage} />
        <Text style={styles.mediaTitle} numberOfLines={2}>
          {title}
        </Text>
        {studio && (
          <Text style={styles.studioName} numberOfLines={1}>
            {studio}
          </Text>
        )}
        {item.averageScore && (
          <View style={styles.scoreContainer}>
            <Ionicons name="bar-chart" size={10} color={colors.primary} />
            <Text style={styles.scoreText}>{item.averageScore}%</Text>
          </View>
        )}
      </Pressable>
    );
  };

  const renderSection = (
    label: string,
    season: Season,
    year: number,
    data: SeasonalMedia[]
  ) => (
    <View style={styles.section}>
      <Pressable
        style={styles.sectionHeader}
        onPress={() => navigation.navigate("SeasonList", { season, year, label })}
      >
        <View>
          <Text style={styles.sectionTitle}>{label}</Text>
          <Text style={styles.sectionSubtitle}>
            {formatSeasonName(season)} {year}
          </Text>
        </View>
        <Ionicons name="chevron-forward" size={20} color={colors.textSecondary} />
      </Pressable>
      <ScrollView
        horizontal
        showsHorizontalScrollIndicator={false}
        contentContainerStyle={styles.horizontalList}
      >
        {data.map(renderMediaCard)}
      </ScrollView>
    </View>
  );

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
      <ScrollView
        contentContainerStyle={[styles.content, { paddingTop: insets.top + 16 }]}
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            onRefresh={() => loadData(true)}
            tintColor={colors.primary}
          />
        }
      >
        {renderSection(
          "Current Season",
          seasonInfo.current.season,
          seasonInfo.current.year,
          currentSeasonAnime
        )}

        {renderSection(
          "Upcoming Season",
          seasonInfo.next.season,
          seasonInfo.next.year,
          nextSeasonAnime
        )}
      </ScrollView>
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
  content: {
    paddingBottom: 24,
  },
  section: {
    marginBottom: 24,
  },
  sectionHeader: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
    paddingHorizontal: 16,
    marginBottom: 12,
  },
  sectionTitle: {
    fontSize: 20,
    fontWeight: "600",
    color: colors.textPrimary,
  },
  sectionSubtitle: {
    fontSize: 14,
    color: colors.textSecondary,
    marginTop: 2,
  },
  horizontalList: {
    paddingHorizontal: 16,
    gap: 12,
  },
  mediaCard: {
    width: 120,
  },
  coverImage: {
    width: 120,
    height: 170,
    borderRadius: 8,
    backgroundColor: colors.surface,
  },
  mediaTitle: {
    fontSize: 13,
    fontWeight: "500",
    color: colors.textPrimary,
    marginTop: 8,
  },
  studioName: {
    fontSize: 11,
    color: colors.textSecondary,
    marginTop: 2,
  },
  scoreContainer: {
    flexDirection: "row",
    alignItems: "center",
    gap: 4,
    marginTop: 4,
  },
  scoreText: {
    fontSize: 11,
    color: colors.textSecondary,
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
