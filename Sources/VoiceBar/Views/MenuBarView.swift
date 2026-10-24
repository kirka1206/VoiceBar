import AppKit
import SwiftUI
import VoiceBarCore
import VoiceBarPlatform

struct MenuBarView: View {
    @ObservedObject var controller: AppController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            controller.toggleRecording()
        } label: {
            Label(recordButtonTitle, systemImage: controller.isRecording ? "stop.fill" : "mic.fill")
        }
        .disabled(!controller.isRecording && (!controller.isEngineReady || controller.isStarting || controller.isProcessing))

        if controller.isRecording || controller.isProcessing {
            Text(controller.statusMessage)
            Text(Self.duration(controller.recordingDuration))
                .foregroundStyle(.secondary)
        } else {
            Text(controller.statusMessage)
                .foregroundStyle(.secondary)
        }

        if let chunk = controller.previewChunks.last {
            Divider()
            Text("Последний фрагмент")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(TranscriptAssembler.render(
                [chunk],
                withSourceLabels: controller.activeSourceSelection == .both
            ))
                .lineLimit(3)
        }

        if let notice = controller.notice {
            Divider()
            Text(notice)
                .lineLimit(4)
            Button("Скрыть сообщение") { controller.clearNotice() }
        }

        Divider()
        Button("Открыть историю") { openWindow(id: "history") }
        SettingsLink {
            Label("Настройки…", systemImage: "gearshape")
        }
        Divider()
        Button("Завершить VoiceBar") { NSApp.terminate(nil) }
    }

    private var recordButtonTitle: String {
        if controller.isStarting { return "Подготовка записи…" }
        if controller.isProcessing { return "Распознавание…" }
        return controller.isRecording ? "Остановить и вставить" : "Начать диктовку"
    }

    private static func duration(_ interval: TimeInterval) -> String {
        VoiceBarFormatting.duration(interval)
    }
}
