import Foundation
import VoiceBarCore

struct TranscriptionResult: Sendable {
    let chunks: [TranscriptChunk]
    let failedSegments: Int
    let firstFailureMessage: String?
}

enum RealtimeTranscriberError: LocalizedError, Equatable {
    case vocabularyPromptOverBudget(tokenCount: Int, tokenBudget: Int)

    var errorDescription: String? {
        switch self {
        case .vocabularyPromptOverBudget(let tokenCount, let tokenBudget):
            "Словарь занимает \(tokenCount) токенов при лимите \(tokenBudget). Удалите часть терминов в настройках, чтобы начать распознавание."
        }
    }
}

final class RealtimeTranscriber: @unchecked Sendable {
    private let inputQueue = DispatchQueue(label: "com.kir.voicebar.audio-input", qos: .userInitiated)
    private let inferenceQueue = DispatchQueue(label: "com.kir.voicebar.whisper", qos: .userInitiated)
    private let engine: any SpeechRecognitionEngine
    private let language: TranscriptionLanguage
    private let initialPrompt: String?
    private let correctionRules: [RecognitionNormalizer.Rule]
    private var normalizers: [AudioSource: StreamingResampler] = [:]
    private var chunkers: [AudioSource: AudioChunker] = [:]
    private var sessionOrigin: TimeInterval?
    private var assembler = TranscriptAssembler()
    private var failedSegments = 0
    private var firstFailureMessage: String?
    private let onUpdate: @Sendable ([TranscriptChunk]) -> Void
    private let onError: @Sendable (String) -> Void

    init(
        engine: any SpeechRecognitionEngine,
        language: TranscriptionLanguage,
        recognitionVocabulary: String,
        correctionRules: String = "",
        sources: [AudioSource],
        onUpdate: @escaping @Sendable ([TranscriptChunk]) -> Void,
        onError: @escaping @Sendable (String) -> Void
    ) throws {
        self.engine = engine
        self.language = language
        let prompt = RecognitionVocabulary.initialPrompt(from: recognitionVocabulary)
        if let prompt {
            let tokenCount = try engine.initialPromptTokenCount(for: prompt)
            let usage = RecognitionVocabulary.PromptUsage(
                tokenCount: tokenCount,
                tokenBudget: engine.initialPromptTokenBudget
            )
            guard usage.isWithinBudget else {
                throw RealtimeTranscriberError.vocabularyPromptOverBudget(
                    tokenCount: usage.tokenCount,
                    tokenBudget: usage.tokenBudget
                )
            }
        }
        self.initialPrompt = prompt
        self.correctionRules = RecognitionNormalizer.rules(from: correctionRules)
        self.onUpdate = onUpdate
        self.onError = onError
        for source in sources {
            normalizers[source] = StreamingResampler()
        }
    }

    func append(_ packet: AudioPacket) {
        inputQueue.async { [weak self] in
            guard let self, var normalizer = self.normalizers[packet.source] else { return }

            let origin = self.sessionOrigin ?? packet.captureTime
            self.sessionOrigin = origin
            var chunker = self.chunkers[packet.source] ?? AudioChunker(
                source: packet.source,
                initialStartTime: max(0, packet.captureTime - origin)
            )

            let normalizedSamples = normalizer.process(packet.samples, sampleRate: packet.sampleRate)
            self.normalizers[packet.source] = normalizer
            let readyChunks = chunker.append(normalizedSamples)
            self.chunkers[packet.source] = chunker
            for chunk in readyChunks {
                self.enqueueInference(for: chunk)
            }
        }
    }

    func finish(completion: @escaping @Sendable (TranscriptionResult) -> Void) {
        inputQueue.async { [weak self] in
            guard let self else { return }
            for source in self.chunkers.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
                guard var chunker = self.chunkers[source] else { continue }
                if let finalChunk = chunker.finish() {
                    self.enqueueInference(for: finalChunk)
                }
                self.chunkers[source] = chunker
            }

            self.inferenceQueue.async { [weak self] in
                guard let self else { return }
                let result = TranscriptionResult(
                    chunks: self.assembler.chunks,
                    failedSegments: self.failedSegments,
                    firstFailureMessage: self.firstFailureMessage
                )
                DispatchQueue.main.async {
                    completion(result)
                }
            }
        }
    }

    private func enqueueInference(for chunk: AudioChunk) {
        inferenceQueue.async { [weak self] in
            guard let self else { return }
            do {
                let recognizedText = try self.engine.transcribe(
                    samples: chunk.samples,
                    language: self.language,
                    initialPrompt: self.initialPrompt
                )
                let text = RecognitionNormalizer.normalize(recognizedText, using: self.correctionRules)
                guard !text.isEmpty else { return }
                if self.assembler.append(source: chunk.source, startTime: chunk.startTime, text: text) != nil {
                    let snapshot = self.assembler.chunks
                    DispatchQueue.main.async {
                        self.onUpdate(snapshot)
                    }
                }
            } catch {
                let message = error.localizedDescription
                self.failedSegments += 1
                if self.firstFailureMessage == nil {
                    self.firstFailureMessage = message
                }
                DispatchQueue.main.async {
                    self.onError(message)
                }
            }
        }
    }
}
