import Foundation
import Testing
import ZIPFoundation
@testable import ListrDesktop

@Suite("Book import")
struct BookImportServiceTests {
    @Test("imports FB2 metadata and sections")
    func importsFB2() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appending(path: "sample.fb2")
        try fb2Fixture.write(to: url, atomically: true, encoding: .utf8)

        let book = try BookImportService().importBook(from: url)

        #expect(book.format == .fb2)
        #expect(book.title == "Fixture Book")
        #expect(book.author == "Ada Lovelace")
        #expect(book.chapters.count == 2)
        #expect(book.chapters[0].title == "First Chapter")
        #expect(book.chapters[0].text.contains("First paragraph"))
        #expect(book.chapters[1].title == "Second Chapter")
    }

    @Test("imports EPUB spine chapters")
    func importsEPUB() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appending(path: "sample.epub")
        try makeEPUB(at: url)

        let book = try BookImportService().importBook(from: url)

        #expect(book.format == .epub)
        #expect(book.title == "EPUB Fixture")
        #expect(book.author == "Test Author")
        #expect(book.chapters.map(\.title) == ["Opening", "Ending"])
        #expect(book.chapters[0].text.contains("The first EPUB chapter"))
        #expect(book.chapters[1].text.contains("The final EPUB chapter"))
    }

    @Test("imports EPUB chapters with nested paths, anchors, and declared encoding")
    func importsMessyEPUBPathsAndEncoding() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appending(path: "messy.epub")
        try makeMessyEPUB(at: url)

        let book = try BookImportService().importBook(from: url)

        #expect(book.format == .epub)
        #expect(book.title == "Messy EPUB")
        #expect(book.author == "Unknown author")
        #expect(book.chapters.map(\.title) == ["Вступление"])
        #expect(book.chapters[0].text.contains("Привет мир"))
        #expect(book.chapters[0].text.contains("©"))
    }
}

