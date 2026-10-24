import AVFoundation
import Foundation
import VoiceBarCore

enum AudioCaptureError: LocalizedError {
    case microphonePermissionDenied
    case noMicrophoneInput
    case unsupportedMicrophoneFormat
    case microphoneStart(String)
    case systemCaptureStart(Int32)
    case systemCaptureFormat
    case systemCaptureTimeout

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            "Нет доступа к микрофону. Разрешите VoiceBar доступ в Системных настройках → Конфиденциальность и безопасность → Микрофон."
        case .noMicrophoneInput:
            "macOS не обнаружила устройство ввода звука."
        case .unsupportedMicrophoneFormat:
            "Формат микрофона не удалось преобразовать в моно PCM."
        case .microphoneStart(let message):
            "Не удалось запустить микрофон: \(message)"
        case .systemCaptureStart(let status):
            "Не удалось запустить захват системного звука (Core Audio: \(status)). Проверьте разрешение VoiceBar в Системных настройках → Конфиденциальность и безопасность → Запись системного аудио."
        case .systemCaptureFormat:
            "Системный audio tap вернул неподдерживаемый формат."
        case .systemCaptureTimeout:
            "Core Audio не подготовил устройство для захвата системного звука."
        }
    }
}

final class MicrophoneCapture {
    private let engine = AVAudioEngine()
    private var isRunning = false

    init() {}

    func start(onPacket: @escaping @Sendable (AudioPacket) -> Void) async throws {
        try await requestPermission()

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.channelCount > 0, inputFormat.sampleRate > 0 else {
            throw AudioCaptureError.noMicrophoneInput
        }
        guard let monoFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: inputFormat.sampleRate,
            channels: 1,
            interleaved: false
        ), let converter = AVAudioConverter(from: inputFormat, to: monoFormat) else {
            throw AudioCaptureError.unsupportedMicrophoneFormat
        }
        converter.primeMethod = .none

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4_096, format: inputFormat) { buffer, _ in
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * monoFormat.sampleRate / inputFormat.sampleRate + 32)
            guard let converted = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: capacity) else { return }
            var suppliedInput = false
            var conversionError: NSError?
            converter.convert(to: converted, error: &conversionError) { _, status in
                guard !suppliedInput else {
                    status.pointee = .noDataNow
                    return nil
                }
                suppliedInput = true
                status.pointee = .haveData
                return buffer
            }

            guard conversionError == nil,
                  let channel = converted.floatChannelData?.pointee,
                  converted.frameLength > 0 else { return }
            let samples = Array(UnsafeBufferPointer(start: channel, count: Int(converted.frameLength)))
            onPacket(AudioPacket(source: .microphone, samples: samples, sampleRate: monoFormat.sampleRate))
        }

        engine.prepare()
        do {
            try engine.start()
            isRunning = true
        } catch {
            input.removeTap(onBus: 0)
            throw AudioCaptureError.microphoneStart(error.localizedDescription)
        }
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
    }

    private func requestPermission() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { continuation.resume(returning: $0) }
            }
            guard granted else { throw AudioCaptureError.microphonePermissionDenied }
        case .denied, .restricted:
            throw AudioCaptureError.microphonePermissionDenied
        @unknown default:
            throw AudioCaptureError.microphonePermissionDenied
        }
    }
}
