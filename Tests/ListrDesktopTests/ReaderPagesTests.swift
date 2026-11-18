import AppKit
import Testing
@testable import ListrDesktop

@Suite("Reader pages")
struct ReaderPagesTests {
    @Test("pages run in order, never overlap and hold every word of the chapter")
    func coversText() {
        let text = (1...300).map { "Paragraph \($0) has a few words in it to wrap." }.joined(separator: "\n\n")
        let pages = ReaderPages.split(text, font: .listrReading(size: 20), lineSpacing: 10, size: CGSize(width: 400, height: 300))

        #expect(pages.count > 5)
        for (a, b) in zip(pages, pages.dropFirst()) { #expect(NSMaxRange(a) <= b.location) }
        #expect(NSMaxRange(pages.last!) == (text as NSString).length)
        let joined = pages.map { (text as NSString).substring(with: $0) }.joined()
        #expect(joined.filter { !$0.isWhitespace } == text.filter { !$0.isWhitespace })
    }
}
