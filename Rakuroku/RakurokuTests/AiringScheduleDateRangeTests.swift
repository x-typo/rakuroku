import Foundation
import Testing
@testable import Rakuroku

@Suite("Airing schedule date ranges")
struct AiringScheduleDateRangeTests {
    @Test("Rejects invalid weekday indexes", arguments: [-1, 7])
    func rejectsInvalidDayIndex(_ dayIndex: Int) throws {
        let calendar = try denverCalendar()
        #expect(AiringScheduleDateRange.bounds(
            dayIndex: dayIndex,
            now: Date(timeIntervalSince1970: 0),
            calendar: calendar
        ) == nil)
    }

    @Test("Ordinary local day spans 24 hours")
    func ordinaryDay() throws {
        let bounds = try bounds(year: 2026, month: 1, day: 11)
        #expect(bounds.endExclusive - bounds.startInclusive == 86_400)
        #expect(bounds.queryLowerExclusive == bounds.startInclusive - 1)
    }

    @Test("Spring-forward day spans 23 hours")
    func springForwardDay() throws {
        let bounds = try bounds(year: 2026, month: 3, day: 8)
        #expect(bounds.endExclusive - bounds.startInclusive == 82_800)
    }

    @Test("Fall-back day spans 25 hours")
    func fallBackDay() throws {
        let bounds = try bounds(year: 2026, month: 11, day: 1)
        #expect(bounds.endExclusive - bounds.startInclusive == 90_000)
    }

    private func bounds(year: Int, month: Int, day: Int) throws -> AiringScheduleBounds {
        let calendar = try denverCalendar()
        let now = try #require(calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: 12
        )))
        let dayIndex = calendar.component(.weekday, from: now) - 1
        return try #require(AiringScheduleDateRange.bounds(
            dayIndex: dayIndex,
            now: now,
            calendar: calendar
        ))
    }

    private func denverCalendar() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Denver"))
        return calendar
    }
}