extension BookImportServiceTests {
    @Test("FB2 keeps inline text, separates paragraphs, splits nested sections, skips notes")
    func importsNestedFB2() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appending(path: "nested.fb2")
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <FictionBook><description><title-info><book-title>Nested</book-title></title-info></description>
        <body><section><title><p>Part One</p></title>
        <section><title><p>Alpha</p></title><p>One <emphasis>loud</emphasis> word.</p><p>Next<a type="note">[1]</a> line.</p></section>
        <section><title><p>Beta</p></title><p>Second text.</p></section>
        </section></body>
        <body name="notes"><section><p>Footnote text.</p></section></body>
        </FictionBook>
        """.write(to: url, atomically: true, encoding: .utf8)

        let book = try BookImportService().importBook(from: url)

        #expect(book.chapters.map(\.title) == ["Alpha", "Beta"])
        #expect(book.chapters[0].text == "One loud word. Next line.")
        #expect(book.chapters.map(\.index) == [1, 2])
    }

    @Test("FB2 without sections still imports its text")
    func importsSectionlessFB2() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appending(path: "flat.fb2")
        try """
        <?xml version="1.0" encoding="utf-8"?>
        <FictionBook><description><title-info><book-title>Flat</book-title></title-info></description>
        <body><p>First paragraph.</p><p>Second paragraph.</p></body></FictionBook>
        """.write(to: url, atomically: true, encoding: .utf8)

        let book = try BookImportService().importBook(from: url)

        let text = book.chapters.map(\.text).joined(separator: "\n")
        #expect(text.contains("First paragraph."))
        #expect(text.contains("Second paragraph."))
        #expect(!text.contains("paragraph.Second"))
    }

    @Test("EPUB chapters follow the table of contents, small files join their chapter, cover is read")
    func importsEPUBByTableOfContents() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appending(path: "toc.epub")
        let archive = try Archive(url: url, accessMode: .create)
        try archive.addData("META-INF/container.xml", """
        <container><rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles></container>
        """)
        try archive.addData("OEBPS/content.opf", """
        <package><metadata><dc:title>Split Book</dc:title><meta name="cover" content="img"/></metadata>
        <manifest>
          <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
          <item id="img" href="images/front.jpg" media-type="image/jpeg"/>
          <item id="a" href="text/a.xhtml" media-type="application/xhtml+xml"/>
          <item id="b" href="text/b.xhtml" media-type="application/xhtml+xml"/>
          <item id="c" href="text/c.xhtml" media-type="application/xhtml+xml"/>
          <item id="d" href="text/d.xhtml" media-type="application/xhtml+xml"/>
        </manifest>
        <spine toc="ncx"><itemref idref="a"/><itemref idref="b"/><itemref idref="c"/><itemref idref="d"/></spine></package>
        """)
        try archive.addData("OEBPS/toc.ncx", """
        <ncx><navMap>
          <navPoint><navLabel><text>The Storm</text></navLabel><content src="text/b.xhtml#top"/></navPoint>
          <navPoint><navLabel><text>The Calm</text></navLabel><content src="text/d.xhtml"/></navPoint>
        </navMap></ncx>
        """)
        try archive.addData("OEBPS/images/front.jpg", Data([0xFF, 0xD8, 0xFF, 0xE0]))
        try archive.addData("OEBPS/text/a.xhtml", "<html><body><p>Dedication.</p></body></html>")
        try archive.addData("OEBPS/text/b.xhtml", "<html><body><p>Wind rose.</p></body></html>")
        try archive.addData("OEBPS/text/c.xhtml", "<html><body><p>Rain fell.</p></body></html>")
        try archive.addData("OEBPS/text/d.xhtml", "<html><body><p>Sun came.</p></body></html>")

        let book = try BookImportService().importBook(from: url)

        #expect(book.chapters.map(\.title) == ["Beginning", "The Storm", "The Calm"])
        #expect(book.chapters[1].text == "Wind rose. Rain fell.")
        #expect(book.coverData == Data([0xFF, 0xD8, 0xFF, 0xE0]))
    }

    @Test("EPUB footnotes kept as numbered files at the end are not chapters")
    func dropsEPUBFootnoteFiles() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appending(path: "notes.epub")
        let archive = try Archive(url: url, accessMode: .create)
        let notes = (1...25).map { "n\($0)" }
        try archive.addData("META-INF/container.xml", """
        <container><rootfiles><rootfile full-path="content.opf"/></rootfiles></container>
        """)
        try archive.addData("content.opf", """
        <package><metadata><dc:title>Noted</dc:title></metadata><manifest>
        <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
        <item id="one" href="one.xhtml" media-type="application/xhtml+xml"/>
        <item id="two" href="two.xhtml" media-type="application/xhtml+xml"/>
        \(notes.map { #"<item id="\#($0)" href="\#($0).xhtml" media-type="application/xhtml+xml"/>"# }.joined())
        </manifest><spine toc="ncx"><itemref idref="one"/><itemref idref="two"/>
        \(notes.map { #"<itemref idref="\#($0)"/>"# }.joined())</spine></package>
        """)
        try archive.addData("toc.ncx", """
        <ncx><navMap>
        <navPoint><navLabel><text>1</text></navLabel><content src="one.xhtml"/></navPoint>
        <navPoint><navLabel><text>2</text></navLabel><content src="two.xhtml"/></navPoint>
        \((1...25).map { "<navPoint><navLabel><text>\($0)</text></navLabel><content src=\"n\($0).xhtml\"/></navPoint>" }.joined())
        </navMap></ncx>
        """)
        let longChapter = String(repeating: "A real chapter sentence. ", count: 200)
        try archive.addData("one.xhtml", "<html><body><p>\(longChapter)</p></body></html>")
        try archive.addData("two.xhtml", "<html><body><p>\(longChapter)</p></body></html>")
        for (index, note) in notes.enumerated() {
            try archive.addData("\(note).xhtml", "<html><body><p>\(index + 1) A short footnote.</p></body></html>")
        }

        let book = try BookImportService().importBook(from: url)

        #expect(book.chapters.map(\.title) == ["1", "2"])
    }

    @Test("zipped FB2 imports, with its cover")
    func importsZippedFB2WithCover() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appending(path: "book.fb2.zip")
        let archive = try Archive(url: url, accessMode: .create)
        try archive.addData("inner name.fb2", """
        <?xml version="1.0" encoding="utf-8"?>
        <FictionBook xmlns:l="http://www.w3.org/1999/xlink"><description><title-info>
        <book-title>Zipped</book-title><coverpage><image l:href="#cover.jpg"/></coverpage>
        </title-info></description>
        <body><section><title><p>One</p></title><p>Text.</p></section></body>
        <binary id="other.png" content-type="image/png">AAAA</binary>
        <binary id="cover.jpg" content-type="image/jpeg">/9j/
        4A==</binary></FictionBook>
        """)

        #expect(BookFormat.detect(from: url) == .fb2)
        let book = try BookImportService().importBook(from: url)

        #expect(book.title == "Zipped")
        #expect(book.chapters.map(\.title) == ["One"])
        #expect(book.coverData == Data([0xFF, 0xD8, 0xFF, 0xE0]))
    }

    @Test("TXT in Windows-1251 imports as Russian text, not garbage")
    func importsCP1251Text() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appending(path: "book.txt")
        try #require("Привет, мир".data(using: .windowsCP1251)).write(to: url)

        let book = try BookImportService().importBook(from: url)

        #expect(book.chapters[0].text == "Привет, мир")
    }

    @Test("EPUB drops <head> text and decodes named and hex entities")
    func cleansEPUBHTML() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appending(path: "head.epub")
        let archive = try Archive(url: url, accessMode: .create)
        try archive.addData("META-INF/container.xml", #"<container><rootfiles><rootfile full-path="c.opf"/></rootfiles></container>"#)
        try archive.addData("c.opf", #"<package><manifest><item id="a" href="a.xhtml"/></manifest><spine><itemref idref="a"/></spine></package>"#)
        try archive.addData("a.xhtml", "<html><head><title>HEADTITLE</title></head><body><h1>T</h1><p>&laquo;Да&raquo; &#x2014; &amp;lt;</p></body></html>")

        let book = try BookImportService().importBook(from: url)

        #expect(book.chapters[0].text == "T «Да» — &lt;")
    }
}

private let fb2Fixture = """
<?xml version="1.0" encoding="UTF-8"?>
<FictionBook>
  <description>
    <title-info>
      <author><first-name>Ada</first-name><last-name>Lovelace</last-name></author>
      <book-title>Fixture Book</book-title>
    </title-info>
  </description>
  <body>
    <section>
      <title><p>First Chapter</p></title>
      <p>First paragraph for narration.</p>
      <p>Second paragraph.</p>
    </section>
    <section>
      <title><p>Second Chapter</p></title>
      <p>Another readable section.</p>
    </section>
  </body>
</FictionBook>
"""

private func makeEPUB(at url: URL) throws {
    let archive = try Archive(url: url, accessMode: .create)

    try archive.addData("mimetype", "application/epub+zip")
    try archive.addData("META-INF/container.xml", """
    <?xml version="1.0"?>
    <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
      <rootfiles>
        <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
      </rootfiles>
    </container>
    """)
    try archive.addData("OEBPS/content.opf", """
    <?xml version="1.0" encoding="UTF-8"?>
    <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
      <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
        <dc:title>EPUB Fixture</dc:title>
        <dc:creator>Test Author</dc:creator>
      </metadata>
      <manifest>
        <item id="chapter1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
        <item id="chapter2" href="chapter2.xhtml" media-type="application/xhtml+xml"/>
      </manifest>
      <spine>
        <itemref idref="chapter1"/>
        <itemref idref="chapter2"/>
      </spine>
    </package>
    """)
    try archive.addData("OEBPS/chapter1.xhtml", """
    <html xmlns="http://www.w3.org/1999/xhtml"><body><h1>Opening</h1><p>The first EPUB chapter.</p></body></html>
    """)
    try archive.addData("OEBPS/chapter2.xhtml", """
    <html xmlns="http://www.w3.org/1999/xhtml"><body><h1>Ending</h1><p>The final EPUB chapter.</p></body></html>
    """)
}

private func makeMessyEPUB(at url: URL) throws {
    let archive = try Archive(url: url, accessMode: .create)

    try archive.addData("mimetype", "application/epub+zip")
    try archive.addData("META-INF/container.xml", """
    <?xml version="1.0"?>
    <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
      <rootfiles>
        <rootfile full-path="OPS/package/content.opf" media-type="application/oebps-package+xml"/>
      </rootfiles>
    </container>
    """)
    try archive.addData("OPS/package/content.opf", """
    <?xml version="1.0" encoding="UTF-8"?>
    <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
      <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
        <dc:title>Messy EPUB</dc:title>
      </metadata>
      <manifest>
        <item id="chapter1" href="../Text/chapter%201.xhtml#body" media-type="application/xhtml+xml"/>
      </manifest>
      <spine>
        <itemref idref="chapter1"/>
      </spine>
    </package>
    """)

    let chapter = """
    <html><head><meta charset="windows-1251"></head><body><h1>Вступление</h1><p>Привет мир &#169;</p></body></html>
    """
    try archive.addData(
        "OPS/Text/chapter 1.xhtml",
        chapter.data(using: .windowsCP1251)!
    )
}

private extension Archive {
    func addData(_ path: String, _ string: String) throws {
        let data = Data(string.utf8)
        try addData(path, data)
    }

    func addData(_ path: String, _ data: Data) throws {
        try addEntry(
            with: path,
            type: .file,
            uncompressedSize: Int64(data.count),
            compressionMethod: .none
        ) { position, size in
            data.subdata(in: Int(position)..<Int(position) + size)
        }
    }
}

private struct TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
