import Foundation

public struct AudioChunk: Sendable {
    public let source: AudioSource
    public let startTime: TimeInterval
    public let samples: [Float]
}

public struct AudioChunker: Sendable {
    public static let targetSampleRate = 16_000.0
    public static let windowDuration: TimeInterval = 5
    public static let overlapDuration: TimeInterval = 0.75

    private let source: AudioSource
    private let windowSize = Int(targetSampleRate * windowDuration)
    private let stepSize = Int(targetSampleRate * (windowDuration - overlapDuration))
    private var bufferedSamples: [Float] = []
    private var nextStartTime: TimeInterval = 0

    public init(source: AudioSource, initialStartTime: TimeInterval = 0) {
        self.source = source
        self.nextStartTime = initialStartTime
    }

    public mutating func append(_ samples: [Float]) -> [AudioChunk] {
        bufferedSamples.append(contentsOf: samples)
        var output: [AudioChunk] = []

        while bufferedSamples.count >= windowSize {
            output.append(AudioChunk(
                source: source,
                startTime: nextStartTime,
                samples: Array(bufferedSamples.prefix(windowSize))
            ))
            bufferedSamples.removeFirst(stepSize)
            nextStartTime += Double(stepSize) / Self.targetSampleRate
        }

        return output
    }

    public mutating func finish(minimumDuration: TimeInterval = 0.25) -> AudioChunk? {
        guard Double(bufferedSamples.count) / Self.targetSampleRate >= minimumDuration else {
            bufferedSamples.removeAll(keepingCapacity: false)
            return nil
        }

        let chunk = AudioChunk(source: source, startTime: nextStartTime, samples: bufferedSamples)
        bufferedSamples.removeAll(keepingCapacity: false)
        return chunk
    }
}

/// Resamples a mono stream without resetting phase at each audio callback.
public struct StreamingResampler: Sendable {
    private var inputSamples: [Float] = []
    private var nextOutputPosition: Double = 0
    private var currentInputRate: Double?

    public init() {}

    public mutating func process(_ samples: [Float], sampleRate: Double) -> [Float] {
        guard sampleRate > 0, !samples.isEmpty else { return [] }
        if currentInputRate != sampleRate {
            inputSamples.removeAll(keepingCapacity: false)
            nextOutputPosition = 0
            currentInputRate = sampleRate
        }
        guard sampleRate != AudioChunker.targetSampleRate else { return samples }

        inputSamples.append(contentsOf: samples)
        let step = sampleRate / AudioChunker.targetSampleRate
        var output: [Float] = []
        while nextOutputPosition + 1 < Double(inputSamples.count) {
            let lowerIndex = Int(nextOutputPosition)
            let fraction = Float(nextOutputPosition - Double(lowerIndex))
            let lower = inputSamples[lowerIndex]
            let upper = inputSamples[lowerIndex + 1]
            output.append(lower + (upper - lower) * fraction)
            nextOutputPosition += step
        }

        let consumed = max(0, Int(nextOutputPosition) - 1)
        if consumed > 0 {
            inputSamples.removeFirst(consumed)
            nextOutputPosition -= Double(consumed)
        }
        return output
    }
}
