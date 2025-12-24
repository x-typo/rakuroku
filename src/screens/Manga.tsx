import { useState, useEffect, useCallback, useMemo } from "react";
import {
  StyleSheet,
  Text,
  View,
  TextInput,
  Modal,
  TouchableOpacity,
  Pressable,
  FlatList,
  RefreshControl,
  Image,
  ActivityIndicator,
} from "react-native";
import { Ionicons } from "@expo/vector-icons";
import { useIsFocused } from "@react-navigation/native";
import {
  fetchMediaList,
  filterByStatus,
  searchEntries,
  MediaListEntry,
} from "../api";

const FILTERS = ["All", "Reading", "Completed", "Dropped", "Planning"] as const;
type Filter = (typeof FILTERS)[number];

interface MangaScreenProps {
  showFilterModal?: boolean;
  onCloseFilterModal?: () => void;
}

export default function MangaScreen({
  showFilterModal = false,
  onCloseFilterModal,
}: MangaScreenProps) {
  const [searchQuery, setSearchQuery] = useState("");
  const [selectedFilter, setSelectedFilter] = useState<Filter>("All");
  const [showSearch, setShowSearch] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const [loading, setLoading] = useState(true);
  const [entries, setEntries] = useState<MediaListEntry[]>([]);
  const [error, setError] = useState<string | null>(null);
  const isFocused = useIsFocused();

  const loadData = useCallback(async () => {
    try {
      setError(null);
      const data = await fetchMediaList("MANGA");
      setEntries(data);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to load data");
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, []);

  useEffect(() => {
    loadData();
  }, [loadData]);

  useEffect(() => {
    if (!isFocused) {
      setShowSearch(false);
      setSearchQuery("");
    }
  }, [isFocused]);

  const handleFilterSelect = (filter: Filter) => {
    setSelectedFilter(filter);
    setShowSearch(false);
    setSearchQuery("");
    onCloseFilterModal?.();
  };

  const handleRefresh = () => {
    setRefreshing(true);
    loadData();
  };

  const handleScroll = (event: { nativeEvent: { contentOffset: { y: number } } }) => {
    const offsetY = event.nativeEvent.contentOffset.y;
    if (offsetY < -50 && !showSearch) {
      setShowSearch(true);
    }
  };

  const filteredEntries = useMemo(
    () => searchEntries(filterByStatus(entries, selectedFilter), searchQuery),
    [entries, selectedFilter, searchQuery]
  );

  const getProgressText = (entry: MediaListEntry) => {
    const total = entry.media.chapters;
    if (total) {
      return `${entry.progress}/${total}`;
    }
    return `${entry.progress}`;
  };

  const renderItem = useCallback(
    ({ item }: { item: MediaListEntry }) => (
      <View style={styles.entryCard}>
        <Image
          source={{ uri: item.media.coverImage.medium }}
          style={styles.coverImage}
        />
        <View style={styles.entryInfo}>
          <Text style={styles.entryTitle} numberOfLines={2}>
            {item.media.title.english || item.media.title.romaji}
          </Text>
          <Text style={styles.entryProgress}>{getProgressText(item)}</Text>
        </View>
      </View>
    ),
    []
  );

  const renderHeader = () => {
    if (!showSearch) return null;
    return (
      <View style={styles.searchContainer}>
        <TextInput
          style={styles.searchBar}
          placeholder="Search"
          placeholderTextColor="#9CA3AF"
          value={searchQuery}
          onChangeText={setSearchQuery}
          autoFocus
        />
        {searchQuery.length > 0 && (
          <TouchableOpacity
            style={styles.clearButton}
            onPress={() => setSearchQuery("")}
          >
            <Ionicons name="close-circle" size={20} color="#9CA3AF" />
          </TouchableOpacity>
        )}
      </View>
    );
  };

  const renderEmpty = () => (
    <View style={styles.centered}>
      <Text style={styles.emptyText}>
        {searchQuery ? "No results found" : "No manga in this list"}
      </Text>
    </View>
  );

  const renderContent = () => {
    if (loading) {
      return (
        <View style={styles.centered}>
          <ActivityIndicator size="large" color="#3B82F6" />
        </View>
      );
    }

    if (error) {
      return (
        <View style={styles.centered}>
          <Text style={styles.errorText}>{error}</Text>
          <TouchableOpacity style={styles.retryButton} onPress={loadData}>
            <Text style={styles.retryText}>Retry</Text>
          </TouchableOpacity>
        </View>
      );
    }

    return (
      <FlatList
        data={filteredEntries}
        renderItem={renderItem}
        keyExtractor={(item) => item.id.toString()}
        ListHeaderComponent={renderHeader}
        ListEmptyComponent={renderEmpty}
        keyboardShouldPersistTaps="handled"
        keyboardDismissMode="on-drag"
        onScroll={handleScroll}
        scrollEventThrottle={16}
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            onRefresh={handleRefresh}
            tintColor="#3B82F6"
          />
        }
      />
    );
  };

  return (
    <View style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.title}>{selectedFilter}</Text>
      </View>

      {renderContent()}

      <Modal
        visible={showFilterModal}
        transparent
        animationType="slide"
        onRequestClose={onCloseFilterModal}
      >
        <Pressable style={styles.modalOverlay} onPress={onCloseFilterModal}>
          <View style={styles.modalContent}>
            <Text style={styles.modalTitle}>Manga List</Text>
            {FILTERS.map((filter) => (
              <TouchableOpacity
                key={filter}
                style={[
                  styles.filterOption,
                  selectedFilter === filter && styles.filterOptionSelected,
                ]}
                onPress={() => handleFilterSelect(filter)}
              >
                <Text
                  style={[
                    styles.filterText,
                    selectedFilter === filter && styles.filterTextSelected,
                  ]}
                >
                  {filter}
                </Text>
              </TouchableOpacity>
            ))}
          </View>
        </Pressable>
      </Modal>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: "#000",
  },
  header: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
    paddingHorizontal: 16,
    paddingTop: 16,
    paddingBottom: 8,
  },
  title: {
    fontSize: 28,
    fontWeight: "bold",
    color: "#fff",
  },
  searchContainer: {
    flexDirection: "row",
    alignItems: "center",
    marginHorizontal: 16,
    marginBottom: 8,
  },
  searchBar: {
    flex: 1,
    backgroundColor: "#1c1c1e",
    color: "#fff",
    paddingHorizontal: 16,
    paddingVertical: 12,
    paddingRight: 40,
    borderRadius: 10,
    fontSize: 16,
  },
  clearButton: {
    position: "absolute",
    right: 12,
    top: 0,
    bottom: 0,
    justifyContent: "center",
  },
  centered: {
    flex: 1,
    alignItems: "center",
    justifyContent: "center",
    paddingVertical: 100,
  },
  emptyText: {
    fontSize: 16,
    color: "#9CA3AF",
  },
  errorText: {
    fontSize: 16,
    color: "#EF4444",
    marginBottom: 16,
  },
  retryButton: {
    backgroundColor: "#3B82F6",
    paddingHorizontal: 24,
    paddingVertical: 12,
    borderRadius: 8,
  },
  retryText: {
    color: "#fff",
    fontSize: 16,
    fontWeight: "600",
  },
  entryCard: {
    flexDirection: "row",
    padding: 12,
    borderBottomWidth: 1,
    borderBottomColor: "#1c1c1e",
  },
  coverImage: {
    width: 60,
    height: 85,
    borderRadius: 6,
    backgroundColor: "#1c1c1e",
  },
  entryInfo: {
    flex: 1,
    marginLeft: 12,
    justifyContent: "center",
  },
  entryTitle: {
    fontSize: 16,
    fontWeight: "600",
    color: "#fff",
    marginBottom: 4,
  },
  entryProgress: {
    fontSize: 14,
    color: "#9CA3AF",
  },
  modalOverlay: {
    flex: 1,
    backgroundColor: "rgba(0, 0, 0, 0.5)",
    justifyContent: "flex-end",
  },
  modalContent: {
    backgroundColor: "#1c1c1e",
    borderTopLeftRadius: 20,
    borderTopRightRadius: 20,
    paddingTop: 20,
    paddingBottom: 40,
    paddingHorizontal: 16,
  },
  modalTitle: {
    fontSize: 20,
    fontWeight: "bold",
    color: "#fff",
    textAlign: "center",
    marginBottom: 20,
  },
  filterOption: {
    paddingVertical: 16,
    paddingHorizontal: 16,
    borderRadius: 10,
  },
  filterOptionSelected: {
    backgroundColor: "#3B82F6",
  },
  filterText: {
    fontSize: 18,
    color: "#fff",
  },
  filterTextSelected: {
    fontWeight: "bold",
  },
});
