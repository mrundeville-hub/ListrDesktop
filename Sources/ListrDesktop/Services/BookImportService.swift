import Foundation
import ZIPFoundation

enum BookImportError: LocalizedError {
    case unsupportedFormat(String)
    case unreadableFile
    case emptyBook
    case invalidEPUB(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext): "Unsupported book format: \(ext)"
        case .unreadableFile: "The selected file could not be read."
        case .emptyBook: "No readable chapters were found in this book."
        case .invalidEPUB(let reason): "Invalid EPUB: \(reason)"
        }
    }
}

struct ImportedBook: Sendable {
    var title: String
    var author: String
    var format: BookFormat
    var chapters: [Chapter]
    var sourceURL: URL
}

struct BookImportService: Sendable {
    func importBook(from url: URL) throws -> ImportedBook {
        guard let format = BookFormat.detect(from: url) else {
            throw BookImportError.unsupportedFormat(url.pathExtension)
        }

        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }

        switch format {
        case .fb2:
            return try FB2BookParser().parse(url: url)
        case .epub:
            return try EPUBBookParser().parse(url: url)
        case .plainText:
            return try PlainTextBookParser().parse(url: url)
        }
    }
}

private struct PlainTextBookParser {
    func parse(url: URL) throws -> ImportedBook {
        // Russian .txt books are as often Windows-1251 as UTF-8.
        guard let text = TextCleaner.decodeHTML(try Data(contentsOf: url)) else {
            throw BookImportError.unreadableFile
        }
        let cleaned = TextCleaner.clean(text)
        guard !cleaned.isEmpty else { throw BookImportError.emptyBook }

        return ImportedBook(
            title: url.deletingPathExtension().lastPathComponent,
            author: "Unknown author",
            format: .plainText,
            chapters: ChapterSplitter.split(cleaned),
            sourceURL: url
        )
    }
}

private struct FB2BookParser {
    func parse(url: URL) throws -> ImportedBook {
        let data = try Data(contentsOf: url)
        let delegate = FB2XMLDelegate(fallbackTitle: url.deletingPathExtension().lastPathComponent)
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            throw parser.parserError ?? BookImportError.unreadableFile
        }

        let chapters = delegate.chapters.isEmpty ? ChapterSplitter.split(delegate.fullText) : delegate.chapters
        guard !chapters.isEmpty else { throw BookImportError.emptyBook }

        return ImportedBook(
            title: delegate.title,
            author: delegate.author,
            format: .fb2,
            chapters: chapters,
            sourceURL: url
        )
    }
}

private final class FB2XMLDelegate: NSObject, XMLParserDelegate {
    private let fallbackTitle: String
    private var path: [String] = []
    private var titleBuffer = ""
    private var firstName = ""
    private var middleName = ""
    private var lastName = ""
    private var sectionDepth = 0
    private var isInNotesBody = false
    private static let textElements: Set<String> = ["p", "subtitle", "text-author", "v"]
    private var chapterTitle = ""
    private var chapterText = ""

    private(set) var title: String
    private(set) var fullText = ""
    private(set) var chapters: [Chapter] = []

    var author: String {
        let name = [firstName, middleName, lastName]
            .map(TextCleaner.clean)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return name.isEmpty ? "Unknown author" : name
    }

