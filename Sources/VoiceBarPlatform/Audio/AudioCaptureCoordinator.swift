import Foundation
import VoiceBarCore

final class AudioCaptureCoordinator {
    private let microphone = MicrophoneCapture()
    private let systemAudio = SystemAudioCapture()
    private var startedSources: [AudioSource] = []

    init() {}

    func start(
        sources: [AudioSource],
        onPacket: @escaping @Sendable (AudioPacket) -> Void
    ) async throws {
        stop()
        do {
            for source in sources {
                switch source {
                case .microphone:
                    try await microphone.start(onPacket: onPacket)
                    startedSources.append(source)
                case .system:
                    guard #available(macOS 14.2, *) else {
                        throw AudioCaptureError.systemCaptureFormat
                    }
                    try systemAudio.start(onPacket: onPacket)
                    startedSources.append(source)
                }
            }
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        if startedSources.contains(.microphone) {
            microphone.stop()
        }
        if startedSources.contains(.system) {
            if #available(macOS 14.2, *) {
                systemAudio.stop()
            }
        }
        startedSources.removeAll()
    }
}
