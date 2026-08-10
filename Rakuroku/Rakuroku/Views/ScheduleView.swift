import SwiftUI

struct ScheduleView: View {

    @Environment(AuthStore.self) private var authStore
    @Environment(MediaLibraryStore.self) private var mediaLibraryStore

    @State private var selectedDay = Calendar.current.component(.weekday, from: Date()) - 1
    @State private var schedules: [AiringSchedule] = []
    @State private var loading = true
    @State private var error: String?

    private let days = ["S", "M", "T", "W", "T", "F", "S"]
    private let weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    private var personalizationWarning: String? {
        let libraryState = mediaLibraryStore.state(for: .anime)
        if case .failed(let message) = libraryState.phase {
            return libraryState.hasUsableData
                ? "List refresh failed. \(message)"
                : "List status unavailable. \(message)"
        }
        return nil
    }

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
                ContentErrorView(message: error) { Task { await refreshData() } }
            } else if schedules.isEmpty {
                ScrollView {
                    Text("No episodes airing this day")
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 320)
                }
                .refreshable { await refreshData() }
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(schedules) { schedule in
                            scheduleRow(schedule)
                        }
                    }
                    .padding(16)
                }
                .refreshable { await refreshData() }
            }
        }
        .background(Theme.background)
        .task(id: selectedDay) { await loadSchedule() }
        .task(id: authStore.mediaLibrarySession.id) { await loadLibrary() }
    }

    @ViewBuilder
    private func scheduleRow(_ schedule: AiringSchedule) -> some View {
        let hasAired = Double(schedule.airingAt) < Date().timeIntervalSince1970
        let libraryState = mediaLibraryStore.state(for: .anime)
        let userStatus = libraryState.hasUsableData
            ? mediaLibraryStore.status(mediaID: schedule.media.id, type: .anime)
            : nil
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
        .opacity(!libraryState.hasUsableData || isHighlighted ? 1 : 0.5)
    }

    private func loadSchedule() async {
        let requestedDay = selectedDay
        loading = true
        error = nil
        do {
            let result = try await AniListClient.shared.fetchAiringSchedule(dayIndex: requestedDay)
            try Task.checkCancellation()
            guard requestedDay == selectedDay else { return }
            schedules = result
            loading = false
        } catch where error.isCancellation {
            return
        } catch {
            guard requestedDay == selectedDay, !Task.isCancelled else { return }
            self.error = error.localizedDescription
            loading = false
        }
    }

    private func loadLibrary() async {
        let session = authStore.mediaLibrarySession
        await mediaLibraryStore.load(.anime, session: session)
    }

    private func refreshData() async {
        let session = authStore.mediaLibrarySession
        async let scheduleLoad: Void = loadSchedule()
        async let libraryLoad: Void = mediaLibraryStore.load(.anime, session: session, force: true)
        _ = await (scheduleLoad, libraryLoad)
    }
}
