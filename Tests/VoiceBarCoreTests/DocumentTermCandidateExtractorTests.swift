import Testing
@testable import VoiceBarCore

@Test
func documentTermsCombineCasingAcrossDocumentsAndKeepPageEvidence() {
    let candidates = DocumentTermCandidateExtractor.candidates(
        in: [
            DocumentTextFragment(sourceName: "architecture.pdf", pageNumber: 2, text: "The team selected VMware and vSphere for the Kubernetes cluster."),
            DocumentTextFragment(sourceName: "notes.md", text: "We run VMWARE in production and use vSphere with Kubernetes.")
        ],
        excluding: ["vmware"]
    )

    #expect(!candidates.contains { $0.term.lowercased() == "vmware" })
    let vSphere = candidates.first { $0.term.lowercased() == "vsphere" }
    #expect(vSphere?.term == "vSphere")
    #expect(vSphere?.occurrenceCount == 2)
    #expect(vSphere?.evidence.first?.sourceName == "architecture.pdf")
    #expect(vSphere?.evidence.first?.pageNumber == 2)
}

@Test
func longEvidenceExcerptsKeepTheCandidateVisible() {
    let text = String(repeating: "😀", count: 300)
        + "AuroraScheduler"
        + String(repeating: " configuration", count: 25)
    let candidates = DocumentTermCandidateExtractor.candidates(
        in: [DocumentTextFragment(sourceName: "architecture.txt", text: text)]
    )

    let candidate = candidates.first { $0.term == "AuroraScheduler" }
    let excerpt = candidate?.evidence.first?.excerpt ?? ""

    #expect(excerpt.contains("AuroraScheduler"))
    #expect(excerpt.hasPrefix("…"))
    #expect(excerpt.hasSuffix("…"))
    #expect(!excerpt.contains("�"))
    #expect(excerpt.count <= 182)
}

@Test
func documentCandidateRankingMeetsTheAgreedPrecisionAtTwentyTarget() {
    let relevantTerms = [
        "Deckhouse", "Deckhouse Platform", "Deckhouse Kubernetes Platform", "Deckhouse Development Portal", "Deckhouse Code",
        "DKP", "DVP", "DDP", "DOP", "DVP CSE", "Kubernetes", "Stronghold", "Commander", "Observability Platform",
        "Prom++", "DaaS", "VMware", "vSphere", "GPU", "AI", "API", "CI/CD", "SLA", "DORA", "FinOps", "MLOps",
        "Vault", "platform engineering", "SRE", "SLO", "MTTR", "CSE"
    ]
    let repeatedTerms = relevantTerms.map { term in
        "\(term) supports the cluster; the team uses \(term) for technical operations."
    }.joined(separator: "\n")
    let distractors = """
    Alice Smith reviewed the proposal.
    Project Aurora started in spring.
    Northwind Labs joined the meeting.
    The first design uses familiar English words.
    Our customer requested a short summary.
    """
    let candidates = DocumentTermCandidateExtractor.candidates(
        in: [DocumentTextFragment(sourceName: "synthetic-labeled-fixture.txt", text: repeatedTerms + "\n" + distractors)],
        limit: 100
    )
    let precision = DocumentTermCandidateExtractor.precisionAt20(
        candidates: candidates,
        relevantTerms: Set(relevantTerms)
    )

    #expect(candidates.count >= 20)
    #expect(precision >= 0.80)
    #expect(!candidates.contains { $0.term.lowercased() == "our" })
    #expect(!candidates.contains { $0.term.lowercased() == "first" })
}

@Test
func promptUsageReportsTheCompleteTokenBudgetWithoutTruncatingVocabulary() {
    let usage = RecognitionVocabulary.PromptUsage(tokenCount: 224, tokenBudget: 223)

    #expect(usage.tokenCount == 224)
    #expect(usage.tokenBudget == 223)
    #expect(!usage.isWithinBudget)
    #expect(usage.remainingTokens == 0)
    #expect(RecognitionVocabulary.terms(from: "Deckhouse\nKubernetes") == ["Deckhouse", "Kubernetes"])
}

@Test
func confirmingSelectedDocumentTermsAddsOnlyThoseTerms() {
    let selectedTerms = ["AuroraScheduler", "AtlasMetrics"]
    let result = RecognitionVocabulary.merge(
        existing: "Deckhouse Platform\nKubernetes",
        imported: selectedTerms.joined(separator: "\n")
    )

    #expect(result.addedCount == 2)
    #expect(result.text == "Deckhouse Platform\nKubernetes\nAuroraScheduler\nAtlasMetrics")
}