    init(fallbackTitle: String) {
        self.fallbackTitle = fallbackTitle
        self.title = fallbackTitle
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        path.append(elementName)
        if elementName == "body", attributeDict["name"] == "notes" {
            isInNotesBody = true // footnotes are not chapters
        }
        if elementName == "section", isInBody {
            // Every section is its own chapter, so "Part → Chapter" books keep their chapters.
            appendChapter()
            sectionDepth += 1
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if pathSuffix(["description", "title-info", "book-title"]) {
            titleBuffer += string
        } else if pathSuffix(["description", "title-info", "author", "first-name"]) {
            firstName += string
        } else if pathSuffix(["description", "title-info", "author", "middle-name"]) {
            middleName += string
        } else if pathSuffix(["description", "title-info", "author", "last-name"]) {
            lastName += string
        } else if sectionDepth > 0, path.contains("title") {
            chapterTitle += string
        } else if shouldCollectBodyText {
            // Text outside any <section> only feeds the fallback split for section-less books.
            fullText += string
            if sectionDepth > 0 { chapterText += string }
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "book-title" {
            let cleanedTitle = TextCleaner.clean(titleBuffer)
            if !cleanedTitle.isEmpty { title = cleanedTitle }
        }

        if isInBody, Self.textElements.contains(elementName) {
            // Paragraphs carry no whitespace of their own; without this they fuse together.
            if sectionDepth > 0, path.contains("title") {
                chapterTitle += " "
            } else {
                fullText += "\n"
                if sectionDepth > 0 { chapterText += "\n" }
            }
        }

        if elementName == "section", isInBody {
            appendChapter()
            sectionDepth -= 1
        }
        if elementName == "body" {
            isInNotesBody = false
        }
        _ = path.popLast()
    }

    private var isInBody: Bool {
        path.contains("body") && !isInNotesBody
    }

    private var shouldCollectBodyText: Bool {
        // Any depth, so <emphasis>/<strong> inside a paragraph is kept; <a> is a footnote marker.
        guard isInBody, !path.contains("a") else { return false }
        return path.contains(where: Self.textElements.contains)
    }

    private func pathSuffix(_ suffix: [String]) -> Bool {
        path.suffix(suffix.count).elementsEqual(suffix)
    }

    private func appendChapter() {
        let text = TextCleaner.clean(chapterText)
        let cleanedTitle = TextCleaner.clean(chapterTitle)
        chapterTitle = ""
        chapterText = ""
        guard !text.isEmpty else { return }
        chapters.append(Chapter(
            id: UUID(),
            index: chapters.count + 1,
            title: cleanedTitle.isEmpty ? "Chapter \(chapters.count + 1)" : cleanedTitle,
            text: text,
            status: .pending,
            audioPath: nil,
            timingPath: nil
        ))
    }
}

private struct EPUBBookParser {
    func parse(url: URL) throws -> ImportedBook {
        let archive = try Archive(url: url, accessMode: .read)

        let containerData = try data(named: "META-INF/container.xml", in: archive)
        let rootfilePath = try EPUBContainerParser.parse(data: containerData)
        let opfData = try data(named: rootfilePath, in: archive)
        let package = try EPUBPackageParser.parse(data: opfData)
        let basePath = URL(fileURLWithPath: rootfilePath).deletingLastPathComponent().relativePath

        var chapters: [Chapter] = []
        for itemID in package.spineIDs {
            guard let href = package.manifest[itemID] else { continue }
            let chapterPath = normalizedEPUBPath(basePath: basePath, href: href)
            guard let chapterData = try? data(named: chapterPath, in: archive),
                  let html = TextCleaner.decodeHTML(chapterData) else {
                continue
            }
            let text = TextCleaner.htmlToText(html)
            guard !text.isEmpty else { continue }
            chapters.append(Chapter(
                id: UUID(),
                index: chapters.count + 1,
                title: TextCleaner.firstHeading(in: html) ?? "Chapter \(chapters.count + 1)",
                text: text,
                status: .pending,
                audioPath: nil,
                timingPath: nil
            ))
        }

        guard !chapters.isEmpty else { throw BookImportError.emptyBook }

        return ImportedBook(
            title: package.title.isEmpty ? url.deletingPathExtension().lastPathComponent : package.title,
            author: package.author.isEmpty ? "Unknown author" : package.author,
            format: .epub,
            chapters: chapters,
            sourceURL: url
        )
    }

    private func data(named path: String, in archive: Archive) throws -> Data {
        guard let entry = archive[path] else {
            throw BookImportError.invalidEPUB("missing \(path)")
        }
        var data = Data()
        _ = try archive.extract(entry) { chunk in
            data.append(chunk)
        }
        return data
    }

    private func normalizedEPUBPath(basePath: String, href: String) -> String {
        let normalizedBase = basePath == "." ? "" : basePath
        let hrefWithoutAnchor = href
            .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
            .split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let combined = normalizedBase.isEmpty ? String(hrefWithoutAnchor) : "\(normalizedBase)/\(hrefWithoutAnchor)"
        let decoded = combined.removingPercentEncoding ?? combined
        return normalizePathSegments(decoded)
    }

    private func normalizePathSegments(_ path: String) -> String {
        var result: [String] = []
        for segment in path.split(separator: "/", omittingEmptySubsequences: false).map(String.init) {
            switch segment {
            case "", ".":
                continue
            case "..":
                if !result.isEmpty {
                    result.removeLast()
                }
            default:
                result.append(segment)
            }
        }
        return result.joined(separator: "/")
    }
}

private struct EPUBPackage {
    var title: String
    var author: String
    var manifest: [String: String]
    var spineIDs: [String]
}

private final class EPUBContainerParser: NSObject, XMLParserDelegate {
    private var rootfilePath: String?

    static func parse(data: Data) throws -> String {
        let delegate = EPUBContainerParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), let rootfilePath = delegate.rootfilePath else {
            throw parser.parserError ?? BookImportError.invalidEPUB("container has no rootfile")
        }
        return rootfilePath
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "rootfile", rootfilePath == nil {
            rootfilePath = attributeDict["full-path"]
        }
    }
}

private final class EPUBPackageParser: NSObject, XMLParserDelegate {
    private var path: [String] = []
    private var titleBuffer = ""
    private var authorBuffer = ""
    private var manifest: [String: String] = [:]
    private var spineIDs: [String] = []

