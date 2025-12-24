import { useCallback } from "react";
import { StyleSheet, Text, View, FlatList, RefreshControl } from "react-native";
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
    showSearch,
    setSearchQuery,
    handleRefresh,
    handleScroll,
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

  const renderHeader = () => {
    if (!showSearch) return null;
    return (
      <SearchBar
        value={searchQuery}
        onChangeText={setSearchQuery}
        onClear={() => setSearchQuery("")}
        autoFocus
      />
    );
  };

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

      <FlatList
        data={filteredEntries}
        renderItem={renderItem}
        keyExtractor={(item) => item.id.toString()}
        contentContainerStyle={styles.listContent}
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
});
