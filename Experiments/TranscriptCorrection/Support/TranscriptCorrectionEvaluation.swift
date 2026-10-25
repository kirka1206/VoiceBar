import Foundation

public struct TranscriptCorrectionCase: Codable, Equatable, Sendable {
    public struct ExpectedCorrection: Codable, Equatable, Sendable {
        public let source: String
        public let target: String

        public init(source: String, target: String) {
            self.source = source
            self.target = target
        }
    }

    public let id: String
    public let category: String
    public let rawWhisper: String
    public let deterministic: String
    public let reference: String
    public let vocabulary: [String]
    public let expectedCorrections: [ExpectedCorrection]
    public let alreadyCorrect: Bool

    public init(
        id: String,
        category: String,
        rawWhisper: String,
        deterministic: String,
        reference: String,
        vocabulary: [String],
        expectedCorrections: [ExpectedCorrection] = [],
        alreadyCorrect: Bool = false
    ) {
        self.id = id
        self.category = category
        self.rawWhisper = rawWhisper
        self.deterministic = deterministic
        self.reference = reference
        self.vocabulary = vocabulary
        self.expectedCorrections = expectedCorrections
        self.alreadyCorrect = alreadyCorrect
    }
}

public struct TranscriptCorrectionCaseResult: Codable, Equatable, Sendable {
    public let id: String
    public let rawWhisper: String
    public let deterministic: String
    public let modelOutput: String
    public let reference: String
    public let totalDurationMilliseconds: Double
    public let targetCorrections: Int
    public let successfulTargetCorrections: Int
    public let changedAlreadyCorrectText: Bool

    public init(testCase: TranscriptCorrectionCase, modelOutput: String, totalDurationMilliseconds: Double) {
        id = testCase.id
        rawWhisper = testCase.rawWhisper
        deterministic = testCase.deterministic
        self.modelOutput = modelOutput
        reference = testCase.reference
        self.totalDurationMilliseconds = totalDurationMilliseconds
        targetCorrections = testCase.expectedCorrections.count
        successfulTargetCorrections = testCase.expectedCorrections.filter {
            Self.containsWholePhrase(modelOutput, $0.target) && !Self.containsWholePhrase(modelOutput, $0.source)
        }.count
        changedAlreadyCorrectText = testCase.alreadyCorrect && Self.trimmed(modelOutput) != Self.trimmed(testCase.reference)
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func containsWholePhrase(_ text: String, _ phrase: String) -> Bool {
        guard !phrase.isEmpty else { return false }
        let escaped = NSRegularExpression.escapedPattern(for: phrase)
        guard let expression = try? NSRegularExpression(
            pattern: "(?<![\\p{L}\\p{N}_])\(escaped)(?![\\p{L}\\p{N}_])",
            options: [.caseInsensitive]
        ) else { return false }
        return expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}

public struct TranscriptCorrectionMetrics: Codable, Equatable, Sendable {
    public let caseCount: Int
    public let rawWordErrorRate: Double
    public let deterministicWordErrorRate: Double
    public let modelWordErrorRate: Double
    public let expectedTermCorrections: Int
    public let successfulTermCorrections: Int
    public let alreadyCorrectCaseCount: Int
    public let falseChangesToAlreadyCorrectCases: Int
    public let meanInferenceMilliseconds: Double
    public let maximumInferenceMilliseconds: Double

    public init(results: [TranscriptCorrectionCaseResult]) {
        caseCount = results.count
        let references = results.map { Self.tokens($0.reference) }
        let denominator = max(1, references.reduce(0) { $0 + $1.count })
        rawWordErrorRate = Double(Self.totalDistance(results.map { Self.tokens($0.rawWhisper) }, references)) / Double(denominator)
        deterministicWordErrorRate = Double(Self.totalDistance(results.map { Self.tokens($0.deterministic) }, references)) / Double(denominator)
        modelWordErrorRate = Double(Self.totalDistance(results.map { Self.tokens($0.modelOutput) }, references)) / Double(denominator)
        expectedTermCorrections = results.reduce(0) { $0 + $1.targetCorrections }
        successfulTermCorrections = results.reduce(0) { $0 + $1.successfulTargetCorrections }
        let correctCases = results.filter { $0.targetCorrections == 0 && $0.rawWhisper == $0.reference }
        alreadyCorrectCaseCount = correctCases.count
        falseChangesToAlreadyCorrectCases = correctCases.filter { $0.changedAlreadyCorrectText }.count
        meanInferenceMilliseconds = results.isEmpty ? 0 : results.map(\.totalDurationMilliseconds).reduce(0, +) / Double(results.count)
        maximumInferenceMilliseconds = results.map(\.totalDurationMilliseconds).max() ?? 0
    }

    public var termCorrectionRate: Double {
        expectedTermCorrections == 0 ? 1 : Double(successfulTermCorrections) / Double(expectedTermCorrections)
    }

    public var falseChangeRate: Double {
        alreadyCorrectCaseCount == 0 ? 0 : Double(falseChangesToAlreadyCorrectCases) / Double(alreadyCorrectCaseCount)
    }

    private static func tokens(_ text: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: "[\\p{L}\\p{N}]+") else { return [] }
        return expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range, in: text).map { String(text[$0]).lowercased() }
        }
    }

    private static func totalDistance(_ left: [[String]], _ right: [[String]]) -> Int {
        zip(left, right).reduce(0) { $0 + distance($1.0, $1.1) }
    }

    private static func distance(_ left: [String], _ right: [String]) -> Int {
        var previous = Array(0...right.count)
        for (leftIndex, leftToken) in left.enumerated() {
            var current = Array(repeating: 0, count: right.count + 1)
            current[0] = leftIndex + 1
            for (rightIndex, rightToken) in right.enumerated() {
                current[rightIndex + 1] = min(
                    previous[rightIndex + 1] + 1,
                    current[rightIndex] + 1,
                    previous[rightIndex] + (leftToken == rightToken ? 0 : 1)
                )
            }
            previous = current
        }
        return previous[right.count]
    }
}
