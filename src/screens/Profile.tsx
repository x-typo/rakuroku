import { useState, useEffect, useCallback } from "react";
import {
  StyleSheet,
  Text,
  View,
  Image,
  ScrollView,
  RefreshControl,
  ActivityIndicator,
  TouchableOpacity,
  Pressable,
  Modal,
  TextInput,
} from "react-native";
import { useNavigation } from "@react-navigation/native";
import { NativeStackNavigationProp } from "@react-navigation/native-stack";
import { Ionicons } from "@expo/vector-icons";
import { colors } from "../constants";
import { fetchUser, fetchUserActivities } from "../api";
import { User, ListActivity } from "../types";
import { useAuth } from "../context";
import { RootStackParamList } from "../../App";
import { formatTimeAgo } from "../utils";

function formatActivityStatus(activity: ListActivity): string {
  const title = activity.media.title.english || activity.media.title.romaji;
  const status = activity.status?.toLowerCase() || "";
  const progress = activity.progress;

  if (progress) {
    if (status.includes("watched")) {
      return `Watched episode ${progress} of ${title}`;
    }
    if (status.includes("read")) {
      return `Read chapter ${progress} of ${title}`;
    }
    return `${status} ${progress} of ${title}`;
  }

  if (status.includes("completed")) {
    return `Completed ${title}`;
  }
  if (status.includes("dropped")) {
    return `Dropped ${title}`;
  }
  if (status.includes("paused")) {
    return `Paused ${title}`;
  }
  if (status.includes("planning")) {
    return `Plans to watch ${title}`;
  }
  if (status.includes("rewatched") || status.includes("reread")) {
    return `Rewatching ${title}`;
  }

  return `${status} ${title}`;
}

type NavigationProp = NativeStackNavigationProp<RootStackParamList>;

