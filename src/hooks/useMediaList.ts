import { useState, useEffect, useCallback, useMemo } from "react";
import { useIsFocused } from "@react-navigation/native";
import { fetchMediaList, filterByStatus, searchEntries } from "../api";
import { MediaType, MediaListEntry } from "../types";

interface UseMediaListOptions {
  type: MediaType;
  defaultFilter: string;
}

interface UseMediaListReturn {
  entries: MediaListEntry[];
  filteredEntries: MediaListEntry[];
  loading: boolean;
  error: string | null;
  refreshing: boolean;
  searchQuery: string;
  selectedFilter: string;
  showSearch: boolean;
  setSearchQuery: (query: string) => void;
  setSelectedFilter: (filter: string) => void;
  setShowSearch: (show: boolean) => void;
  handleRefresh: () => void;
  handleScroll: (event: { nativeEvent: { contentOffset: { y: number } } }) => void;
  handleFilterSelect: (filter: string, onClose?: () => void) => void;
  loadData: () => Promise<void>;
}

export function useMediaList({
  type,
  defaultFilter,
}: UseMediaListOptions): UseMediaListReturn {
  const [entries, setEntries] = useState<MediaListEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);
  const [searchQuery, setSearchQuery] = useState("");
  const [selectedFilter, setSelectedFilter] = useState(defaultFilter);
  const [showSearch, setShowSearch] = useState(false);
  const isFocused = useIsFocused();

  const loadData = useCallback(async () => {
    try {
      setError(null);
      const data = await fetchMediaList(type);
      setEntries(data);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to load data");
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [type]);

  useEffect(() => {
    loadData();
  }, [loadData]);

  useEffect(() => {
    if (!isFocused) {
      setShowSearch(false);
      setSearchQuery("");
      setSelectedFilter(defaultFilter);
    }
  }, [isFocused, defaultFilter]);

  const filteredEntries = useMemo(
    () => searchEntries(filterByStatus(entries, selectedFilter), searchQuery),
    [entries, selectedFilter, searchQuery]
  );

  const handleRefresh = useCallback(() => {
    setRefreshing(true);
    loadData();
  }, [loadData]);

  const handleScroll = useCallback(
    (event: { nativeEvent: { contentOffset: { y: number } } }) => {
      const offsetY = event.nativeEvent.contentOffset.y;
      if (offsetY < -50 && !showSearch) {
        setShowSearch(true);
      }
    },
    [showSearch]
  );

  const handleFilterSelect = useCallback(
    (filter: string, onClose?: () => void) => {
      setSelectedFilter(filter);
      setShowSearch(false);
      setSearchQuery("");
      onClose?.();
    },
    []
  );

  return {
    entries,
    filteredEntries,
    loading,
    error,
    refreshing,
    searchQuery,
    selectedFilter,
    showSearch,
    setSearchQuery,
    setSelectedFilter,
    setShowSearch,
    handleRefresh,
    handleScroll,
    handleFilterSelect,
    loadData,
  };
}
