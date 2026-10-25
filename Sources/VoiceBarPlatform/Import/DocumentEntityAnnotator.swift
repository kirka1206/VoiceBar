import Foundation
import NaturalLanguage
import VoiceBarCore

public enum DocumentEntityAnnotator {
    public static func namedEntities(in text: String) -> [DocumentNamedEntity] {
        guard !text.isEmpty else { return [] }

        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]
        var entities: [DocumentNamedEntity] = []

        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .nameType,
            options: options
        ) { tag, range in
            guard let tag, let kind = entityKind(for: tag) else { return true }
            entities.append(DocumentNamedEntity(range: NSRange(range, in: text), kind: kind))
            return true
        }

        return entities
    }

    private static func entityKind(for tag: NLTag) -> DocumentNamedEntity.Kind? {
        switch tag {
        case .personalName: .person
        case .organizationName: .organization
        case .placeName: .place
        default: nil
        }
    }
}
