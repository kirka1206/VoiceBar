import Testing
@testable import VoiceBarCore
@testable import TranscriptCorrectionEvaluationSupport

@Test
func correctionMetricsMeasureTermFixesAndPreservationSeparately() {
    let cases = [
        TranscriptCorrectionCase(
            id: "contextual-term",
            category: "contextual-correction",
            rawWhisper: "Сравнили Deckhouse Platform с текстурой.",
            deterministic: "Сравнили Deckhouse Platform с текстурой.",
            reference: "Сравнили Deckhouse Platform с платформой.",
            vocabulary: ["Deckhouse Platform"],
            expectedCorrections: [.init(source: "текстурой", target: "платформой")]
        ),
        TranscriptCorrectionCase(
            id: "already-correct",
            category: "preservation",
            rawWhisper: "Текстурой покрытия интересовался дизайнер.",
            deterministic: "Текстурой покрытия интересовался дизайнер.",
            reference: "Текстурой покрытия интересовался дизайнер.",
            vocabulary: ["Deckhouse Platform"],
            alreadyCorrect: true
        )
    ]
    let results = [
        TranscriptCorrectionCaseResult(testCase: cases[0], modelOutput: "Сравнили Deckhouse Platform с платформой.", totalDurationMilliseconds: 150),
        TranscriptCorrectionCaseResult(testCase: cases[1], modelOutput: "Текстурой покрытия интересовался дизайнер.", totalDurationMilliseconds: 50)
    ]
    let metrics = TranscriptCorrectionMetrics(results: results)

    #expect(metrics.caseCount == 2)
    #expect(metrics.expectedTermCorrections == 1)
    #expect(metrics.successfulTermCorrections == 1)
    #expect(metrics.termCorrectionRate == 1)
    #expect(metrics.alreadyCorrectCaseCount == 1)
    #expect(metrics.falseChangesToAlreadyCorrectCases == 0)
    #expect(metrics.modelWordErrorRate < metrics.rawWordErrorRate)
    #expect(metrics.meanInferenceMilliseconds == 100)
    #expect(metrics.maximumInferenceMilliseconds == 150)
}

@Test
func correctionMetricsCountChangesToAlreadyCorrectTextAsFalseChanges() {
    let testCase = TranscriptCorrectionCase(
        id: "false-rewrite",
        category: "preservation",
        rawWhisper: "Командир группы открыл встречу.",
        deterministic: "Командир группы открыл встречу.",
        reference: "Командир группы открыл встречу.",
        vocabulary: ["Commander"],
        alreadyCorrect: true
    )
    let result = TranscriptCorrectionCaseResult(
        testCase: testCase,
        modelOutput: "Commander группы открыл встречу.",
        totalDurationMilliseconds: 10
    )
    let metrics = TranscriptCorrectionMetrics(results: [result])

    #expect(metrics.falseChangesToAlreadyCorrectCases == 1)
    #expect(metrics.falseChangeRate == 1)
    #expect(metrics.modelWordErrorRate > metrics.rawWordErrorRate)
}

@Test
func correctionMetricsCountCapitalizationOnlyChangesAsFalseChanges() {
    let testCase = TranscriptCorrectionCase(
        id: "capitalization-only-rewrite",
        category: "preservation",
        rawWhisper: "Commander joined the call.",
        deterministic: "Commander joined the call.",
        reference: "Commander joined the call.",
        vocabulary: ["Commander"],
        alreadyCorrect: true
    )
    let result = TranscriptCorrectionCaseResult(
        testCase: testCase,
        modelOutput: "commander joined the call.",
        totalDurationMilliseconds: 10
    )

    #expect(result.changedAlreadyCorrectText)
}
