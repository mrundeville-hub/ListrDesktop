import Foundation
import Testing
@testable import ListrDesktop

@Suite("Timing and listening stats")
struct TimingAndStatsTests {
    @Test("words stay inside the segment the engine timed them in")
    func segmentsAnchorWords() {
        let text = "One two. Three four five."
        let timing = ChapterTimingBuilder.build(text: text, duration: 10, segments: [
            TimingSegment(location: 0, length: 9, start: 0, end: 2),
            TimingSegment(location: 9, length: 16, start: 6, end: 10)
        ])

        #expect(timing.words.map(\.text) == ["One", "two", "Three", "four", "five"])
        #expect(timing.words[1].end == 2)       // "two" ends with its sentence
        #expect(timing.words[2].start == 6)     // "Three" waits for the second sentence
        #expect(abs(timing.words[4].end - 10) < 0.001)
        #expect(timing.word(at: 3)?.text == "two") // the silence between belongs to the last word
    }

    @Test("without segments a sentence end takes longer than a plain word gap")
    func estimateModelsPauses() {
        let timing = ChapterTimingBuilder.build(text: "aaaa. aaaa aaaa", duration: 9)
        let durations = timing.words.map { $0.end - $0.start }

        #expect(durations[0] > durations[1])
        #expect(abs(timing.words[2].end - 9) < 0.001)
    }

    @MainActor
    @Test("sums listening by month and year and counts the streak")
    func listeningStats() throws {
        let defaults = try #require(UserDefaults(suiteName: "listr-tests-\(UUID().uuidString)"))
        let stats = ListeningStatsStore(defaults: defaults)
        let calendar = Calendar.current
        let today = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 12)))
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }

        stats.add(600, on: today)
        stats.add(300, on: day(-1))
        stats.add(120, on: day(-3))    // gap on day -2 breaks the streak
        stats.add(900, on: day(-20))   // October

        #expect(stats.secondsThisMonth(today) == 1020)
        #expect(stats.secondsThisYear(today) == 1920)
        #expect(stats.streak(endingOn: today) == 2)
        #expect(stats.streak(endingOn: day(1)) == 2) // nothing yet "today" keeps yesterday's streak
        #expect(ListeningSummary.duration(3725) == "1h 2m")
    }
}
