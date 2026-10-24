import Foundation

public enum AudioSource: String, CaseIterable, Codable, Identifiable, Sendable {
    case microphone
    case system

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .microphone: "Микрофон"
        case .system: "Системный звук"
        }
    }
}

public enum SourceSelection: String, CaseIterable, Identifiable, Sendable {
    case microphone
    case system
    case both

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .microphone: "Микрофон"
        case .system: "Системный звук"
        case .both: "Оба источника"
        }
    }

    public var sources: [AudioSource] {
        switch self {
        case .microphone: [.microphone]
        case .system: [.system]
        case .both: [.microphone, .system]
        }
    }
}

public enum TranscriptionLanguage: String, CaseIterable, Identifiable, Sendable {
    case russian = "ru"
    case english = "en"
    case automatic = "auto"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .russian: "Русский"
        case .english: "English"
        case .automatic: "Авто"
        }
    }
}

public struct AudioPacket: Sendable {
    public let source: AudioSource
    public let samples: [Float]
    public let sampleRate: Double
    public let captureTime: TimeInterval

    public init(
        source: AudioSource,
        samples: [Float],
        sampleRate: Double,
        captureTime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        self.source = source
        self.samples = samples
        self.sampleRate = sampleRate
        self.captureTime = captureTime
    }
}
