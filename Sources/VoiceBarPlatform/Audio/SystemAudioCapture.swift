import CoreAudio
import Foundation
import VoiceBarCore

final class SystemAudioCapture {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var isRunning = false
    private var sampleRate: Double = 0
    private var onPacket: (@Sendable (AudioPacket) -> Void)?

    init() {}

    @available(macOS 14.2, *)
    func start(onPacket: @escaping @Sendable (AudioPacket) -> Void) throws {
        stop()
        self.onPacket = onPacket

        let excludedProcess = Self.audioObject(for: getpid()).map { [$0] } ?? []
        let description = CATapDescription(monoGlobalTapButExcludeProcesses: excludedProcess)
        description.name = "VoiceBar System Audio"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr else {
            reset()
            throw AudioCaptureError.systemCaptureStart(status)
        }

        guard let format = Self.tapFormat(for: tapID),
              format.mFormatID == kAudioFormatLinearPCM,
              format.mBitsPerChannel == 32,
              format.mChannelsPerFrame == 1,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mSampleRate > 0 else {
            reset()
            throw AudioCaptureError.systemCaptureFormat
        }
        sampleRate = format.mSampleRate

        let aggregateUID = UUID().uuidString
        // Starting the tap only after audio appears can stall a dictation session when output is silent.
        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "VoiceBar System Audio",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true
            ]]
        ]

        status = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregateDeviceID)
        guard status == noErr else {
            reset()
            throw AudioCaptureError.systemCaptureStart(status)
        }
        guard Self.waitUntilAlive(aggregateDeviceID) else {
            reset()
            throw AudioCaptureError.systemCaptureTimeout
        }

        status = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateDeviceID, nil) { [weak self] _, inputData, _, _, _ in
            guard let self else { return }
            self.consume(inputData)
        }
        guard status == noErr else {
            reset()
            throw AudioCaptureError.systemCaptureStart(status)
        }

        status = AudioDeviceStart(aggregateDeviceID, ioProcID)
        guard status == noErr else {
            reset()
            throw AudioCaptureError.systemCaptureStart(status)
        }
        isRunning = true
    }

    @available(macOS 14.2, *)
    func stop() {
        if isRunning {
            _ = AudioDeviceStop(aggregateDeviceID, ioProcID)
            isRunning = false
        }
        reset()
    }

    private func consume(_ data: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: data))
        guard let first = buffers.first,
              first.mNumberChannels == 1,
              let rawSamples = first.mData,
              first.mDataByteSize >= UInt32(MemoryLayout<Float>.size) else { return }

        let count = Int(first.mDataByteSize) / MemoryLayout<Float>.size
        let samples = Array(UnsafeBufferPointer(
            start: rawSamples.assumingMemoryBound(to: Float.self),
            count: count
        ))
        onPacket?(AudioPacket(source: .system, samples: samples, sampleRate: sampleRate))
    }

    @available(macOS 14.2, *)
    private func reset() {
        if let ioProcID, aggregateDeviceID != kAudioObjectUnknown {
            _ = AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
        }
        ioProcID = nil
        if aggregateDeviceID != kAudioObjectUnknown {
            _ = AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
        }
        aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        if tapID != kAudioObjectUnknown {
            _ = AudioHardwareDestroyProcessTap(tapID)
        }
        tapID = AudioObjectID(kAudioObjectUnknown)
        onPacket = nil
        sampleRate = 0
    }

    private static func audioObject(for processID: pid_t) -> AudioObjectID? {
        var pid = processID
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var objectID = AudioObjectID(kAudioObjectUnknown)
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            UInt32(MemoryLayout<pid_t>.size),
            &pid,
            &dataSize,
            &objectID
        )
        guard status == noErr, objectID != kAudioObjectUnknown else { return nil }
        return objectID
    }

    private static func tapFormat(for tapID: AudioObjectID) -> AudioStreamBasicDescription? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var format = AudioStreamBasicDescription()
        var dataSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &dataSize, &format)
        return status == noErr ? format : nil
    }

    private static func waitUntilAlive(_ deviceID: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        for _ in 0..<30 {
            var isAlive: UInt32 = 0
            var dataSize = UInt32(MemoryLayout<UInt32>.size)
            let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &isAlive)
            if status == noErr, isAlive != 0 { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }
}
