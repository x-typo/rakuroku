import { useState, useEffect, useCallback, useRef } from "react";
import {
  StyleSheet,
  Text,
  View,
  ScrollView,
  FlatList,
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
import { fetchSeasonalAnime, getSeasonInfo, searchMedia } from "../api";
import { SeasonalMedia, Season } from "../types";
import { RootStackParamList } from "../../App";
import { SearchBar } from "../components";

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
  const [searchResults, setSearchResults] = useState<SeasonalMedia[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [searching, setSearching] = useState(false);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [searchQuery, setSearchQuery] = useState("");
  const [hasNextPage, setHasNextPage] = useState(false);
  const currentPage = useRef(1);
  const searchDebounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);

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

  const performSearch = useCallback(async (query: string) => {
    if (!query.trim()) {
      setSearchResults([]);
      setSearching(false);
      return;
    }

    setSearching(true);
    currentPage.current = 1;

    try {
      const result = await searchMedia(query, 1, 25);
      setSearchResults(result.media);
      setHasNextPage(result.hasNextPage);
    } catch (err) {
      // Silently fail on search - user can try again
    } finally {
      setSearching(false);
    }
  }, []);

  const loadMoreSearchResults = useCallback(async () => {
    if (loadingMore || !hasNextPage || !searchQuery.trim()) return;

    setLoadingMore(true);
    const nextPage = currentPage.current + 1;

    try {
      const result = await searchMedia(searchQuery, nextPage, 25);
      setSearchResults((prev) => [...prev, ...result.media]);
      setHasNextPage(result.hasNextPage);
      currentPage.current = nextPage;
    } catch (err) {
      // Silently fail on load more
    } finally {
      setLoadingMore(false);
    }
  }, [searchQuery, loadingMore, hasNextPage]);

  useEffect(() => {
    loadData();
  }, [loadData]);

  useEffect(() => {
    if (searchDebounceRef.current) {
      clearTimeout(searchDebounceRef.current);
    }

    if (!searchQuery.trim()) {
      setSearchResults([]);
      setSearching(false);
      return;
    }

    setSearching(true);
    searchDebounceRef.current = setTimeout(() => {
      performSearch(searchQuery);
    }, 300);

    return () => {
      if (searchDebounceRef.current) {
        clearTimeout(searchDebounceRef.current);
      }
    };
  }, [searchQuery, performSearch]);

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

  const renderSearchResultItem = useCallback(
    ({ item }: { item: SeasonalMedia }) => {
      const title = item.title.english || item.title.romaji;
      const studio = getMainStudio(item);

      return (
        <Pressable
          style={styles.searchResultItem}
          onPress={() => navigation.navigate("MediaDetail", { mediaId: item.id })}
        >
          <Image
            source={{ uri: item.coverImage.medium }}
            style={styles.searchResultCover}
          />
          <View style={styles.searchResultInfo}>
            <Text style={styles.searchResultTitle} numberOfLines={2}>
              {title}
            </Text>
            {studio && (
              <Text style={styles.searchResultStudio} numberOfLines={1}>
                {studio}
              </Text>
            )}
            <View style={styles.searchResultMeta}>
              {item.averageScore && (
                <View style={styles.scoreContainer}>
                  <Ionicons name="bar-chart" size={12} color={colors.primary} />
                  <Text style={styles.scoreText}>{item.averageScore}%</Text>
                </View>
              )}
              {item.format && (
                <Text style={styles.formatText}>{item.format}</Text>
              )}
            </View>
          </View>
        </Pressable>
      );
    },
    [navigation]
  );

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

  const renderSearchFooter = () => {
    if (!loadingMore) return null;
    return (
      <View style={styles.footerLoader}>
        <ActivityIndicator size="small" color={colors.primary} />
      </View>
    );
  };

  const isSearching = searchQuery.trim().length > 0;

  if (loading && !isSearching) {
    return (
      <View style={[styles.container, styles.centered]}>
        <ActivityIndicator size="large" color={colors.primary} />
      </View>
    );
  }

  if (error && !isSearching) {
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
    <View style={[styles.container, { paddingTop: insets.top + 16 }]}>
      <View style={styles.searchBarContainer}>
        <SearchBar
          value={searchQuery}
          onChangeText={setSearchQuery}
          onClear={() => setSearchQuery("")}
        />
      </View>

      {isSearching ? (
        searching && searchResults.length === 0 ? (
          <View style={[styles.container, styles.centered]}>
            <ActivityIndicator size="large" color={colors.primary} />
          </View>
        ) : searchResults.length === 0 ? (
          <View style={[styles.container, styles.centered]}>
            <Text style={styles.emptyText}>No results found</Text>
          </View>
        ) : (
          <FlatList
            data={searchResults}
            renderItem={renderSearchResultItem}
            keyExtractor={(item) => item.id.toString()}
            contentContainerStyle={styles.searchResultsList}
            onEndReached={loadMoreSearchResults}
            onEndReachedThreshold={0.5}
            ListFooterComponent={renderSearchFooter}
            keyboardShouldPersistTaps="handled"
            keyboardDismissMode="on-drag"
          />
        )
      ) : (
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
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  searchBarContainer: {
    marginBottom: 16,
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
  emptyText: {
    fontSize: 16,
    color: colors.textSecondary,
    textAlign: "center",
  },
  searchResultsList: {
    paddingBottom: 24,
  },
  searchResultItem: {
    flexDirection: "row",
    paddingHorizontal: 16,
    paddingVertical: 12,
  },
  searchResultCover: {
    width: 70,
    height: 100,
    borderRadius: 6,
    backgroundColor: colors.surface,
  },
  searchResultInfo: {
    flex: 1,
    marginLeft: 12,
    justifyContent: "center",
  },
  searchResultTitle: {
    fontSize: 15,
    fontWeight: "600",
    color: colors.textPrimary,
    marginBottom: 4,
  },
  searchResultStudio: {
    fontSize: 13,
    color: colors.textSecondary,
    marginBottom: 4,
  },
  searchResultMeta: {
    flexDirection: "row",
    alignItems: "center",
    gap: 12,
  },
  formatText: {
    fontSize: 12,
    color: colors.textSecondary,
  },
  footerLoader: {
    paddingVertical: 16,
    alignItems: "center",
  },
});
