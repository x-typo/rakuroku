import SwiftUI

struct ScheduleView: View {

    @Environment(AuthStore.self) private var authStore

    @State private var selectedDay = Calendar.current.component(.weekday, from: Date()) - 1
    @State private var schedules: [AiringSchedule] = []
    @State private var userStatusMap: [Int: MediaListStatus]?
    @State private var loading = true
    @State private var error: String?
    @State private var personalizationWarning: String?

    private let days = ["S", "M", "T", "W", "T", "F", "S"]
    private let weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

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
                    .accessibilityLabel(weekdayNames[index])
                    .accessibilityValue(selectedDay == index ? "Selected" : "")
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

            if let personalizationWarning {
                ContentWarningView(message: personalizationWarning)
                    .padding(.top, 8)
            }

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
        let userStatus = userStatusMap?[schedule.media.id]
        let isHighlighted = userStatus == .current || userStatus == .completed

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

                    Text(hasAired ? "Aired at \(Formatters.airingTime(schedule.airingAt))" : "Airing at \(Formatters.airingTime(schedule.airingAt))")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(hasAired ? Theme.textSecondary : Theme.warning)
                }
                .padding(12)

                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .opacity(userStatusMap == nil || isHighlighted ? 1 : 0.5)
    }

    private func loadData() async {
        loading = true
        error = nil
        personalizationWarning = nil
        userStatusMap = nil
        do {
            async let scheduleData = AniListClient.shared.fetchAiringSchedule(dayIndex: selectedDay)
            let username = authStore.username.trimmingCharacters(in: .whitespacesAndNewlines)
            async let animeList: [MediaListEntry]? = !username.isEmpty
                ? AniListClient.shared.fetchMediaList(
                    type: .anime,
                    username: username,
                    accessToken: authStore.accessToken
                )
                : nil

            let s = try await scheduleData
            try Task.checkCancellation()
            schedules = s
            loading = false

            do {
                let list = try await animeList
                try Task.checkCancellation()
                if let list {
                    userStatusMap = Dictionary(
                        list.map { ($0.media.id, $0.status) },
                        uniquingKeysWith: { _, latest in latest }
                    )
                }
            } catch where error.isCancellation {
                throw error
            } catch AniListError.rateLimited {
                guard !Task.isCancelled else { return }
                userStatusMap = nil
                personalizationWarning = "List status unavailable. \(AniListError.rateLimited.localizedDescription)"
            } catch {
                guard !Task.isCancelled else { return }
                userStatusMap = nil
                personalizationWarning = "List status unavailable. \(error.localizedDescription)"
            }
        } catch where error.isCancellation {
            return
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}
