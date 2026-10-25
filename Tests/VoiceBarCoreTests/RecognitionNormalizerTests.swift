import Testing
@testable import VoiceBarCore

@Test
func normalizerCorrectsEnglishAndTransliteratedTechnicalTerms() {
    let rules = RecognitionNormalizer.rules(from: "Vesphere => vSphere\nкубернетис => Kubernetes")

    #expect(
        RecognitionNormalizer.normalize("Настроили Vesphere, затем кубернетис.", using: rules) ==
            "Настроили vSphere, затем Kubernetes."
    )
}

@Test
func normalizerPrefersTheLongestOverlappingPhrase() {
    let rules = RecognitionNormalizer.rules(
        from: "Kubernetes => Kubernetes\nDeckhouse Kubernetes Platform => DKP"
    )

    #expect(
        RecognitionNormalizer.normalize("Deckhouse Kubernetes Platform supports Kubernetes.", using: rules) ==
            "DKP supports Kubernetes."
    )
}

@Test
func normalizerPreservesPunctuationAndDoesNotReplaceSubstrings() {
    let rules = RecognitionNormalizer.rules(from: "Vesphere => vSphere\nAPI => Application Programming Interface")

    #expect(
        RecognitionNormalizer.normalize("(Vesphere), \"API\" and capability.", using: rules) ==
            "(vSphere), \"Application Programming Interface\" and capability."
    )
}

@Test
func normalizerDoesNotApplyKnownAmbiguousRussianWordsGlobally() {
    let rules = RecognitionNormalizer.rules(
        from: "текстурой => Deckhouse Kubernetes Platform\nкубернетис => Kubernetes"
    )

    #expect(
        RecognitionNormalizer.normalize("Поверхность покрыта текстурой; установлен кубернетис.", using: rules) ==
            "Поверхность покрыта текстурой; установлен Kubernetes."
    )
}

@Test
func correctionImportKeepsExistingConflictsAndAddsOnlyNewRules() {
    let result = RecognitionNormalizer.merge(
        existing: "Vesphere => vSphere",
        imported: "vesphere => VMware\nKubernetes => Kubernetes\nKUBERNETES => Kubernetes"
    )

    #expect(result.text == "Vesphere => vSphere\nKubernetes => Kubernetes")
    #expect(result.addedCount == 1)
    #expect(result.conflicts == ["vesphere => VMware"])
}

@Test
func normalizationBeforeAssemblyStillRemovesChunkOverlap() {
    let rules = RecognitionNormalizer.rules(from: "кубернетис => Kubernetes")
    var assembler = TranscriptAssembler()

    assembler.append(
        source: .microphone,
        startTime: 0,
        text: RecognitionNormalizer.normalize("Настроили кластер на кубернетис", using: rules)
    )
    assembler.append(
        source: .microphone,
        startTime: 4.25,
        text: RecognitionNormalizer.normalize("на Kubernetes и проверили API", using: rules)
    )

    #expect(assembler.rendered(withSourceLabels: false) == "Настроили кластер на Kubernetes и проверили API")
}
