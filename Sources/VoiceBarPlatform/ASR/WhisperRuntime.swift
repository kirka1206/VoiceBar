import Foundation
import Darwin
import VoiceBarCore

enum WhisperRuntimeError: LocalizedError {
    case libraryMissing
    case missingSymbol(String)
    case modelUnavailable(String)
    case tokenization(String)
    case transcription(String)

    var errorDescription: String? {
        switch self {
        case .libraryMissing:
            "Не найдена собранная библиотека whisper.cpp. Соберите приложение скриптом build-app.sh."
        case .missingSymbol(let name):
            "Библиотека распознавания не содержит функцию \(name)."
        case .modelUnavailable(let message), .tokenization(let message), .transcription(let message):
            message
        }
    }
}

protocol SpeechRecognitionEngine: Sendable {
    var initialPromptTokenBudget: Int { get }
    func initialPromptTokenCount(for prompt: String) throws -> Int
    func transcribe(
        samples: [Float],
        language: TranscriptionLanguage,
        initialPrompt: String?
    ) throws -> String
}

/// Holds one whisper.cpp context for the whole app session; chunk transcriptions
/// reuse the loaded model instead of reopening its multi-gigabyte weights.
final class WhisperRuntime: SpeechRecognitionEngine, @unchecked Sendable {
    private typealias CreateFunction = @convention(c) (
        UnsafePointer<CChar>, UnsafeMutablePointer<CChar>?, Int32
    ) -> UnsafeMutableRawPointer?
    private typealias DestroyFunction = @convention(c) (UnsafeMutableRawPointer?) -> Void
    private typealias PromptBudgetFunction = @convention(c) (UnsafeMutableRawPointer?) -> Int32
    private typealias PromptTokenCountFunction = @convention(c) (
        UnsafeMutableRawPointer?, UnsafePointer<CChar>?
    ) -> Int32
    private typealias TranscribeFunction = @convention(c) (
        UnsafeMutableRawPointer?, UnsafePointer<Float>?, Int32, UnsafePointer<CChar>?,
        UnsafePointer<CChar>?, UnsafeMutablePointer<CChar>?, Int32,
        UnsafeMutablePointer<CChar>?, Int32
    ) -> Int32

    private let libraryHandle: UnsafeMutableRawPointer
    private let context: UnsafeMutableRawPointer
    private let contextLock = NSLock()
    private let destroy: DestroyFunction
    private let promptBudgetFunction: PromptBudgetFunction
    private let promptTokenCountFunction: PromptTokenCountFunction
    private let transcribeFunction: TranscribeFunction

    var initialPromptTokenBudget: Int {
        contextLock.lock()
        defer { contextLock.unlock() }
        return Int(promptBudgetFunction(context))
    }

    init(modelURL: URL, libraryURL: URL? = nil) throws {
        guard let resolvedLibraryURL = libraryURL ?? Self.locateLibrary(),
              let handle = dlopen(resolvedLibraryURL.path, RTLD_NOW | RTLD_LOCAL) else {
            throw WhisperRuntimeError.libraryMissing
        }

        do {
            let create: CreateFunction = try Self.symbol("voicebar_whisper_create", from: handle)
            let destroy: DestroyFunction = try Self.symbol("voicebar_whisper_destroy", from: handle)
            let promptBudget: PromptBudgetFunction = try Self.symbol("voicebar_whisper_initial_prompt_budget", from: handle)
            let promptTokenCount: PromptTokenCountFunction = try Self.symbol("voicebar_whisper_prompt_token_count", from: handle)
            let transcribe: TranscribeFunction = try Self.symbol("voicebar_whisper_transcribe", from: handle)

            var errorBuffer = [CChar](repeating: 0, count: 2_048)
            let createdContext = modelURL.path.withCString { path in
                errorBuffer.withUnsafeMutableBufferPointer { buffer in
                    create(path, buffer.baseAddress, Int32(buffer.count))
                }
            }
            guard let createdContext else {
                let error = String(cString: errorBuffer)
                throw WhisperRuntimeError.modelUnavailable(error.isEmpty ? "Не удалось загрузить модель Whisper." : error)
            }

            self.libraryHandle = handle
            self.context = createdContext
            self.destroy = destroy
            self.promptBudgetFunction = promptBudget
            self.promptTokenCountFunction = promptTokenCount
            self.transcribeFunction = transcribe
        } catch {
            dlclose(handle)
            throw error
        }
    }

    deinit {
        destroy(context)
        dlclose(libraryHandle)
    }

    func initialPromptTokenCount(for prompt: String) throws -> Int {
        contextLock.lock()
        defer { contextLock.unlock() }
        let count = prompt.withCString { promptTokenCountFunction(context, $0) }
        guard count >= 0 else {
            throw WhisperRuntimeError.tokenization("Не удалось измерить размер словаря для подсказки Whisper.")
        }
        return Int(count)
    }

    func transcribe(
        samples: [Float],
        language: TranscriptionLanguage,
        initialPrompt: String?
    ) throws -> String {
        guard !samples.isEmpty, samples.count <= Int(Int32.max) else {
            throw WhisperRuntimeError.transcription("Сегмент аудио пустой или слишком большой.")
        }

        var textBuffer = [CChar](repeating: 0, count: 65_536)
        var errorBuffer = [CChar](repeating: 0, count: 2_048)
        let prompt = initialPrompt ?? ""
        contextLock.lock()
        defer { contextLock.unlock() }
        let result = samples.withUnsafeBufferPointer { sampleBuffer in
            language.rawValue.withCString { languageCode in
                prompt.withCString { promptPointer in
                    textBuffer.withUnsafeMutableBufferPointer { text in
                        errorBuffer.withUnsafeMutableBufferPointer { error in
                            transcribeFunction(
                                context,
                                sampleBuffer.baseAddress,
                                Int32(sampleBuffer.count),
                                languageCode,
                                promptPointer,
                                text.baseAddress,
                                Int32(text.count),
                                error.baseAddress,
                                Int32(error.count)
                            )
                        }
                    }
                }
            }
        }

        guard result == 0 else {
            let message = String(cString: errorBuffer)
            throw WhisperRuntimeError.transcription(message.isEmpty ? "Ошибка распознавания аудио." : message)
        }
        return String(cString: textBuffer).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func locateLibrary() -> URL? {
        let candidates = [
            Bundle.main.privateFrameworksURL?.appendingPathComponent("libVoiceBarWhisper.dylib"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("build/whisper/libVoiceBarWhisper.dylib"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("dist/VoiceBar.app/Contents/Frameworks/libVoiceBarWhisper.dylib")
        ].compactMap { $0 }

        return candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) })
    }

    private static func symbol<T>(_ name: String, from handle: UnsafeMutableRawPointer) throws -> T {
        guard let pointer = dlsym(handle, name) else {
            throw WhisperRuntimeError.missingSymbol(name)
        }
        return unsafeBitCast(pointer, to: T.self)
    }
}
