import Foundation

public enum RecognitionNormalizer {
    public struct Rule: Equatable, Sendable {
        public let recognizedVariant: String
        public let canonicalSpelling: String

        public init(recognizedVariant: String, canonicalSpelling: String) {
            self.recognizedVariant = recognizedVariant
            self.canonicalSpelling = canonicalSpelling
        }
    }

    public struct MergeResult: Equatable, Sendable {
        public let text: String
        public let addedCount: Int
        public let conflicts: [String]

        public init(text: String, addedCount: Int, conflicts: [String]) {
            self.text = text
            self.addedCount = addedCount
            self.conflicts = conflicts
        }
    }

    private static let ambiguousRussianAliases: Set<String> = [
        "командир",
        "ключ",
        "текстура",
        "текстурой"
    ]

    public static func rules(from text: String) -> [Rule] {
        var seenAliases = Set<String>()
        return text
            .components(separatedBy: .newlines)
            .compactMap { parseRule(from: $0) }
            .filter { seenAliases.insert($0.recognizedVariant.lowercased()).inserted }
    }

    public static func merge(existing: String, imported: String) -> MergeResult {
        var rulesByAlias: [String: Rule] = [:]
        for rule in rules(from: existing) {
            rulesByAlias[rule.recognizedVariant.lowercased()] = rule
        }

        var addedLines: [String] = []
        var conflicts: [String] = []
        for line in imported.components(separatedBy: .newlines) {
            guard let rule = parseRule(from: line) else { continue }
            let key = rule.recognizedVariant.lowercased()
            if let existingRule = rulesByAlias[key] {
                if existingRule.canonicalSpelling.caseInsensitiveCompare(rule.canonicalSpelling) != .orderedSame {
                    conflicts.append(line.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                continue
            }

            rulesByAlias[key] = rule
            addedLines.append("\(rule.recognizedVariant) => \(rule.canonicalSpelling)")
        }

        let existingText = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        let mergedText = [existingText, addedLines.joined(separator: "\n")]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        return MergeResult(text: mergedText, addedCount: addedLines.count, conflicts: conflicts)
    }

    public static func ambiguousAliases(in text: String) -> [String] {
        rules(from: text)
            .map(\.recognizedVariant)
            .filter { ambiguousRussianAliases.contains($0.lowercased()) }
    }

    public static func normalize(_ text: String, using rules: [Rule]) -> String {
        let applicableRules = rules
            .enumerated()
            .filter { !ambiguousRussianAliases.contains($0.element.recognizedVariant.lowercased()) }
            .sorted { left, right in
                let leftLength = (left.element.recognizedVariant as NSString).length
                let rightLength = (right.element.recognizedVariant as NSString).length
                return leftLength == rightLength ? left.offset < right.offset : leftLength > rightLength
            }
        guard !applicableRules.isEmpty else { return text }

        let ruleByVariant = Dictionary(
            uniqueKeysWithValues: applicableRules.map {
                ($0.element.recognizedVariant.lowercased(), $0.element.canonicalSpelling)
            }
        )
        let alternatives = applicableRules
            .map { NSRegularExpression.escapedPattern(for: $0.element.recognizedVariant) }
            .joined(separator: "|")
        let pattern = "(?<![\\p{L}\\p{N}_])(?:\(alternatives))(?![\\p{L}\\p{N}_])"

        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }

        let matches = expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard !matches.isEmpty else { return text }

        let mutableText = NSMutableString(string: text)
        for match in matches.reversed() {
            let matchedVariant = mutableText.substring(with: match.range).lowercased()
            guard let canonicalSpelling = ruleByVariant[matchedVariant] else { continue }
            mutableText.replaceCharacters(in: match.range, with: canonicalSpelling)
        }
        return mutableText as String
    }

    private static func parseRule(from line: String) -> Rule? {
        let parts = line.components(separatedBy: "=>")
        guard parts.count == 2 else { return nil }
        let variant = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let canonical = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !variant.isEmpty, !canonical.isEmpty else { return nil }
        return Rule(recognizedVariant: variant, canonicalSpelling: canonical)
    }
}
