import SwiftUI

struct ScheduleView: View {


    @State private var selectedDay = Calendar.current.component(.weekday, from: Date()) - 1
    @State private var schedules: [AiringSchedule] = []
    @State private var userStatusMap: [Int: MediaListStatus] = [:]
    @State private var loading = true
    @State private var error: String?

    private let days = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        VStack(spacing: 0) {
            // Day selector bar
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
        let title = schedule.media.title.display
        let hasAired = Double(schedule.airingAt) < Date().timeIntervalSince1970
        let userStatus = userStatusMap[schedule.media.id]
        let isHighlighted = userStatus == .current || userStatus == .completed

        HStack(spacing: 0) {
            NavigationLink(value: MediaDetailDestination(mediaId: schedule.media.id)) {
                HStack(spacing: 0) {
                    AsyncCoverImage(url: schedule.media.coverImage?.medium, width: 80, height: 110)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
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
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .opacity(isHighlighted ? 1 : 0.5)
    }

    private func loadData() async {
        if schedules.isEmpty { loading = true }
        error = nil
        do {
            async let scheduleData = AniListClient.shared.fetchAiringSchedule(dayIndex: selectedDay)
            async let animeList = AniListClient.shared.fetchMediaList(type: .anime)
            let (s, list) = try await (scheduleData, animeList)
            schedules = s
            userStatusMap = Dictionary(uniqueKeysWithValues: list.map { ($0.media.id, $0.status) })
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}
