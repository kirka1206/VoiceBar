import Foundation

public struct DocumentTextFragment: Equatable, Sendable {
    public let sourceName: String
    public let pageNumber: Int?
    public let text: String
    public let namedEntities: [DocumentNamedEntity]

    public init(
        sourceName: String,
        pageNumber: Int? = nil,
        text: String,
        namedEntities: [DocumentNamedEntity] = []
    ) {
        self.sourceName = sourceName
        self.pageNumber = pageNumber
        self.text = text
        self.namedEntities = namedEntities
    }
}

public struct DocumentNamedEntity: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case person
        case organization
        case place
    }

    /// UTF-16 offsets in the fragment's text, matching Foundation's NSRange APIs.
    public let range: NSRange
    public let kind: Kind

    public init(range: NSRange, kind: Kind) {
        self.range = range
        self.kind = kind
    }
}

public struct DocumentTermEvidence: Equatable, Sendable, Identifiable {
    public let sourceName: String
    public let pageNumber: Int?
    public let excerpt: String

    public var id: String { "\(sourceName):\(pageNumber ?? 0):\(excerpt)" }

    public init(sourceName: String, pageNumber: Int?, excerpt: String) {
        self.sourceName = sourceName
        self.pageNumber = pageNumber
        self.excerpt = excerpt
    }
}

public struct DocumentTermCandidate: Equatable, Sendable, Identifiable {
    public let term: String
    public let occurrenceCount: Int
    public let relevanceScore: Int
    public let evidence: [DocumentTermEvidence]

    public var id: String { term.lowercased() }

    public init(term: String, occurrenceCount: Int, relevanceScore: Int, evidence: [DocumentTermEvidence]) {
        self.term = term
        self.occurrenceCount = occurrenceCount
        self.relevanceScore = relevanceScore
        self.evidence = evidence
    }
}

public enum DocumentTermCandidateExtractor {
    private struct Token {
        let text: String
        let range: NSRange
    }

    private struct Aggregate {
        var preferredSpelling: String
        var spellingScore: Int
        var occurrenceCount = 0
        var nonSentenceInitialCount = 0
        var documents = Set<String>()
        var namedEntityPenalty = 0
        var evidence: [DocumentTermEvidence] = []
    }

    public struct Accumulator {
        private let excluded: Set<String>
        private var aggregates: [String: Aggregate] = [:]

        public init(excluding existingTerms: [String] = []) {
            excluded = Set(existingTerms.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        }

        public mutating func add(_ fragment: DocumentTextFragment) {
            DocumentTermCandidateExtractor.collectCandidates(from: fragment, into: &aggregates)
        }

        public func candidates(limit: Int = 100) -> [DocumentTermCandidate] {
            guard limit > 0 else { return [] }
            return aggregates.compactMap { key, value in
                guard !excluded.contains(key) else { return nil }
                let score = (min(value.occurrenceCount, 5) * 20)
                    + (value.nonSentenceInitialCount > 0 ? 20 : 0)
                    + (min(value.documents.count, 4) * 15)
                    + value.spellingScore
                    - value.namedEntityPenalty
                return DocumentTermCandidate(
                    term: value.preferredSpelling,
                    occurrenceCount: value.occurrenceCount,
                    relevanceScore: score,
                    evidence: value.evidence
                )
            }
            .sorted {
                if $0.relevanceScore != $1.relevanceScore { return $0.relevanceScore > $1.relevanceScore }
                if $0.occurrenceCount != $1.occurrenceCount { return $0.occurrenceCount > $1.occurrenceCount }
                return $0.term.localizedStandardCompare($1.term) == .orderedAscending
            }
            .prefix(limit)
            .map { $0 }
        }
    }

    private static let tokenExpression = try! NSRegularExpression(
        pattern: "(?<![A-Za-z0-9])[A-Za-z][A-Za-z0-9]*(?:(?:\\+{1,2})|(?:[/.-][A-Za-z0-9]+)+)?(?![A-Za-z0-9])"
    )

    private static let functionWords: Set<String> = [
        "a", "all", "an", "and", "as", "at", "both", "by", "can", "each", "first", "for", "from", "he", "her",
        "here", "him", "how", "in", "into", "is", "it", "its", "new", "of", "on", "or", "our", "second",
        "she", "that", "the", "their", "them", "there", "these", "they", "this", "those", "to", "we", "what",
        "when", "where", "which", "who", "why", "will", "with", "you", "your"
    ]

    private static let genericSingleWords: Set<String> = [
        "about", "agenda", "architecture", "background", "business", "code", "company", "configuration",
        "customer", "data", "design", "development", "document", "example", "guide", "history", "implementation",
        "information", "introduction", "management", "meeting", "overview", "platform", "portal", "process",
        "product", "project", "release", "report", "review", "solution", "status", "system", "team", "update", "version",
        "co", "company", "corp", "corporation", "gmbh", "inc", "incorporated", "limited", "llc", "ltd", "plc"
    ]

    private static let organizationSuffixes: Set<String> = [
        "co", "company", "corp", "corporation", "foundation", "gmbh", "group", "inc", "incorporated", "labs",
        "limited", "llc", "ltd", "plc"
    ]

