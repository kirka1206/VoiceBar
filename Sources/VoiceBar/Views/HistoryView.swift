import AppKit
import Carbon.HIToolbox
import SwiftData
import SwiftUI
import VoiceBarCore
import VoiceBarPlatform

struct HistoryView: View {
    @ObservedObject var controller: AppController
    @AppStorage("dictationHotKeyMode") private var hotKeyMode = DictationHotKeyMode.toggle.rawValue
    @AppStorage("dictationHotKeyModifiers") private var hotKeyModifiers = Int(controlKey | optionKey)
    @AppStorage("dictationHotKeyName") private var hotKeyName = "Пробел"
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TranscriptEntry.createdAt, order: .reverse) private var entries: [TranscriptEntry]

    var body: some View {
        VStack(spacing: 0) {
            livePanel
            if let notice = controller.notice {
                HStack(alignment: .top) {
                    Text(notice)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Скрыть") { controller.clearNotice() }
                        .buttonStyle(.plain)
                }
                .font(.callout)
                .padding(12)
                .background(.yellow.opacity(0.12))
            }

            if entries.isEmpty {
                ContentUnavailableView {
                    Label(
                        controller.isEngineReady ? "Готов к диктовке" : "Подготовка модели Whisper",
                        systemImage: controller.isEngineReady ? "waveform" : "arrow.down.circle"
                    )
                } description: {
                    Text(controller.isEngineReady
                         ? hotKeyInstruction
                         : "При первом запуске скачивается локальная модель размером около 1,5 ГБ. Дождитесь окончания подготовки, затем поставьте курсор в поле нужного приложения и используйте горячую клавишу.")
                } actions: {
                    Button {
                        controller.toggleRecording()
                    } label: {
                        Label(
                            controller.isEngineReady ? "Начать диктовку" : "Подготовка модели…",
                            systemImage: "mic.fill"
                        )
                    }
                    .disabled(!controller.isEngineReady || controller.isStarting || controller.isProcessing)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(entry.createdAt, format: .dateTime.year().month().day().hour().minute())
                                Spacer()
                                Text(sourceTitle(entry.sourceSelection))
                                    .foregroundStyle(.secondary)
                            }
                            .font(.caption)
                            Text(entry.text)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            HStack {
                                Text(languageTitle(entry.language))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Копировать") {
                                    controller.copyToClipboard(entry.text)
                                }
                                .buttonStyle(.borderless)
                            }
                            .font(.caption)
                        }
                        .padding(.vertical, 6)
                    }
                    .onDelete(perform: deleteEntries)
                }
                .listStyle(.inset)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    controller.toggleRecording()
                } label: {
                    Label(
                        controller.isStarting ? "Подготовка записи…" : controller.isRecording ? "Остановить" : "Диктовать",
                        systemImage: controller.isRecording ? "stop.fill" : "mic.fill"
                    )
                }
                .disabled(!controller.isRecording && (!controller.isEngineReady || controller.isStarting || controller.isProcessing))
                SettingsLink {
                    Label("Настройки", systemImage: "gearshape")
                }
            }
        }
    }

    private var livePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(controller.statusMessage, systemImage: controller.isRecording ? "record.circle" : "waveform")
                    .foregroundStyle(controller.isRecording ? .red : .primary)
                Spacer()
                if controller.isRecording {
                    Text(Self.duration(controller.recordingDuration))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            if controller.previewChunks.isEmpty {
                Text(controller.isRecording
                     ? "Говорите — готовые фрагменты появятся здесь."
                     : controller.isEngineReady
                         ? "Управление: \(hotKeyInstruction)"
                         : "Первый запуск загружает модель; после этого распознавание работает офлайн.")
                    .foregroundStyle(.secondary)
            } else {
                Text(controller.previewText)
                    .lineLimit(4)
                    .textSelection(.enabled)
            }
            if let progress = controller.modelProgress {
                ProgressView(value: progress)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35))
    }

    private func deleteEntries(at offsets: IndexSet) {
        for index in offsets { modelContext.delete(entries[index]) }
        try? modelContext.save()
    }

    private var hotKeyInstruction: String {
        HotKeyFormatter.instruction(
            mode: DictationHotKeyMode(rawValue: hotKeyMode) ?? .toggle,
            combination: HotKeyFormatter.displayName(modifiers: hotKeyModifiers, keyName: hotKeyName)
        )
    }

    private func sourceTitle(_ rawValue: String) -> String {
        SourceSelection(rawValue: rawValue)?.title ?? rawValue
    }

    private func languageTitle(_ rawValue: String) -> String {
        TranscriptionLanguage(rawValue: rawValue)?.title ?? rawValue
    }

    private static func duration(_ interval: TimeInterval) -> String {
        VoiceBarFormatting.duration(interval)
    }
}
