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
    @State private var showingClearConfirmation = false
    @State private var isCapturingHotKey = false
    @State private var showingVocabularyImporter = false
    @State private var vocabularyImportMessage: String?
    @State private var hasPostEventAccess = CGPreflightPostEventAccess()

    var body: some View {
        TabView {
            generalSettings
                .tabItem { Label("Основные", systemImage: "slider.horizontal.3") }

            vocabularySettings
                .tabItem { Label("Словарь", systemImage: "text.book.closed") }
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
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasPostEventAccess = CGPreflightPostEventAccess()
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
            }

            Section {
                Text("Список передаётся Whisper как контекстная подсказка для каждого фрагмента записи. Это помогает сохранить написание терминов, но не гарантирует распознавание и иногда может склонять модель к словам из списка. Подсказка ограничена контекстным окном Whisper, поэтому при большом списке часть терминов может учитываться слабее.")
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
                vocabularyImportMessage = "Новых терминов добавлено: \(merged.addedCount)."
            } catch {
                vocabularyImportMessage = "Не удалось прочитать файл: \(error.localizedDescription)"
            }
        case .failure(let error):
            vocabularyImportMessage = "Не удалось загрузить файл: \(error.localizedDescription)"
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
