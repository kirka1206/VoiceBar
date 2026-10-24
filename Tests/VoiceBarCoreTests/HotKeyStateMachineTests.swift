import Testing
@testable import VoiceBarCore

@Test
func toggleHotKeyActsOnPressAndIgnoresReleaseAndKeyRepeat() {
    var state = DictationHotKeyStateMachine()

    #expect(state.handle(.pressed, mode: .toggle) == .toggle)
    #expect(state.handle(.pressed, mode: .toggle) == .none)
    #expect(state.handle(.released, mode: .toggle) == .none)
    #expect(state.handle(.pressed, mode: .toggle) == .toggle)
}

@Test
func pushToTalkStartsOnceAndStopsOnRelease() {
    var state = DictationHotKeyStateMachine()

    #expect(state.handle(.pressed, mode: .pushToTalk) == .start)
    #expect(state.handle(.pressed, mode: .pushToTalk) == .none)
    #expect(state.handle(.released, mode: .pushToTalk) == .stop)
    #expect(state.handle(.released, mode: .pushToTalk) == .none)
}

@Test
func releaseUsesModeThatWasActiveWhenKeyWasPressed() {
    var toggle = DictationHotKeyStateMachine()
    #expect(toggle.handle(.pressed, mode: .toggle) == .toggle)
    #expect(toggle.handle(.released, mode: .pushToTalk) == .none)

    var pushToTalk = DictationHotKeyStateMachine()
    #expect(pushToTalk.handle(.pressed, mode: .pushToTalk) == .start)
    #expect(pushToTalk.handle(.released, mode: .toggle) == .stop)
}

@Test
func cancellingHeldPushToTalkStopsIt() {
    var state = DictationHotKeyStateMachine()
    #expect(state.handle(.pressed, mode: .pushToTalk) == .start)
    #expect(state.cancel() == .stop)
    #expect(state.handle(.released, mode: .pushToTalk) == .none)
}