    private static let technicalPhraseWords: Set<String> = [
        "architecture", "engineering", "infrastructure", "networking", "observability", "operations", "orchestration",
        "security", "virtualization"
    ]

    private static let lowercaseTechnicalPhraseExpression: NSRegularExpression = {
        let pattern = "(?i)(?<![A-Za-z0-9])(?:[A-Za-z]+\\s+)?(?:\(technicalPhraseWords.sorted().joined(separator: "|")))(?![A-Za-z0-9])"
        return try! NSRegularExpression(pattern: pattern)
    }()

    public static func candidates(
        in fragments: [DocumentTextFragment],
        excluding existingTerms: [String] = [],
        limit: Int = 100
    ) -> [DocumentTermCandidate] {
        var accumulator = Accumulator(excluding: existingTerms)
        for fragment in fragments { accumulator.add(fragment) }
        return accumulator.candidates(limit: limit)
    }

    private static func collectCandidates(from fragment: DocumentTextFragment, into aggregates: inout [String: Aggregate]) {
        let text = fragment.text as NSString
        let tokens = tokenExpression.matches(in: fragment.text, range: NSRange(location: 0, length: text.length)).compactMap { match -> Token? in
            guard let range = Range(match.range, in: fragment.text) else { return nil }
            return Token(text: String(fragment.text[range]), range: match.range)
        }

        for token in tokens where isTechnicalSingle(token.text) {
            add(
                token.text,
                range: token.range,
                text: text,
                fragment: fragment,
                to: &aggregates
            )
        }

        var phraseRun: [Token] = []
        for (index, token) in tokens.enumerated() {
            let canJoinPrevious: Bool = {
                guard let previous = phraseRun.last else { return true }
                let previousEnd = NSMaxRange(previous.range)
                let gap = text.substring(with: NSRange(location: previousEnd, length: token.range.location - previousEnd))
                return gap.allSatisfy(\.isWhitespace)
            }()

            if isPhraseToken(token.text), canJoinPrevious {
                phraseRun.append(token)
                if phraseRun.count == 4 {
                    addPhrase(phraseRun, text: text, fragment: fragment, to: &aggregates)
                    phraseRun = [token]
                }
            } else {
                addPhrase(phraseRun, text: text, fragment: fragment, to: &aggregates)
                phraseRun = isPhraseToken(token.text) ? [token] : []
            }

            if index == tokens.count - 1 {
                addPhrase(phraseRun, text: text, fragment: fragment, to: &aggregates)
            }
        }

        addLowercaseTechnicalPhrases(in: fragment, text: text, to: &aggregates)
    }

    private static func addPhrase(
        _ tokens: [Token],
        text: NSString,
        fragment: DocumentTextFragment,
        to aggregates: inout [String: Aggregate]
    ) {
        guard tokens.count >= 2 else { return }
        let first = tokens[0]
        let last = tokens[tokens.count - 1]
        let range = NSRange(location: first.range.location, length: NSMaxRange(last.range) - first.range.location)
        let phrase = text.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
        let words = tokens.map { $0.text.lowercased() }
        guard !words.contains(where: functionWords.contains) else { return }
        guard tokens.allSatisfy({ isPhraseToken($0.text) }) else { return }
        add(phrase, range: range, text: text, fragment: fragment, to: &aggregates)
    }

    private static func addLowercaseTechnicalPhrases(
        in fragment: DocumentTextFragment,
        text: NSString,
        to aggregates: inout [String: Aggregate]
    ) {
        let range = NSRange(location: 0, length: text.length)
        for match in lowercaseTechnicalPhraseExpression.matches(in: fragment.text, range: range) {
            let phrase = text.substring(with: match.range).trimmingCharacters(in: .whitespacesAndNewlines)
            let words = phrase.split(whereSeparator: \.isWhitespace)
            guard words.count >= 2, words.count <= 3 else { continue }
            add(phrase, range: match.range, text: text, fragment: fragment, to: &aggregates)
        }
    }

    private static func add(
        _ spelling: String,
        range: NSRange,
        text: NSString,
        fragment: DocumentTextFragment,
        to aggregates: inout [String: Aggregate]
    ) {
        let normalized = spelling.lowercased()
        guard !normalized.isEmpty else { return }
        let spellingScore = styleScore(spelling)
        var aggregate = aggregates[normalized] ?? Aggregate(preferredSpelling: spelling, spellingScore: spellingScore)
        if spellingScore > aggregate.spellingScore {
            aggregate.preferredSpelling = spelling
            aggregate.spellingScore = spellingScore
        }
        aggregate.occurrenceCount += 1
        aggregate.documents.insert(fragment.sourceName)
        aggregate.namedEntityPenalty = max(
            aggregate.namedEntityPenalty,
            namedEntityPenalty(for: range, spelling: spelling, in: text, entities: fragment.namedEntities)
        )
        if !isSentenceInitial(range.location, in: text) { aggregate.nonSentenceInitialCount += 1 }
        if aggregate.evidence.count < 3 {
            let item = DocumentTermEvidence(
                sourceName: fragment.sourceName,
                pageNumber: fragment.pageNumber,
                excerpt: excerpt(around: range, in: text)
            )
            if !aggregate.evidence.contains(item) { aggregate.evidence.append(item) }
        }
        aggregates[normalized] = aggregate
    }

