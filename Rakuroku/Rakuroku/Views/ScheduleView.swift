import SwiftUI

struct ScheduleView: View {

    @Environment(AuthStore.self) private var authStore

    @State private var selectedDay = Calendar.current.component(.weekday, from: Date()) - 1
    @State private var schedules: [AiringSchedule] = []
    @State private var userStatusMap: [Int: MediaListStatus] = [:]
    @State private var loading = true
    @State private var error: String?
    @State private var openingDiscussionId: Int?

    private let days = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { index in
                    Button {
                        selectedDay = index
                    } label: {
                        Text(days[index])
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(selectedDay == index ? Theme.primary : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding(4)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .simultaneousGesture(
                DragGesture(minimumDistance: 30)
                    .onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        if value.translation.width < -50 {
                            selectedDay = (selectedDay + 1) % 7
                        } else if value.translation.width > 50 {
                            selectedDay = (selectedDay - 1 + 7) % 7
                        }
                    }
            )

            if loading {
                ContentLoadingView()
            } else if let error {
                ContentErrorView(message: error) { Task { await loadData() } }
            } else if schedules.isEmpty {
                Spacer()
                Text("No episodes airing this day")
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(schedules) { schedule in
                            scheduleRow(schedule)
                        }
                    }
                    .padding(16)
                }
                .refreshable { await loadData() }
            }
        }
        .background(Theme.background)
        .task(id: selectedDay) { await loadData() }
    }

    @ViewBuilder
    private func scheduleRow(_ schedule: AiringSchedule) -> some View {
        let hasAired = Double(schedule.airingAt) < Date().timeIntervalSince1970
        let userStatus = userStatusMap[schedule.media.id]
        let isHighlighted = userStatus == .current || userStatus == .completed
        let isOpening = openingDiscussionId == schedule.id

        NavigationLink(value: MediaDetailDestination(mediaId: schedule.media.id)) {
            HStack(spacing: 0) {
                AsyncCoverImage(url: schedule.media.coverImage?.medium, width: 80, height: 110)

                VStack(alignment: .leading, spacing: 4) {
                    Text(schedule.media.title.display)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        Text("Episode \(schedule.episode)")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)

                        if let status = userStatus, let label = Formatters.statusLabel(status),
                           let color = Formatters.statusColor(status) {
                            Text(label)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(color)
                        }
                    }

                    HStack(spacing: 12) {
                        Text(hasAired ? "Aired at \(Formatters.airingTime(schedule.airingAt))" : "Airing at \(Formatters.airingTime(schedule.airingAt))")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(hasAired ? Theme.textSecondary : Theme.warning)

                        if hasAired {
                            Button {
                                Task { await openDiscussion(schedule) }
                            } label: {
                                if isOpening {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                        .tint(Theme.textSecondary)
                                } else {
                                    HStack(spacing: 4) {
                                        Image(systemName: "bubble.left.fill")
                                            .font(.caption2)
                                        Text("Discuss")
                                            .font(.caption.weight(.semibold))
                                    }
                                    .foregroundStyle(Theme.textPrimary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Theme.surfaceLight)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                            }
                            .disabled(isOpening)
                        }
                    }
                }
                .padding(12)

                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .opacity(isHighlighted ? 1 : 0.5)
    }

    private func openDiscussion(_ schedule: AiringSchedule) async {
        openingDiscussionId = schedule.id

        let url = await RedditDiscussion.findUrl(
            anilistId: schedule.media.id,
            episode: schedule.episode,
            airingAt: schedule.airingAt
        )

        if let url {
            await UIApplication.shared.open(url)
        }
        openingDiscussionId = nil
    }

    private func loadData() async {
        loading = true
        error = nil
        do {
            async let scheduleData = AniListClient.shared.fetchAiringSchedule(dayIndex: selectedDay)
            async let animeList = AniListClient.shared.fetchMediaList(type: .anime, username: authStore.username)
            let (s, list) = try await (scheduleData, animeList)
            schedules = s
            userStatusMap = Dictionary(uniqueKeysWithValues: list.map { ($0.media.id, $0.status) })
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}

// MARK: - Reddit Discussion Finder

private enum RedditDiscussion {

    static func findUrl(anilistId: Int, episode: Int, airingAt: Int) async -> URL? {
        let query = "author:AutoLovepon anilist.co/anime/\(anilistId)"
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchURL = URL(string: "https://www.reddit.com/r/anime/search.json?restrict_sr=1&sort=new&limit=25&q=\(encoded)") else {
            return nil
        }

        var request = URLRequest(url: searchURL)
        request.setValue("rakuroku/1.0 (reddit-discussion-linker)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return nil
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let listing = json["data"] as? [String: Any],
              let children = listing["children"] as? [[String: Any]] else {
            return nil
        }

        let expectedNeedle = "anilist.co/anime/\(anilistId)"

        struct Candidate {
            let permalink: String
            let parsedEpisode: Int?
            let createdUtc: Double
        }

        let candidates: [Candidate] = children.compactMap { child in
            guard let post = child["data"] as? [String: Any],
                  let author = post["author"] as? String, author == "AutoLovepon",
                  let subreddit = post["subreddit"] as? String, subreddit == "anime",
                  let title = post["title"] as? String,
                  let permalink = post["permalink"] as? String else { return nil }

            if let selftext = post["selftext"] as? String, !selftext.contains(expectedNeedle) {
                return nil
            }

            let createdUtc = post["created_utc"] as? Double ?? 0
            return Candidate(
                permalink: permalink,
                parsedEpisode: parseEpisode(from: title),
                createdUtc: createdUtc
            )
        }.sorted { $0.createdUtc > $1.createdUtc }

        // Prefer exact episode match
        if let exact = candidates.first(where: { $0.parsedEpisode == episode }) {
            return URL(string: "https://www.reddit.com\(exact.permalink)")
        }

        // Fall back to closest by airing time
        let airingUtc = Double(airingAt)
        let earlyWindow: Double = 12 * 3600
        let lateWindow: Double = 3 * 86400

        let timed = candidates
            .filter { $0.createdUtc > 0 && $0.createdUtc >= airingUtc - earlyWindow && $0.createdUtc <= airingUtc + lateWindow }
            .sorted { abs($0.createdUtc - airingUtc) < abs($1.createdUtc - airingUtc) }

        if let best = timed.first {
            return URL(string: "https://www.reddit.com\(best.permalink)")
        }

        return nil
    }

    private static func parseEpisode(from title: String) -> Int? {
        let pattern = #"-\s*Episode\s+(\d+)\s+discussion(?:\s*-\s*FINAL)?\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
              let range = Range(match.range(at: 1), in: title) else {
            return nil
        }
        return Int(title[range])
    }
}
