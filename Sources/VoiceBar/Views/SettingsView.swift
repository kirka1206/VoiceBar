import AppKit
import Carbon.HIToolbox
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers
import VoiceBarCore
import VoiceBarPlatform

struct SettingsView: View {
    @ObservedObject var controller: AppController
    @AppStorage("sourceSelection") private var sourceSelection = SourceSelection.microphone.rawValue
    @AppStorage("transcriptionLanguage") private var language = TranscriptionLanguage.russian.rawValue
    @AppStorage("autoInsert") private var autoInsert = true
    @AppStorage("dictationHotKeyMode") private var hotKeyMode = DictationHotKeyMode.toggle.rawValue
    @AppStorage("dictationHotKeyKeyCode") private var hotKeyKeyCode = Int(kVK_Space)
    @AppStorage("dictationHotKeyModifiers") private var hotKeyModifiers = Int(controlKey | optionKey)
    @AppStorage("dictationHotKeyName") private var hotKeyName = "Пробел"
    @AppStorage("recognitionVocabulary") private var recognitionVocabulary = ""
    @AppStorage("recognitionCorrectionRules") private var recognitionCorrectionRules = ""
    @State private var showingClearConfirmation = false
    @State private var isCapturingHotKey = false
    @State private var showingVocabularyImporter = false
    @State private var vocabularyImportMessage: String?
    @State private var showingDocumentImporter = false
    @State private var showingCandidateReview = false
    @State private var isExtractingDocumentTerms = false
    @State private var documentTermCandidates: [DocumentTermCandidate] = []
    @State private var documentImportSummary = ""
    @State private var documentImportMessage: String?
    @State private var showingCorrectionImporter = false
    @State private var correctionImportMessage: String?
    @State private var hasPostEventAccess = CGPreflightPostEventAccess()

    var body: some View {
        TabView {
            generalSettings
                .tabItem { Label("Основные", systemImage: "slider.horizontal.3") }

            vocabularySettings
                .tabItem { Label("Словарь", systemImage: "text.book.closed") }

            correctionSettings
                .tabItem { Label("Исправления", systemImage: "arrow.2.circlepath") }
        }
        .padding(18)
        .confirmationDialog(
            "Удалить локальную историю VoiceBar?",
            isPresented: $showingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Очистить историю", role: .destructive) { controller.clearHistory() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Будут удалены сохранённые тексты и их метаданные.")
        }
        .fileImporter(
            isPresented: $showingVocabularyImporter,
            allowedContentTypes: [.plainText]
        ) { result in
            importVocabulary(result)
        }
        .fileImporter(
            isPresented: $showingCorrectionImporter,
            allowedContentTypes: [.plainText]
        ) { result in
            importCorrectionRules(result)
        }
        .fileImporter(
            isPresented: $showingDocumentImporter,
            allowedContentTypes: DocumentTextExtractor.allowedContentTypes,
            allowsMultipleSelection: true
        ) { result in
            importDocuments(result)
        }
        .sheet(isPresented: $showingCandidateReview) {
            DocumentTermReviewView(
                candidates: documentTermCandidates,
                importSummary: documentImportSummary,
                onAdd: addDocumentTerms
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasPostEventAccess = CGPreflightPostEventAccess()
        }
        .onChange(of: recognitionVocabulary, initial: true) { _, vocabulary in
            controller.requestPromptUsage(for: vocabulary)
        }
        .onChange(of: controller.isEngineReady) { _, isReady in
            if isReady { controller.requestPromptUsage(for: recognitionVocabulary) }
        }
    }