    private static func namedEntityPenalty(
        for range: NSRange,
        spelling: String,
        in text: NSString,
        entities: [DocumentNamedEntity]
    ) -> Int {
        entities.reduce(0) { penalty, entity in
            guard NSLocationInRange(range.location, entity.range), NSMaxRange(range) <= NSMaxRange(entity.range) else {
                return penalty
            }
            let candidateStyle = styleScore(spelling)
            if candidateStyle >= 35 { return penalty }

            let entityPenalty: Int
            switch entity.kind {
            case .person: entityPenalty = 500
            case .place: entityPenalty = 300
            case .organization:
                let entityWords = text.substring(with: entity.range)
                    .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                    .map { $0.lowercased() }
                entityPenalty = entityWords.contains(where: organizationSuffixes.contains) ? 1_200 : 20
            }
            return max(penalty, entityPenalty)
        }
    }

    private static func isTechnicalSingle(_ spelling: String) -> Bool {
        let lower = spelling.lowercased()
        guard !functionWords.contains(lower), !genericSingleWords.contains(lower) else { return false }
        let letters = spelling.filter(\.isLetter)
        guard letters.count >= 2 else { return false }
        return styleScore(spelling) > 0
    }

    private static func isPhraseToken(_ spelling: String) -> Bool {
        let lower = spelling.lowercased()
        guard !functionWords.contains(lower) else { return false }
        return styleScore(spelling) > 0
    }

    private static func isAcronym(_ spelling: String) -> Bool {
        let letters = spelling.filter(\.isLetter)
        return letters.count >= 2 && letters.allSatisfy(\.isUppercase)
    }

    private static func isMixedCase(_ spelling: String) -> Bool {
        spelling.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains { word in
            let letters = Array(word.filter(\.isLetter))
            return letters.contains(where: \.isUppercase)
                && letters.contains(where: \.isLowercase)
                && letters.dropFirst().contains(where: \.isUppercase)
        }
    }

    private static func isTitleCase(_ spelling: String) -> Bool {
        guard let first = spelling.first else { return false }
        return first.isUppercase && spelling.dropFirst().contains(where: \.isLowercase)
    }

    private static func styleScore(_ spelling: String) -> Int {
        if spelling.contains("+") || spelling.contains("/") || spelling.contains(".") { return 45 }
        if isMixedCase(spelling) { return 40 }
        if isAcronym(spelling) { return 35 }
        if isTitleCase(spelling) { return 20 }
        return 0
    }

    private static func isSentenceInitial(_ location: Int, in text: NSString) -> Bool {
        guard location > 0 else { return true }
        var index = location - 1
        while index >= 0 {
            let character = text.character(at: index)
            if character == 0x20 || character == 0x09 || character == 0x0A || character == 0x0D || character == 0xA0 {
                index -= 1
                continue
            }
            return character == 0x2E || character == 0x21 || character == 0x3F
        }
        return true
    }

    private static func excerpt(around range: NSRange, in text: NSString) -> String {
        let prefixRange = NSRange(location: 0, length: range.location)
        let lineBreakBefore = text.range(of: "\n", options: .backwards, range: prefixRange)
        let startOfLine = lineBreakBefore.location == NSNotFound ? 0 : NSMaxRange(lineBreakBefore)
        let suffixRange = NSRange(location: range.location, length: text.length - range.location)
        let lineBreakAfter = text.range(of: "\n", options: [], range: suffixRange)
        let endOfLine = lineBreakAfter.location == NSNotFound ? text.length : lineBreakAfter.location
        let lineRange = NSRange(location: startOfLine, length: endOfLine - startOfLine)
        let line = text.substring(with: lineRange)
        if line.utf16.count <= 180 { return line.trimmingCharacters(in: .whitespacesAndNewlines) }

        let candidateRange = NSRange(location: range.location - startOfLine, length: range.length)
        guard candidateRange.length <= 180 else {
            return text.substring(with: range)
        }

        let contextLength = 180 - candidateRange.length
        var windowStart = max(0, candidateRange.location - contextLength / 2)
        var windowEnd = min(line.utf16.count, windowStart + 180)
        if windowEnd < NSMaxRange(candidateRange) {
            windowStart = max(0, NSMaxRange(candidateRange) - 180)
            windowEnd = min(line.utf16.count, windowStart + 180)
        }

        let lineNSString = line as NSString
        let proposedRange = NSRange(location: windowStart, length: windowEnd - windowStart)
        let excerptRange = lineNSString.rangeOfComposedCharacterSequences(for: proposedRange)
        let excerpt = (excerptRange.location > 0 ? "…" : "")
            + lineNSString.substring(with: excerptRange)
            + (NSMaxRange(excerptRange) < lineNSString.length ? "…" : "")
        return excerpt.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
