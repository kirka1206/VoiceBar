import Foundation
import Testing
import VoiceBarCore
@testable import VoiceBarPlatform

@Test
func streamingDocumentExtractionMatchesCollectedFragments() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("voicebar-\(UUID().uuidString).txt")
    defer { try? FileManager.default.removeItem(at: url) }
    try "Kubernetes and VMware".write(to: url, atomically: true, encoding: .utf8)

    let expected = try DocumentTextExtractor.extract(from: url)
    var streamed: [DocumentTextFragment] = []
    try DocumentTextExtractor.forEachFragment(from: url) { streamed.append($0) }

    #expect(streamed == expected)
}
