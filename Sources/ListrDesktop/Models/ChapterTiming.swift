import Foundation

struct ChapterTiming: Codable, Sendable, Equatable {
    var text: String
    var words: [ChapterWordTiming]

    func word(at elapsed: TimeInterval) -> ChapterWordTiming? {
        words.first { elapsed >= $0.start && elapsed < $0.end } ?? words.last(where: { elapsed >= $0.start })
    }
}

struct ChapterWordTiming: Codable, Sendable, Equatable, Identifiable {
    var id: Int { index }
    var index: Int
    var text: String
    var location: Int
    var length: Int
    var start: TimeInterval
    var end: TimeInterval
}

enum ChapterTimingBuilder {
    static func build(text: String, duration: TimeInterval) -> ChapterTiming {
        let words = tokenize(text)
        guard !words.isEmpty else {
            return ChapterTiming(text: text, words: [])
        }

        let usableDuration = max(duration, Double(words.count) * 0.18)
        let totalWeight = words.reduce(0.0) { total, word in
            total + weight(for: word.text)
        }

        var cursor: TimeInterval = 0
        let timedWords = words.enumerated().map { index, word in
            let share = weight(for: word.text) / totalWeight
            let wordDuration = max(usableDuration * share, 0.12)
            let start = min(cursor, usableDuration)
            let end = min(cursor + wordDuration, usableDuration)
            cursor = end

            return ChapterWordTiming(
                index: index,
                text: word.text,
                location: word.location,
                length: word.length,
                start: start,
                end: max(end, start + 0.08)
            )
        }

        return ChapterTiming(text: text, words: timedWords)
    }

    private static func tokenize(_ text: String) -> [(text: String, location: Int, length: Int)] {
        guard let regex = try? NSRegularExpression(pattern: #"[\p{L}\p{N}]+(?:[-'’][\p{L}\p{N}]+)*"#) else {
            return []
        }

        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        return regex.matches(in: text, range: range).map { match in
            (
                text: nsText.substring(with: match.range),
                location: match.range.location,
                length: match.range.length
            )
        }
    }

    private static func weight(for word: String) -> Double {
        max(Double(word.count), 1) + 1.4
    }
}
