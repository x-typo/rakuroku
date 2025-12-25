import { useCallback } from "react";
import { StyleSheet, Text, View, FlatList, RefreshControl, ActivityIndicator } from "react-native";
import { colors, ANIME_FILTERS, DEFAULT_ANIME_FILTER } from "../constants";
import { MediaListEntry } from "../types";
import { useMediaList } from "../hooks";
import {
  MediaCard,
  SearchBar,
  FilterModal,
  EmptyState,
  ErrorState,
  LoadingState,
} from "../components";

interface AnimeScreenProps {
  showFilterModal?: boolean;
  onCloseFilterModal?: () => void;
}

export default function AnimeScreen({
  showFilterModal = false,
  onCloseFilterModal,
}: AnimeScreenProps) {
  const {
    filteredEntries,
    loading,
    error,
    refreshing,
    searchQuery,
    selectedFilter,
    setSearchQuery,
    handleRefresh,
    handleFilterSelect,
    loadData,
  } = useMediaList({
    type: "ANIME",
    defaultFilter: DEFAULT_ANIME_FILTER,
  });

  const renderItem = useCallback(
    ({ item }: { item: MediaListEntry }) => <MediaCard entry={item} type="ANIME" />,
    []
  );

  const renderEmpty = () => (
    <EmptyState
      message={searchQuery ? "No results found" : "No anime in this list"}
    />
  );

  if (loading) {
    return (
      <View style={styles.container}>
        <View style={styles.header}>
          <Text style={styles.title}>{selectedFilter}</Text>
        </View>
        <LoadingState />
      </View>
    );
  }

  if (error) {
    return (
      <View style={styles.container}>
        <View style={styles.header}>
          <Text style={styles.title}>{selectedFilter}</Text>
        </View>
        <ErrorState message={error} onRetry={loadData} />
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.title}>{selectedFilter}</Text>
      </View>

      <SearchBar
        value={searchQuery}
        onChangeText={setSearchQuery}
        onClear={() => setSearchQuery("")}
      />

      <FlatList
        data={filteredEntries}
        renderItem={renderItem}
        keyExtractor={(item) => item.id.toString()}
        contentContainerStyle={styles.listContent}
        ListEmptyComponent={renderEmpty}
        keyboardShouldPersistTaps="handled"
        keyboardDismissMode="interactive"
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            onRefresh={handleRefresh}
            tintColor={colors.primary}
          />
        }
      />

      <FilterModal
        visible={showFilterModal}
        onClose={onCloseFilterModal ?? (() => {})}
        title="Anime List"
        filters={ANIME_FILTERS}
        selectedFilter={selectedFilter}
        onSelectFilter={(filter) => handleFilterSelect(filter, onCloseFilterModal)}
      />

      {refreshing && (
        <View style={styles.loadingOverlay}>
          <ActivityIndicator size="large" color={colors.primary} />
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
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
    color: colors.textPrimary,
  },
  listContent: {
    paddingBottom: 16,
  },
  loadingOverlay: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: "rgba(0, 0, 0, 0.5)",
    alignItems: "center",
    justifyContent: "center",
  },
});
