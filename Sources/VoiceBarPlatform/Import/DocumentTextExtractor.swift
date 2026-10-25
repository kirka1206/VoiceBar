import Foundation
import PDFKit
import UniformTypeIdentifiers
import VoiceBarCore

public enum DocumentTextExtractorError: LocalizedError, Equatable {
    case unsupportedFormat(String)
    case cannotRead
    case invalidTextEncoding
    case invalidDocument
    case emptyDocument
    case encryptedPDF
    case noSearchableText

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let fileExtension):
            "Формат .\(fileExtension) не поддерживается."
        case .cannotRead:
            "Не удалось открыть выбранный файл."
        case .invalidTextEncoding:
            "Не удалось прочитать текстовую кодировку файла."
        case .invalidDocument:
            "Файл повреждён или не соответствует заявленному формату."
        case .emptyDocument:
            "В документе нет текста."
        case .encryptedPDF:
            "PDF защищён паролем и не может быть прочитан."
        case .noSearchableText:
            "В PDF нет извлекаемого текста. Для сканированных страниц OCR не выполняется."
        }
    }
}

public enum DocumentTextExtractor {
    private static let supportedExtensions: Set<String> = ["txt", "md", "csv", "rtf", "doc", "docx", "pdf"]

    public static var allowedContentTypes: [UTType] {
        supportedExtensions.sorted().compactMap { UTType(filenameExtension: $0) }
    }

    public static func extract(from url: URL) throws -> [DocumentTextFragment] {
        var fragments: [DocumentTextFragment] = []
        try forEachFragment(from: url) { fragments.append($0) }
        return fragments
    }

    public static func forEachFragment(
        from url: URL,
        consume: (DocumentTextFragment) -> Void
    ) throws {
        let fileExtension = url.pathExtension.lowercased()
        guard supportedExtensions.contains(fileExtension) else {
            throw DocumentTextExtractorError.unsupportedFormat(fileExtension.isEmpty ? "?" : fileExtension)
        }

        if fileExtension == "pdf" {
            try extractPDF(from: url, consume: consume)
            return
        }

        let text: String
        switch fileExtension {
        case "txt", "md", "csv":
            text = try readPlainText(from: url)
        case "rtf":
            text = try readAttributedText(from: url, type: .rtf)
        case "doc":
            text = try readAttributedText(from: url, type: .docFormat)
        case "docx":
            text = try readAttributedText(from: url, type: .officeOpenXML)
        default:
            throw DocumentTextExtractorError.unsupportedFormat(fileExtension)
        }

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DocumentTextExtractorError.emptyDocument
        }
        consume(makeFragment(sourceName: url.lastPathComponent, text: text))
    }

    private static func readPlainText(from url: URL) throws -> String {
        let data = try coordinatedRead(from: url) { try Data(contentsOf: $0) }
        if let text = String(data: data, encoding: .utf8) { return text }
        if let text = String(data: data, encoding: .utf16) { return text }
        if let text = String(data: data, encoding: .utf16LittleEndian) { return text }
        if let text = String(data: data, encoding: .utf16BigEndian) { return text }
        throw DocumentTextExtractorError.invalidTextEncoding
    }

    private static func readAttributedText(from url: URL, type: NSAttributedString.DocumentType) throws -> String {
        let data = try coordinatedRead(from: url) { try Data(contentsOf: $0) }
        do {
            let document = try NSAttributedString(
                data: data,
                options: [.documentType: type],
                documentAttributes: nil
            )
            return document.string
        } catch {
            throw DocumentTextExtractorError.invalidDocument
        }
    }

    private static func extractPDF(from url: URL, consume: (DocumentTextFragment) -> Void) throws {
        try coordinatedRead(from: url) { coordinatedURL in
            guard let document = PDFDocument(url: coordinatedURL) else { throw DocumentTextExtractorError.cannotRead }
            guard !document.isEncrypted else { throw DocumentTextExtractorError.encryptedPDF }

            var searchablePageCount = 0
            for index in 0..<document.pageCount {
                guard let text = document.page(at: index)?.string,
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                searchablePageCount += 1
                consume(makeFragment(sourceName: url.lastPathComponent, pageNumber: index + 1, text: text))
            }
            guard searchablePageCount > 0 else { throw DocumentTextExtractorError.noSearchableText }
        }
    }

    private static func coordinatedRead<T>(from url: URL, accessor: (URL) throws -> T) throws -> T {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var result: Result<T, Error>?
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            result = Result { try accessor(coordinatedURL) }
        }

        if coordinationError != nil { throw DocumentTextExtractorError.cannotRead }
        guard let result else { throw DocumentTextExtractorError.cannotRead }
        do {
            return try result.get()
        } catch let error as DocumentTextExtractorError {
            throw error
        } catch {
            throw DocumentTextExtractorError.cannotRead
        }
    }

    private static func makeFragment(sourceName: String, pageNumber: Int? = nil, text: String) -> DocumentTextFragment {
        DocumentTextFragment(
            sourceName: sourceName,
            pageNumber: pageNumber,
            text: text,
            namedEntities: DocumentEntityAnnotator.namedEntities(in: text)
        )
    }
}
