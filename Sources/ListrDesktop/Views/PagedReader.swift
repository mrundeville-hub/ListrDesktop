import AppKit
import SwiftUI

// The chapter set as book pages that fit the view. The page holding the spoken word stays still
// while the highlight runs down it; when the voice moves past its last line the next page fades
// in, so the eye reads each page top to bottom instead of chasing scrolling text.
struct PagedReader: View {
    @Environment(PlaybackStore.self) private var playbackStore

    let fontSize: CGFloat
    var margin: CGFloat = 48

    @State private var pages: [NSRange] = []

    private var font: NSFont { .listrReading(size: fontSize) }
    private var lineSpacing: CGFloat { (fontSize * 0.5).rounded() } // ~1.6 line height, as book apps use

    var body: some View {
        GeometryReader { geo in
            // A readable measure (~65 characters) centered, and never closer than `margin` to an edge.
            let width = max(min(fontSize * 30, geo.size.width - 2 * margin), 120)
            let height = max(geo.size.height - margin - Self.footerHeight, fontSize * 4)
            let index = pageIndex

            VStack(spacing: 0) {
                Text(playbackStore.highlightedPage(pages.indices.contains(index) ? pages[index] : nil, font: font))
                    .lineSpacing(lineSpacing)
                    // No .textSelection: it turns the page into an AppKit text field that is laid
                    // out again on every word, and whose per-word links make each accessibility
                    // query walk the whole page. That alone kept a core busy.
                    .listrSeeksOnWordClick(playbackStore)
                    .frame(width: width, height: height, alignment: .topLeading)
                    .id(index)
                    .transition(.opacity)

                Text(pages.count > 1 ? "Page \(index + 1) of \(pages.count)" : " ")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .frame(height: Self.footerHeight)
            }
            .padding(.top, margin)
            .frame(maxWidth: .infinity)
            .animation(.easeInOut(duration: 0.35), value: index)
            .task(id: PageLayout(chapter: playbackStore.currentChapterID, width: width, height: height)) {
                // Re-paginate once a resize settles, not on every frame of it.
                if !pages.isEmpty { try? await Task.sleep(for: .milliseconds(150)) }
                guard !Task.isCancelled else { return }
                // Keep a line spare: SwiftUI may break a line a little differently from TextKit.
                pages = ReaderPages.split(
                    playbackStore.currentText, font: font, lineSpacing: lineSpacing,
                    size: CGSize(width: width, height: height - font.listrLineHeight(lineSpacing))
                )
            }
        }
    }

    private static let footerHeight: CGFloat = 40

    private var pageIndex: Int {
        guard let word = playbackStore.currentWord else { return 0 }
        return pages.lastIndex { $0.location <= word.location } ?? 0
    }
}

private struct PageLayout: Equatable {
    var chapter: Chapter.ID?
    var width: CGFloat
    var height: CGFloat
}

enum ReaderPages {
    /// Splits `text` into the ranges (UTF-16, like NSRange) that fill one `size` page each.
    /// Blank lines a page would start with are left off it.
    static func split(_ text: String, font: NSFont, lineSpacing: CGFloat, size: CGSize) -> [NSRange] {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.lineBreakStrategy = .standard
        let storage = NSTextStorage(string: text, attributes: [.font: font, .paragraphStyle: style])
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)

        let string = storage.string as NSString
        var pages: [NSRange] = []
        var location = 0
        while location < string.length {
            let container = NSTextContainer(size: size)
            container.lineFragmentPadding = 0
            layout.addTextContainer(container)
            let page = layout.characterRange(forGlyphRange: layout.glyphRange(for: container), actualGlyphRange: nil)
            guard page.length > 0 else { break } // too small for even one line

            var start = page.location
            while start < NSMaxRange(page), CharacterSet.whitespacesAndNewlines.contains(UnicodeScalar(string.character(at: start)) ?? " ") {
                start += 1
            }
            if start < NSMaxRange(page) {
                pages.append(NSRange(location: start, length: NSMaxRange(page) - start))
            }
            location = NSMaxRange(page)
        }
        return pages
    }
}

extension NSFont {
    /// New York, the serif Apple's own reading apps set long text in.
    static func listrReading(size: CGFloat) -> NSFont {
        let base = NSFont.systemFont(ofSize: size)
        return base.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: size) } ?? base
    }

    func listrLineHeight(_ lineSpacing: CGFloat) -> CGFloat {
        NSLayoutManager().defaultLineHeight(for: self) + lineSpacing
    }
}

extension PlaybackStore {
    /// One page of the chapter, karaoke style: what was read is solid, what is coming is faded,
    /// and the spoken word gets a soft wash (no weight change, so the text never reflows).
    /// Every word links to its own moment in the audio. `nil` shows the start of the chapter.
    func highlightedPage(_ page: NSRange?, font: NSFont) -> AttributedString {
        let source = currentText as NSString
        let page = page ?? NSRange(location: 0, length: min(source.length, 1200))
        let word = currentWord.map { NSRange(location: $0.location, length: $0.length) }

        var text = AttributedString(source.substring(with: page))
        text.font = Font(font as CTFont)
        text.foregroundColor = ListrTheme.ink.opacity(word == nil ? 0.6 : 0.4)

        if let word {
            let read = NSRange(location: 0, length: min(max(word.location - page.location, 0), page.length))
            if let range = Range(read, in: text) { text[range].foregroundColor = ListrTheme.ink }
            if let range = Range(NSRange(location: word.location - page.location, length: word.length), in: text) {
                text[range].foregroundColor = ListrTheme.ink
                text[range].backgroundColor = ListrTheme.highlight.opacity(0.7)
            }
        }

        for word in words(in: page) {
            guard let range = Range(NSRange(location: word.location - page.location, length: word.length), in: text) else { continue }
            text[range].link = URL(string: "listr-seek:\(word.start)")
        }
        return text
    }
}
