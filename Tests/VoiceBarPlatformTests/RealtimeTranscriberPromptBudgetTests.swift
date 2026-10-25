import Foundation
import Testing
@testable import VoiceBarPlatform
import VoiceBarCore

@Test
func overBudgetVocabularyIsRejectedBeforeRecognitionStarts() {
    let engine = PromptBudgetStubEngine(tokenCount: 224, tokenBudget: 223)
    var receivedError: RealtimeTranscriberError?

    do {
        _ = try RealtimeTranscriber(
            engine: engine,
            language: .russian,
            recognitionVocabulary: "Deckhouse Kubernetes Platform",
            sources: [.microphone],
            onUpdate: { _ in },
            onError: { _ in }
        )
    } catch let error as RealtimeTranscriberError {
        receivedError = error
    } catch {}

    #expect(receivedError == .vocabularyPromptOverBudget(tokenCount: 224, tokenBudget: 223))
    #expect(engine.transcriptionCount == 0)
}

private final class PromptBudgetStubEngine: SpeechRecognitionEngine, @unchecked Sendable {
    let initialPromptTokenBudget: Int
    private let tokenCount: Int
    private(set) var transcriptionCount = 0

    init(tokenCount: Int, tokenBudget: Int) {
        self.tokenCount = tokenCount
        initialPromptTokenBudget = tokenBudget
    }

    func initialPromptTokenCount(for prompt: String) throws -> Int { tokenCount }

    func transcribe(samples: [Float], language: TranscriptionLanguage, initialPrompt: String?) throws -> String {
        transcriptionCount += 1
        return ""
    }
}
