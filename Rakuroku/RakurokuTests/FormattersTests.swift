import Testing
@testable import Rakuroku

@Suite("Formatters")
@MainActor
struct FormattersTests {
    @Test("Maps known and unknown media formats")
    func formatTypes() {
        #expect(Formatters.formatType("TV_SHORT") == "TV Short")
        #expect(Formatters.formatType("NOVEL") == "Light Novel")
        #expect(Formatters.formatType("CUSTOM") == "CUSTOM")
        #expect(Formatters.formatType(nil) == "")
    }

    @Test("Formats complete, partial, invalid, and missing dates")
    func fuzzyDates() {
        #expect(Formatters.formatFuzzyDate(FuzzyDate(year: 2026, month: 3, day: 8)) == "Mar 8, 2026")
        #expect(Formatters.formatFuzzyDate(FuzzyDate(year: 2026, month: nil, day: nil)) == "2026")
        #expect(Formatters.formatFuzzyDate(FuzzyDate(year: 2026, month: 13, day: 1)) == "2026")
        #expect(Formatters.formatFuzzyDate(nil) == "TBA")
    }

    @Test("Strips markup and decodes common entities")
    func stripsHTML() {
        let input = "  <p>Hello</p><br><b>World &amp; friends</b>\n\n\n  "
        #expect(Formatters.stripHtml(input) == "Hello\nWorld & friends")
    }

    @Test("Advances seasons and rolls the year after fall")
    func nextSeason() {
        let spring = Formatters.nextSeason(after: (season: .winter, year: 2026))
        #expect(spring.season == .spring)
        #expect(spring.year == 2026)

        let winter = Formatters.nextSeason(after: (season: .fall, year: 2026))
        #expect(winter.season == .winter)
        #expect(winter.year == 2027)
    }
}
