import Foundation
import SwiftData

@Model
public final class TranscriptEntry {
    @Attribute(.unique) public var id: UUID
    public var createdAt: Date
    public var text: String
    public var language: String
    public var sourceSelection: String

    public init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        text: String,
        language: String,
        sourceSelection: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.text = text
        self.language = language
        self.sourceSelection = sourceSelection
    }
}
