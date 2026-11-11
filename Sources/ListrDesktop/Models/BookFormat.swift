import Foundation
import UniformTypeIdentifiers

enum BookFormat: String, CaseIterable, Identifiable, Sendable, Codable {
    case fb2
    case epub
    case plainText

    var id: String { rawValue }

    static let supportedTypes: [UTType] = [
        UTType(filenameExtension: "fb2") ?? .xml,
        UTType(filenameExtension: "epub") ?? .data,
        UTType(filenameExtension: "fbz") ?? .zip,
        .zip, // .fb2.zip, the way FB2 books are usually downloaded
        .plainText,
        .text
    ]

    static func detect(from url: URL) -> BookFormat? {
        switch url.pathExtension.lowercased() {
        case "fb2", "fbz", "zip": .fb2
        case "epub": .epub
        case "txt", "text": .plainText
        default: nil
        }
    }
}
