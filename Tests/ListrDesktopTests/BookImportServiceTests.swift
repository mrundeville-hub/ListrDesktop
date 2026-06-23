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

private extension Archive {
    func addData(_ path: String, _ string: String) throws {
        let data = Data(string.utf8)
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
