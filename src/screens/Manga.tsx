import { useState, useEffect } from "react";
import {
  StyleSheet,
  Text,
  View,
  TextInput,
  Keyboard,
  Modal,
  TouchableOpacity,
  Pressable,
  ScrollView,
  RefreshControl,
} from "react-native";
import { Ionicons } from "@expo/vector-icons";
import { useIsFocused } from "@react-navigation/native";

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
  const isFocused = useIsFocused();

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
    // TODO: Fetch data from AniList API
    setTimeout(() => {
      setRefreshing(false);
    }, 500);
  };

  const handleScroll = (event: { nativeEvent: { contentOffset: { y: number } } }) => {
    const offsetY = event.nativeEvent.contentOffset.y;
    // Show search when pulling down (negative offset) past threshold
    if (offsetY < -50 && !showSearch) {
      setShowSearch(true);
    }
  };

  return (
    <View style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.title}>{selectedFilter}</Text>
      </View>

      <ScrollView
        contentContainerStyle={styles.scrollContent}
        alwaysBounceVertical={true}
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
      >
        {showSearch && (
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
        )}
        <Pressable style={styles.content} onPress={Keyboard.dismiss}>
          <Text style={styles.emptyText}>Your manga list will appear here</Text>
        </Pressable>
      </ScrollView>

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
  scrollContent: {
    flexGrow: 1,
    minHeight: "100%",
  },
  content: {
    flex: 1,
    alignItems: "center",
    justifyContent: "center",
    paddingVertical: 100,
  },
  emptyText: {
    fontSize: 16,
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
