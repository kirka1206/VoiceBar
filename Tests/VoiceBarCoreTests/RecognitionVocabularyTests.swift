import Testing
@testable import VoiceBarCore

@Test
func vocabularyTrimsLinesAndDeduplicatesWithoutChangingFirstSpelling() {
    #expect(RecognitionVocabulary.terms(from: " VMware \n\nvmware\nKubernetes ") == ["VMware", "Kubernetes"])
}

@Test
func vocabularyImportMergesUniqueTermsWithExistingEntriesFirst() {
    let result = RecognitionVocabulary.merge(
        existing: "VMware\nDeckhouse Kubernetes Platform",
        imported: "vmware\nKubernetes\nDeckhouse Kubernetes Platform"
    )

    #expect(result.text == "VMware\nDeckhouse Kubernetes Platform\nKubernetes")
    #expect(result.addedCount == 1)
}

@Test
func vocabularyBuildsWhisperPromptOnlyWhenTermsExist() {
    #expect(RecognitionVocabulary.initialPrompt(from: " \n ") == nil)
    #expect(
        RecognitionVocabulary.initialPrompt(from: "Deckhouse Kubernetes Platform") ==
            "Возможные англоязычные технические термины и названия: Deckhouse Kubernetes Platform. Сохраняй их написание, если они произнесены."
    )
}
