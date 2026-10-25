import VoiceBarCore

extension DocumentTermCandidateExtractor {
    static func precisionAt20(candidates: [DocumentTermCandidate], relevantTerms: Set<String>) -> Double {
        let top = candidates.prefix(20)
        guard !top.isEmpty else { return 0 }
        let relevant = Set(relevantTerms.map { $0.lowercased() })
        return Double(top.filter { relevant.contains($0.term.lowercased()) }.count) / Double(top.count)
    }
}
