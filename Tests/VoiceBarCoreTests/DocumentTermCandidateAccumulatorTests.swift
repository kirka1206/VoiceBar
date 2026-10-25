import Testing
@testable import VoiceBarCore

@Test
func documentTermAccumulatorMatchesBatchRankingAcrossDocuments() {
    let fragments = [
        DocumentTextFragment(sourceName: "architecture.pdf", pageNumber: 1, text: "Deckhouse Platform uses Kubernetes and VMware."),
        DocumentTextFragment(sourceName: "operations.md", text: "The team runs Deckhouse Platform on Kubernetes with vSphere.")
    ]
    let expected = DocumentTermCandidateExtractor.candidates(in: fragments, excluding: ["VMware"])
    var accumulator = DocumentTermCandidateExtractor.Accumulator(excluding: ["VMware"])
    for fragment in fragments { accumulator.add(fragment) }

    #expect(accumulator.candidates() == expected)
}
