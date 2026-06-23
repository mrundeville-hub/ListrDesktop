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
        let text = try String(contentsOf: url, encoding: .utf8)
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
        if elementName == "section", isInBody {
            if sectionDepth == 0 {
                chapterTitle = ""
                chapterText = ""
            }
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
        } else if sectionDepth > 0, path.last == "title" {
            chapterTitle += string
        } else if sectionDepth > 0, shouldCollectBodyText {
            chapterText += string
            fullText += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "book-title" {
            let cleanedTitle = TextCleaner.clean(titleBuffer)
            if !cleanedTitle.isEmpty { title = cleanedTitle }
        }

        if elementName == "section", isInBody {
            sectionDepth -= 1
            if sectionDepth == 0 {
                appendChapter()
            }
        }
        _ = path.popLast()
    }

    private var isInBody: Bool {
        path.contains("body")
    }

    private var shouldCollectBodyText: Bool {
        guard isInBody else { return false }
        return ["p", "subtitle", "text-author", "v"].contains(path.last)
    }

    private func pathSuffix(_ suffix: [String]) -> Bool {
        path.suffix(suffix.count).elementsEqual(suffix)
    }

    private func appendChapter() {
        let text = TextCleaner.clean(chapterText)
        guard !text.isEmpty else { return }
        let cleanedTitle = TextCleaner.clean(chapterTitle)
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
                  let html = String(data: chapterData, encoding: .utf8) ?? String(data: chapterData, encoding: .windowsCP1251) else {
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
        let combined = normalizedBase.isEmpty ? href : "\(normalizedBase)/\(href)"
        return combined.removingPercentEncoding ?? combined
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
        } else if elementName == "itemref", let idref = attributeDict["idref"] {
            spineIDs.append(idref)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if path.last == "title" {
            titleBuffer += string
        } else if path.last == "creator" {
            authorBuffer += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        _ = path.popLast()
    }
}

private enum ChapterSplitter {
    static func split(_ text: String) -> [Chapter] {
        let cleaned = TextCleaner.clean(text)
        guard !cleaned.isEmpty else { return [] }

        let separators = ["\n\n# ", "\n\nChapter ", "\n\nГлава "]
        for separator in separators where cleaned.contains(separator) {
            let parts = cleaned.components(separatedBy: separator)
            return parts.enumerated().compactMap { index, part in
                let chapterText = TextCleaner.clean(index == 0 ? part : separator.trimmingCharacters(in: .whitespacesAndNewlines) + part)
                guard !chapterText.isEmpty else { return nil }
                return Chapter(id: UUID(), index: index + 1, title: "Chapter \(index + 1)", text: chapterText, status: .pending, audioPath: nil, timingPath: nil)
            }
        }

        return [Chapter(id: UUID(), index: 1, title: "Chapter 1", text: cleaned, status: .pending, audioPath: nil, timingPath: nil)]
    }
}

private enum TextCleaner {
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
        value = value.replacingOccurrences(of: #"<script[\s\S]*?</script>"#, with: " ", options: .regularExpression)
        value = value.replacingOccurrences(of: #"<style[\s\S]*?</style>"#, with: " ", options: .regularExpression)
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

    private static func decodeEntities(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }
}
