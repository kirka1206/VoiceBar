import AppKit
import CoreGraphics
import CoreText
import Foundation
import PDFKit
import Testing
import VoiceBarCore
@testable import VoiceBarPlatform

@Test
func documentTextExtractorReadsTextAndWordFormats() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    try "Kubernetes and VMware".write(to: directory.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
    try "Kubernetes and VMware".write(to: directory.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)
    try "Kubernetes,VMware".write(to: directory.appendingPathComponent("notes.csv"), atomically: true, encoding: .utf8)

    #expect(try DocumentTextExtractor.extract(from: directory.appendingPathComponent("notes.txt")).first?.text.contains("Kubernetes") == true)
    #expect(try DocumentTextExtractor.extract(from: directory.appendingPathComponent("notes.md")).first?.text.contains("VMware") == true)
    #expect(try DocumentTextExtractor.extract(from: directory.appendingPathComponent("notes.csv")).first?.text.contains("VMware") == true)

    for (fileName, documentType) in [
        ("notes.rtf", NSAttributedString.DocumentType.rtf),
        ("notes.doc", NSAttributedString.DocumentType.docFormat),
        ("notes.docx", NSAttributedString.DocumentType.officeOpenXML)
    ] {
        let attributed = NSAttributedString(string: "Kubernetes and VMware")
        let data = try attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: documentType]
        )
        let url = directory.appendingPathComponent(fileName)
        try data.write(to: url)
        let fragments = try DocumentTextExtractor.extract(from: url)
        #expect(fragments.map(\.text).joined().contains("Kubernetes"))
    }
}

@Test
func documentTextExtractorReadsSearchablePDFAndRejectsScannedOrEmptyPDF() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let searchableURL = directory.appendingPathComponent("searchable.pdf")
    try makePDF(text: "Kubernetes and VMware").write(to: searchableURL)
    let fragments = try DocumentTextExtractor.extract(from: searchableURL)
    #expect(fragments.count == 1)
    #expect(fragments[0].pageNumber == 1)
    #expect(fragments[0].text.contains("Kubernetes"))

    let scannedURL = directory.appendingPathComponent("scan.pdf")
    try makePDF(text: nil).write(to: scannedURL)
    do {
        _ = try DocumentTextExtractor.extract(from: scannedURL)
        Issue.record("A PDF without a text layer should not be OCR-processed.")
    } catch {
        #expect(error as? DocumentTextExtractorError == .noSearchableText)
    }
}

@Test
func documentTextExtractorReportsEncryptedEmptyAndUnsupportedFiles() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let emptyURL = directory.appendingPathComponent("empty.txt")
    try Data().write(to: emptyURL)
    do {
        _ = try DocumentTextExtractor.extract(from: emptyURL)
        Issue.record("An empty document should be reported.")
    } catch {
        #expect(error as? DocumentTextExtractorError == .emptyDocument)
    }

    let unsupportedURL = directory.appendingPathComponent("notes.xlsx")
    try Data([0]).write(to: unsupportedURL)
    do {
        _ = try DocumentTextExtractor.extract(from: unsupportedURL)
        Issue.record("An unsupported format should be reported.")
    } catch {
        #expect(error as? DocumentTextExtractorError == .unsupportedFormat("xlsx"))
    }

    let encryptedURL = directory.appendingPathComponent("locked.pdf")
    let unencrypted = PDFDocument(data: makePDF(text: "Kubernetes"))!
    let written = unencrypted.write(
        to: encryptedURL,
        withOptions: [
            .userPasswordOption: "secret",
            .ownerPasswordOption: "owner"
        ]
    )
    guard written else {
        Issue.record("Could not generate an encrypted PDF fixture on this macOS version.")
        return
    }
    do {
        _ = try DocumentTextExtractor.extract(from: encryptedURL)
        Issue.record("An encrypted PDF should be reported.")
    } catch {
        #expect(error as? DocumentTextExtractorError == .encryptedPDF)
    }
}

