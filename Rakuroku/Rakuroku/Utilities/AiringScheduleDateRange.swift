import Foundation

nonisolated struct AiringScheduleBounds: Equatable, Sendable {
    let startInclusive: Int
    let endExclusive: Int

    var queryLowerExclusive: Int { startInclusive - 1 }
}

nonisolated enum AiringScheduleDateRange {
    static func bounds(
        dayIndex: Int,
        now: Date = Date(),
        calendar sourceCalendar: Calendar = .current
    ) -> AiringScheduleBounds? {
        guard (0..<7).contains(dayIndex) else { return nil }

        let calendar = sourceCalendar
        let currentDay = calendar.component(.weekday, from: now) - 1
        let daysToAdd = dayIndex - currentDay

        guard let targetDate = calendar.date(byAdding: .day, value: daysToAdd, to: now) else {
            return nil
        }

        let startOfDay = calendar.startOfDay(for: targetDate)
        guard let startOfNextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return nil
        }

        return AiringScheduleBounds(
            startInclusive: Int(startOfDay.timeIntervalSince1970),
            endExclusive: Int(startOfNextDay.timeIntervalSince1970)
        )
    }
}
