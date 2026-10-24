import Foundation

public struct TranscriptChunk: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let source: AudioSource
    public let startTime: TimeInterval
    public let text: String

    public init(id: UUID = UUID(), source: AudioSource, startTime: TimeInterval, text: String) {
        self.id = id
        self.source = source
        self.startTime = startTime
        self.text = text
    }
}

public struct TranscriptAssembler: Sendable {
    private(set) public var chunks: [TranscriptChunk] = []
    private var latestRawTextBySource: [AudioSource: String] = [:]

    public init() {}

    @discardableResult
    public mutating func append(source: AudioSource, startTime: TimeInterval, text: String) -> TranscriptChunk? {
        let rawText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawText.isEmpty else { return nil }

        let cleanedText = removingRepeatedPrefix(from: rawText, after: latestRawTextBySource[source] ?? "")
        latestRawTextBySource[source] = rawText
        guard !cleanedText.isEmpty else { return nil }

        let chunk = TranscriptChunk(source: source, startTime: startTime, text: cleanedText)
        var lowerBound = 0
        var upperBound = chunks.count
        while lowerBound < upperBound {
            let middle = lowerBound + (upperBound - lowerBound) / 2
            if Self.isOrdered(before: chunk, chunks[middle]) {
                upperBound = middle
            } else {
                lowerBound = middle + 1
            }
        }
        chunks.insert(chunk, at: lowerBound)
        return chunk
    }

    public func rendered(withSourceLabels: Bool) -> String {
        Self.render(chunks, withSourceLabels: withSourceLabels)
    }

    public static func render(_ chunks: [TranscriptChunk], withSourceLabels: Bool) -> String {
        chunks.map { chunk in
            withSourceLabels ? "\(chunk.source.title): \(chunk.text)" : chunk.text
        }
        .joined(separator: " ")
    }

    private static func isOrdered(before lhs: TranscriptChunk, _ rhs: TranscriptChunk) -> Bool {
        if lhs.startTime == rhs.startTime {
            return lhs.source.rawValue < rhs.source.rawValue
        }
        return lhs.startTime < rhs.startTime
    }

    private func removingRepeatedPrefix(from current: String, after previous: String) -> String {
        let previousWords = previous.split(whereSeparator: \.isWhitespace).map(String.init)
        let currentWords = current.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !previousWords.isEmpty, !currentWords.isEmpty else { return current }

        let largestOverlap = min(12, previousWords.count, currentWords.count)
        var overlap = 0
        for count in stride(from: largestOverlap, through: 1, by: -1) {
            let oldTail = previousWords.suffix(count).map(Self.normalizedWord)
            let newHead = currentWords.prefix(count).map(Self.normalizedWord)
            if oldTail == newHead {
                overlap = count
                break
            }
        }

        return currentWords.dropFirst(overlap).joined(separator: " ")
    }

    private static func normalizedWord(_ word: String) -> String {
        word.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
