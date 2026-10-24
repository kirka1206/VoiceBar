import SwiftData
import SwiftUI
import VoiceBarCore
import VoiceBarPlatform

@main
struct VoiceBarApp: App {
    private let modelContainer: ModelContainer
    @StateObject private var controller: AppController

    init() {
        do {
            let container = try ModelContainer(for: TranscriptEntry.self)
            modelContainer = container
            _controller = StateObject(wrappedValue: AppController(modelContext: container.mainContext))
        } catch {
            fatalError("Не удалось открыть локальную историю VoiceBar: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup("История VoiceBar", id: "history") {
            HistoryView(controller: controller)
                .modelContainer(modelContainer)
                .frame(minWidth: 520, minHeight: 440)
        }

        Settings {
            SettingsView(controller: controller)
                .modelContainer(modelContainer)
                .frame(width: 500, height: 560)
        }

        MenuBarExtra {
            MenuBarView(controller: controller)
                .modelContainer(modelContainer)
        } label: {
            Image(systemName: controller.isRecording ? "waveform.circle.fill" : "waveform")
                .foregroundStyle(controller.isRecording ? .red : .primary)
        }
        .menuBarExtraStyle(.menu)
    }
}
