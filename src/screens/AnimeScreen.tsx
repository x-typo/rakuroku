import { useState } from "react";
import {
  StyleSheet,
  Text,
  View,
  TextInput,
  Keyboard,
  TouchableWithoutFeedback,
  Modal,
  TouchableOpacity,
  Pressable,
} from "react-native";
import { Ionicons } from "@expo/vector-icons";

const FILTERS = ["All", "Watching", "Completed", "Dropped", "Planning"] as const;
type Filter = (typeof FILTERS)[number];

interface AnimeScreenProps {
  showFilterModal?: boolean;
  onCloseFilterModal?: () => void;
}

export default function AnimeScreen({
  showFilterModal = false,
  onCloseFilterModal,
}: AnimeScreenProps) {
  const [searchQuery, setSearchQuery] = useState("");
  const [selectedFilter, setSelectedFilter] = useState<Filter>("All");

  const handleFilterSelect = (filter: Filter) => {
    setSelectedFilter(filter);
    onCloseFilterModal?.();
  };

  return (
    <TouchableWithoutFeedback onPress={Keyboard.dismiss}>
      <View style={styles.container}>
        <View style={styles.searchContainer}>
          <TextInput
            style={styles.searchBar}
            placeholder="Search"
            placeholderTextColor="#9CA3AF"
            value={searchQuery}
            onChangeText={setSearchQuery}
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
        <View style={styles.content}>
          <Text style={styles.title}>Anime</Text>
          <Text style={styles.subtitle}>
            {selectedFilter === "All"
              ? "Your anime list will appear here"
              : `Showing: ${selectedFilter}`}
          </Text>
        </View>

        <Modal
          visible={showFilterModal}
          transparent
          animationType="slide"
          onRequestClose={onCloseFilterModal}
        >
          <Pressable style={styles.modalOverlay} onPress={onCloseFilterModal}>
            <View style={styles.modalContent}>
              <Text style={styles.modalTitle}>Anime List</Text>
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
    </TouchableWithoutFeedback>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: "#000",
  },
  searchContainer: {
    marginHorizontal: 16,
    marginTop: 16,
    position: "relative",
  },
  searchBar: {
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
  content: {
    flex: 1,
    alignItems: "center",
    justifyContent: "center",
  },
  title: {
    fontSize: 24,
    fontWeight: "bold",
    marginBottom: 8,
    color: "#fff",
  },
  subtitle: {
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