    private var generalSettings: some View {
        Form {
            Section("Распознавание") {
                Picker("Источник звука", selection: $sourceSelection) {
                    ForEach(SourceSelection.allCases) { source in
                        Text(source.title).tag(source.rawValue)
                    }
                }
                Picker("Язык", selection: $language) {
                    ForEach(TranscriptionLanguage.allCases) { language in
                        Text(language.title).tag(language.rawValue)
                    }
                }
                Toggle("Вставлять результат в активное приложение", isOn: $autoInsert)
                if autoInsert {
                    Label(
                        hasPostEventAccess ? "Автовставка разрешена" : "Нужно разрешение на управление компьютером",
                        systemImage: hasPostEventAccess ? "checkmark.circle.fill" : "exclamationmark.circle"
                    )
                    .font(.callout)
                    .foregroundStyle(hasPostEventAccess ? .green : .secondary)
                    if !hasPostEventAccess {
                        Text("Если VoiceBar уже включён в этом списке, но вставка не разрешена, удалите старую запись и добавьте текущую VoiceBar.app заново.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Запросить разрешение на вставку") {
                            _ = CGRequestPostEventAccess()
                            hasPostEventAccess = CGPreflightPostEventAccess()
                        }
                    }
                    Button("Открыть настройки разрешения…") {
                        openPrivacyPane("Privacy_Accessibility")
                    }
                }
            }

            Section("Горячая клавиша") {
                Picker("Режим", selection: $hotKeyMode) {
                    ForEach(DictationHotKeyMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                Text(hotKeyModeDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                LabeledContent("Сочетание") {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .controlBackgroundColor))
                        Text(isCapturingHotKey ? "Нажмите сочетание…" : hotKeyDisplayName)
                            .font(.system(.body, design: .rounded).monospaced())
                            .lineLimit(1)
                            .allowsHitTesting(false)
                        HotKeyRecorderField(
                            isCapturing: $isCapturingHotKey,
                            onCapture: { keyCode, modifiers, keyName in
                                hotKeyKeyCode = keyCode
                                hotKeyModifiers = modifiers
                                hotKeyName = keyName
                                isCapturingHotKey = false
                                controller.updateGlobalHotKey()
                            }
                        )
                    }
                    .frame(width: 210, height: 32)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                    .help("Нажмите здесь, затем задайте сочетание как минимум с одной клавишей-модификатором.")
                }
                Text("По умолчанию: Control + Option + Пробел. Некоторые системные сочетания могут быть заняты macOS.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Локальные данные") {
                Text("Хранятся последние 100 текстов. Аудиозаписи на диск не сохраняются.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Очистить историю…", role: .destructive) {
                    showingClearConfirmation = true
                }
            }

            Section("Состояние движка") {
                Text(controller.statusMessage)
                if let progress = controller.modelProgress {
                    ProgressView(value: progress)
                }
                if !controller.isEngineReady {
                    Button(controller.isPreparingEngine ? "Подготовка…" : "Повторить подготовку") {
                        controller.retryEnginePreparation()
                    }
                    .disabled(controller.isPreparingEngine)
                }
                if controller.canRedownloadModel {
                    Button("Загрузить модель заново") {
                        controller.redownloadModel()
                    }
                    .disabled(controller.isPreparingEngine)
                }
                HStack {
                    Button("Настройки микрофона") { openPrivacyPane("Privacy_Microphone") }
                    Button("Запись системного аудио") { openPrivacyPane("Privacy_AudioCapture") }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var vocabularySettings: some View {
        Form {
            Section("Английские термины") {
                Text("Добавляйте по одному термину или названию на строку. Многословные названия, например Deckhouse Kubernetes Platform, оставляйте целиком на одной строке.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                TextEditor(text: $recognitionVocabulary)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 190)
                    .accessibilityLabel("Список терминов для распознавания")

                HStack {
                    Text("Терминов: \(RecognitionVocabulary.terms(from: recognitionVocabulary).count)")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Загрузить из файла…") {
                        showingVocabularyImporter = true
                    }
                }

                if let vocabularyImportMessage {
                    Text(vocabularyImportMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let promptUsage = controller.promptUsage(for: recognitionVocabulary) {
                    Label(
                        "Подсказка: \(promptUsage.tokenCount) из \(promptUsage.tokenBudget) токенов",
                        systemImage: promptUsage.isWithinBudget ? "checkmark.circle" : "exclamationmark.triangle.fill"
                    )
                    .font(.callout)
                    .foregroundColor(promptUsage.isWithinBudget ? .secondary : .red)
                    if !promptUsage.isWithinBudget {
                        Text("Сохранённый словарь останется без изменений, но запись заблокирована, пока подсказка превышает лимит. Удалите часть терминов из списка.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } else {
                    Text("Размер подсказки станет доступен после загрузки модели Whisper.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Добавить термины из документов") {
                Text("VoiceBar ищет технические названия в текстовых документах, Word и PDF с текстовым слоем. Сканированные PDF не распознаются. Файлы обрабатываются на этом Mac и не сохраняются в истории. Если файл хранится в iCloud Drive или другом File Provider, macOS при необходимости загрузит его для чтения.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button(isExtractingDocumentTerms ? "Извлечение…" : "Выбрать документы…") {
                    showingDocumentImporter = true
                }
                .disabled(isExtractingDocumentTerms)
                if let documentImportMessage {
                    Text(documentImportMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Section {
                Text("Список передаётся Whisper как контекстная подсказка для каждого фрагмента записи. Это помогает сохранить написание терминов, но не гарантирует распознавание и иногда может склонять модель к словам из списка. VoiceBar показывает заполнение лимита выбранной модели и не начнёт запись, если полный список его превышает.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var correctionSettings: some View {
        Form {
            Section("Варианты распознавания → правильное написание") {
                Text("Указывайте по одному правилу на строку в формате «как распознаётся => как писать». Например: Vesphere => vSphere. Правила применяются к целым словам и фразам; более длинная фраза имеет приоритет.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                TextEditor(text: $recognitionCorrectionRules)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 190)
                    .accessibilityLabel("Правила исправления распознавания")

                HStack {
                    Text("Правил: \(RecognitionNormalizer.rules(from: recognitionCorrectionRules).count)")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Загрузить из файла…") {
                        showingCorrectionImporter = true
                    }
                }

                let ambiguousAliases = RecognitionNormalizer.ambiguousAliases(in: recognitionCorrectionRules)
                if !ambiguousAliases.isEmpty {
                    Text("Неоднозначные русские слова не исправляются автоматически: \(ambiguousAliases.joined(separator: ", ")). Их написание зависит от контекста.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let correctionImportMessage {
                    Text(correctionImportMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Text("Исправления применяются к каждому сегменту до сборки расшифровки, поэтому предварительный просмотр и итоговый текст используют одинаковое написание. Обычные русские слова, которые могут встречаться в других значениях, оставляются без автоматической замены.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func importVocabulary(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let didStartAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let imported = try String(contentsOf: url, encoding: .utf8)
                let importedCount = RecognitionVocabulary.terms(from: imported).count
                guard importedCount > 0 else {
                    vocabularyImportMessage = "В файле нет терминов: ожидается по одному на строку."
                    return
                }

                let merged = RecognitionVocabulary.merge(existing: recognitionVocabulary, imported: imported)
                recognitionVocabulary = merged.text
                vocabularyImportMessage = vocabularyImportStatus(addedCount: merged.addedCount, vocabulary: merged.text)
            } catch {
                vocabularyImportMessage = "Не удалось прочитать файл: \(error.localizedDescription)"
            }
        case .failure(let error):
            vocabularyImportMessage = "Не удалось загрузить файл: \(error.localizedDescription)"
        }
    }

    private func importDocuments(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard !urls.isEmpty else { return }
            let currentVocabulary = recognitionVocabulary
            isExtractingDocumentTerms = true
            documentImportMessage = "Читаем выбранные документы локально…"
            Task.detached(priority: .userInitiated) {
                var accumulator = DocumentTermCandidateExtractor.Accumulator(
                    excluding: RecognitionVocabulary.terms(from: currentVocabulary)
                )
                var processedFileCount = 0
                var failures: [String] = []

                for url in urls {
                    let didStartAccessing = url.startAccessingSecurityScopedResource()
                    defer {
                        if didStartAccessing { url.stopAccessingSecurityScopedResource() }
                    }
                    do {
                        try DocumentTextExtractor.forEachFragment(from: url) { fragment in
                            accumulator.add(fragment)
                        }
                        processedFileCount += 1
                    } catch {
                        failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
                    }
                }

                let candidates = accumulator.candidates(limit: 100)
                let summaryParts = ["Обработано файлов: \(processedFileCount) из \(urls.count)."]
                    + (failures.isEmpty ? [] : ["Не удалось обработать:\n" + failures.joined(separator: "\n")])
                let summary = summaryParts.joined(separator: " ")
                let hasFailures = !failures.isEmpty

                await MainActor.run {
                    isExtractingDocumentTerms = false
                    documentTermCandidates = candidates
                    documentImportSummary = summary
                    if candidates.isEmpty {
                        documentImportMessage = !hasFailures
                            ? "Подходящих новых терминов не найдено."
                            : summary + "\nНовых терминов для проверки нет."
                    } else {
                        documentImportMessage = summary + " Проверьте предложения перед добавлением."
                        showingCandidateReview = true
                    }
                }
            }
        case .failure(let error):
            documentImportMessage = "Не удалось открыть выбор файлов: \(error.localizedDescription)"
        }
    }

    private func addDocumentTerms(_ terms: [String]) {
        guard !terms.isEmpty else { return }
        let merged = RecognitionVocabulary.merge(existing: recognitionVocabulary, imported: terms.joined(separator: "\n"))
        recognitionVocabulary = merged.text
        vocabularyImportMessage = vocabularyImportStatus(addedCount: merged.addedCount, vocabulary: merged.text)
        documentImportMessage = "Добавлено терминов: \(merged.addedCount). \(documentImportSummary)"
    }

    private func vocabularyImportStatus(addedCount: Int, vocabulary: String) -> String {
        var message = "Новых терминов добавлено: \(addedCount)."
        if let promptUsage = controller.promptUsage(for: vocabulary), !promptUsage.isWithinBudget {
            message += " Подсказка превышает лимит: \(promptUsage.tokenCount)/\(promptUsage.tokenBudget) токенов. Все строки сохранены; сократите словарь перед записью."
        }
        return message
    }

    private func importCorrectionRules(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let didStartAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let imported = try String(contentsOf: url, encoding: .utf8)
                let merged = RecognitionNormalizer.merge(existing: recognitionCorrectionRules, imported: imported)
                recognitionCorrectionRules = merged.text

                var messages: [String] = []
                if merged.addedCount > 0 {
                    messages.append("Добавлено правил: \(merged.addedCount).")
                }
                if !merged.conflicts.isEmpty {
                    messages.append("Конфликтующие строки: \(merged.conflicts.joined(separator: "; ")). Существующие правила сохранены; измените их в редакторе, если нужен другой вариант.")
                }
                if messages.isEmpty {
                    messages.append("Новых правил нет: строки пусты, некорректны или уже добавлены.")
                }
                correctionImportMessage = messages.joined(separator: " ")
            } catch {
                correctionImportMessage = "Не удалось прочитать файл: \(error.localizedDescription)"
            }
        case .failure(let error):
            correctionImportMessage = "Не удалось загрузить файл: \(error.localizedDescription)"
        }
    }

    private func openPrivacyPane(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }

    private var hotKeyModeDescription: String {
        HotKeyFormatter.instruction(
            mode: DictationHotKeyMode(rawValue: hotKeyMode) ?? .toggle,
            combination: hotKeyDisplayName
        )
    }

    private var hotKeyDisplayName: String {
        HotKeyFormatter.displayName(modifiers: hotKeyModifiers, keyName: hotKeyName)
    }
}
