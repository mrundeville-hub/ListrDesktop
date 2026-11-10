import Foundation
import Observation

/// How long audio has actually been playing, per calendar day.
@MainActor
@Observable
final class ListeningStatsStore {
    /// Seconds listened, keyed by local day "2026-11-11".
    private(set) var secondsByDay: [String: Double]

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var pending: Double = 0
    @ObservationIgnored private var unsaved: Double = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        secondsByDay = defaults.dictionary(forKey: Keys.secondsByDay) as? [String: Double] ?? [:]
    }

    func add(_ seconds: TimeInterval, on date: Date = .now) {
        // Published once a second, not on every 0.1 s playback tick.
        pending += seconds
        guard pending >= 1 else { return }
        secondsByDay[Self.dayKey(date), default: 0] += pending
        unsaved += pending
        pending = 0

        // ponytail: saved every 10 s of listening; a quit can lose up to 10 s of the count.
        if unsaved >= 10 {
            defaults.set(secondsByDay, forKey: Keys.secondsByDay)
            unsaved = 0
        }
    }

    func seconds(on date: Date) -> Double {
        secondsByDay[Self.dayKey(date)] ?? 0
    }

    func secondsThisMonth(_ date: Date = .now) -> Double {
        total(prefix: String(Self.dayKey(date).prefix(7)))
    }

    func secondsThisYear(_ date: Date = .now) -> Double {
        total(prefix: String(Self.dayKey(date).prefix(4)))
    }

    /// Days in a row with at least a minute of listening. Today not counting yet does not break it.
    func streak(endingOn date: Date = .now) -> Int {
        let calendar = Calendar.current
        var day = date
        if seconds(on: day) < 60 {
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        var count = 0
        while seconds(on: day) >= 60, let previous = calendar.date(byAdding: .day, value: -1, to: day) {
            count += 1
            day = previous
        }
        return count
    }

    private func total(prefix: String) -> Double {
        secondsByDay.reduce(0) { $1.key.hasPrefix(prefix) ? $0 + $1.value : $0 }
    }

    private static func dayKey(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

private enum Keys {
    static let secondsByDay = "stats.secondsByDay"
}