    static func parse(data: Data) throws -> EPUBPackage {
        let delegate = EPUBPackageParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw parser.parserError ?? BookImportError.invalidEPUB("could not parse OPF package")
        }
        return EPUBPackage(
            title: TextCleaner.clean(delegate.titleBuffer),
            author: TextCleaner.clean(delegate.authorBuffer),
            manifest: delegate.manifest,
            spineIDs: delegate.spineIDs
        )
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        path.append(elementName)
        if elementName == "item", let id = attributeDict["id"], let href = attributeDict["href"] {
            manifest[id] = href
        } else if elementName == "itemref", let idref = attributeDict["idref"], attributeDict["linear"] != "no" {
            spineIDs.append(idref)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if elementNameMatches(path.last, "title") {
            titleBuffer += string
        } else if elementNameMatches(path.last, "creator") {
            authorBuffer += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        _ = path.popLast()
    }

    private func elementNameMatches(_ value: String?, _ localName: String) -> Bool {
        guard let value else { return false }
        return value == localName || value.hasSuffix(":\(localName)")
    }
}

private enum ChapterSplitter {
    static func split(_ text: String) -> [Chapter] {
        let cleaned = TextCleaner.clean(text)
        guard !cleaned.isEmpty else { return [] }

        let separators = ["\n\n# ", "\n\nChapter ", "\n\nГлава "]
        for separator in separators where cleaned.contains(separator) {
            let parts = cleaned.components(separatedBy: separator)
            let texts = parts.enumerated()
                .map { index, part in
                    TextCleaner.clean(index == 0 ? part : separator.trimmingCharacters(in: .whitespacesAndNewlines) + part)
                }
                .filter { !$0.isEmpty }
            return texts.enumerated().map { index, chapterText in
                Chapter(id: UUID(), index: index + 1, title: "Chapter \(index + 1)", text: chapterText, status: .pending, audioPath: nil, timingPath: nil)
            }
        }

        return [Chapter(id: UUID(), index: 1, title: "Chapter 1", text: cleaned, status: .pending, audioPath: nil, timingPath: nil)]
    }
}

private enum TextCleaner {
    static func decodeHTML(_ data: Data) -> String? {
        if let declaredEncoding = declaredHTMLEncoding(in: data),
           let decoded = String(data: data, encoding: declaredEncoding) {
            return decoded
        }

        // UTF-16 only with a BOM: without one it "decodes" any even-length CP1251 file into garbage.
        let hasUTF16BOM = data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF])
        return String(data: data, encoding: .utf8)
            ?? (hasUTF16BOM ? String(data: data, encoding: .utf16) : nil)
            ?? String(data: data, encoding: .windowsCP1251)
            ?? String(data: data, encoding: .isoLatin1)
    }

    static func clean(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func htmlToText(_ html: String) -> String {
        var value = html
        // <head> goes too: its <title> would otherwise be read aloud at the start of every chapter.
        value = value.replacingOccurrences(of: #"(?i)<(head|script|style)\b[\s\S]*?</\1>"#, with: " ", options: .regularExpression)
        value = value.replacingOccurrences(of: #"</(p|div|section|chapter|h[1-6]|li)>"#, with: "\n\n", options: .regularExpression)
        value = value.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        value = decodeEntities(value)
        return clean(value)
    }

    static func firstHeading(in html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"<h[1-3][^>]*>([\s\S]*?)</h[1-3]>"#, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let titleRange = Range(match.range(at: 1), in: html) else {
            return nil
        }
        let title = htmlToText(String(html[titleRange]))
        return title.isEmpty ? nil : title
    }

    private static let namedEntities: [String: String] = [
        "nbsp": " ", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "amp": "&", "shy": "",
        "mdash": "—", "ndash": "–", "hellip": "…", "laquo": "«", "raquo": "»", "copy": "©"
    ]

    /// Named, decimal and hex entities in one pass, so "&amp;lt;" stays "&lt;".
    private static func decodeEntities(_ value: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"&(#[xX][0-9A-Fa-f]+|#\d+|[A-Za-z]+);"#) else {
            return value
        }

        let nsValue = value as NSString
        var result = value
        for match in regex.matches(in: value, range: NSRange(location: 0, length: nsValue.length)).reversed() {
            let name = nsValue.substring(with: match.range(at: 1))
            let replacement: String?
            if name.hasPrefix("#") {
                let isHex = name.dropFirst().lowercased().hasPrefix("x")
                let codePoint = isHex ? UInt32(name.dropFirst(2), radix: 16) : UInt32(name.dropFirst())
                replacement = codePoint.flatMap(UnicodeScalar.init).map(String.init)
            } else {
                replacement = namedEntities[name]
            }
            guard let replacement, let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: replacement)
        }
        return result
    }

    private static func declaredHTMLEncoding(in data: Data) -> String.Encoding? {
        guard
            let prefix = String(data: data.prefix(4096), encoding: .isoLatin1),
            let regex = try? NSRegularExpression(
                pattern: #"charset\s*=\s*["']?([A-Za-z0-9._-]+)"#,
                options: [.caseInsensitive]
            )
        else {
            return nil
        }

        let range = NSRange(prefix.startIndex..<prefix.endIndex, in: prefix)
        guard
            let match = regex.firstMatch(in: prefix, range: range),
            let encodingRange = Range(match.range(at: 1), in: prefix)
        else {
            return nil
        }

        switch prefix[encodingRange].lowercased() {
        case "utf-8", "utf8":
            return .utf8
        case "utf-16", "utf16":
            return .utf16
        case "windows-1251", "cp1251":
            return .windowsCP1251
        case "iso-8859-1", "latin1":
            return .isoLatin1
        default:
            return nil
        }
    }
}
