import Foundation

public enum RecognitionVocabulary {
    public static func terms(from text: String) -> [String] {
        var seen = Set<String>()
        return text
            .components(separatedBy: .newlines)
            .compactMap { line in
                let term = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !term.isEmpty, seen.insert(term.lowercased()).inserted else { return nil }
                return term
            }
    }

    public static func merge(existing: String, imported: String) -> (text: String, addedCount: Int) {
        let existingTerms = terms(from: existing)
        let mergedTerms = terms(from: existing + "\n" + imported)
        return (mergedTerms.joined(separator: "\n"), mergedTerms.count - existingTerms.count)
    }

    public static func initialPrompt(from text: String) -> String? {
        let vocabularyTerms = terms(from: text)
        guard !vocabularyTerms.isEmpty else { return nil }

        return "Возможные англоязычные технические термины и названия: "
            + vocabularyTerms.joined(separator: ", ")
            + ". Сохраняй их написание, если они произнесены."
    }
}
