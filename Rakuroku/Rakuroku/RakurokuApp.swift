import SwiftUI

class AppDelegate: NSObject, UIApplicationDelegate {
    static var allowLandscape = false

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.allowLandscape ? [.portrait, .landscapeLeft, .landscapeRight] : .portrait
    }
}

@main
struct RakurokuApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var authStore = AuthStore()
    @State private var animeKaiStore = AnimeKaiStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authStore)
                .environment(animeKaiStore)
                .preferredColorScheme(.dark)
        }
    }
}

// Each tab gets its own NavigationStack so navigation state is independent per tab
struct ContentView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var selectedTab = Tab.anime
    @State private var ready = false

    enum Tab: Hashable {
        case discover, anime, manga, schedule, profile
    }

    var body: some View {
        Group {
            if ready {
                TabView(selection: $selectedTab) {
                    SwiftUI.Tab("Discover", systemImage: "magnifyingglass", value: Tab.discover) {
                        TabNavigationWrapper { DiscoverView() }
                    }

                    SwiftUI.Tab("Anime", systemImage: "tv", value: Tab.anime) {
                        TabNavigationWrapper { AnimeListView() }
                    }

                    SwiftUI.Tab("Manga", systemImage: "book", value: Tab.manga) {
                        TabNavigationWrapper { MangaListView() }
                    }

                    SwiftUI.Tab("Schedule", systemImage: "calendar", value: Tab.schedule) {
                        TabNavigationWrapper { ScheduleView() }
                    }

                    SwiftUI.Tab("Profile", systemImage: "person", value: Tab.profile) {
                        TabNavigationWrapper { ProfileView() }
                    }
                }
                .tint(Theme.primary)
            } else {
                ProgressView().tint(Theme.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.background)
            }
        }
        .task {
            if let token = authStore.accessToken {
                do {
                    let user = try await AniListClient.shared.fetchAuthenticatedUser(accessToken: token)
                    authStore.updateUsername(user.name)
                } catch {
                    authStore.logout()
                }
            }
            ready = true
        }
    }
}

/// Wraps each tab's content in its own NavigationStack with shared destinations
struct TabNavigationWrapper<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        NavigationStack {
            content()
                .navigationDestination(for: MediaDetailDestination.self) { dest in
                    MediaDetailView(mediaId: dest.mediaId)
                }
                .navigationDestination(for: StudioDestination.self) { dest in
                    StudioView(studioId: dest.studioId, studioName: dest.studioName)
                }
                .navigationDestination(for: SeasonListDestination.self) { dest in
                    SeasonListView(season: dest.season, year: dest.year, label: dest.label)
                }
        }
    }
}

// Navigation destinations
struct MediaDetailDestination: Hashable {
    let mediaId: Int
}

struct StudioDestination: Hashable {
    let studioId: Int
    let studioName: String
}

struct SeasonListDestination: Hashable {
    let season: Season
    let year: Int
    let label: String
}
