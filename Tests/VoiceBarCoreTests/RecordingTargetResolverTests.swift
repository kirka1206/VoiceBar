import Testing
@testable import VoiceBarCore

@Test
func recordingUsesCurrentExternalApplicationWhenAvailable() {
    #expect(RecordingTargetResolver.resolve(
        frontmostProcessID: 42,
        lastExternalProcessID: 17,
        ownProcessID: 99
    ) == 42)
}

@Test
func recordingStartedFromVoiceBarUsesLastExternalApplication() {
    #expect(RecordingTargetResolver.resolve(
        frontmostProcessID: 99,
        lastExternalProcessID: 17,
        ownProcessID: 99
    ) == 17)
}

@Test
func recordingHasNoTargetWhenOnlyVoiceBarIsAvailable() {
    #expect(RecordingTargetResolver.resolve(
        frontmostProcessID: 99,
        lastExternalProcessID: 99,
        ownProcessID: 99
    ) == nil)
}
