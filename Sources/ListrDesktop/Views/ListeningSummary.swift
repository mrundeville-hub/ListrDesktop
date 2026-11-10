import SwiftUI

// Top of the library: how much you have listened, and a dot for each of the last 35 days.
struct ListeningSummary: View {
    @Environment(ListeningStatsStore.self) private var stats

    var body: some View {
        let now = Date()
        let streak = stats.streak(endingOn: now)

        HStack(alignment: .top, spacing: 44) {
            figure(Self.duration(stats.secondsThisMonth(now)), "listened in \(now.formatted(.dateTime.month(.wide)))")
            figure(Self.duration(stats.secondsThisYear(now)), "in \(now.formatted(.dateTime.year()))")
            figure("\(streak)", streak == 1 ? "day in a row" : "days in a row")

            Spacer(minLength: 0)

            ActivityDots(today: now)
        }
        .accessibilityElement(children: .combine)
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 34, weight: .regular))
                .monospacedDigit()
                .foregroundStyle(ListrTheme.ink)
                .contentTransition(.numericText())
                .animation(.snappy, value: value)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(ListrTheme.mutedLabel)
        }
        .fixedSize()
    }

    static func duration(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}

// Five weeks of days, oldest first. A day you listened is a solid dot, darker for longer.
private struct ActivityDots: View {
    @Environment(ListeningStatsStore.self) private var stats

    let today: Date

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                ForEach(0..<5, id: \.self) { week in
                    GridRow {
                        ForEach(0..<7, id: \.self) { weekday in
                            dot(daysAgo: 34 - (week * 7 + weekday))
                        }
                    }
                }
            }
            Text("Last 5 weeks")
                .font(.system(size: 11))
                .foregroundStyle(ListrTheme.mutedLabel)
        }
    }

    private func dot(daysAgo: Int) -> some View {
        let day = Calendar.current.date(byAdding: .day, value: -daysAgo, to: today) ?? today
        let seconds = stats.seconds(on: day)
        let listened = seconds >= 60
        // Half an hour or more reads as fully dark.
        let strength = 0.35 + 0.65 * min(seconds / 1800, 1)

        return Circle()
            .fill(ListrTheme.ink.opacity(listened ? strength : 0.14))
            .frame(width: listened ? 9 : 5, height: listened ? 9 : 5)
            .frame(width: 10, height: 10)
            .overlay {
                if daysAgo == 0 {
                    Circle()
                        .strokeBorder(ListrTheme.ink.opacity(0.35), lineWidth: 1)
                        .frame(width: 16, height: 16)
                }
            }
            .help("\(day.formatted(.dateTime.day().month(.wide))): \(ListeningSummary.duration(seconds))")
    }
}
