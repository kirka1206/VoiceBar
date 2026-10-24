import Foundation

@main
enum VoiceBarCoreChecks {
    static func main() {
        checkChunkWindows()
        checkOverlapAndSourceOrdering()
        checkResampling()
        print("Core audio/transcript checks passed.")
    }

    private static func checkChunkWindows() {
        var chunker = AudioChunker(source: .microphone, initialStartTime: 0.2)
        precondition(chunker.append(Array(repeating: 0.1, count: 64_000)).isEmpty)
        let first = chunker.append(Array(repeating: 0.1, count: 16_000))
        precondition(first.count == 1)
        precondition(first[0].samples.count == 80_000)
        precondition(first[0].startTime == 0.2)

        let second = chunker.append(Array(repeating: 0.1, count: 80_000))
        precondition(second.count == 1)
        precondition(abs(second[0].startTime - 4.45) < 0.0001)
        precondition(second[0].samples.count == 80_000)
        precondition(chunker.finish() != nil)
    }

    private static func checkOverlapAndSourceOrdering() {
        var assembler = TranscriptAssembler()
        assembler.append(source: .microphone, startTime: 0, text: "Привет, мир.")
        assembler.append(source: .system, startTime: 4.25, text: "Привет, мир.")
        assembler.append(source: .microphone, startTime: 4.25, text: "мир, как дела?")

        precondition(assembler.chunks.map(\.source) == [.microphone, .microphone, .system])
        precondition(assembler.chunks.map(\.text) == ["Привет, мир.", "как дела?", "Привет, мир."])
        precondition(assembler.rendered(withSourceLabels: true) ==
            "Микрофон: Привет, мир. Микрофон: как дела? Системный звук: Привет, мир.")
    }

    private static func checkResampling() {
        var resampler = StreamingResampler()
        let output = resampler.process(Array(repeating: 0.5, count: 4_800), sampleRate: 48_000)
        precondition(!output.isEmpty)
        precondition(output.allSatisfy { abs($0 - 0.5) < 0.0001 })
    }
}
