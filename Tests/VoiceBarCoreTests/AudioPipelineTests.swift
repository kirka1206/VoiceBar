import Testing
@testable import VoiceBarCore

@Test
func chunkerEmitsOverlappingWindowsAndFlushesTheTail() {
    var chunker = AudioChunker(source: .microphone)

    #expect(chunker.append(Array(repeating: 0.1, count: 64_000)).isEmpty)
    let first = chunker.append(Array(repeating: 0.1, count: 16_000))
    #expect(first.count == 1)
    #expect(first[0].samples.count == 80_000)
    #expect(first[0].startTime == 0)

    let second = chunker.append(Array(repeating: 0.1, count: 80_000))
    #expect(abs((second.first?.startTime ?? -1) - 4.25) < 0.0001)
    #expect(second.first?.samples.count == 80_000)
    #expect(chunker.finish() != nil)
}

@Test
func assemblerRemovesOnlySameSourceOverlapAndSortsByTime() {
    var assembler = TranscriptAssembler()
    assembler.append(source: .microphone, startTime: 0, text: "Привет, мир.")
    assembler.append(source: .system, startTime: 4.25, text: "Привет, мир.")
    assembler.append(source: .microphone, startTime: 4.25, text: "мир, как дела?")

    #expect(assembler.chunks.map(\.source) == [.microphone, .microphone, .system])
    #expect(assembler.chunks.map(\.text) == ["Привет, мир.", "как дела?", "Привет, мир."])
    #expect(
        assembler.rendered(withSourceLabels: true) ==
            "Микрофон: Привет, мир. Микрофон: как дела? Системный звук: Привет, мир."
    )
}

@Test
func streamingResamplerPreservesConstantSignal() {
    var resampler = StreamingResampler()
    let output = resampler.process(Array(repeating: 0.5, count: 4_800), sampleRate: 48_000)

    #expect(!output.isEmpty)
    #expect(output.allSatisfy { abs($0 - 0.5) < 0.0001 })
}