@Test
func documentTermRankingKeepsRepeatedPersonalNamesBelowTechnicalTerms() {
    let relevantTerms = [
        "Deckhouse", "Deckhouse Platform", "Deckhouse Kubernetes Platform", "Deckhouse Development Portal", "Deckhouse Code",
        "DKP", "DVP", "DDP", "DOP", "DVP CSE", "Kubernetes", "Stronghold", "Commander", "Observability Platform",
        "Prom++", "DaaS", "VMware", "vSphere", "GPU", "AI", "API", "CI/CD", "SLA", "DORA", "FinOps", "MLOps",
        "Vault", "platform engineering", "SRE", "SLO", "MTTR", "CSE"
    ]
    let technicalText = relevantTerms.map { "The team uses \($0) in the platform architecture." }.joined(separator: "\n")
    let names = ["Alice Smith", "Morgan Reed", "Jordan Blake"]
        .map { String(repeating: "\($0) reviewed the proposal. ", count: 8) }
        .joined(separator: "\n")
    let organizations = ["Microsoft Corporation", "Google LLC", "Acme Corporation"]
        .map { String(repeating: "\($0) reviewed the proposal. ", count: 8) }
        .joined(separator: "\n")
    let text = technicalText + "\n" + names + "\n" + organizations
    let namedEntities = namedEntityRanges(
        in: text,
        values: ["Alice Smith", "Morgan Reed", "Jordan Blake"],
        kind: .person
    ) + namedEntityRanges(
        in: text,
        values: ["Microsoft Corporation", "Google LLC", "Acme Corporation"],
        kind: .organization
    )
    let fragment = DocumentTextFragment(
        sourceName: "labeled-ranking-fixture.txt",
        text: text,
        namedEntities: namedEntities
    )
    let candidates = DocumentTermCandidateExtractor.candidates(in: [fragment])
    let topTwenty = Array(candidates.prefix(20))
    let relevant = Set(relevantTerms.map { $0.lowercased() })
    let precision = Double(topTwenty.filter { relevant.contains($0.term.lowercased()) }.count) / Double(topTwenty.count)

    #expect(topTwenty.count == 20)
    #expect(precision >= 0.80)
    #expect(candidates.contains { $0.term == "Alice Smith" })
    #expect(topTwenty.allSatisfy {
        !["Alice Smith", "Morgan Reed", "Jordan Blake", "Microsoft Corporation", "Google LLC", "Acme Corporation"].contains($0.term)
    })
}

@Test
func documentEntityAnnotatorRecognizesNamesAndReturnsValidRanges() {
    let text = "Alice Smith reviewed the proposal."
    let entities = DocumentEntityAnnotator.namedEntities(in: text)
    let nsText = text as NSString

    #expect(entities.contains {
        $0.kind == .person && nsText.substring(with: $0.range) == "Alice Smith"
    })
    #expect(entities.allSatisfy {
        $0.range.location >= 0 && NSMaxRange($0.range) <= nsText.length
    })
}

private func makePDF(text: String?) -> Data {
    let data = NSMutableData()
    var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
    let consumer = CGDataConsumer(data: data as CFMutableData)!
    let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)!
    context.beginPDFPage(nil)
    if let text {
        let font = NSFont(name: "Helvetica", size: 14)!
        let attributed = NSAttributedString(string: text, attributes: [.font: font])
        let line = CTLineCreateWithAttributedString(attributed as CFAttributedString)
        context.textPosition = CGPoint(x: 72, y: 720)
        CTLineDraw(line, context)
    }
    context.endPDFPage()
    context.closePDF()
    return data as Data
}

private func namedEntityRanges(
    in text: String,
    values: [String],
    kind: DocumentNamedEntity.Kind
) -> [DocumentNamedEntity] {
    let nsText = text as NSString
    return values.flatMap { value in
        var ranges: [DocumentNamedEntity] = []
        var searchRange = NSRange(location: 0, length: nsText.length)
        while searchRange.length > 0 {
            let match = nsText.range(of: value, options: [], range: searchRange)
            guard match.location != NSNotFound else { break }
            ranges.append(DocumentNamedEntity(range: match, kind: kind))
            let nextLocation = NSMaxRange(match)
            guard nextLocation < nsText.length else { break }
            searchRange = NSRange(location: nextLocation, length: nsText.length - nextLocation)
        }
        return ranges
    }
}
