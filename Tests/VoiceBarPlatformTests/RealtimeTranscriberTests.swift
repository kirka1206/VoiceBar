import Foundation
import Testing
@testable import VoiceBarPlatform
import VoiceBarCore

@Test
func realtimeTranscriberNormalizesEachSegmentBeforeRemovingOverlap() async {
    let engine = StubSpeechRecognitionEngine(responses: [
        "Настроили кластер на кубернетис",
        "на Kubernetes и проверили API"
    ])
    let transcriber = RealtimeTranscriber(
        engine: engine,
        language: .russian,
        recognitionVocabulary: "",
        correctionRules: "кубернетис => Kubernetes",
        sources: [.microphone],
        onUpdate: { _ in },
        onError: { _ in }
    )

    transcriber.append(AudioPacket(
        source: .microphone,
        samples: Array(repeating: 0.1, count: 80_000),
        sampleRate: 16_000,
        captureTime: 1
    ))
    let result = await withCheckedContinuation { continuation in
        transcriber.finish { continuation.resume(returning: $0) }
    }

    #expect(result.failedSegments == 0)
    #expect(result.chunks.map(\.text) == ["Настроили кластер на Kubernetes", "и проверили API"])
}

private final class StubSpeechRecognitionEngine: SpeechRecognitionEngine, @unchecked Sendable {
    private let lock = NSLock()
    private let responses: [String]
    private var responseIndex = 0

    init(responses: [String]) {
        self.responses = responses
    }

    func transcribe(samples: [Float], language: TranscriptionLanguage, initialPrompt: String?) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        guard responseIndex < responses.count else { return "" }
        defer { responseIndex += 1 }
        return responses[responseIndex]
    }
}
