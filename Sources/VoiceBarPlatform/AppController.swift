import AppKit
import Combine
import Carbon.HIToolbox
import Foundation
import SwiftData
import VoiceBarCore

@MainActor
public final class AppController: ObservableObject {
    @Published public private(set) var isRecording = false
    @Published public private(set) var isStarting = false
    @Published public private(set) var isProcessing = false
    @Published public private(set) var isEngineReady = false
    @Published public private(set) var isPreparingEngine = false
    @Published public private(set) var canRedownloadModel = false
    @Published public private(set) var modelProgress: Double?
    @Published public private(set) var statusMessage = "Подготовка распознавателя…"
    @Published public private(set) var notice: String?
    @Published public private(set) var previewChunks: [TranscriptChunk] = []
    @Published public private(set) var recordingDuration: TimeInterval = 0
    @Published public private(set) var activeSourceSelection: SourceSelection = .microphone
    public var previewText: String {
        TranscriptAssembler.render(previewChunks, withSourceLabels: activeSourceSelection == .both)
    }

    private let modelContext: ModelContext
    private let modelStore = ModelStore()
    private let capture = AudioCaptureCoordinator()
    private let inserter = TextInserter()
    private let foregroundAppTracker: ForegroundAppTracker
    private var engine: WhisperRuntime?
    private var transcriber: RealtimeTranscriber?
    private var activeLanguage: TranscriptionLanguage = .russian
    private var recordingTargetProcessID: pid_t?
    private var historyGeneration: UInt64 = 0
    private var recordingHistoryGeneration: UInt64?
    private var recordingStartedAt: Date?
    private var durationTask: Task<Void, Never>?
    private var globalHotKey: GlobalHotKey?
    private var hotKeyStateMachine = DictationHotKeyStateMachine()
    private var holdHotKeyShouldContinue = false
    private var holdHotKeyStartPending = false
    private var holdHotKeyOwnsRecording = false

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.foregroundAppTracker = ForegroundAppTracker()
        UserDefaults.standard.register(defaults: [
            "sourceSelection": SourceSelection.microphone.rawValue,
            "transcriptionLanguage": TranscriptionLanguage.russian.rawValue,
            "autoInsert": true,
            "dictationHotKeyMode": DictationHotKeyMode.toggle.rawValue,
            "dictationHotKeyKeyCode": Int(kVK_Space),
            "dictationHotKeyModifiers": Int(controlKey | optionKey),
            "dictationHotKeyName": "Пробел"
        ])
        registerGlobalHotKey()
        Task { await prepareEngine() }
    }

    public func toggleRecording() {
        if isRecording {
            stopRecording()
        } else if !isStarting && !isProcessing {
            Task { await startRecording() }
        }
    }

    public func updateGlobalHotKey() {
        handleHotKeyAction(hotKeyStateMachine.cancel())
        globalHotKey?.unregister()
        globalHotKey = nil
        registerGlobalHotKey()
    }

    public func retryEnginePreparation() {
        guard !isPreparingEngine, !isRecording, !isStarting, !isProcessing else { return }
        Task { await prepareEngine() }
    }

    public func redownloadModel() {
        guard canRedownloadModel, !isPreparingEngine, !isRecording, !isStarting, !isProcessing else { return }
        Task { await prepareEngine(forceModelDownload: true) }
    }

    public func clearNotice() {
        notice = nil
    }

    public func copyToClipboard(_ text: String) {
        inserter.copyToClipboard(text)
        clearNotice()
    }

    public func clearHistory() {
        historyGeneration &+= 1
        do {
            let entries = try modelContext.fetch(FetchDescriptor<TranscriptEntry>())
            for entry in entries { modelContext.delete(entry) }
            try modelContext.save()
            notice = "История очищена."
        } catch {
            notice = "Не удалось очистить историю: \(error.localizedDescription)"
        }
    }

    private func prepareEngine(forceModelDownload: Bool = false) async {
        guard !isPreparingEngine, !isStarting, !isRecording, !isProcessing else { return }
        isPreparingEngine = true
        defer { isPreparingEngine = false }

        isEngineReady = false
        modelProgress = nil
        statusMessage = "Проверка локального движка…"

        guard let libraryURL = WhisperRuntime.locateLibrary() else {
            statusMessage = "Движок whisper.cpp не собран."
            notice = "Для сборки VoiceBar нужны полный Xcode и CMake. Запустите ./scripts/build-app.sh из каталога проекта."
            return
        }

        do {
            let modelURL = try await modelStore.ensureModel(forceDownload: forceModelDownload) { [weak self] progress in
                Task { @MainActor in
                    self?.modelProgress = progress
                    self?.statusMessage = progress.map { "Загрузка модели: \(Int($0 * 100))%" } ?? "Загрузка модели Whisper…"
                }
            }
            statusMessage = "Загрузка модели в память…"
            let loadedEngine = try await Task.detached(priority: .userInitiated) {
                try WhisperRuntime(modelURL: modelURL, libraryURL: libraryURL)
            }.value
            engine = loadedEngine
            isEngineReady = true
            canRedownloadModel = false
            modelProgress = nil
            statusMessage = "Готово к диктовке"
            notice = nil
        } catch {
            modelProgress = nil
            statusMessage = "Распознаватель не готов"
            notice = error.localizedDescription
            if let runtimeError = error as? WhisperRuntimeError,
               case .modelUnavailable(_) = runtimeError {
                canRedownloadModel = true
            }
        }
    }

    private func startRecording() async {
        guard !isStarting, !isRecording, !isProcessing else { return }
        guard let engine else {
            notice = statusMessage == "Движок whisper.cpp не собран"
                ? "Соберите приложение скриптом ./scripts/build-app.sh."
                : "Дождитесь подготовки модели Whisper."
            holdHotKeyStartPending = false
            holdHotKeyShouldContinue = false
            return
        }

        isStarting = true
        recordingTargetProcessID = foregroundAppTracker.targetProcessIDForRecording()
        statusMessage = "Запуск записи…"
        notice = nil
        activeSourceSelection = SourceSelection(rawValue: UserDefaults.standard.string(forKey: "sourceSelection") ?? "") ?? .microphone
        activeLanguage = TranscriptionLanguage(rawValue: UserDefaults.standard.string(forKey: "transcriptionLanguage") ?? "") ?? .russian
        recordingHistoryGeneration = historyGeneration

        let transcriber = RealtimeTranscriber(
            engine: engine,
            language: activeLanguage,
            sources: activeSourceSelection.sources,
            onUpdate: { [weak self] chunks in
                Task { @MainActor in self?.previewChunks = chunks }
            },
            onError: { [weak self] message in
                Task { @MainActor in self?.notice = "Ошибка распознавания: \(message)" }
            }
        )
        self.transcriber = transcriber

        do {
            try await capture.start(sources: activeSourceSelection.sources) { packet in
                transcriber.append(packet)
            }
            isStarting = false
            isRecording = true
            isProcessing = false
            previewChunks = []
            recordingStartedAt = .now
            recordingDuration = 0
            statusMessage = "Идёт запись · \(activeSourceSelection.title)"
            startDurationClock()
            let startedForHoldHotKey = holdHotKeyStartPending
            holdHotKeyStartPending = false
            holdHotKeyOwnsRecording = startedForHoldHotKey && holdHotKeyShouldContinue
            if startedForHoldHotKey && !holdHotKeyShouldContinue {
                stopRecording()
            }
        } catch {
            isStarting = false
            self.transcriber = nil
            recordingTargetProcessID = nil
            recordingHistoryGeneration = nil
            holdHotKeyStartPending = false
            holdHotKeyShouldContinue = false
            holdHotKeyOwnsRecording = false
            statusMessage = "Запись не началась"
            notice = error.localizedDescription
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        holdHotKeyOwnsRecording = false
        let completedHistoryGeneration = recordingHistoryGeneration ?? historyGeneration
        capture.stop()
        isRecording = false
        isProcessing = true
        durationTask?.cancel()
        durationTask = nil
        statusMessage = "Распознавание последних фрагментов…"

        guard let transcriber else {
            finishProcessing(
                result: TranscriptionResult(chunks: [], failedSegments: 0, firstFailureMessage: nil),
                historyGeneration: completedHistoryGeneration
            )
            return
        }
        transcriber.finish { [weak self] result in
            Task { @MainActor in
                self?.finishProcessing(result: result, historyGeneration: completedHistoryGeneration)
            }
        }
    }

    private func finishProcessing(result: TranscriptionResult, historyGeneration completedGeneration: UInt64) {
        let chunks = result.chunks
        previewChunks = chunks
        let text = TranscriptAssembler.render(chunks, withSourceLabels: activeSourceSelection == .both)
        .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            isProcessing = false
            transcriber = nil
            recordingHistoryGeneration = nil
            recordingStartedAt = nil
            recordingTargetProcessID = nil
            if result.failedSegments > 0 {
                statusMessage = "Речь не распознана"
                notice = "Не удалось распознать сегментов: \(result.failedSegments). \(result.firstFailureMessage ?? "Попробуйте повторить запись.")"
            } else {
                statusMessage = "Речь не распознана"
                notice = "Попробуйте говорить ближе к микрофону или проверьте, что системный звук воспроизводился во время записи."
            }
            return
        }

        var persistenceFailure: String?
        if completedGeneration == historyGeneration {
            do {
                modelContext.insert(TranscriptEntry(
                    createdAt: .now,
                    text: text,
                    language: activeLanguage.rawValue,
                    sourceSelection: activeSourceSelection.rawValue
                ))
                try pruneHistory()
                try modelContext.save()
            } catch {
                persistenceFailure = "Не удалось сохранить историю: \(error.localizedDescription)"
            }
        } else {
            persistenceFailure = "Результат не добавлен в историю, потому что её очистили во время распознавания."
        }

        var deliveryMessage: String
        let autoInsert = UserDefaults.standard.bool(forKey: "autoInsert")
        if result.failedSegments > 0 {
            if autoInsert {
                inserter.copyToClipboard(text)
                deliveryMessage = "Не удалось распознать сегментов: \(result.failedSegments). Частичный текст скопирован; автоматическая вставка отменена."
            } else {
                deliveryMessage = "Не удалось распознать сегментов: \(result.failedSegments). Сохранён частичный результат; автоматическая вставка отключена."
            }
            if let firstFailureMessage = result.firstFailureMessage {
                deliveryMessage += " Ошибка: \(firstFailureMessage)"
            }
            statusMessage = "Частичная расшифровка"
        } else if autoInsert {
            switch inserter.insert(text, intoProcess: recordingTargetProcessID) {
            case .pasted:
                statusMessage = "Текст вставлен"
                deliveryMessage = "Расшифровка вставлена в активное приложение."
            case .clipboardOnly(let message):
                statusMessage = "Текст скопирован"
                deliveryMessage = message
            }
        } else {
            statusMessage = "Расшифровка сохранена"
            deliveryMessage = "Текст сохранён в истории."
        }
        notice = [deliveryMessage, persistenceFailure].compactMap { $0 }.joined(separator: " ")

        isProcessing = false
        transcriber = nil
        recordingHistoryGeneration = nil
        recordingStartedAt = nil
        recordingTargetProcessID = nil
    }

    private func pruneHistory() throws {
        var descriptor = FetchDescriptor<TranscriptEntry>(sortBy: [
            SortDescriptor(\.createdAt, order: .reverse)
        ])
        descriptor.fetchLimit = 101
        let entries = try modelContext.fetch(descriptor)
        if entries.count > 100 {
            for entry in entries.dropFirst(100) { modelContext.delete(entry) }
        }
    }

    private func startDurationClock() {
        durationTask?.cancel()
        durationTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                guard let startedAt = self.recordingStartedAt else { continue }
                self.recordingDuration = Date.now.timeIntervalSince(startedAt)
            }
        }
    }

    private func registerGlobalHotKey() {
        let hotKey = GlobalHotKey { [weak self] event in
            guard let self else { return }
            let event: DictationHotKeyEvent = event == .pressed ? .pressed : .released
            let rawMode = UserDefaults.standard.string(forKey: "dictationHotKeyMode") ?? ""
            let mode = DictationHotKeyMode(rawValue: rawMode) ?? .toggle
            self.handleHotKeyAction(self.hotKeyStateMachine.handle(event, mode: mode))
        }
        do {
            let defaults = UserDefaults.standard
            let keyCode = UInt32(clamping: defaults.integer(forKey: "dictationHotKeyKeyCode"))
            let modifiers = UInt32(clamping: defaults.integer(forKey: "dictationHotKeyModifiers"))
            guard modifiers != 0 else {
                notice = "Для глобальной горячей клавиши нужен хотя бы один модификатор: Control, Option, Shift или Command."
                return
            }
            try hotKey.register(keyCode: keyCode, modifiers: modifiers)
            globalHotKey = hotKey
            if let notice, notice.contains("сочетание клавиш") {
                self.notice = nil
            }
        } catch {
            notice = error.localizedDescription
        }
    }

    private func handleHotKeyAction(_ action: DictationHotKeyAction) {
        switch action {
        case .none:
            break
        case .toggle:
            toggleRecording()
        case .start:
            beginHoldHotKeyRecording()
        case .stop:
            endHoldHotKeyRecording()
        }
    }

    private func beginHoldHotKeyRecording() {
        if isStarting && holdHotKeyStartPending {
            holdHotKeyShouldContinue = true
            return
        }
        guard !isStarting, !isRecording, !isProcessing else { return }
        holdHotKeyShouldContinue = true
        holdHotKeyStartPending = true
        Task { await startRecording() }
    }

    private func endHoldHotKeyRecording() {
        guard holdHotKeyShouldContinue || holdHotKeyStartPending || holdHotKeyOwnsRecording else { return }
        holdHotKeyShouldContinue = false
        if holdHotKeyOwnsRecording {
            holdHotKeyOwnsRecording = false
            stopRecording()
        }
    }
}