export default function ProfileScreen() {
  const navigation = useNavigation<NavigationProp>();
  const { isAuthenticated, isLoading: authLoading, authError, login, logout, setManualToken, clearAuthError } = useAuth();
  const [user, setUser] = useState<User | null>(null);
  const [activities, setActivities] = useState<ListActivity[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [manualTokenModalVisible, setManualTokenModalVisible] = useState(false);
  const [manualTokenValue, setManualTokenValue] = useState("");

  const loadData = useCallback(async (showRefreshing = false) => {
    if (showRefreshing) {
      setRefreshing(true);
    } else {
      setLoading(true);
    }
    setError(null);

    try {
      const userData = await fetchUser();
      setUser(userData);

      const activityData = await fetchUserActivities(userData.id);
      setActivities(activityData);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to load profile");
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, []);

  useEffect(() => {
    loadData();
  }, [loadData]);

  if (loading) {
    return (
      <View style={styles.centerContainer}>
        <ActivityIndicator size="large" color={colors.primary} />
      </View>
    );
  }

  if (error) {
    return (
      <View style={styles.centerContainer}>
        <Text style={styles.errorText}>{error}</Text>
        <TouchableOpacity style={styles.retryButton} onPress={() => loadData()}>
          <Text style={styles.retryText}>Retry</Text>
        </TouchableOpacity>
      </View>
    );
  }

  if (!user) {
    return (
      <View style={styles.centerContainer}>
        <Text style={styles.subtitle}>No user data available</Text>
      </View>
    );
  }

  const hoursWatched = Math.round(user.statistics.anime.minutesWatched / 60);

  return (
    <View style={styles.container}>
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
        <View style={styles.avatarContainer}>
          <Image source={{ uri: user.avatar.large }} style={styles.avatar} />
        </View>

        <Text style={styles.username}>{user.name}</Text>

        <View style={styles.statsContainer}>
          <View style={styles.statCard}>
            <Text style={styles.statValue}>{user.statistics.anime.count}</Text>
            <Text style={styles.statLabel}>Anime</Text>
          </View>
          <View style={styles.statCard}>
            <Text style={styles.statValue}>{user.statistics.anime.episodesWatched}</Text>
            <Text style={styles.statLabel}>Episodes</Text>
          </View>
          <View style={styles.statCard}>
            <Text style={styles.statValue}>{hoursWatched}</Text>
            <Text style={styles.statLabel}>Hours</Text>
          </View>
        </View>

        <View style={styles.statsContainer}>
          <View style={styles.statCard}>
            <Text style={styles.statValue}>{user.statistics.manga.count}</Text>
            <Text style={styles.statLabel}>Manga</Text>
          </View>
          <View style={styles.statCard}>
            <Text style={styles.statValue}>{user.statistics.manga.chaptersRead}</Text>
            <Text style={styles.statLabel}>Chapters</Text>
          </View>
        </View>

        <View style={styles.authSection}>
          {authLoading ? (
            <ActivityIndicator size="small" color={colors.primary} />
          ) : isAuthenticated ? (
            <Pressable style={styles.authButton} onPress={logout}>
              <Ionicons name="log-out-outline" size={20} color={colors.textPrimary} />
              <Text style={styles.authButtonText}>Sign Out</Text>
            </Pressable>
          ) : (
            <>
              <Pressable style={[styles.authButton, styles.authButtonPrimary]} onPress={login}>
                <Ionicons name="log-in-outline" size={20} color={colors.textPrimary} />
                <Text style={styles.authButtonText}>Sign in with AniList</Text>
              </Pressable>
              <Pressable
                style={[styles.authButton, styles.authButtonSecondary]}
                onPress={() => setManualTokenModalVisible(true)}
              >
                <Ionicons name="key-outline" size={20} color={colors.textPrimary} />
                <Text style={styles.authButtonText}>Paste Access Token</Text>
              </Pressable>
              {authError && (
                <Pressable style={styles.authErrorBanner} onPress={clearAuthError}>
                  <Text style={styles.authErrorText}>{authError}</Text>
                  <Text style={styles.authErrorDismiss}>Tap to dismiss</Text>
                </Pressable>
              )}
            </>
          )}
        </View>

        <View style={styles.activitiesSection}>
          <Text style={styles.sectionTitle}>Recent Activity</Text>
          {activities.length === 0 ? (
            <Text style={styles.noActivities}>No recent activities</Text>
          ) : (
            activities.map((activity) => (
              <Pressable
                key={activity.id}
                style={styles.activityRow}
                onPress={() => navigation.navigate("MediaDetail", { mediaId: activity.media.id })}
              >
                <Image
                  source={{ uri: activity.media.coverImage.medium }}
                  style={styles.activityPoster}
                />
                <View style={styles.activityInfo}>
                  <Text style={styles.activityStatus} numberOfLines={2}>
                    {formatActivityStatus(activity)}
                  </Text>
                </View>
                <Text style={styles.activityTime}>
                  {formatTimeAgo(activity.createdAt)}
                </Text>
              </Pressable>
            ))
          )}
        </View>
      </ScrollView>

      {refreshing && (
        <View style={styles.loadingOverlay}>
          <ActivityIndicator size="large" color={colors.primary} />
        </View>
      )}

      <Modal
        visible={manualTokenModalVisible}
        transparent
        animationType="fade"
        onRequestClose={() => setManualTokenModalVisible(false)}
      >
        <Pressable style={styles.modalOverlay} onPress={() => setManualTokenModalVisible(false)}>
          <Pressable style={styles.manualTokenModal} onPress={() => {}}>
            <Text style={styles.manualTokenTitle}>Paste AniList Token</Text>
            <Text style={styles.manualTokenHint}>
              If browser login is blocked, you can paste an existing AniList OAuth access token here.
            </Text>

            <TextInput
              style={styles.manualTokenInput}
              placeholder="access_token…"
              placeholderTextColor={colors.textSecondary}
              autoCapitalize="none"
              autoCorrect={false}
              value={manualTokenValue}
              onChangeText={setManualTokenValue}
            />

            <View style={styles.manualTokenButtonsRow}>
              <Pressable
                style={styles.manualTokenSaveButton}
                onPress={async () => {
                  await setManualToken(manualTokenValue);
                  setManualTokenModalVisible(false);
                  setManualTokenValue("");
                }}
              >
                <Text style={styles.manualTokenSaveText}>Save</Text>
              </Pressable>
              <Pressable
                style={styles.manualTokenCancelButton}
                onPress={() => setManualTokenModalVisible(false)}
              >
                <Text style={styles.manualTokenCancelText}>Cancel</Text>
              </Pressable>
            </View>
          </Pressable>
        </Pressable>
      </Modal>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  content: {
    alignItems: "center",
    paddingVertical: 32,
  },
  centerContainer: {
    flex: 1,
    backgroundColor: colors.background,
    alignItems: "center",
    justifyContent: "center",
  },
  avatarContainer: {
    marginBottom: 16,
  },
  avatar: {
    width: 120,
    height: 120,
    borderRadius: 60,
  },
  username: {
    fontSize: 24,
    fontWeight: "bold",
    color: colors.textPrimary,
    marginBottom: 24,
  },
  statsContainer: {
    flexDirection: "row",
    marginBottom: 16,
    gap: 12,
  },
  statCard: {
    backgroundColor: colors.surface,
    borderRadius: 12,
    paddingVertical: 16,
    paddingHorizontal: 24,
    alignItems: "center",
    minWidth: 100,
  },
  statValue: {
    fontSize: 20,
    fontWeight: "bold",
    color: colors.textPrimary,
    marginBottom: 4,
  },
  statLabel: {
    fontSize: 14,
    color: colors.textSecondary,
  },
  activitiesSection: {
    width: "100%",
    paddingHorizontal: 16,
    marginTop: 16,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: "bold",
    color: colors.textPrimary,
    marginBottom: 16,
  },
  noActivities: {
    fontSize: 14,
    color: colors.textSecondary,
    textAlign: "center",
  },
  activityRow: {
    flexDirection: "row",
    backgroundColor: colors.surface,
    borderRadius: 12,
    marginBottom: 12,
    overflow: "hidden",
    alignItems: "center",
  },
  activityPoster: {
    width: 50,
    height: 70,
  },
  activityInfo: {
    flex: 1,
    paddingHorizontal: 12,
    paddingVertical: 8,
  },
  activityStatus: {
    fontSize: 14,
    color: colors.textPrimary,
  },
  activityTime: {
    fontSize: 12,
    color: colors.textSecondary,
    paddingRight: 12,
  },
  subtitle: {
    fontSize: 16,
    color: colors.textSecondary,
  },
  errorText: {
    fontSize: 16,
    color: colors.error,
    marginBottom: 16,
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
  loadingOverlay: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: "rgba(0, 0, 0, 0.5)",
    alignItems: "center",
    justifyContent: "center",
  },
  authSection: {
    width: "100%",
    paddingHorizontal: 16,
    marginTop: 8,
    marginBottom: 8,
    alignItems: "center",
  },
  authButton: {
    flexDirection: "row",
    alignItems: "center",
    gap: 8,
    backgroundColor: colors.surface,
    paddingHorizontal: 20,
    paddingVertical: 12,
    borderRadius: 8,
  },
  authButtonPrimary: {
    backgroundColor: colors.primary,
  },
  authButtonSecondary: {
    marginTop: 10,
    backgroundColor: colors.surfaceLight,
  },
  authButtonText: {
    color: colors.textPrimary,
    fontSize: 16,
    fontWeight: "600",
  },
  authErrorBanner: {
    marginTop: 12,
    width: "100%",
    backgroundColor: "rgba(239, 68, 68, 0.15)",
    borderRadius: 10,
    paddingVertical: 10,
    paddingHorizontal: 12,
    alignItems: "center",
  },
  authErrorText: {
    fontSize: 13,
    fontWeight: "700",
    color: colors.error,
    textAlign: "center",
  },
  authErrorDismiss: {
    marginTop: 4,
    fontSize: 12,
    color: colors.textSecondary,
    textAlign: "center",
  },
  modalOverlay: {
    flex: 1,
    backgroundColor: "rgba(0, 0, 0, 0.7)",
    justifyContent: "center",
    alignItems: "center",
  },
  manualTokenModal: {
    backgroundColor: colors.surface,
    borderRadius: 16,
    padding: 24,
    width: "85%",
    maxWidth: 360,
  },
  manualTokenTitle: {
    fontSize: 18,
    fontWeight: "bold",
    color: colors.textPrimary,
    textAlign: "center",
    marginBottom: 10,
  },
  manualTokenHint: {
    fontSize: 13,
    color: colors.textSecondary,
    textAlign: "center",
    marginBottom: 14,
  },
  manualTokenInput: {
    backgroundColor: colors.background,
    borderRadius: 12,
    paddingHorizontal: 14,
    paddingVertical: 12,
    color: colors.textPrimary,
    fontSize: 14,
  },
  manualTokenButtonsRow: {
    flexDirection: "row",
    gap: 12,
    marginTop: 16,
  },
  manualTokenSaveButton: {
    flex: 1,
    backgroundColor: colors.primary,
    borderRadius: 12,
    paddingVertical: 12,
    alignItems: "center",
  },
  manualTokenSaveText: {
    fontSize: 14,
    fontWeight: "700",
    color: colors.textPrimary,
  },
  manualTokenCancelButton: {
    flex: 1,
    backgroundColor: colors.surfaceLight,
    borderRadius: 12,
    paddingVertical: 12,
    alignItems: "center",
  },
  manualTokenCancelText: {
    fontSize: 14,
    fontWeight: "700",
    color: colors.textPrimary,
  },
});
