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

/// A stretch of text whose start and end in the audio are known exactly: a sentence (Piper,
/// Silero) or a single word (system voice). Engines write these next to the audio they produce.
struct TimingSegment: Codable, Sendable, Equatable {
    var location: Int // UTF-16 offsets into the chapter text, like NSRange
    var length: Int
    var start: TimeInterval
    var end: TimeInterval

    static func sidecarURL(for audioURL: URL) -> URL {
        audioURL.appendingPathExtension("segments.json")
    }

    /// Reads and removes the sidecar an engine left for `audioURL`, if it left one.
    static func takeSidecar(for audioURL: URL) -> [TimingSegment] {
        let url = sidecarURL(for: audioURL)
        defer { try? FileManager.default.removeItem(at: url) }
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([TimingSegment].self, from: data)) ?? []
    }
}

enum ChapterTimingBuilder {
    /// Word timings for a chapter. With `segments` the words are only spread inside each known
    /// stretch, so the highlight can never drift further than one sentence. Without them the
    /// whole chapter is one stretch — an estimate.
    static func build(text: String, duration: TimeInterval, segments: [TimingSegment] = []) -> ChapterTiming {
        let words = tokenize(text)
        guard !words.isEmpty else {
            return ChapterTiming(text: text, words: [])
        }

        let spans = segments.isEmpty
            ? [TimingSegment(location: 0, length: (text as NSString).length, start: 0, end: max(duration, Double(words.count) * 0.18))]
            : segments.sorted { $0.start < $1.start }

        var timedWords: [ChapterWordTiming] = []
        var nextWord = 0
        for (spanIndex, span) in spans.enumerated() {
            // The last span also takes any words past its end, so none are dropped.
            let spanEnd = spanIndex == spans.count - 1 ? Int.max : span.location + span.length
            var spanWords: [Word] = []
            while nextWord < words.count, words[nextWord].location < spanEnd {
                spanWords.append(words[nextWord])
                nextWord += 1
            }
            guard !spanWords.isEmpty else { continue }

            let totalWeight = spanWords.reduce(0.0) { $0 + $1.weight }
            var cursor = span.start
            for word in spanWords {
                let wordDuration = max(span.end - span.start, 0) * word.weight / totalWeight
                timedWords.append(ChapterWordTiming(
                    index: timedWords.count,
                    text: word.text,
                    location: word.location,
                    length: word.length,
                    start: cursor,
                    end: cursor + wordDuration
                ))
                cursor += wordDuration
            }
        }

        return ChapterTiming(text: text, words: timedWords)
    }

    private struct Word {
        let text: String
        let location: Int
        let length: Int
        let weight: Double
    }

    private static func tokenize(_ text: String) -> [Word] {
        guard let regex = try? NSRegularExpression(pattern: #"[\p{L}\p{N}]+(?:[-'’][\p{L}\p{N}]+)*"#) else {
            return []
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        return matches.enumerated().map { index, match in
            let word = nsText.substring(with: match.range)
            // What sits between this word and the next decides how long the voice pauses after it.
            let gapEnd = index + 1 < matches.count ? matches[index + 1].range.location : nsText.length
            let gap = nsText.substring(with: NSRange(location: NSMaxRange(match.range), length: gapEnd - NSMaxRange(match.range)))
            return Word(
                text: word,
                location: match.range.location,
                length: match.range.length,
                weight: Double(word.count) + 1.4 + pauseWeight(after: gap)
            )
        }
    }

    // ponytail: fixed guesses in "letters' worth of time"; only matters for estimated stretches.
    private static func pauseWeight(after gap: String) -> Double {
        if gap.contains(where: { ".!?…".contains($0) }) { return 7 }
        if gap.contains(where: { ",;:—–".contains($0) }) { return 3 }
        return 0
    }
}
